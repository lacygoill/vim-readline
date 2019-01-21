if exists('g:autoloaded_readline')
    finish
endif
let g:autoloaded_readline = 1

" FIXME: `Del` is broken with some composing characters.{{{
"
" Sometimes, our functions return `Del`.
" Most of the time, it works as expected; but watch this:
"
"     Ë͙͙̬̹͈͔̜́̽D̦̩̱͕͗̃͒̅̐I̞̟̣̫ͯ̀ͫ͑ͧT̞Ŏ͍̭̭̞͙̆̎̍R̺̟̼͈̟̓͆
"
" Press, `Del` while the cursor is at the beginning of the word, in a buffer; it
" works.
" Now, do the same on the command-line; you'll have to press the key `51` times!
" `51` is the output of `strchars('Ë͙͙̬̹͈͔̜́̽D̦̩̱͕͗̃͒̅̐I̞̟̣̫ͯ̀ͫ͑ͧT̞Ŏ͍̭̭̞͙̆̎̍R̺̟̼͈̟̓͆')`, btw.
" Because of this, some readline functions  don't work with these types of text,
" while on the command-line, like `M-d` and `C-w`.
"}}}

" OLD code {{{1
" What was its purpose? {{{2
"
" It was a complicated mechanism to break  the undo sequence after a sequence of
" deletions, so  that we could  recover the state  of the buffer  after deleting
" some  text. It was  useful,  for example,  to  recover the  state  (2) in  the
" following edition:
"
"                        cursor
"                        v
"         (1) hello world|
"
"                 C-w
"
"         (2) hello |
"
"                 i people
"
"         (3) hello people|

" Why don't we use it anymore? {{{2
"
" Because:
"
"         • either you break  the undo sequence just BEFORE the next
"           insertion of a character, after a sequence of deletion
"
"         • or you break it just AFTER
"
" If you break it just before, then  when you insert a register after a sequence
" of deletions,  the last  character of  the register  is changed  (deleted then
" replaced with the 1st).
"
" If you break it just after, then  a custom abbreviation may be expanded in the
" middle of a word you type.
" MWE:
"
"         :inorea al la
"
"           ┌ text in buffer
"         ┌─┤
"         val|
"            ^
"            cursor
"
"         C-w val SPC
"             → vla ✘
"
" MWE:
"     :inorea al la
"     :ino <c-x>d  <bs><bs><bs>v<c-g>ual
"                               └────┤
"                                    └ this is where our custom function
"                                      was breaking the undo sequence
"
"     val C-x d SPC
"     vla ✘~

" What dit the code look like? {{{2
" Autocmd {{{3
"
"      augroup my_granular_undo
"          ...
"
"          We could probably  have replaced these 2  permanent autocommands with
"          fire-once equivalent.
"
"          au InsertLeave      * let s:deleting = 0
"          au InsertCharPre    * call s:break_undo_after_deletions(v:char)
"                                                                  ├────┘
"                                                                  │
"          not  needed if  you  break  the undo  sequence  just  AFTER the  next
"          insertion of a character, after  a sequence of deletions (only needed
"          if you do it just BEFORE)
"      augroup END

" Function {{{3
"      fu! s:break_undo_after_deletions(char) abort {{{4
"          if s:deleting
"             To exclude  the first  inserted character from  the undo  sequence, we
"             should call `feedkeys()` like this:
"
"                     call feedkeys("\<bs>\<c-g>u".v:char, 'in')
"             Why "\<bs>" ?{{{
"
"             It  seems that  when InsertCharPre  occurs, v:char  is already  in the
"             typeahead buffer. We  can change its  value but not insert  sth before
"             it.   We need  to break  undo sequence  BEFORE `v:char`,  so that  the
"             latter is part of the next edition.
"             Thus, we delete it (BS), break undo (C-g u), then reinsert it (v:char).
            "}}}
