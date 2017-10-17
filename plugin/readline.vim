if exists('g:loaded_readline')
    finish
endif
let g:loaded_readline = 1

if !has('nvim')
    " FIXME:
    " This mapping allows us  to use keys whose 1st keycode  is escape (left, right,
    " M-…) as the lhs of other mappings. How does it work? Why is it necessary?
    "
    " However, it creates a timeout (3s) when we try to escape to normal mode.
    " How to reduce the timeout to a few ms?
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
    exe "set <m-a>=\ea"
    exe "set <m-b>=\eb"
    exe "set <m-d>=\ed"
    exe "set <m-e>=\ee"
    exe "set <m-f>=\ef"
    exe "set <m-n>=\en"
    exe "set <m-p>=\ep"
    exe "set <m-t>=\et"
    exe "set <m-u>=\eu"
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

cno <c-a>  <home>

" C-b        backward-char {{{3

"                                     ┌─ close wildmenu
"                                     │
cno <expr> <c-b>  (wildmenumode() ? '<down>' : '').'<left>'

" C-d        delete-char {{{3

" If the cursor is at the end of the command line, we want C-d to keep its
" normal behavior which is to list names that match the pattern in front of
" the cursor.
" However, if it's before the end, we want C-d to delete the character after
" it.

cno <expr> <c-d>  getcmdpos() > strlen(getcmdline()) ? '<c-d>' : '<Del>'

" C-f        forward-char {{{3

cno <c-f>  <right>

" C-g        abort {{{3

cno <expr> <c-g>  '<c-c>'

" C-k        kill-line {{{3

cno <c-k>  <c-\>ematchstr(getcmdline(), '.*\%'.getcmdpos().'c')<cr>

" C-t        transpose-chars {{{3

ino <expr> <c-t> readline#transpose_chars('i')
cno <expr> <c-t> readline#transpose_chars('c')

" META {{{2
" M-b/f      forward-word backward-word {{{3

" We can't use this:
"
"     cno <m-b> <s-left>
"     cno <m-f> <s-right>
"
" Because it seems to consider `-` as part of a word.
" `M-b`, `M-f` would move too far compared to readline.

ino <expr> <m-b> readline#move_by_words(0, 'i')
ino <expr> <m-f> readline#move_by_words(1, 'i')

"                                    ┌─  close wildmenu
"                                    │
cno <expr> <m-b> (wildmenumode() ? '<down>' : '').readline#move_by_words(0, 'c')
cno <expr> <m-f> (wildmenumode() ? '<down>' : '').readline#move_by_words(1, 'c')

if !has('nvim')
    tno <expr> <m-b> readline#move_by_words(0, 't')
    tno <expr> <m-f> readline#move_by_words(1, 't')
endif

" M-d        kill-word {{{3

" Delete until the beginning of the next word.
" In bash, M-d does the same, and is bound to the function kill-word.

ino <expr> <m-d>  readline#kill_word('i')
cno <expr> <m-d>  readline#kill_word('c')

if !has('nvim')
    tno <expr> <m-d>  readline#kill_word('t')
endif

" M-n/p      down up {{{3

" FIXME:
" The `M-n` mapping prevents us from typing `î` on the command line.
" For the moment, type `q:` or use `[[=i=]]` in a search.

" For the `M-n` mapping to work, we need to give the same value for 'wildchar'
" and 'wildcharm'. We gave them both the value `<Tab>`.
cno <m-n> <Down>

" For more info:
"
" https://groups.google.com/d/msg/vim_dev/xf5TRb4uR4Y/djk2dq2poaQJ
" http://stackoverflow.com/a/14849216

" history-search-backward
" history-search-forward
cno <m-p> <up>

if !has('nvim')
    " FIXME:
    " doesn't behave exactly like it should
    tno <m-n> <down>
    tno <m-p> <up>
endif

" M-t        transpose-words {{{3

ino <silent>   <m-t>                       <c-r>=readline#transpose_words('i')<cr>
cno            <m-t>                       <c-\>ereadline#transpose_words('c')<cr>

if !has('nvim')
    tno <expr> <m-t>  readline#transpose_words('t')
endif

nmap           <m-t>                    <plug>(transpose_words)
nno  <silent>  <plug>(transpose_words)  :<c-u>exe readline#transpose_words('n')<cr>

" M-u        upcase-word {{{3

ino  <silent> <m-u>                <c-r>=readline#upcase_word('i')<cr>
nmap <silent> <m-u>                <plug>(upcase_word)
nno  <silent> <plug>(upcase_word)  :<c-u>exe readline#upcase_word('n')<cr>

cno           <m-u>                <c-\>ereadline#upcase_word('c')<cr>

if !has('nvim')
    tno <expr> <m-u>  readline#upcase_word('t')
endif
