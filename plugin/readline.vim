if exists('g:loaded_readline')
    finish
endif
let g:loaded_readline = 1


if !has('nvim')
    " FIXME:
    " This mapping allows us  to use keys whose 1st keycode  is escape (left, right,
    " M-…) as the lhs of other mappings. How does it work? Why is it necessary?
    tno <esc><c-a> <esc><c-a>

    " don't use `c-w` as a prefix to execute special commands in a terminal window
    " `c-w` should delete the previous word
    " use `c-o` instead
    set termkey=<c-o>
endif


" KEYSYMS {{{1

" On my machine, Vim doesn't know what are the right keycodes produced by
" certains keysyms such as `M-b`.
" It probably knows something, but it's wrong.
" For example, it thinks that the keysym `M-b` is produced by `â`.
" Which is confirmed if we just write this mapping:
"
"     ino <M-b> hello
"
" … then try to insert `â`. It will insert `hello`.
" But Vim doesn't really know what's `M-b`, because if we `M-b` in insert
" mode, it doesn't insert `hello`, it just escapes to normal mode then go back
" a word.
" We need to teach it the correct keycodes which are produced by `M-b`.
" To find the keycodes, insert the keysym literally (ex: C-v M-b).
"
" We do the same thing for other keysyms following the pattern `M-{char}`.
"
" Why do we test whether we are in a terminal and not in gVim?
" Because gVim already knows these keysyms. No need to teach it.
" Besides, when we hit M-{char}, we don't know whether gVim receives the same
" keycodes as Vim in a terminal.

if !has('gui_running') && !has('nvim')
    exe "set <M-a>=\ea"
    exe "set <M-b>=\eb"
    exe "set <M-d>=\ed"
    exe "set <M-e>=\ee"
    exe "set <M-f>=\ef"
    exe "set <M-m>=\em"
    exe "set <M-n>=\en"
    exe "set <M-p>=\ep"
    exe "set <M-s>=\es"
    exe "set <M-t>=\et"
    exe "set <M-u>=\eu"
    exe "set <M-v>=\ev"
endif

" Problem1:
"
" Every time we set and use a meta key as the {lhs} of an insert-mode mapping,
" a macro containing a sequence of key presses such as:
"
"         Esc + {char used in a meta mapping}
"
" … produces unexpected results when it's replayed.
" See here for more info:
"
"     https://github.com/tpope/vim-rsi/issues/13
"
" Reproduction:
"
"     'foobar'
"     'foobar'
"
" Position the cursor right on the first quote of the first line and type:
"
"     qq cl `` Esc f' . q
"
" Now move the cursor on the first quote of the second line and type:
"
"     @q
"
" Expected result:
"
"     ``foobar``
"
"     … and we should end up in normal mode
"
" Real result (if we have an insert mode mapping using `M-f` to move forward
" by a word):
"
"     ``foobar''.
"
"     … and we end up in insert mode
"
" Solution:
"
" Neovim isn't affected. Switch to Neovim.
" OR, temporarily disable meta keys before replaying a macro (`@q`):
"
"     :FM
"
" … then reenable them once the macro has been used (`:FM` again).

" Problem2:
"
" A mapping using a meta key prevents the insertion of some special characters
" for example:
"
"     ino <M-b> …
"     → i_â    ✘
"
" Why?
" Because, for some reason, Vim thinks, wrongly, that `â` produces `M-b`.
" The fact, that we told Vim that `Esc b` produces `M-b` doesn't fix this
" issue. The only thing it changed, is that now, Vim thinks that `Esc b` AND `â`
" both produce `M-b`.
"
" Disabling the meta keys with `:FM` doesn't fix this issue, because the pb
" doesn't come from the meta key being set, but simply from the mapping.
"
" Solution:
"
" Use digraphs:
"
"     a^    →    â
"
" It could be a good idea to use digraphs, even if we didn't face this issue,
" because we often make mistakes when trying to type characters with accent.
" Also, if you forget what's the digraph for a special character, remember
" you can use `:ucs {keyword}` (`ucs` = `UnicodeSearch`).
"
" Example:    :ucs circumflex
"
" Or use replace mode. In replace mode, our insert-mode mappings don't apply.

" MAPPINGS {{{1
" CTRL {{{2
" C-a        beginning-of-line {{{3

cno <c-a> <Home>

" C-b        backward-char {{{3

"                                    ┌─ close wildmenu
"                                    │
cno <expr> <c-b> (wildmenumode() ? '<down>' : '').'<left>'

" C-d        delete-char {{{3