"             Why pass the 'i' flag to feedkeys(…)?{{{
"
"             Suppose we don't give 'i', and we have this mapping:
"                                           ino abc def
"
"             Then we write:                hello foo
"             We delete foo with C-w:       hello
"             If we type abc, we'll get:    hello ded
"
"             Why ded and not def?
"
"               1. a b c                 keys which are typed initially
"
"               2. d e f                 expansion due to mapping
"
"                                                • the expansion occurs as soon as we type `c`
"
"                                                • 3 InsertCharPre events occurs right after `d`
"                                                  is written inside the typeahead buffer
"
"                                                • this function will be called only for the 1st one,
"                                                  because after its 1st invocation, `s:deleting` will
"                                                  be reset to 0
"
"                                                • when it's called, v:char will be `d`,
"                                                  the 1st character to be inserted
"
"               3. d e f BS C-g u d      the 4 last keys are written by `feedkeys()`
"                                        AT THE END of the typeahead buffer
"
"               4. d e d                 ✘
"
"             The 4 last keys were added too late.
"             The solution is to insert them at the beginning of the typeahead buffer,
"             by giving the 'i' flag to feedkeys(…). The 3rd step then becomes:
"
"                                 ┌ expansion of `abc`
"                  ┌──────────────┤
"               3. d BS C-g u d e f
"                    └────────┤
"                             └ inserted by our custom function when `InsertCharPre` occurs
            "}}}

"             But we won't try to exclude it:
"
"              call feedkeys("\<c-g>u", 'int')
"             Why?{{{
"
"             To be  sure that the register  we put from insert  mode will never
"             mutate.
            "}}}
"             When could it mutate?{{{
"
"             If you delete  some text, with `C-w` for example,  then put a register
"             whose contents is 'hello', you will insert 'hellh':
"
"                     C-w C-r "
"                     hellh~
"                         ^✘
            "}}}
"             Why does it happen?{{{
"
"             If you copy the text 'abc' in the unnamed register, then put it:
"
"                     C-r "
"
"             … it triggers 3 InsertCharPre:
"
"                     • v:char = 'a'
"                     • v:char = 'b'
"                     • v:char = 'c'
"
"             When the 1st one is triggered, and `feedkeys()` is invoked to add some
"             keys in the typeahead buffer, they are inserted AFTER `bc`.
"             This seems to indicate that when  you put a register, all its contents
"             is  immediately written  in  the  typeahead buffer. The  InsertCharPre
"             events are fired AFTERWARDS for each inserted character.
"
"             We  can  still   reliably  change  any  inserted   key,  by  resetting
"             `v:char`. The issue is specific to feedkeys().
"             Unfortunately,  we have  to  use feedkeys(),  because  we can't  write
"             special characters  in `v:char`,  like `BS` and  `C-g`; they  would be
"             inserted literally.
"
"             MWE:
"             the goal being to replace any `a` with `x`:
"
"                     augroup replace_a_with_x
"                         au!
"                         au InsertCharPre * call Func()
"                     augroup END
"
"                     fu! Func() abort
"                         if v:char is# 'a'
"                             " ✔
"                             " let v:char = 'x'
"                             " ✘ fails when putting a register containing `abc`
"                             " call feedkeys("\<bs>x", 'int')
"                         endif
"                     endfu
            "}}}
"              let s:deleting = 0
"          endif
"      endfu

" Initialization {{{3
"
" The autocmd will  be installed after the  1st time we use one  of our mapping.
" So, the 1st  time we enter insert  mode, and press a custom  mapping, it won't
" have been  installed, and `s:deleting` won't  have been set yet.   But for our
" functions to work, it must exist no matter what.
"
"      let s:deleting = 0
" }}}1
" Autocmds {{{1

augroup my_granular_undo
    au!

    " Why resetting `s:concat_next_kill`?{{{
    "
    "         :one two
    "         C-w Esc
    "         :three
    "         C-w
    "         C-y
    "         threetwo    ✘~
    "         C-y
    "         three       ✔~
    "}}}
    " Why `[^=]` instead of `*`?{{{
    "
    " We have some readline mappings in  insert mode and command-line mode whose
    " rhs uses `c-r =`.
    " When they are invoked, we shouldn't reset those variables.
    " Otherwise:
    "
    "     " press C-d
    "     echo b|ar
    "           ^
    "           cursor
    "
    "     " press C-d
    "     echo br
    "
    "     " press C-d
    "     echo b
    "
    "     " press C-_ (✔)
    "     echo br
    "
    "     " press C-_ (✘ we should get bar)
    "     echo br
    "}}}
    " Won't it cause an issue when we leave the expression command-line?{{{
    "
    " Usually, we enter the expression command-line from command-line mode,
    " so the variables will be reset after we leave the regular command-line.
    "
    " But yeah, after entering the command-line from insert mode or command-line
    " mode, then getting back to the previous mode, we'll have an outdated undolist,
    " which won't be removed until we get back to normal mode.
    "
    " It should rarely happen, as I don't use the expression register frequently.
    " And when it does happen, the real  issue will only occur if we press `C-_`
    " enough to get back to this outdated undolist.
    "
    " It doesn't seem a big deal atm.
    "}}}
    au CmdlineLeave  [^=]  let s:concat_next_kill = 0
    " reset undolist and marks when we leave insert/command-line mode
    au CmdlineLeave  [^=]  let s:undolist_c = [] | let s:mark_c = 0
    au InsertLeave   [^=]  let s:undolist_i = [] | let s:mark_i = 0
