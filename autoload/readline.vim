if exists('g:autoloaded_readline')
    finish
endif
let g:autoloaded_readline = 1

" Autocmds {{{1

augroup my_granular_undo
    au!
    au InsertEnter   * let s:deleting = 0
    au InsertCharPre * call s:break_undo_after_deletions(v:char)
augroup END

" Functions {{{1
fu! readline#backward_char(mode) abort "{{{2
    let s:concat_next_kill = 0

    " SPC + C-h = close wildmenu
    return a:mode ==# 'i'
    \?         "\<c-g>U\<left>"
    \:         (wildmenumode() ? "\<space>\<c-h>" : '')."\<left>"
endfu

fu! readline#backward_kill_word(mode) abort "{{{2
    let isk_save = &l:isk
    try
        call s:set_isk()

        let [ line, pos ] = s:get_line_pos(a:mode)

        "              ┌ word before cursor
        "              │            ┌ there may be some non-word text between the word and the cursor
        "              │            │         ┌ the cursor
        "            ┌─┤┌───────────┤┌────────┤
        let pat = '\v\k*%(%(\k@!.)+)?%'.pos.'c'

        let killed_text     = matchstr(line, pat)
        let s:kill_ring_top = killed_text.(s:concat_next_kill ? s:kill_ring_top : '')
        call s:set_concat_next_kill(a:mode, 0)

        " Do NOT feed "BS" directly, because sometimes it would delete too much text.
        " It may happen when the cursor is after a sequence of whitespace (1 BS = &sw chars deleted).
        " Instead, feed "Left Del".
        return s:break_undo_before_deletions(a:mode)
        \     .repeat((a:mode ==# 'i' ? "\<c-g>U" : '')."\<left>\<del>",
        \             strchars(killed_text, 1)
        \            )
    catch
    finally
        let &l:isk = isk_save
    endtry
endfu

fu! readline#beginning_of_line(mode) abort "{{{2
    let s:concat_next_kill = 0
    return a:mode ==# 'c'
    \?         "\<home>"
    \:     col('.') >= match(getline('.'), '\S') + 1
    \?         repeat("\<c-g>U\<left>", col('.') - match(getline('.'), '\S') - 1)
    \:         repeat("\<c-g>U\<right>", match(getline('.'), '\S') - col('.') + 1)
endfu

fu! s:break_undo_after_deletions(char) abort "{{{2
    if s:deleting
        " To exclude  the first  inserted character from  the undo  sequence, we
        " should call `feedkeys()` like this:
        "
        "         call feedkeys("\<bs>\<c-g>u".v:char, 'in')
        " Why "\<bs>" ?{{{
        "
        " It  seems that  when InsertCharPre  occurs, v:char  is already  in the
        " typeahead buffer. We  can change its  value but not insert  sth before
        " it.   We need  to break  undo sequence  BEFORE `v:char`,  so that  the
        " latter is part of the next edition.
        " Thus, we delete it (BS), break undo (C-g u), then reinsert it (v:char).
        "}}}
        " Why pass the 'i' flag to feedkeys(…)?{{{
        "
        " Suppose we don't give 'i', and we have this mapping:
        "                               ino abc def
        "
        " Then we write:                hello foo
        " We delete foo with C-w:       hello
        " If we type abc, we'll get:    hello ded
        "
        " Why ded and not def?
        "
        "   1. a b c                 keys which are typed initially
        "
        "   2. d e f                 expansion due to mapping
        "
        "                                    • the expansion occurs as soon as we type `c`
        "
        "                                    • InsertCharPre occurs right after `d` is written
        "                                      into the typeahead buffer
        "
        "                                    • v:char is `d`, the 1st character to be inserted
        "
        "   3. d e f BS C-g u d      the 4 last keys are written by `feedkeys()`
        "                            AT THE END of the typeahead buffer
        "
        "   4. d e d                 ✘
        "
        " The 4 last keys were added too late.
        " The solution is to insert them at the beginning of the typeahead buffer,
        " by giving the 'i' flag to feedkeys(…). The 3rd step then becomes:
        "
        "                     ┌ expansion of `abc`
        "      ┌──────────────┤
        "   3. d BS C-g u d e f
        "        └────────┤
        "                 └ inserted by our custom function when `InsertCharPre` occurs
"}}}

        " FIXME:
        " But we won't try to exclude it:
        call feedkeys("\<c-g>u", 'int')
        " Why?{{{
        "
        " To be  sure that the  contents of a register  we put from  insert mode
        " will never be altered.
        "}}}
        " When could it be altered?{{{
        "
        " If you delete  some text, with `C-w` for example,  then put a register
        " whose contents is 'hello', you will insert 'hellh':
        "
        "         C-w C-r "
        "                     → hellh
        "                           ^✘
        "}}}
        " Why does it happen?{{{
        "
        " If you copy the text 'abc' in the unnamed register, then put it:
        "
        "         C-r "
        "
        " … it triggers 3 InsertCharPre:
        "
        "         • v:char = 'a'
        "         • v:char = 'b'
        "         • v:char = 'c'
        "
        " When the 1st one is triggered, and `feedkeys()` is invoked to add some
        " keys in the typeahead buffer, they are inserted AFTER `bc`.
        " This seems to indicate that when  you put a register, all its contents
        " is  immediately written  in  the  typeahead buffer. The  InsertCharPre
        " events are fired AFTERWARDS for each inserted character.
        "
        " We  can  still   reliably  change  any  inserted   key,  by  resetting
        " `v:char`. The issue is specific to feedkeys().
        " Unfortunately,  we have  to  use feedkeys(),  because  we can't  write
        " special characters  in `v:char`,  like `BS` and  `C-g`; they  would be
        " inserted literally.
        "
        " Watch:
        " the goal being to replace any `a` with `x`:
        "
        "         augroup replace_a_with_x
        "             au!
        "             au InsertCharPre * call Func()
        "         augroup END
        "
        "         fu! Func() abort
        "             if v:char ==# 'a'
        "                 " ✔
        "                 " let v:char = 'x'
        "                 " ✘ fails when putting a register containing `abc`
        "                 " call feedkeys("\<bs>x", 'int')
        "             endif
        "         endfu
        "}}}
        let s:deleting = 0
    endif
endfu

fu! s:break_undo_before_deletions(mode) abort "{{{2
    if a:mode ==# 'c' || s:deleting
        return ''
    else
        let s:deleting = 1
        return "\<c-g>u"
    endif
endfu

" Purpose:{{{
"
" By default, when we delete some words with C-w in insert mode, if we
" escape to go in normal mode, realise it was a mistake, and hit u to undo,
" we can't get back our deleted words because they are part of a single
" edition. Thus, u and C-r can get us back before or after that single
" edition, but not somewhere in the middle where our deleted words are.
" To fix this, we define the following mappings which breaks the undo sequence:
"
"         • before we delete a word (C-w)
"           to be able to recover the word
"
"         • before we delete the line (C-u)
"           to be able to recover the line
"
"         • after a sequence of deletions (with C-w/C-u),
"           followed by the insertion of a character,
"           to be able to re-perform these deletions,
"           useful if we want to get rid of the text we've inserted afterwards.
"
" Whenever we go into insert mode, we reset `s:deleting` to 0.
" When it's 1, it means the last key pressed was C-w/C-u.
" When it's 0, it means the last key pressed was something else.
"}}}

fu! readline#delete_char(mode) abort "{{{2
    let s:concat_next_kill = 0
    if a:mode ==# 'c'
        " If the cursor is  at the end of the command line, we  want C-d to keep
        " its normal behavior  which is to list names that  match the pattern in
        " front of the cursor.  However, if it's  before the end, we want C-d to
        " delete the character after it.
        return getcmdpos() > strlen(getcmdline()) ? "\<c-d>" : "\<del>"
    endif

    " If the popup menu is visible, scroll a page down.
    " If no menu, and we're BEFORE the end of the line,   delete next character.
    " "                     AT the end of the line,       delete the newline.
    if pumvisible()
        let l:key = repeat("\<c-n>", s:fast_scroll_in_pum)

    elseif col('.') <= strlen(getline('.'))
        let l:key = "\<del>"

    elseif col('.') > strlen(getline('.'))
        let l:key = "\<c-g>j\<home>\<bs>"
    endif

    return l:key
endfu

fu! readline#end_of_line() abort "{{{2
    let s:concat_next_kill = 0
    return repeat("\<c-g>U\<right>", col('$') - col('.'))
endfu

fu! readline#forward_char(mode) abort "{{{2
    let s:concat_next_kill = 0
    return a:mode ==# 'c'
    \?         "\<right>"
    \:     col('.') > strlen(getline('.'))
    \?         "\<c-f>"
    \:         "\<c-g>U\<right>"
    " Go the right if we're in the middle of the line (custom), or fix the
    " indentation if we're at the end (default)
endfu

fu! s:get_line_pos(mode) abort "{{{2
    let [ line, pos ] = a:mode ==# 'c'
    \?                      [ getcmdline(), getcmdpos() ]
    \:                      [ getline('.'), col('.') ]

    return [ line, pos ]
endfu

fu! readline#kill_line(mode) abort "{{{2
    let [ line, pos ] = s:get_line_pos(a:mode)

    let killed_text     = matchstr(line, '.*\%'.pos.'c\zs.*')
    let s:kill_ring_top = killed_text.(s:concat_next_kill ? s:kill_ring_top : '')
    call s:set_concat_next_kill(a:mode, 1)

    return s:break_undo_before_deletions(a:mode)
    \     .repeat("\<del>", strchars(killed_text, 1))
endfu

fu! readline#kill_word(mode) abort "{{{2
    let isk_save = &l:isk
    try
        call s:set_isk()

        let [ line, pos ] = s:get_line_pos(a:mode)

        "                       ┌ from the beginning of the word containing the cursor
        "                       │ until the cursor
        "                       │ if the cursor is outside of a word, the pattern
        "                       │ still matches, because we use `*`, not `+`
        "            ┌──────────┤
        let pat = '\v\k*%'.pos.'c\zs%(\k+|.{-}<\k+>|%(\k@!.)+)'
        "                             └─┤ └───────┤ └───────┤
        "                               │         │         └ or all the non-word text we're in
        "                               │         └───────── or the next word if we're outside of a word
        "                               └─────────────────── the rest of the word after the cursor

        let killed_text     = matchstr(line, pat)
        let s:kill_ring_top = (s:concat_next_kill ? s:kill_ring_top : '').killed_text
        call s:set_concat_next_kill(a:mode, 0)

        return s:break_undo_before_deletions(a:mode).repeat("\<del>", strchars(killed_text, 1))

    catch
    finally
        let &l:isk = isk_save
    endtry
endfu

fu! readline#move_by_words(fwd, mode) abort "{{{2
" NOTE:
" Implementing this function was tricky, it has to handle:
"
"    • multi-byte characters (éàî)
"    • multi-cell characters (tab)
"    • composing characters  ( ́)

    let isk_save = &l:isk
    try
        let s:concat_next_kill = 0
        call s:set_isk()

        let [ line, pos ] = s:get_line_pos(a:mode)

        " old_char_idx = nr of characters before cursor in its current position
        " new_char_idx = "                                         new     "

        "                               ignore composing characters ┐
        " necessary to move correctly on a line such as:            │
        "          ́ foo  ́ bar  ́                                     │
        let old_char_idx = strchars(matchstr(line, '.*\%'.pos.'c'), 1)

        if a:fwd
            " all characters from the beginning of the line until the last
            " character of the nearest NEXT word (current one if we're in a word,
            " or somewhere AFTER otherwise)
            let pat = '\v.*%'.pos.'c%(.{-1,}>\ze|.*)'
            "                                    │
            "   if there's no word where we are, ┘
            " nor after us, then go on until the end of the line
            let new_char_idx = strchars(matchstr(line, pat), 1)
        else
            " all characters from the beginning of the line until the first
            " character of the nearest PREVIOUS word (current one if we're in a
            " word, or somewhere BEFORE otherwise)
            let pat          = '\v.*\ze<.{-1,}%'.pos.'c'
            let new_char_idx = strchars(matchstr(line, pat), 1)
        endif

        let diff = old_char_idx - new_char_idx
        let building_motion = a:mode ==# 'i'
        \?                        diff > 0 ? "\<c-g>U\<left>" : "\<c-g>U\<right>"
        \:                    a:mode ==# 'c'
        \?                        diff > 0 ? "\<left>" : "\<right>"
        \:                        diff > 0 ? "\<c-b>"  : "\<c-f>"

        return repeat(building_motion, abs(diff))

    " the `catch` clause prevents errors from being echoed
    " if you try to throw the exception manually (echo v:exception, echo
    " v:throwpoint), nothing will be displayed, so don't bother
    catch
    finally
        let &l:isk = isk_save
    endtry
    return ''
endfu

fu! s:set_concat_next_kill(mode, this_kill_is_big) abort "{{{2
    let s:concat_next_kill  = a:this_kill_is_big && s:last_kill_was_big ? 0 : 1
    let s:last_kill_was_big = a:this_kill_is_big
    if a:mode ==# 'c'
        return
    endif

    " If we delete a multi-char text, then  move the cursor OR insert some text,
    " then re-delete  a multi-char  text the  2 multi-char  texts should  NOT be
    " concatenated.
    "
    " FIXME:
    " We should make the autocmd listen  to CursorMovedI, but it would, wrongly,
    " reset `s:concat_next_kill`  when we  delete a  2nd multi-char  text right
    " after a 1st one.
    augroup reset_concatenate_kills
        au!
        au InsertCharPre,InsertEnter,InsertLeave *
        \      let s:concat_next_kill = 0
        \|     exe 'au! reset_concatenate_kills'
        \|     aug! reset_concatenate_kills
    augroup END
endfu

fu! s:set_isk() abort "{{{2
    " readline doesn't consider `-`, `#`, `_` as part of a word,
    " contrary to Vim which may disagree for some of them.
    "
    " Removing them from 'isk' allows us to operate on the following “words“:
    "
    "         foo-bar
    "         foo#bar
    "         foo_bar

    " Previously, we used this code:
    "         setl isk-=_ isk-=- isk-=#
    "
    " But sometimes, the mapping behaved strangely.
    " So now, I prefer to give an explicit value to `isk`.

    setl isk=@,48-57,192-255
endfu

fu! readline#transpose_chars(mode) abort "{{{2
    let [ pos, line ] = a:mode ==# 'i'
    \?                      [ col('.'), getline('.') ]
    \:                      [ getcmdpos(), getcmdline() ]

    let s:concat_next_kill = 0
    if pos > strlen(line)
        " We use `matchstr()` because of potential multibyte characters.
        " Test on this:
        "
        "     âêîôû
        return a:mode ==# 'i'
        \?         "\<c-g>U\<left>\<bs>\<c-g>U\<right>".matchstr(line, '.\ze.\%'.pos.'c')
        \:         "\<left>\<bs>\<right>".matchstr(line, '.\ze.\%'.pos.'c')

    elseif pos > 1
        return a:mode ==# 'i'
        \?         "\<bs>\<c-g>U\<right>".matchstr(line, '.\%'.pos.'c')
        \:         "\<bs>\<right>".matchstr(line, '.\%'.pos.'c')

    else
        return ''
    endif
endfu

fu! readline#transpose_words(mode) abort "{{{2
    let isk_save = &l:isk
    try
        let s:concat_next_kill = 0
        call s:set_isk()

        let [ line, pos ] = s:get_line_pos(a:mode)

        " We're looking for 2 words which are separated by non-word characters.
        "
        " Why non-word characters, and not whitespace?
        " Because transposition works even when 2 words are separated by special
        " characters such as backticks:
        "
        "     foo``|``bar    ⇒    bar````foo
        "          ^
        "          cursor
        let pat = '(<\k+>)(%(\k@!.)+)(<\k+>)'

        " This concat will be used at the end, once Vim thinks it has found
        " a match for 2 words.
        " It checks that the cursor isn't on the first word. For example, the
        " cursor being represented by the pipe:
        "
        "                 e|cho foo
        "
        " … there should be no transposition (to mimic readline)
        let not_on_first = '\v%(<\k*%'.pos.'c\k+>)@!&'

        " The cursor mustn't be before the 2 words:
        "
        "         foo | bar baz
        "               └─────┤
        "                     └ don't transpose those 2
        let not_before = '%(%'.pos.'c.*)@<!'

        " The cursor mustn't be after the 2 words, unless it is inside
        " a sequence of non-words characters at the end of the line:
        "
        "         foo bar | baz
        "         └─────┤
        "               └ don't transpose those 2
        let not_after = '%(%(.*%'.pos.'c)@!|%(%(\k@!.)*$)@=)'
        " OR it is after them, BUT there are only non-word characters between
        " them and the end of the line
        "
        "         foo bar !?`,;:.
        "                └──────┤
        "                       └ the cursor may be anywhere in here

        " final pattern
        let pat = not_on_first.not_before.pat.not_after

        let new_pos  = match(line, pat.'\zs')+1
        let rep      = '\3\2\1'
        let new_line = substitute(line, pat, rep, '')

        if a:mode ==# 'c'
            call setcmdpos(new_pos)
            return new_line
        else
            call setline(line('.'), new_line)
            call cursor(line('.'), new_pos)
            if a:mode ==# 'n'
                sil! call repeat#set("\<plug>(transpose_words)")
            endif
            return ''
        endif

    catch
        return 'echoerr '.string(v:exception)

    finally
        let &l:isk = isk_save
    endtry

    return ''
endfu

fu! readline#unix_line_discard(mode) abort "{{{2
    if pumvisible()
        return repeat("\<c-p>", s:fast_scroll_in_pum)
    endif

    let [ line, pos ] = s:get_line_pos(a:mode)

    if a:mode ==# 'c'
        let s:kill_ring_top = matchstr(line, '.*\%'.pos.'c').(s:concat_next_kill ? s:kill_ring_top : '')
        call s:set_concat_next_kill(a:mode, 1)
    else
        let s:mode = a:mode
        let s:before_cursor = matchstr(line, '.*\%'.pos.'c')
        call timer_start(0, {-> execute('  let s:kill_ring_top = substitute(s:before_cursor,
        \                                                                   matchstr(getline("."),
        \                                                                            ".*\\%".col(".")."c"),
        \                                                                   "", "")
        \                                          .(s:concat_next_kill ? s:kill_ring_top : "")
        \                                | call s:set_concat_next_kill(s:mode, 1)
        \                               ')
        \                   })
    endif
    return s:break_undo_before_deletions(a:mode)."\<c-u>"
endfu

fu! readline#upcase_word(mode) abort "{{{2
    let isk_save = &l:isk
    try
        let s:concat_next_kill = 0
        call s:set_isk()

        let [ line, pos ] = s:get_line_pos(a:mode)

        let pat      = '\v\k*%'.pos.'c\zs%(\k+|.{-}<\k+>|%(\k@!.)+)'
        let new_line = substitute(line, pat, '\U\0', '')
        let new_pos  = match(line, pat.'\zs') + 1

        if a:mode ==# 'c'
            call setcmdpos(new_pos)
            if pos > strlen(line)
                return line
            else
                return new_line
            endif
        else
            call setline(line('.'), new_line)
            call cursor(line('.'), new_pos)
            if a:mode ==# 'n'
                sil! call repeat#set("\<plug>(upcase_word)")
            endif
            return ''
        endif

    catch
        echohl ErrorMsg
        echo v:exception.' | '.v:throwpoint
        echohl NONE
    finally
        let &l:isk = isk_save
    endtry

    return ''
endfu
fu! readline#yank() abort "{{{2
    let s:concat_next_kill = 0
    let @- = s:kill_ring_top
    return "\<c-r>-"
endfu

" Variables {{{1

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
let s:last_kill_was_big  = 0

let s:concat_next_kill   = 0
let s:fast_scroll_in_pum = 5
let s:kill_ring_top      = ''

" The autocmd will be installed the 1st time we use one of our mapping.
" So, the first time we enter insert  mode, and press a custom mapping, it won't
" have been installed, and `s:deleting` won't have been set yet.
" But for our functions to work, it must exist no matter what.
let s:deleting = 0