" If the cursor is at the end of the command line, we want C-d to keep its
" normal behavior which is to list names that match the pattern in front of
" the cursor.
" However, if it's before the end, we want C-d to delete the character after
" it.

cno <expr> <c-d> getcmdpos() > strlen(getcmdline()) ? '<c-d>' : '<Del>'

" C-f        forward-char {{{3

cno        <c-f>       <Right>

" C-g        abort {{{3

cno <expr> <c-g> '<c-c>'

" C-k        kill-line {{{3

cno <c-k> <c-\>ematchstr(getcmdline(), '.*\%'.getcmdpos().'c')<cr>

" C-t        transpose-chars {{{3

ino <expr> <c-t> <sid>transpose_chars(1)
cno <expr> <c-t> <sid>transpose_chars(0)

fu! s:transpose_chars(insert_mode) abort

    let [ pos, line ] = a:insert_mode
                     \?     [ col('.'), getline('.') ]
                     \:     [ getcmdpos(), getcmdline() ]

    if pos > strlen(line)
        " We use `matchstr()` because of potential multibyte characters.
        " Test on this:
        "
        "     âêîôû
        return a:insert_mode
        \?         "\<c-g>U\<left>\<bs>\<c-g>U\<right>".matchstr(line, '.\ze.\%'.pos.'c')
        \:         "\<left>\<bs>\<right>".matchstr(line, '.\ze.\%'.pos.'c')

    elseif pos > 1
        return a:insert_mode
        \?         "\<bs>\<c-g>U\<right>".matchstr(line, '.\%'.pos.'c')
        \:         "\<bs>\<right>".matchstr(line, '.\%'.pos.'c')

    else
        return ''
    endif
endfu

" META {{{2
" M-b/f      forward-word backward-word {{{3

" We can't use this:
"     cno <M-b> <S-Left>
"     cno <M-f> <S-Right>
"
" Because it seems to consider `-` as part of a word.
" `M-b`, `M-f` would move too far compared to readline.

ino <expr> <M-b> <sid>move_by_words(0, 'i')
ino <expr> <M-f> <sid>move_by_words(1, 'i')

"                                    ┌─  close wildmenu
"                                    │
cno <expr> <M-b> (wildmenumode() ? '<down>' : '').<sid>move_by_words(0, 'c')
cno <expr> <M-f> (wildmenumode() ? '<down>' : '').<sid>move_by_words(1, 'c')

if !has('nvim')
    tno <expr> <M-b> <sid>move_by_words(0, 't')
    tno <expr> <M-f> <sid>move_by_words(1, 't')
endif

" NOTE:
" Implementing this function was tricky, it has to handle:
"
"    • multi-byte characters (éàî)
"    • multi-cell characters (tab)
"    • composing characters  ( ́)

fu! s:move_by_words(fwd, mode) abort
    let isk_save = &l:isk
    try
        " Previously, we used this code:
        "         setl isk-=_ isk-=- isk-=#
        "
        " But sometimes, the mapping behaves strangely.
        " So, I prefer to give an explicit value to `isk`.
        setl isk=@,48-57,192-255

        let [ line, old_pos ] = a:mode ==# 'i'
                              \?     [ getline('.'), col('.') ]
                              \: a:mode ==# 'c'
                              \?     [ getcmdline(), getcmdpos() ]
                              \:     [ term_getline('', '.'), term_getcursor('')[1] ]
                              "                     │    │                   │   │
                              "                     │    │                   │   └─ cursor column
                              "                     │    │                   └─ current buffer
                              "                     │    └─ current line
                              "                     └─ current buffer

        let atom = a:mode ==# 't' ? 'v' : 'c'

        " old_char_idx = nr of characters before cursor in its current position
        " new_char_idx = "                                         new     "

        "                                     ignore composing characters ┐
        " necessary to move correctly on a line such as:                  │
        "          ́ foo  ́ bar  ́                                           │
        let old_char_idx = strchars(matchstr(line, '.*\%'.old_pos.atom), 1)

        if a:fwd
            " all characters from the beginning of the line until the last
            " character of the nearest NEXT word (current one if we're in a word,
            " or somewhere AFTER otherwise)
            let pat = '\v.*%'.old_pos.atom.'%(.{-1,}>\ze|.*)'
            "                                            │
            "           if there's no word where we are, ┘
            " nor after us, then go on until the end of the line
            let new_char_idx = strchars(matchstr(line, pat), 1)
        else
            " all characters from the beginning of the line until the first
            " character of the nearest PREVIOUS word (current one if we're in a
            " word, or somewhere BEFORE otherwise)
            let pat          = '\v.*\ze<.{-1,}%'.old_pos.atom
            let new_char_idx = strchars(matchstr(line, pat), 1)
        endif

        let diff = old_char_idx - new_char_idx
        let building_motion = a:mode ==# 'i'
                           \?    diff > 0 ? "\<c-g>U\<left>" : "\<c-g>U\<right>"
                           \: a:mode ==# 'c'
                           \?    diff > 0 ? "\<left>" : "\<right>"
                           \:    diff > 0 ? "\<c-b>"  : "\<c-f>"

        let motion = repeat(building_motion, abs(diff))
        if a:mode ==# 't'
            call term_sendkeys('', motion)
            return ''
        else
            return motion
        endif

    " the `catch` clause prevents errors from being echoed
    " if you try to throw the exception manually (echo v:exception, echo
    " v:throwpoint), nothing will be displayed, so don't bother
    catch
    finally
        let &l:isk = isk_save
    endtry
    return ''