augroup END

" Functions {{{1
fu! s:add_to_kill_ring(mode, text, after, this_kill_is_big) abort "{{{2
    if s:concat_next_kill
        let s:kill_ring_{a:mode}[-1] = a:after
                                   \ ?     s:kill_ring_{a:mode}[-1].a:text
                                   \ :     a:text.s:kill_ring_{a:mode}[-1]
    else
        if s:kill_ring_{a:mode} ==# ['']
            let s:kill_ring_{a:mode} = [a:text]
        else
            " the kill ring  is never reset in readline; we  should not reset it
            " either but I don't like letting it  grow too much, so we keep only
            " the last 10 killed text
            if len(s:kill_ring_{a:mode}) > 10
                call remove(s:kill_ring_{a:mode}, 0, len(s:kill_ring_{a:mode}) - 9)
            endif
            " before adding  sth in  the kill-ring,  check whether  it's already
            " there, and if it is, remove it
            call filter(s:kill_ring_{a:mode}, { i,v -> v isnot# a:text })
            call add(s:kill_ring_{a:mode}, a:text)
        endif
    endif
    call s:set_concat_next_kill(a:mode, a:this_kill_is_big)
endfu

fu! readline#add_to_undolist() abort "{{{2
    augroup add_to_undolist
        au!
        au User add_to_undolist_c call s:add_to_undolist('c', getcmdline(), getcmdpos())
        au User add_to_undolist_i call s:add_to_undolist('i', getline('.'), col('.'))
    augroup END
endfu

fu! s:add_to_undolist(mode, line, pos) abort "{{{2
    let undo_len = len(s:undolist_{a:mode})
    if undo_len > 100
        " limit the size of the undolist to 100 entries
        call remove(s:undolist_{a:mode}, 0, undo_len - 101)
    endif
    let s:undolist_{a:mode} += [[a:line,
                                \ strchars(matchstr(a:line, '.*\%'.a:pos.'c'), 1)]]
endfu

fu! readline#backward_char(mode) abort "{{{2
    let s:concat_next_kill = 0

    " SPC + C-h = close wildmenu
    return a:mode is# 'i'
       \ ?     "\<c-g>U\<left>"
       \ :     (wildmenumode() ? "\<space>\<c-h>" : '')."\<left>"
endfu

fu! readline#backward_delete_char(mode) abort "{{{2
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 0, 0)
    return "\<c-h>"
endfu

fu! readline#backward_kill_word(mode) abort "{{{2
    let isk_save = &l:isk
    try
        let [line, pos] = s:setup_and_get_info(a:mode, 1, 0, 1)
        "            ┌ word before cursor{{{
        "            │
        "            │  ┌ there may be some non-word text between the word and the cursor
        "            │  │
        "            │  │            ┌ the cursor
        "            ├┐ ├───────────┐├───────┐}}}
        let pat = '\v\k*%(%(\k@!.)+)?%'.pos.'c'

        let killed_text = matchstr(line, pat)
        call s:add_to_kill_ring(a:mode, killed_text, 0, 0)

        " Do NOT feed "BS" directly, because sometimes it would delete too much text.
        " It may happen when the cursor is after a sequence of whitespace (1 BS = &sw chars deleted).
        " Instead, feed "Left Del".
        return s:break_undo_before_deletions(a:mode)
        \     .repeat((a:mode is# 'i' ? "\<c-g>U" : '')."\<left>\<del>",
        \             strchars(killed_text, 1))
    catch
        return lg#catch_error()
    finally
        let &l:isk = isk_save
    endtry
    return ''
endfu

fu! readline#beginning_of_line(mode) abort "{{{2
    let s:concat_next_kill = 0
    return a:mode is# 'c'
       \ ?     "\<home>"
       \ : col('.') >= match(getline('.'), '\S') + 1
       \ ?     repeat("\<c-g>U\<left>", strchars(matchstr(getline('.'), '\S.*\%'.col('.').'c'), 1))
       \ :     repeat("\<c-g>U\<right>", strchars(matchstr(getline('.'), '\%'.col('.').'c\s*\ze\S'), 1))
endfu

fu! s:break_undo_before_deletions(mode) abort "{{{2
    if a:mode is# 'c' || s:deleting
        return ''
    else
        " If  the execution  has reached  this point,  it means  we're going  to
        " delete some multi-char text. But, if we delete another multi-char text
        " right after, we don't want to, again, break the undo sequence.
        let s:deleting = 1
        " We'll reenable the breaking of the undo sequence before a deletion, the
        " next time we insert a character, or leave insert mode.
        augroup enable_break_undo_before_deletions
            au!
            au InsertLeave,InsertCharPre * sil! let s:deleting = 0
                \ | exe 'au! enable_break_undo_before_deletions'
                \ |     aug! enable_break_undo_before_deletions
        augroup END
        return "\<c-g>u"
    endif
endfu
" Purpose:{{{
"
"         • A is a text we insert
"         • B is a text we insert after A
"         • C is a text we insert to replace B after deleting the latter
"
" Without any custom “granular undo“, we can only visit:
"
"         • ∅
"         • AC
"
" This function presses `C-g  u` the first time we delete  a multi-char text, in
" any given sequence of multi-char deletions.
" This allows us to visit AB.
" In the past, we used some code, which broke the undo sequence after a sequence
" of  deletions. It allowed  us to  visit A  (alone). We don't  use it  anymore,
" because it leads to too many issues.
"}}}

fu! readline#change_case_save(upcase) abort "{{{2
    let s:change_case_up = a:upcase
    return ''
endfu

fu! readline#change_case_word(type, ...) abort "{{{2
    "                               ^ mode
    let isk_save = &l:isk
    try
        let mode = get(a:, '1', 'n')
        let [line, pos] = s:setup_and_get_info(mode, 1, 1, 1)
        let pat    = '\v\k*%'.pos.'c\zs%(\k+|.{-}<\k+>|%(\k@!.)+)'
        let word   = matchstr(line, pat)
        let length = strchars(word, 1)

        if mode is# 'c'
            if pos > strlen(line)
                return ''
            else
                " we  can't return `Del`,  so we directly  feed the keys  to the
                " typeahead buffer
                call feedkeys(repeat("\<del>", length), 'int')
                return s:change_case_up ? toupper(word) : tolower(word)
            endif
        elseif mode is# 'i'
            return repeat("\<del>", length).(s:change_case_up ? toupper(word) : tolower(word))
        elseif mode is# 'n'
            let new_line = substitute(line, pat, (s:change_case_up ? '\U' : '\L').'\0', '')
            let new_pos  = match(line, pat.'\zs') + 1
            call setline('.', new_line)
            call cursor('.', new_pos)
        endif

    catch
        return lg#catch_error()
    finally
        let &l:isk = isk_save
    endtry

    return ''
endfu

fu! readline#delete_char(mode) abort "{{{2
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 1, 0)

    if a:mode is# 'c'
        " If the cursor is  at the end of the command-line, we  want C-d to keep
        " its normal behavior  which is to list names that  match the pattern in
        " front of the cursor.  However, if it's  before the end, we want C-d to
        " delete the character after it.

        if getcmdpos() <= strlen(getcmdline()) || getcmdtype() isnot# ':'
            call feedkeys("\<del>", 'int')
        else
            " Before pressing  `C-d`, we first  redraw to erase the  possible listed
            " completion suggestions. This makes consecutive listings more readable.
            " MWE:
            "       :h dir       C-d
            "       :h dire      C-d
            "       :h directory C-d
            redraw
            call feedkeys("\<c-d>", 'int')
        endif
        return ''
    endif

    " If the popup menu is visible, scroll a page down.
    " If no menu, and we're BEFORE the end of the line,   delete next character.
    " "                     AT the end of the line,       delete the newline.
    let seq = pumvisible()
        \ ?     repeat("\<c-n>", s:FAST_SCROLL_IN_PUM)
        \ : col('.') <= strlen(getline('.'))
        \ ?     "\<del>"
        \ :     "\<c-g>j\<home>\<bs>"
    call feedkeys(seq, 'int')
    return ''
endfu

fu! readline#edit_and_execute_command() abort "{{{2
    let s:cedit_save = &cedit
    let &cedit = "\<c-x>"
    call feedkeys(&cedit, 'int')
    augroup restore_cedit
        au!
        au CmdWinEnter * sil! let &cedit = s:cedit_save
            \ | unlet! s:cedit_save
            \ | exe 'au! restore_cedit' | aug! restore_cedit
    augroup END
    return ''
endfu

fu! readline#end_of_line() abort "{{{2
    let s:concat_next_kill = 0
    return repeat("\<c-g>U\<right>", col('$') - col('.'))
endfu

fu! readline#exchange_point_and_mark(mode) abort "{{{2
    let [line, pos] = s:setup_and_get_info(a:mode, 0, 0, 0)
    let new_pos = s:mark_{a:mode}

    if a:mode is# 'i'
        let old_pos = strchars(matchstr(line, '.*\%'.pos.'c'), 1)
        let motion = new_pos > old_pos
                 \ ?     "\<c-g>U\<right>"
                 \ :     "\<c-g>U\<left>"
    endif

    let s:mark_{a:mode} = strchars(matchstr(line, '.*\%'.pos.'c'), 1)
    return a:mode is# 'c'
       \ ?     "\<c-b>".repeat("\<right>", new_pos)
       \ :     repeat(motion, abs(new_pos - old_pos))
endfu

fu! readline#forward_char(mode) abort "{{{2
    let s:concat_next_kill = 0
    return a:mode is# 'c'
       \ ?    (wildmenumode() ? "\<space>\<c-h>" : '')."\<right>"
       \ : col('.') > strlen(getline('.'))
       \ ?     ''
       \ :     "\<c-g>U\<right>"
    " Go the right if we're in the middle of the line (custom), or fix the
    " indentation if we're at the end (default)
endfu

fu! readline#kill_line(mode) abort "{{{2
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 0, 0)

    let killed_text = matchstr(line, '.*\%'.pos.'c\zs.*')
    call s:add_to_kill_ring(a:mode, killed_text, 1, 1)

    return s:break_undo_before_deletions(a:mode)
    \     .repeat("\<del>", strchars(killed_text, 1))
