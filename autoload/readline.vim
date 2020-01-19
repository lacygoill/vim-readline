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

" Old Code: {{{1
" What was its purpose? {{{2
"
" It was a complicated mechanism to break  the undo sequence after a sequence of
" deletions, so  that we could  recover the state  of the buffer  after deleting
" some  text. It was  useful,  for example,  to  recover the  state  (2) in  the
" following edition:
"
"                    cursor
"                    v
"     (1) hello world|
"
"             C-w
"
"     (2) hello |
"
"             i people
"
"     (3) hello people|

" Why don't we use it anymore? {{{2
"
" Because:
"
"    - either you  break the undo sequence  just *before* the next  insertion of a
"    character, after a sequence of deletion
"
"    - or you break it just *after*
"
" If you break it just before, then  when you insert a register after a sequence
" of deletions,  the last  character of  the register  is changed  (deleted then
" replaced with the 1st).
"
" If you break it just after, then  a custom abbreviation may be expanded in the
" middle of a word you type.
" MWE:
"
"     :inorea al la
"
"     ┌ text in buffer
"     ├─┐
"     val|
"        ^
"        cursor
"
"     C-w val SPC
"         → vla ✘
"
" MWE:
"
"     :inorea al la
"     :ino <c-x>d <bs><bs><bs>v<c-g>ual
"                              ├────┘
"                              └ this is where our custom function
"                                was breaking the undo sequence
"
"     val C-x d SPC
"     vla ✘~

" What dit the code look like? {{{2
" Autocmd {{{3
"
"     augroup my_granular_undo
"         ...
"
"         We could  probably have replaced  these 2 permanent  autocommands with
"         one-shot equivalent.
"
"         au InsertLeave      * let s:deleting = 0
"         au InsertCharPre    * call s:break_undo_after_deletions(v:char)
"                                                                 ├────┘
"                                                                 │
"         not  needed if  you  break  the undo  sequence  just  AFTER the  next
"         insertion of a character, after  a sequence of deletions (only needed
"         if you do it just BEFORE)
"     augroup END

" Function {{{3
"     fu s:break_undo_after_deletions(char) abort {{{4
"         if s:deleting
"            To exclude  the first  inserted character from  the undo  sequence, we
"            should call `feedkeys()` like this:
"
"                    call feedkeys("\<bs>\<c-g>u".v:char, 'in')
"            Why "\<bs>" ?{{{
"
"            It  seems that  when InsertCharPre  occurs, v:char  is already  in the
"            typeahead buffer. We  can change its  value but not insert  sth before
"            it.   We need  to break  undo sequence  BEFORE `v:char`,  so that  the
"            latter is part of the next edition.
"            Thus, we delete it (BS), break undo (C-g u), then reinsert it (v:char).
           "}}}
"            Why pass the 'i' flag to feedkeys(…)?{{{
"
"            Suppose we don't give 'i', and we have this mapping:
"                                          ino abc def
"
"            Then we write:                hello foo
"            We delete foo with C-w:       hello
"            If we type abc, we'll get:    hello ded
"
"            Why ded and not def?
"
"              1. a b c                 keys which are typed initially
"
"              2. d e f                 expansion due to mapping
"
"                                               - the expansion occurs as soon as we type `c`
"
"                                               - 3 InsertCharPre events occurs right after `d`
"                                                 is written inside the typeahead buffer
"
"                                               - this function will be called only for the 1st one,
"                                                 because after its 1st invocation, `s:deleting` will
"                                                 be reset to 0
"
"                                               - when it's called, v:char will be `d`,
"                                                 the 1st character to be inserted
"
"              3. d e f BS C-g u d      the 4 last keys are written by `feedkeys()`
"                                       AT THE END of the typeahead buffer
"
"              4. d e d                 ✘
"
"            The 4 last keys were added too late.
"            The solution is to insert them at the beginning of the typeahead buffer,
"            by giving the 'i' flag to feedkeys(…). The 3rd step then becomes:
"
"                 ┌ expansion of `abc`
"                 ├──────────────┐
"              3. d BS C-g u d e f
"                   ├────────┘
"                   └ inserted by our custom function when `InsertCharPre` occurs
           "}}}