endfu

" M-d        kill-word {{{3

" Delete until the beginning of the next word.
" In bash, M-d does the same, and is bound to the function kill-word.
ino <expr> <M-d>  <sid>kill_word('i')
cno <expr> <M-d>  <sid>kill_word('c')
if !has('nvim')
    tno <expr> <M-d>  <sid>kill_word('t')
endif

fu! s:kill_word(mode) abort
    let isk_save = &l:isk
    try
        " Previously, we used this code:
        "         setl isk-=_ isk-=- isk-=#
        "
        " But sometimes, the mapping behaves strangely.
        " So, I prefer to give an explicit value to `isk`.
        setl isk=@,48-57,192-255

        let [ line, pos ] = a:mode ==# 'i'
                         \?     [ getline('.'), col('.') ]
                         \: a:mode ==# 'c'
                         \?     [ getcmdline(), getcmdpos() ]
                         \:     [ term_getline('', '.'), term_getcursor('')[1] ]

        let atom = a:mode ==# 't' ? 'v' : 'c'

        "                         ┌ from the beginning of the word containing the cursor
        "                         │ until the cursor
        "                         │ if the cursor is outside of a word, the pattern
        "                         │ still matches, because we use `*`, not `+`
        "            ┌────────────┤
        let pat = '\v\k*%'.pos.atom.'\zs%(\k+|.{-}<\k+>|%(\k@!.)+)'
        "                                 └─┤ └───────┤ └───────┤
        "                                   │         │         └ or all the non-word text we're in
        "                                   │         └───────── or the next word if we're outside of a word
        "                                   └─────────────────── the rest of the word after the cursor

        " TODO:
        " understand the behavior of these regexes

        " \v%2c(.{-}<\k+>|\W+)
        " \v%2c(\W+|.{-}<\k+>)
        " \v%2c\W+
        " \v%2c(\k@!.)+
        "
        " \v%2c(.{-}\k+>| ééé)

" ééé ààà
" eee ààà
" foo_bar_baz
" ééé_ààà_îîî

" eee aaa
" \v.{-}\k+>| eee

        if a:mode ==# 't'
            if pos <= strlen(line)
                call term_sendkeys('', repeat("\<c-d>", strchars(matchstr(line, pat), 1)))
            endif
            return ''
        else
            return repeat("\<del>", strchars(matchstr(line, pat), 1))
        endif

    catch
    finally
        let &l:isk = isk_save
    endtry
endfu

" M-n/p      down up {{{3

" FIXME:
" The `M-n` mapping prevents us from typing `î` on the command line.
" For the moment, type `q:` or use `[[=i=]]` in a search.

" For the `M-n` mapping to work, we need to give the same value for 'wildchar'
" and 'wildcharm'. We gave them both the value `<Tab>`.
cno <M-n> <Down>

" For more info:
"
" https://groups.google.com/d/msg/vim_dev/xf5TRb4uR4Y/djk2dq2poaQJ
" http://stackoverflow.com/a/14849216

" history-search-backward
" history-search-forward
cno <M-p> <Up>

if !has('nvim')
    " FIXME:
    " doesn't behave exactly like it should
    tno <m-n> <down>
    tno <m-p> <up>
endif

" M-t        transpose-words {{{3

ino <silent>   <M-t>                       <c-r>=<sid>transpose_words('i')<cr>
cno            <M-t>                       <c-\>e<sid>transpose_words('c')<cr>
if !has('nvim')
    tno <expr> <M-t>  <sid>transpose_words('t')
endif

nmap           <M-t>                    <plug>(transpose_words)
nno  <silent>  <plug>(transpose_words)  :<c-u>exe <sid>transpose_words('n')<cr>

