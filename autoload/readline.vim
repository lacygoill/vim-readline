if exists('g:autoloaded_readline')
    finish
endif
let g:autoloaded_readline = 1

fu! readline#backward_kill_word(mode) abort "{{{1
    let isk_save = &l:isk
    try
        call s:set_isk()

        let [ line, pos ] = s:get_line_pos(a:mode)

        "              ┌ word before cursor
        "              │            ┌ there may be some non-word text between the word and the cursor
        "              │            │         ┌ the cursor
        "            ┌─┤┌───────────┤┌────────┤
        let pat = '\v\k*%(%(\k@!.)+)?%'.pos.'c'
        " Do NOT feed "BS" directly, because sometimes it would delete too much text.
        " It may happen when the cursor is after a sequence of whitespace (1 BS = &sw chars deleted).
        " Instead, feed "Left Del".
        return repeat("\<c-g>U\<left>\<del>", strchars(matchstr(line, pat), 1))
    catch
    finally
        let &l:isk = isk_save
    endtry
endfu

fu! s:get_line_pos(mode) abort "{{{1
    let [ line, pos ] = a:mode ==# 'c'
    \?                      [ getcmdline(), getcmdpos() ]
    \:                      [ getline('.'), col('.') ]

    return [ line, pos ]
endfu

fu! readline#insert_c_d() abort "{{{1
    if pumvisible()
        let l:key = repeat("\<c-n>", 5)

    elseif col('.') <= strlen(getline('.'))
        let l:key = "\<del>"

    elseif col('.') > strlen(getline('.'))
        let l:key = "\<c-g>j\<home>\<bs>"
    endif

    return l:key
endfu

fu! readline#kill_word(mode) abort "{{{1
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

    return repeat("\<del>", strchars(matchstr(line, pat), 1))

    catch
    finally
        let &l:isk = isk_save
    endtry
endfu

fu! readline#move_by_words(fwd, mode) abort "{{{1
" NOTE:
" Implementing this function was tricky, it has to handle:
"
"    • multi-byte characters (éàî)
"    • multi-cell characters (tab)
"    • composing characters  ( ́)

    let isk_save = &l:isk
    try
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

fu! s:set_isk() abort "{{{1
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

fu! readline#transpose_chars(mode) abort "{{{1
    let [ pos, line ] = a:mode ==# 'i'
    \?                      [ col('.'), getline('.') ]
    \:                      [ getcmdpos(), getcmdline() ]

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

fu! readline#transpose_words(mode) abort "{{{1
    let isk_save = &l:isk
    try
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

fu! readline#upcase_word(mode) abort "{{{1
    let isk_save = &l:isk
    try
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