"            But we won't try to exclude it:
"
"             call feedkeys("\<c-g>u", 'int')
"            Why?{{{
"
"            To be  sure that the register  we put from insert  mode will never
"            mutate.
           "}}}
"            When could it mutate?{{{
"
"            If you delete  some text, with `C-w` for example,  then put a register
"            whose contents is 'hello', you will insert 'hellh':
"
"                    C-w C-r "
"                    hellh~
"                        ^✘
           "}}}
"            Why does it happen?{{{
"
"            If you copy the text 'abc' in the unnamed register, then put it:
"
"                    C-r "
"
"            … it triggers 3 InsertCharPre:
"
"                    - v:char = 'a'
"                    - v:char = 'b'
"                    - v:char = 'c'
"
"            When the 1st one is triggered, and `feedkeys()` is invoked to add some
"            keys in the typeahead buffer, they are inserted AFTER `bc`.
"            This seems to indicate that when  you put a register, all its contents
"            is  immediately written  in  the  typeahead buffer. The  InsertCharPre
"            events are fired AFTERWARDS for each inserted character.
"
"            We  can  still   reliably  change  any  inserted   key,  by  resetting
"            `v:char`. The issue is specific to feedkeys().
"            Unfortunately,  we have  to  use feedkeys(),  because  we can't  write
"            special characters  in `v:char`,  like `BS` and  `C-g`; they  would be
"            inserted literally.
"
"            MWE:
"            the goal being to replace any `a` with `x`:
"
"                    augroup replace_a_with_x
"                        au!
"                        au InsertCharPre * call Func()
"                    augroup END
"
"                    fu Func() abort
"                        if v:char is# 'a'
"                            " ✔
"                            " let v:char = 'x'
"                            " ✘ fails when putting a register containing `abc`
"                            " call feedkeys("\<bs>x", 'in')
"                        endif
"                    endfu
           "}}}
"             let s:deleting = 0
"         endif
"     endfu
" }}}3
" Initialization {{{3
"
" The autocmd will  be installed after the  1st time we use one  of our mapping.
" So, the 1st  time we enter insert  mode, and press a custom  mapping, it won't
" have been  installed, and `s:deleting` won't  have been set yet.   But for our
" functions to work, it must exist no matter what.
"
"      let s:deleting = 0
" }}}1
" Init {{{1

augroup my_granular_undo
    au!
    " Why resetting `s:concat_next_kill`?{{{
    "
    "     :one two
    "     C-w Esc
    "     :three
    "     C-w
    "     C-y
    "     threetwo    ✘~
    "     C-y
    "     three       ✔~
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
    "   And why do you also include `>`?{{{
    "
    " When we quit debug mode after hitting a breakpoint, there is noise related
    " to these autocmds:
    "
    "     Entering Debug mode.  Type "cont" to continue.
    "     CmdlineLeave Autocommands for "[^=]"
    "     cmd: let s:concat_next_kill = 0
    "     >
    "     CmdlineLeave Autocommands for "[^=]"
    "     cmd: let s:undolist_c = [] | let s:mark_c = 0
    "     >
    "     CmdlineLeave Autocommands for "[^=]"
    "     cmd: let s:mark_c = 0
    "}}}
    "   Won't it cause an issue when we leave the expression command-line?{{{
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
    "   TODO: We may solve this issue by using the new `<cmd>` argument:{{{
    "
    " https://github.com/vim/vim/issues/4784
    "
    " Once it's implemented, try to use  it in readline key bindings which enter
    " the expression register. Example:
    "
    "     cno <silent><unique> <c-d> <cmd>call readline#delete_char('c')<cr>
    "     ino <silent><unique> <c-d> <cmd>call readline#delete_char('i')<cr>
    "
    " Also, once  `<cmd>` is available,  look everywhere for timers  or `<expr>`
    " mappings. You  may eliminate  them thanks  to `<cmd>`,  and avoid  all the
    " pitfalls they introduce.
    "
    " Maybe get rid of `<c-r>=` too (whenever possible)...
    " Rationale: entering a command-line (no matter the type: `=`, `:`, `/`, ...)
    " can  have undesirable  side-effects  because it  fires `CmdlineEnter`  and
    " `CmdlineLeave`, it makes you lose the visual selection, etc...
    "}}}
    au CmdlineLeave [^=>] let s:concat_next_kill = 0
    " reset undolist and marks when we leave insert/command-line mode
    au CmdlineLeave [^=>] let s:undolist_c = [] | let s:mark_c = 0
    au InsertLeave  [^=>] let s:undolist_i = [] | let s:mark_i = 0