fu! s:transpose_words(mode) abort
    " readline doesn't consider `-`, `#`, `_` as part of a word,
    " contrary to Vim which may disagree for some of them
    "
    " removing them from 'isk' allows us to operate on the following “words“:
    "         foo-bar
    "         foo#bar
    "         foo_bar

    let isk_save = &l:isk
    setl isk=@,48-57,192-255

    try
        let [ line, pos ] = a:mode ==# 'i' || a:mode ==# 'n'
                         \?     [ getline('.'), col('.') ]
                         \: a:mode ==# 'c'
                         \?     [ getcmdline(), getcmdpos() ]
                         \:     [ term_getline('', '.'), term_getcursor('')[1] ]

        let atom = a:mode ==# 't' ? 'v' : 'c'

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
        let not_on_first = '\v%(<\k*%'.pos.atom.'\k+>)@!&'

        " The cursor mustn't be before the 2 words:
        "
        "         foo | bar baz
        "               └─────┤
        "                     └ don't transpose those 2
        let not_before = '%(%'.pos.atom.'.*)@<!'

        " The cursor mustn't be after the 2 words, unless it is inside
        " a sequence of non-words characters at the end of the line:
        "
        "         foo bar | baz
        "         └─────┤
        "               └ don't transpose those 2
        let not_after = '%(%(.*%'.pos.atom.')@!|%(%(\k@!.)*$)@=)'
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

        if a:mode ==# 'i' || a:mode ==# 'n'
            call setline(line('.'), new_line)
            call cursor(line('.'), new_pos)
            if a:mode ==# 'n'
                call repeat#set("\<plug>(transpose_words)")
            endif
            return ''
        elseif a:mode ==# 'c'
            call setcmdpos(new_pos)
            return new_line
        else
            " FIXME:
            " doesn't work as expected when the cursor is at the beginning of the line
            let new_pos -= strchars(matchstr(new_line, '\v.{-}%(\%|#)\s'), 1)
            let new_line = matchstr(new_line, '\v.{-}%(\%|#)\s\zs.*')
            call term_sendkeys('', "\<c-k>\<c-u>".new_line."\<c-a>".repeat("\<c-f>", new_pos))
            return ''
        endif

    catch
        return 'echoerr '.string(v:exception)

    finally
        let &l:isk = isk_save
    endtry

    return ''
endfu

" M-u        upcase-word {{{3

ino  <silent> <m-u>                <c-r>=<sid>upcase_word('i')<cr>
nmap <silent> <m-u>                <plug>(upcase_word)
nno  <silent> <plug>(upcase_word)  :<c-u>exe <sid>upcase_word('n')<cr>

cno           <m-u>                <c-\>e<sid>upcase_word('c')<cr>

if !has('nvim')
    tno <expr> <m-u>  <sid>upcase_word('t')
endif

fu! s:upcase_word(mode) abort
    let isk_save = &l:isk
    try
        setl isk=@,48-57,192-255
        let [ line, pos ] = a:mode ==# 'i' || a:mode ==# 'n'
                         \?     [ getline('.'), col('.') ]
                         \: a:mode ==# 'c'
                         \?     [ getcmdline(), getcmdpos() ]
                         \:     [ term_getline('', '.'), term_getcursor('')[1] ]

        let atom = a:mode ==# 't' ? 'v' : 'c'

        let pat      = '\v\k*%'.pos.atom.'\zs%(\k+|.{-}<\k+>|%(\k@!.)+)'
        let new_line = substitute(line, pat, '\U\0', '')
        " FIXME:
        " weird behavior when we're at the end of the command line in a terminal buffer
        let new_pos  = a:mode ==# 't'
    \?     strchars(matchstr(line, '\v.{-}%(\%|#)\s\zs.{-}\k*%'.pos.'v%(\k+|.{-}<\k+>|%(\k@!.)+)'), 1) + 1
                    \:     match(line, pat.'\zs') + 1

        if a:mode ==# 'i' || a:mode ==# 'n'
            call setline(line('.'), new_line)
            call cursor(line('.'), new_pos)
            if a:mode ==# 'n'
                call repeat#set("\<plug>(upcase_word)")
            endif
            return ''
        elseif a:mode ==# 'c'
            call setcmdpos(new_pos)
            if pos > strlen(line)
                return line
            else
                return new_line
            endif
        else
            let new_line = matchstr(new_line, '\v.{-}%(\%|#)\s\zs.*')
            call term_sendkeys('', "\<c-k>\<c-u>".new_line."\<c-a>".repeat("\<c-f>", new_pos))
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