endfu

fu! readline#kill_word(mode) abort "{{{2
    let isk_save = &l:isk
    try
        let [line, pos] = s:setup_and_get_info(a:mode, 1, 0, 1)
        "            ┌ from the beginning of the word containing the cursor{{{
        "            │ until the cursor
        "            │ if the cursor is outside of a word, the pattern
        "            │ still matches, because we use `*`, not `+`
        "            │
        "            ├──────────┐}}}
        let pat = '\v\k*%'.pos.'c\zs%(\k+|.{-}<\k+>|%(\k@!.)+)'
        "                             ├─┘ ├───────┘ ├───────┘{{{
        "                             │   │         └ or all the non-word text we're in
        "                             │   └ or the next word if we're outside of a word
        "                             └ the rest of the word after the cursor
        "}}}

        let killed_text = matchstr(line, pat)
        call s:add_to_kill_ring(a:mode, killed_text, 1, 0)

        return s:break_undo_before_deletions(a:mode).repeat("\<del>", strchars(killed_text, 1))

    catch
        return lg#catch_error()
    finally
        let &l:isk = isk_save
    endtry
    return ''
endfu

fu! readline#move_by_words(mode, ...) abort "{{{2
" Implementing this function was tricky, it has to handle:{{{
"
"    • multi-byte characters (éàî)
"    • multi-cell characters (tab)
"    • composing characters  ( ́)
"}}}

    let isk_save = &l:isk
    try
        let [mode, is_fwd, capitalize] = a:0
            \ ? [a:mode, a:1, a:2]
            \ : ['n', 1, 1]
        "         ^{{{
        " When  this  function will  be  invoked  from  normal mode,  the  first
        " argument won't be the current mode, but the type of a text-object.
        " We need to pass the mode manually in this case (`'n'`).
        "}}}

        "                                            ┌ if, in addition to moving the cursor forward,{{{
        "                                            │ we're going to capitalize,
        "                                            │ we want to add the current line to the undolist
        "                                            │ to be able to undo
        "                                            │
        "                                            ├────────┐}}}
        let [line, pos] = s:setup_and_get_info(mode, capitalize, 1, 1)
        if is_fwd
            " all characters from the beginning of the line until the last
            " character of the nearest NEXT word (current one if we're in a word,
            " or somewhere AFTER otherwise)
            let pat = '\v.*%'.pos.'c%(.{-1,}>\ze|.*)'
            "                                    │
            "   if there's no word where we are, ┘
            " nor after us, then go on until the end of the line
        else
            " all characters from the beginning of the line until the first
            " character of the nearest PREVIOUS word (current one if we're in a
            " word, or somewhere BEFORE otherwise)
            let pat = '\v.*\ze<.{-1,}%'.pos.'c'
        endif
        let str = matchstr(line, pat)
        let new_pos = len(str)

        let new_pos_char = strchars(str, 1)
        " pos_char     = nr of characters before cursor in its current position
        " new_pos_char = "                                         new     "

        " necessary to move correctly on a line such as:
        "          ́ foo  ́ bar
        let pos_char = strchars(matchstr(line, '.*\%'.pos.'c'), 1)
        "                                                       │
        "                                                       └ ignore composing characters

        let diff = pos_char - new_pos_char
        let building_motion = mode is# 'i'
                          \ ?     diff > 0 ? "\<c-g>U\<left>" : "\<c-g>U\<right>"
                          \ :     diff > 0 ? "\<left>" : "\<right>"

        " Here's how it works in readline:{{{
        "
        "     1. it looks for the keyword character after the cursor
        "
        "        The latter could be right after, or further away.
        "        Which means the capitalization doesn't necessarily uppercase
        "        the first character of a word.
        "
        "     2. it replaces it with its uppercase counterpart
        "
        "     3. it replaces all subsequent characters until a non-keyword character
        "        with their lowercase counterparts
        "}}}
        if capitalize
            let new_line = substitute(line,
            \                         '\v%'.pos.'c.{-}\zs(\k)(.{-})%'.(new_pos+1).'c',
            \                         '\u\1\L\2', '')
            if mode is# 'c'
                let seq = "\<c-e>\<c-u>".new_line."\<c-b>".repeat("\<right>", new_pos_char)
                call feedkeys(seq, 'int')
                return ''
            else
                call setline('.', new_line)
            endif
        endif

        " Why `feedkeys()`?{{{
        "
        " Needed  to move  the cursor at  the end  of the word  when we  want to
        " capitalize it in normal mode.
        "}}}
        let seq = repeat(building_motion, abs(diff))
        return mode is# 'i'
            \ ? seq
            \ : feedkeys(seq, 'int')[-1]

    " the `catch` clause prevents errors from being echoed
    " if you try to throw the exception manually (echo v:exception, echo
    " v:throwpoint), nothing will be displayed, so don't bother
    catch
        return lg#catch_error()
    finally
        let &l:isk = isk_save
    endtry
    return ''