augroup END

let s:deleting = 0

" Why `sil!`?{{{
"
" We resource this file after running `:Debug`:
"
"     ~/.vim/plugged/vim-debug/autoload/debug.vim:142
"}}}
sil! const s:FAST_SCROLL_IN_PUM = 5

let s:mark_i = 0
let s:mark_c = 0

let s:undolist_i = []
let s:undolist_c = []

" When we kill with:
"
"    - M-d: the text is appended  to the top of the kill ring
"    - C-w: the text is prepended "
"    - C-u: the text is prepended "
"    - C-k: the text is appended  "
"
" Exceptions:
" C-k + C-u  →  C-u (only the text killed by C-u goes into the top of the kill ring)
" C-u + C-k  →  C-k ("                       C-k                                   )
"
" Basically, we should *not* concat 2 consecutive big kills.
let s:last_kill_was_big = 0
let s:concat_next_kill = 0
let s:kill_ring_i = ['']
let s:kill_ring_c = ['']

let s:cm_y = 0

" Interface {{{1
fu readline#add_to_undolist() abort "{{{2
    augroup add_to_undolist
        au!
        au User add_to_undolist_c call s:add_to_undolist('c', getcmdline(), getcmdpos())
        au User add_to_undolist_i call s:add_to_undolist('i', getline('.'), col('.'))
    augroup END
endfu

fu s:add_to_undolist(mode, line, pos) abort
    let undo_len = len(s:undolist_{a:mode})
    if undo_len > 100
        " limit the size of the undolist to 100 entries
        call remove(s:undolist_{a:mode}, 0, undo_len - 101)
    endif
    let s:undolist_{a:mode} += [[a:line,
                                \ strchars(matchstr(a:line, '.*\%'..a:pos..'c'), 1)]]
endfu

fu readline#backward_char(mode) abort "{{{2
    let s:concat_next_kill = 0

    " SPC + C-h = close wildmenu
    return a:mode is# 'i'
       \ ?     "\<c-g>U\<left>"
       \ :     (wildmenumode() ? "\<space>\<c-h>" : '').."\<left>"
endfu

fu readline#backward_delete_char(mode) abort "{{{2
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 0, 0)
    return "\<c-h>"
endfu

fu readline#backward_kill_word(mode) abort "{{{2
    let [isk_save, bufnr] = [&l:isk, bufnr('%')]

    " All functions using a `try` conditional causes an issue when we hit a breakpoint while debugging an issue.{{{
    "
    "     $ vim /tmp/vim.vim +'breakadd func vim#refactor#heredoc#main'
    "     " press `=rh` (to run `:RefHeredoc`)
    "     >n
    "     " press `M-b`
    "     :return  made pending~
    "     :return  resumed~
    "
    " Solution: Inspect the type of command-line with `getcmdtype()`.
    " If it's `>`, don't use `try`.
    "
    " ---
    "
    " This solution entails  that there is a risk that  some option (e.g. 'isk')
    " is not properly restored, but that's a risk I'm willing to take.
    " If we're hitting a  breakpoint, it means that sth is  broken; and when sth
    " is broken, we often restart.
    " IOW this issue will have almost no effect in practice.
    "}}}
    if getcmdtype() is# '>'
        return s:backward_kill_word(a:mode)
    else
        try
            return s:backward_kill_word(a:mode)
        catch
            return lg#catch_error()
        finally
            call setbufvar(bufnr, '&isk', isk_save)
        endtry
    endif
    return ''
endfu

fu s:backward_kill_word(mode) abort
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 0, 1)
    "          ┌ word before cursor{{{
    "          │
    "          │  ┌ there may be some non-word text between the word and the cursor
    "          │  │
    "          │  │                   ┌ the cursor
    "          ├─┐├──────────────────┐├──────────┐}}}
    let pat = '\k*\%(\%(\k\@!.\)\+\)\=\%'..pos..'c'

    let killed_text = matchstr(line, pat)
    call s:add_to_kill_ring(a:mode, killed_text, 0, 0)

    " Do *not* feed "BS" directly, because sometimes it would delete too much text.
    " It may happen when the cursor is after a sequence of whitespace (1 BS = &sw chars deleted).
    " Instead, feed "Left Del".
    return s:break_undo_before_deletions(a:mode)
        \  ..repeat((a:mode is# 'i' ? "\<c-g>U" : '').."\<left>\<del>",
        \           strchars(killed_text, 1))
endfu

fu readline#beginning_of_line(mode) abort "{{{2
    let s:concat_next_kill = 0
    return a:mode is# 'c'
       \ ?     "\<home>"
       \ : col('.') >= match(getline('.'), '\S') + 1
       \ ?     repeat("\<c-g>U\<left>", strchars(matchstr(getline('.'), '\S.*\%'..col('.')..'c'), 1))
       \ :     repeat("\<c-g>U\<right>", strchars(matchstr(getline('.'), '\%'..col('.')..'c\s*\ze\S'), 1))
endfu

fu readline#change_case_save(upcase) abort "{{{2
    let s:change_case_up = a:upcase
    return ''
endfu

fu readline#change_case_word(type, ...) abort "{{{2
    "                              ^ mode
    let [isk_save, bufnr] = [&l:isk, bufnr('%')]
    let mode = get(a:, '1', 'n')
    if getcmdtype() is# '>'
        return s:change_case_word(mode)
    else
        try
            return s:change_case_word(mode)
        catch
            return lg#catch_error()
        finally
            call setbufvar(bufnr, '&isk', isk_save)
        endtry
    endif
    return ''
endfu

fu s:change_case_word(mode) abort
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 1, 1)
    let pat = '\k*\%'..pos..'c\zs\%(\k\+\|.\{-}\<\k\+\>\|\%(\k\@!.\)\+\)'
    let word = matchstr(line, pat)
    let length = strchars(word, 1)

    if a:mode is# 'c'
        if pos > strlen(line)
            return ''
        else
            " we  can't return `Del`,  so we directly  feed the keys  to the
            " typeahead buffer
            call feedkeys(repeat("\<del>", length), 'in')
            return s:change_case_up ? toupper(word) : tolower(word)
        endif
    elseif a:mode is# 'i'
        return repeat("\<del>", length)..(s:change_case_up ? toupper(word) : tolower(word))
    elseif a:mode is# 'n'
        let new_line = substitute(line, pat, (s:change_case_up ? '\U' : '\L')..'\0', '')
        let new_pos  = match(line, pat..'\zs') + 1
        call setline('.', new_line)
        call cursor('.', new_pos)
    endif
    return ''
endfu

fu readline#delete_char(mode) abort "{{{2
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 1, 0)

    if a:mode is# 'c'
        " If the cursor is  at the end of the command-line, we  want C-d to keep
        " its normal behavior  which is to list names that  match the pattern in
        " front of the cursor.  However, if it's  before the end, we want C-d to
        " delete the character after it.

        if getcmdpos() <= strlen(getcmdline()) || getcmdtype() isnot# ':'
            call feedkeys("\<del>", 'in')
        else
            " Before pressing  `C-d`, we first  redraw to erase the  possible listed
            " completion suggestions. This makes consecutive listings more readable.
            " MWE:
            "       :h dir       C-d
            "       :h dire      C-d
            "       :h directory C-d
            redraw
            call feedkeys("\<c-d>", 'in')
        endif
        return ''
    endif

    "    - if the pum is visible, and there are enough matches to scroll a page down, scroll
    "    - otherwise, if we're *before* the end of the line, delete next character
    "    - "                   *at* the end of the line,     delete the newline
    let seq = pumvisible() && len(complete_info(['items']).items) > s:FAST_SCROLL_IN_PUM
        \ ?     repeat("\<c-n>", s:FAST_SCROLL_IN_PUM)
        \ : col('.') <= strlen(getline('.'))
        \ ?     "\<del>"
        \ :     "\<c-g>j\<home>\<bs>"
    call feedkeys(seq, 'in')
    return ''
endfu

fu readline#edit_and_execute_command() abort "{{{2
    let s:cedit_save = &cedit
    let &cedit = "\<c-x>"
    call feedkeys(&cedit, 'in')
    au CmdWinEnter * ++once let &cedit = s:cedit_save | unlet! s:cedit_save
    return ''