endfu

fu! s:set_concat_next_kill(mode, this_kill_is_big) abort "{{{2
    let s:concat_next_kill  = a:this_kill_is_big && s:last_kill_was_big ? 0 : 1
    let s:last_kill_was_big = a:this_kill_is_big

    if a:mode is# 'c'
        " Why?{{{
        "
        " After  the next  deletion, it  the command-line  gets empty,  the deletion
        " after that shouldn't be concatenated:
        "
        "         :one C-u
        "         :two C-w
        "         C-y
        "         twoone    ✘~
        "         two       ✔~
        "}}}
        call timer_start(0, {-> getcmdline() =~# '^\s*$' ? execute('let s:concat_next_kill = 0') : '' })
        return
    endif

    " If we delete a multi-char text, then  move the cursor OR insert some text,
    " then re-delete  a multi-char text,  the 2  multi-char texts should  NOT be
    " concatenated.
    "
    " FIXME:
    " We should make the autocmd listen  to CursorMovedI, but it would, wrongly,
    " reset `s:concat_next_kill`  when we  delete a  2nd multi-char  text right
    " after a 1st one.
    augroup reset_concatenate_kills
        au!
        au InsertCharPre,InsertEnter,InsertLeave *
            \ sil! let s:concat_next_kill = 0
            \ | exe 'au! reset_concatenate_kills'
            \ | aug! reset_concatenate_kills
    augroup END
endfu

fu! s:set_isk() abort "{{{2
    " Why re-setting 'isk'?{{{
    "
    " readline doesn't consider `-`, `#`, `_` as part of a word,
    " contrary to Vim which may disagree for some of them.
    "
    " Removing them from 'isk' allows us to operate on the following “words“:
    "
    "         foo-bar
    "         foo#bar
    "         foo_bar
    "}}}
    " Why not using `-=` instead of `=`?{{{
    "
    " Previously, we used this code:
    "         setl isk-=_ isk-=- isk-=#
    "
    " But sometimes, the mapping behaved strangely.
    " So now, I prefer to give an explicit value to `isk`.
    "
    "}}}
    setl isk=@,48-57,192-255
endfu

fu! readline#set_mark(mode) abort "{{{2
    let s:mark_{a:mode} = a:mode is# 'i'
                      \ ?     strchars(matchstr(getline('.'), '.*\%'.col('.').'c'), 1)
                      \ :     strchars(matchstr(getcmdline(), '.*\%'.getcmdpos().'c'), 1)
    return ''
endfu

fu! s:setup_and_get_info(mode, add_to_undolist, reset_concat, set_isk) abort "{{{2
    let [line, pos] = a:mode is# 'c'
                  \ ?     [getcmdline(), getcmdpos()]
                  \ :     [getline('.'), col('.')]

    " `transpose_words()` may call this function from normal mode
    if a:add_to_undolist && a:mode isnot# 'n'
        call s:add_to_undolist(a:mode, line, pos)
    endif

    if a:reset_concat && a:mode isnot# 'n'
        let s:concat_next_kill = 0
    endif

    if a:set_isk
        call s:set_isk()
    endif

    return [line, pos]
endfu

fu! readline#transpose_chars(mode) abort "{{{2
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 1, 0)
    if pos > strlen(line)
        " We use `matchstr()` because of potential multibyte characters.
        " Test on this:
        "
        "     âêîôû
        return a:mode is# 'i'
           \ ?     "\<c-g>U\<left>\<bs>\<c-g>U\<right>".matchstr(line, '.\ze.\%'.pos.'c')
           \ :     "\<left>\<bs>\<right>".matchstr(line, '.\ze.\%'.pos.'c')

    elseif pos > 1
        return a:mode is# 'i'
           \ ?     "\<bs>\<c-g>U\<right>".matchstr(line, '.\%'.pos.'c')
           \ :     "\<bs>\<right>".matchstr(line, '.\%'.pos.'c')

    else
        return ''
    endif
endfu

fu! readline#transpose_words(type, ...) abort "{{{2
    "                              ^
    "                              mode
    let isk_save = &l:isk
    try
        let mode = get(a:, '1', 'n')
        let [line, pos] = s:setup_and_get_info(mode, 1, 1, 1)
        " We're looking for 2 words which are separated by non-word characters.
        " Why non-word characters, and not whitespace?{{{
        "
        " Because transposition works even when 2 words are separated by special
        " characters such as backticks:
        "
        "     foo``|``bar    ⇒    bar````foo
        "          ^
        "          cursor
        "}}}
        let pat = '(<\k+>)(%(\k@!.)+)(<\k+>)'

        " What's this concat (\&) for?{{{
        "
        " It will be used at the end, once Vim thinks it has found a match for 2
        " words.
        " It checks that the cursor isn't on the first word. For example, the
        " cursor being represented by the pipe:
        "
        "                 e|cho foo
        "
        " ... there should be no transposition (to mimic readline)
        "}}}
        let not_on_first = '\v%(<\k*%'.pos.'c\k+>)@!&'

        " The cursor mustn't be before the 2 words:{{{
        "
        "         foo | bar baz
        "               ├─────┘
        "               └ don't transpose those 2
        "}}}
        let not_before = '%(%'.pos.'c.*)@<!'

        " The cursor mustn't be after the 2 words,{{{
        " unless it is  inside a sequence of non-words characters  at the end of
        " the line:
        "
        "         foo bar | baz
        "         ├─────┘
        "         └ don't transpose those 2
        "
        " OR it is after them, BUT there are only non-word characters between
        " them and the end of the line
        "
        "         foo bar !?`,;:.
        "                ├──────┘
        "                └ the cursor may be anywhere in here
        "}}}
        let not_after = '%(%(.*%'.pos.'c)@!|%(%(\k@!.)*$)@=)'

        " final pattern
        let pat = not_on_first.not_before.pat.not_after

        let new_pos  = match(line, pat.'\zs')
        let rep      = '\3\2\1'
        let new_line = substitute(line, pat, rep, '')

        if mode is# 'c'
            let seq = "\<c-e>\<c-u>"
                \ .new_line
                \ ."\<c-b>".repeat("\<right>", new_pos)
            call feedkeys(seq, 'int')
        else
            call setline('.', new_line)
            call cursor('.', new_pos+1)
        endif

    catch
        return lg#catch_error()
    finally
        let &l:isk = isk_save
    endtry
    return ''
endfu

fu! readline#undo(mode) abort "{{{2
    if empty(s:undolist_{a:mode})
        return ''
    endif
    let [old_line, old_pos] = remove(s:undolist_{a:mode}, -1)

    if a:mode is# 'c'
        return "\<c-e>\<c-u>"
        \     .old_line."\<c-b>"
        \     .repeat("\<right>", old_pos)
    else
        " `old_pos` expresses a position with a character count.
        " `cursor()` expects a byte count.
        let pos = strlen(matchstr(old_line, '.\{'.old_pos.'}')) + 1
        call timer_start(0, {-> setline('.', old_line)
        \                     + cursor('.', pos)})
        return ''
    endif
endfu

fu! readline#unix_line_discard(mode) abort "{{{2
    if pumvisible()
        return repeat("\<c-p>", s:FAST_SCROLL_IN_PUM)
    endif

    let [line, pos] = s:setup_and_get_info(a:mode, 1, 0, 0)

    if a:mode is# 'c'
        call s:add_to_kill_ring(a:mode, matchstr(line, '.*\%'.pos.'c'), 0, 1)
    else
        let s:before_cursor = matchstr(line, '.*\%'.pos.'c')
        call timer_start(0, {-> s:add_to_kill_ring(a:mode,
        \                                          substitute(s:before_cursor,
        \                                                     matchstr(getline('.'),
        \                                                              '.*\%'.col('.').'c'),
        \                                                     '', ''),
        \                                          0, 1)
        \                   })
    endif
    return s:break_undo_before_deletions(a:mode)."\<c-u>"
endfu

fu! readline#yank(mode, pop) abort "{{{2
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 1, 0)
    if a:pop
        let length = strchars(s:kill_ring_{a:mode}[-1], 1)
        call insert(s:kill_ring_{a:mode}, remove(s:kill_ring_{a:mode}, -1), 0)
    endif
    let @- = s:kill_ring_{a:mode}[-1]
    return (a:pop
    \       ?    repeat((a:mode is# 'i' ? "\<c-g>U" : '')."\<left>\<del>", length)
    \       :    '')
    \       ."\<c-r>-"
endfu
" }}}1
" Variables {{{1

let s:deleting = 0

let s:FAST_SCROLL_IN_PUM = 5

let s:mark_i = 0
let s:mark_c = 0

let s:undolist_i = []
let s:undolist_c = []

" When we kill with:
"
"         • M-d: the text is appended  to the top of the kill ring
"         • C-w: the text is prepended "
"         • C-u: the text is prepended "
"         • C-k: the text is appended  "
"
" Exceptions:
" C-k + C-u  →  C-u (only the text killed by C-u goes into the top of the kill ring)
" C-u + C-k  →  C-k ("                       C-k                                   )
"
" Basically, we should NOT concat 2 consecutive big kills.
let s:last_kill_was_big = 0
let s:concat_next_kill  = 0
let s:kill_ring_i       = ['']
let s:kill_ring_c       = ['']