endfu

fu readline#end_of_line() abort "{{{2
    let s:concat_next_kill = 0
    return repeat("\<c-g>U\<right>", col('$') - col('.'))
endfu

fu readline#exchange_point_and_mark(mode) abort "{{{2
    let [line, pos] = s:setup_and_get_info(a:mode, 0, 0, 0)
    let new_pos = s:mark_{a:mode}

    if a:mode is# 'i'
        let old_pos = strchars(matchstr(line, '.*\%'..pos..'c'), 1)
        let motion = new_pos > old_pos
                 \ ?     "\<c-g>U\<right>"
                 \ :     "\<c-g>U\<left>"
    endif

    let s:mark_{a:mode} = strchars(matchstr(line, '.*\%'..pos..'c'), 1)
    return a:mode is# 'c'
       \ ?     "\<c-b>"..repeat("\<right>", new_pos)
       \ :     repeat(motion, abs(new_pos - old_pos))
endfu

fu readline#forward_char(mode) abort "{{{2
    let s:concat_next_kill = 0
    return a:mode is# 'c'
       \ ?    (wildmenumode() ? "\<space>\<c-h>" : '').."\<right>"
       \ : col('.') > strlen(getline('.'))
       \ ?     ''
       \ :     "\<c-g>U\<right>"
    " Go the right if we're in the middle of the line (custom), or fix the
    " indentation if we're at the end (default)
endfu

fu readline#kill_line(mode) abort "{{{2
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 0, 0)

    let killed_text = matchstr(line, '.*\%'..pos..'c\zs.*')
    call s:add_to_kill_ring(a:mode, killed_text, 1, 1)

    return s:break_undo_before_deletions(a:mode)
        \ ..repeat("\<del>", strchars(killed_text, 1))
endfu

fu readline#kill_word(mode) abort "{{{2
    let [isk_save, bufnr] = [&l:isk, bufnr('%')]
    if getcmdtype() is# '>'
        return s:kill_word(a:mode)
    else
        try
            return s:kill_word(a:mode)
        catch
            return lg#catch_error()
        finally
            call setbufvar(bufnr, '&isk', isk_save)
        endtry
    endif
    return ''
endfu

fu s:kill_word(mode) abort
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 0, 1)
    "          ┌ from the cursor until the end of the current word;{{{
    "          │ if the cursor is outside of a word, the pattern
    "          │ still matches, because we use `*`, not `+`
    "          │
    "          ├─────────────┐}}}
    let pat = '\k*\%'..pos..'c\zs\%(\k\+\|.\{-}\<\k\+\>\|\%(\k\@!.\)\+\)'
    "                               ├──┘  ├───────────┘  ├──────────┘{{{
    "                               │     │              └ or all the non-word text we're in
    "                               │     └ or the next word if we're outside of a word
    "                               └ the rest of the word after the cursor
    "}}}

    let killed_text = matchstr(line, pat)
    call s:add_to_kill_ring(a:mode, killed_text, 1, 0)

    return s:break_undo_before_deletions(a:mode)..repeat("\<del>", strchars(killed_text, 1))
endfu

fu readline#move_by_words(mode, ...) abort "{{{2
" Implementing this function was tricky, it has to handle:{{{
"
"    - multi-byte characters (éàî)
"    - multi-cell characters (tab)
"    - composing characters  ( ́)
"}}}

    let [isk_save, bufnr] = [&l:isk, bufnr('%')]
    if getcmdtype() is# '>'
        return call('s:move_by_words', [a:mode] + a:000)
    else
        try
            return call('s:move_by_words', [a:mode] + a:000)
        " the `catch` clause prevents errors from being echoed
        " if you try to throw the exception manually (echo v:exception, echo
        " v:throwpoint), nothing will be displayed, so don't bother
        catch
            return lg#catch_error()
        finally
            call setbufvar(bufnr, '&isk', isk_save)
        endtry
    endif
    return ''
endfu

fu s:move_by_words(mode, ...) abort
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
        let pat = '.*\%'..pos..'c\%(.\{-1,}\>\|.*\)'
        "                                      │
        "     if there's no word where we are, ┘
        " nor after us, then go on until the end of the line
    else
        " all characters from the beginning of the line until the first
        " character of the nearest *previous* word (current one if we're in a
        " word, or somewhere *before* otherwise)
        let pat = '.*\ze\<.\{-1,}\%'..pos..'c'
    endif
    let str = matchstr(line, pat)
    let new_pos = len(str)

    let new_pos_char = strchars(str, 1)
    " pos_char     = nr of characters before cursor in its current position
    " new_pos_char = "                                         new     "

    " necessary to move correctly on a line such as:
    "          ́ foo  ́ bar
    let pos_char = strchars(matchstr(line, '.*\%'..pos..'c'), 1)
    "                                                         │
    "                                                         └ ignore composing characters

    let diff = pos_char - new_pos_char
    let building_motion = mode is# 'i'
                      \ ?     diff > 0 ? "\<c-g>U\<left>" : "\<c-g>U\<right>"
                      \ :     diff > 0 ? "\<left>" : "\<right>"

    " Here's how it works in readline:{{{
    "
    "    1. it looks for the keyword character after the cursor
    "
    "       The latter could be right after, or further away.
    "       Which means the capitalization doesn't necessarily uppercase
    "       the first character of a word.
    "
    "    2. it replaces it with its uppercase counterpart
    "
    "    3. it replaces all subsequent characters until a non-keyword character
    "       with their lowercase counterparts
    "}}}
    if capitalize
        let new_line = substitute(line,
            \ '\%'..pos..'c.\{-}\zs\(\k\)\(.\{-}\)\%'..(new_pos+1)..'c',
            \ '\u\1\L\2', '')
        if mode is# 'c'
            let seq = "\<c-e>\<c-u>"..new_line.."\<c-b>"..repeat("\<right>", new_pos_char)
            call feedkeys(seq, 'in')
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
        \ : feedkeys(seq, 'in')[-1]
endfu

fu readline#set_mark(mode) abort "{{{2
    let s:mark_{a:mode} = a:mode is# 'i'
                      \ ?     strchars(matchstr(getline('.'), '.*\%'..col('.')..'c'), 1)
                      \ :     strchars(matchstr(getcmdline(), '.*\%'..getcmdpos()..'c'), 1)
    return ''
endfu

fu readline#transpose_chars(mode) abort "{{{2
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 1, 0)
    if pos > strlen(line)
        " We use `matchstr()` because of potential multi-byte characters.
        " Test on this:
        "
        "     âêîôû
        return a:mode is# 'i'
           \ ?     "\<c-g>U\<left>\<bs>\<c-g>U\<right>"..matchstr(line, '.\ze.\%'..pos..'c')
           \ :     "\<left>\<bs>\<right>"..matchstr(line, '.\ze.\%'..pos..'c')

    elseif pos > 1
        return a:mode is# 'i'
           \ ?     "\<bs>\<c-g>U\<right>"..matchstr(line, '.\%'..pos..'c')
           \ :     "\<bs>\<right>"..matchstr(line, '.\%'..pos..'c')

    else
        return ''
    endif
endfu

fu readline#transpose_words(type, ...) abort "{{{2
    "                             ^
    "                             mode
    let [isk_save, bufnr] = [&l:isk, bufnr('%')]
    let mode = get(a:, '1', 'n')
    if getcmdtype() is# '>'
        return s:transpose_words(mode)
    else
        try
            return s:transpose_words(mode)
        catch
            return lg#catch_error()
        finally
            call setbufvar(bufnr, '&isk', isk_save)
        endtry
    endif
    return ''
endfu

fu s:transpose_words(mode) abort
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 1, 1)
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
    let pat = '\(\<\k\+\>\)\(\%(\k\@!.\)\+\)\(\<\k\+\>\)'

    " What's this concat (\&) for?{{{
    "
    " It will be used  at the end, once Vim thinks it has  found a match for
    " two words.
    " It checks that the cursor isn't on the first word. For example, the
    " cursor being represented by the bar:
    "
    "     e|cho foo
    "
    " ... there should be no transposition (to mimic readline)
    "}}}
    let not_on_first = '\%(\<\k*\%'..pos..'c\k\+\>\)\@!\&'

    " The cursor must not be before the 2 words:{{{
    "
    "         foo | bar baz
    "               ├─────┘
    "               └ don't transpose those 2
    "}}}
    let not_before = '\%(\%'..pos..'c.*\)\@<!'

    " The cursor must not be after the 2 words,{{{
    " unless it is  inside a sequence of non-words characters  at the end of
    " the line:
    "
    "     foo bar | baz
    "     ├─────┘
    "     └ don't transpose those 2
    "
    " *or*  it is  after  them,  *but* there  are  only non-word  characters
    " between them and the end of the line:
    "
    "     foo bar !?`,;:.
    "            ├──────┘
    "            └ the cursor may be anywhere in here
    "}}}
    let not_after = '\%(\%(.*\%'..pos..'c\)\@!\|\%(\%(\k\@!.\)*$\)\@=\)'

    " final pattern
    let pat = not_on_first..not_before..pat..not_after

    let new_pos = strchars(matchstr(line, '.*\%('..pat..'\)'), 1)
    let rep = '\3\2\1'
    let new_line = substitute(line, pat, rep, '')

    if a:mode is# 'c'
        let seq = "\<c-e>\<c-u>"
            \ ..new_line
            \ .."\<c-b>"..repeat("\<right>", new_pos)
        call feedkeys(seq, 'in')
    else
        call setline('.', new_line)
        call cursor('.', new_pos+1)
    endif
    return ''
endfu

fu readline#undo(mode) abort "{{{2
    if empty(s:undolist_{a:mode})
        return ''
    endif
    let [old_line, old_pos] = remove(s:undolist_{a:mode}, -1)
    fu! s:undo_restore_cursor() closure
        if a:mode is# 'c'
            call feedkeys("\<c-b>"..repeat("\<right>", old_pos), 'in')
        else
            exe 'norm! '..(old_pos+1)..'|'
        endif
    endfu
    if a:mode is# 'c'
        au CmdlineChanged * ++once call s:undo_restore_cursor()
        return old_line
    else
        au TextChangedI * ++once call s:undo_restore_cursor()
        call setline('.', old_line)
    endif
    return ''
endfu

fu readline#unix_line_discard(mode) abort "{{{2
    if pumvisible() && len(complete_info(['items']).items) > s:FAST_SCROLL_IN_PUM
        return repeat("\<c-p>", s:FAST_SCROLL_IN_PUM)
    endif

    let [line, pos] = s:setup_and_get_info(a:mode, 1, 0, 0)

    if a:mode is# 'c'
        call s:add_to_kill_ring(a:mode, matchstr(line, '.*\%'..pos..'c'), 0, 1)
    else
        let old_line = matchstr(line, '.*\%'..pos..'c')
        fu! s:add_deleted_text_to_kill_ring() abort closure
            let new_line = matchstr(getline('.'), '.*\%'..col('.')..'c')
            call s:add_to_kill_ring('i', substitute(old_line, '\V'..escape(new_line, '\'), '', ''), 0, 1)
        endfu
        au TextChangedI * ++once call s:add_deleted_text_to_kill_ring()
    endif
    return s:break_undo_before_deletions(a:mode).."\<c-u>"
endfu

fu readline#yank(mode, pop) abort "{{{2
    if pumvisible() | return "\<c-y>" | endif
    if a:pop && (! s:cm_y || len(s:kill_ring_{a:mode}) < 2) | return '' | endif

    " set flag telling that `C-y` or `M-y` has just been pressed
    let s:cm_y = 1
    let [line, pos] = s:setup_and_get_info(a:mode, 1, 1, 0)
    if a:pop
        let length = strchars(s:kill_ring_{a:mode}[-1], 1)
        call insert(s:kill_ring_{a:mode}, remove(s:kill_ring_{a:mode}, -1), 0)
    endif
    if exists('#reset_cm_y')
        au! reset_cm_y
        aug! reset_cm_y
    endif
    au SafeState * ++once call s:reset_cm_y()
    let @- = s:kill_ring_{a:mode}[-1]
    return (a:pop
    \       ?    repeat((a:mode is# 'i' ? "\<c-g>U" : '').."\<left>\<del>", length)
    \       :    '')
    \       .."\<c-r>-"
endfu

fu s:reset_cm_y() abort
    " In the shell, as soon as you move the cursor, `M-y` doesn't do anything anymore.
    " We want the same behavior in Vim.
    augroup reset_cm_y
        au!
        " Do *not* use a long list of events (`CursorMovedI`, `CmdlineChanged`, ...).{{{
        "
        "     au CursorMovedI,CmdlineChanged,InsertLeave,CursorMoved *
        "
        " It would not be as reliable as `SafeState`.
        " E.g., when you  move your cursor on the command-line,  the flag should
        " be reset, but there is no `CmdlineMoved` event.
        " Besides, finding the  right list of events may be  tricky; you have to
        " consider special cases, such as pressing `C-c` to leave insert mode.
        "}}}
        au SafeState * ++once let s:cm_y = 0
    augroup END
endfu
"}}}1
" Util {{{1
fu s:add_to_kill_ring(mode, text, after, this_kill_is_big) abort "{{{2
    if s:concat_next_kill
        let s:kill_ring_{a:mode}[-1] = a:after
                                   \ ?     s:kill_ring_{a:mode}[-1]..a:text
                                   \ :     a:text..s:kill_ring_{a:mode}[-1]
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
            call filter(s:kill_ring_{a:mode}, {_,v -> v isnot# a:text})
            call add(s:kill_ring_{a:mode}, a:text)
        endif
    endif
    call s:set_concat_next_kill(a:mode, a:this_kill_is_big)
endfu

fu s:break_undo_before_deletions(mode) abort "{{{2
    if a:mode is# 'c' || s:deleting
        return ''
    else
        " If  the execution  has reached  this point,  it means  we're going  to
        " delete some multi-char text. But, if we delete another multi-char text
        " right after, we don't want to, again, break the undo sequence.
        let s:deleting = 1
        " We'll re-enable the  breaking of the undo sequence  before a deletion,
        " the next time we insert a character, or leave insert mode.
        augroup readline_reset_deleting
            au!
            au InsertLeave,InsertCharPre * exe 'au! readline_reset_deleting' | let s:deleting = 0
        augroup END
        return "\<c-g>u"
    endif
endfu
" Purpose:{{{
"
"    - A is a text we insert
"    - B is a text we insert after A
"    - C is a text we insert to replace B after deleting the latter
"
" Without any custom “granular undo“, we can only visit:
"
"    - ∅
"    - AC
"
" This function presses `C-g  u` the first time we delete  a multi-char text, in
" any given sequence of multi-char deletions.
" This allows us to visit AB.
" In the past, we used some code, which broke the undo sequence after a sequence
" of  deletions. It allowed  us to  visit A  (alone). We don't  use it  anymore,
" because it leads to too many issues.
"}}}

fu s:set_concat_next_kill(mode, this_kill_is_big) abort "{{{2
    let s:concat_next_kill  = a:this_kill_is_big && s:last_kill_was_big ? 0 : 1
    let s:last_kill_was_big = a:this_kill_is_big

    if a:mode is# 'c'
        " Why?{{{
        "
        " After  the next  deletion, it  the command-line  gets empty,  the deletion
        " after that shouldn't be concatenated:
        "
        "     :one C-u
        "     :two C-w
        "     C-y
        "     twoone    ✘~
        "     two       ✔~
        "}}}
        au CmdlineChanged * ++once if getcmdline() =~# '^\s*$' | execute('let s:concat_next_kill = 0') | endif
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
    augroup readline_reset_concat_next_kill
        au!
        au InsertCharPre,InsertEnter,InsertLeave *
            \   exe 'au! readline_reset_concat_next_kill'
            \ | let s:concat_next_kill = 0
    augroup END
endfu

fu s:set_isk() abort "{{{2
    " Why re-setting 'isk'?{{{
    "
    " readline doesn't consider `-`, `#`, `_` as part of a word,
    " contrary to Vim which may disagree for some of them.
    "
    " Removing them from 'isk' allows us to operate on the following “words“:
    "
    "     foo-bar
    "     foo#bar
    "     foo_bar
    "}}}
    " Why not using `-=` instead of `=`?{{{
    "
    " Previously, we used this code:
    "
    "     setl isk-=_ isk-=- isk-=#
    "
    " But sometimes, the mapping behaved strangely.
    " So now, I prefer to give an explicit value to `isk`.
    "
    "}}}
    setl isk=@,48-57,192-255
endfu

fu s:setup_and_get_info(mode, add_to_undolist, reset_concat, set_isk) abort "{{{2
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

