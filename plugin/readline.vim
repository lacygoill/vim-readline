if exists('g:loaded_readline')
    finish
endif
let g:loaded_readline = 1

" TODO: Try to implement these:{{{
"
"     • yank-nth-arg                     M-C-y
"     • set-mark                         C-@
"     • exchange-point-and-mark          C-x C-x
"     • downcase-word                    M-l
"     • capitalize-word                  M-c
"
" Source:
"     https://www.gnu.org/software/bash/manual/html_node/Bindable-Readline-Commands.html (best?)
"     https://cnswww.cns.cwru.edu/php/chet/readline/readline.html
"}}}
" FIXME: 3 issues with terminal Vim atm:{{{
"
"         • M-a inserts â in terminal gVim (same thing for other M-…)
"           It should work, like it does in Vim's terminal.
"
"         •         tno <esc> <c-\><c-n>
"
"           Breaks   M-….   Example:   pressing   `M-b`  results   in  go   to
"           Terminal-Normal mode (Escape), then one word backward (b).
"           We DO  want to go  one word  backward, but we  also want to  stay in
"           Terminal-Job mode. Because of this, we use this mapping:
"
"                   tno <esc><esc> <c-\><c-n>
"
"         • C-j and C-m are indistinguishable in a zsh completion menu.
"           Minimal `zshrc` to reproduce:
"
"                    autoload -Uz compinit
"                    compinit
"                    zstyle ':completion:*' menu select
"                    zmodload zsh/complist
"                    bindkey -M menuselect '^J' down-line-or-history
"}}}
" FIXME: Can't insert ù â î ô  {{{
"
" A mapping using a meta key prevents the insertion of some special characters
" for example:
"
"         ino <m-b> …
"         → i_â    ✘
"
" Why?
" Because, for some reason, Vim thinks, wrongly, that `â` produces `M-b`.
" The fact, that we told Vim that `Esc b` produces `M-b` doesn't fix this
" issue. The only thing it changed, is that now, Vim thinks that `Esc b` AND `â`
" both produce `M-b`.
"
" Disabling the meta keys with `:ToggleMetaKeys` doesn't fix this issue, because the pb
" doesn't come from the meta key being set, but simply from the mapping.
"
" Solutions:
"
" Literal insertion:
"
"     C-v ^ a    →    â
"
" Use digraphs:
"
"     C-k a ^    →    â
"
" Use replace mode:
"
"     r â    →    â
"
" Use abbreviations
"
" Use equivalence class in a search command
"}}}
" WARNING: {{{1
" Vim doesn't seem able to distinguish `M-y` from ù.
" So, when  you type `ù`  in insert mode, instead  of inserting `ù`,  you will
" invoke `yank()`. If this becomes an issue:
"
"         • install abbreviation for every word containing `ù`
"         • insert `ù` literally
"         • remove this mapping
"         • install a digraph
"         • switch to neovim

" MAPPINGS {{{1
" Try to always preserve breaking undo sequence.{{{
"
" Most of these mappings take care of not breaking undo sequence (C-g U).
" It means we can repeat an edition with the dot command, even if we use them.
" If you add another mapping, try to not break undo sequence. Thanks.
"}}}
" CTRL {{{2
" C-_        undo {{{3

cno <expr> <c-_> readline#undo('c')
ino <expr> <c-_> readline#undo('i')

" C-a        beginning-of-line {{{3

cno <expr> <c-a> readline#beginning_of_line('c')
ino <expr> <c-a> readline#beginning_of_line('i')

" C-b        backward-char {{{3

cno <expr> <c-b>  readline#backward_char('c')
ino <expr> <c-b>  readline#backward_char('i')

" C-d        delete-char {{{3

cno <expr> <c-d> readline#delete_char('c')
ino <expr> <c-d> readline#delete_char('i')

" C-e        end-of-line {{{3

ino <expr> <c-e>    readline#end_of_line()

" C-f        forward-char {{{3

cno <expr> <c-f> readline#forward_char('c')
ino <expr> <c-f> readline#forward_char('i')

" C-g        abort {{{3

cno <expr> <c-g>  '<c-c>'

" C-h backward-delete-char {{{3

cno <expr> <c-h> readline#backward_delete_char('c')
ino <expr> <c-h> readline#backward_delete_char('i')

" C-k        kill-line {{{3

cno <expr> <c-k>      readline#kill_line('c')
ino <expr> <c-k><c-k> readline#kill_line('i')
" In insert mode, we want C-k to keep its original behavior (insert digraph).
" It makes more sense than bind it to a `kill-line` function, because inserting
" digraph is more frequent than killing a line.
"
" But doing so, we lose the possibility to delete everything after the cursor.
" To restore this functionality, we map it to C-k C-k.

" C-t        transpose-chars {{{3

cno <expr> <c-t> readline#transpose_chars('c')
ino <expr> <c-t> readline#transpose_chars('i')

" C-u        unix-line-discard {{{3

cno <expr> <c-u>      readline#unix_line_discard('c')
ino <expr> <c-u>      readline#unix_line_discard('i')

" C-w        backward-kill-word {{{3

cno <expr> <c-w> readline#backward_kill_word('c')
ino <expr> <c-w> readline#backward_kill_word('i')

" C-y        yank {{{3

" Whenever we delete some multi-character text, with:
"
"         • M-d
"         • C-w
"         • C-k
"         • C-u
"
" … we should be able to paste it with C-y, like in readline.

ino <expr> <c-y> readline#yank('i', 0)
cno <expr> <c-y> readline#yank('c', 0)

" META {{{2
" M-b/f      forward-word backward-word {{{3

" We can't use this:
"
"     cno <m-b> <s-left>
"     cno <m-f> <s-right>
"
" Because it seems to consider `-` as part of a word.
" `M-b`, `M-f` would move too far compared to readline.

"                                    ┌─  close wildmenu
"                                    │
cno <expr> <m-b> (wildmenumode() ? '<space><c-h>' : '').readline#move_by_words('c', 0)
cno <expr> <m-f> (wildmenumode() ? '<space><c-h>' : '').readline#move_by_words('c', 1)

ino <expr> <m-b> readline#move_by_words('i', 0)
ino <expr> <m-f> readline#move_by_words('i', 1)

" M-d        kill-word {{{3

" Delete until the beginning of the next word.
" In bash, M-d does the same, and is bound to the function kill-word.

cno <expr> <m-d>  readline#kill_word('c')
ino <expr> <m-d>  readline#kill_word('i')

" M-n/p      down up {{{3

" For the `M-n` mapping to work, we need to give the same value for 'wildchar'
" and 'wildcharm'. We gave them both the value `<Tab>`.
cno <m-n> <down>

" For more info:
"
" https://groups.google.com/d/msg/vim_dev/xf5TRb4uR4Y/djk2dq2poaQJ
" http://stackoverflow.com/a/14849216

" history-search-backward
" history-search-forward
cno <m-p> <up>

" M-t        transpose-words {{{3

cno <expr>     <m-t>                    readline#transpose_words('c')
ino <expr>     <m-t>                    readline#transpose_words('i')

nmap           <m-t>                    <plug>(transpose_words)
nno  <silent>  <plug>(transpose_words)  :<c-u>exe readline#transpose_words('n')<cr>

" M-u        upcase-word {{{3

cno  <expr>   <m-u>                readline#upcase_word('c')
ino  <expr>   <m-u>                readline#upcase_word('i')

nmap <silent> <m-u>                <plug>(upcase_word)
nno  <silent> <plug>(upcase_word)  :<c-u>exe readline#upcase_word('n')<cr>

" M-y        yank-pop {{{3

cno  <expr>   <m-y>    readline#yank('c', 1)
ino  <expr>   <m-y>    readline#yank('i', 1)

" OPTIONS {{{1

if !has('nvim')
    " don't use `c-w` as a prefix to execute commands manipulating the window in
    " which a  terminal buffer  is displayed; `c-w`  should delete  the previous
    " word; use `c-g` instead
    set termkey=<c-g>
endif

" KEYSYMS {{{1
" Why do we need to set `<M-b>` &friends?{{{
"
" On my machine, Vim doesn't know what are the right keycodes produced by
" certains keysyms such as `M-b`.
" It probably knows something, but it's wrong.
" For example, it thinks that the keysym `M-b` is produced by `â`.
" Which is confirmed if we just write this mapping:
"
"     ino <M-b> hello
"
" … then try to insert `â`. It will insert `hello`.
" But Vim doesn't really know what's `M-b`,  because if we press `M-b` in insert
" mode, it doesn't insert `hello`, it just escapes to normal mode then go back a
" word.
" We need to teach it the correct keycodes which are produced by `M-b`.
" To find the keycodes, insert the keysym literally (ex: C-v M-b).
"
" We do the same thing for other keysyms following the pattern `M-{char}`.
"}}}
"  ┌─ no need to teach anything for nvim or gVim (they already know)
"  │
if has('nvim') || has('gui_running')
    finish
endif

" functions {{{2
fu! s:do_not_break_macro_replay() abort "{{{3
    " Warning:{{{
    " `do_not_break_macro_replay()` will NOT work when you do this:
    "
    "         norm! @q
    "
    " … instead, you must do this:
    "
    "         norm @q
"}}}
    call s:set_keysyms(0)

    " We need to save the current value of 'updatetime', to restore it later.
    " However, suppose we do this:
    "
    "         g/pat/norm @q
    "           │
    "           └─ `pat` matching at least 2 texts in the buffer
    "
    " On the second invocation of `@q`, 'ut' will probably be 5ms, not 2000ms.
    " This is because, Vim has executed the 2 macros very fast. In less than 5 ms.
    " CursorHold(I) hasn't been  fired once between the 2  invocations, and 'ut'
    " hasn't been restored properly.
    " So, we must NOT save `&ut` if  its value is abnormally low (less than 1s),
    " instead we'll use 2s as a default value.

    let s:ut_save = &ut >= 1000 ? &ut : 2000
    set updatetime=5
    augroup do_not_break_macro_replay
        au!
        au CursorHold,CursorHoldI * call s:set_keysyms(1)
                                    \| let &ut = s:ut_save
                                    \| unlet! s:ut_save
                                    \| exe 'au! do_not_break_macro_replay'
                                    \| exe 'aug! do_not_break_macro_replay'
    augroup END

    return '@'.nr2char(getchar())
endfu

fu! s:enable_keysyms_on_command_line() abort "{{{3
    call s:set_keysyms(1)
    " Do NOT return `:` immediately.
    " The previous function call sets some special options, and for some reason,
    " setting these prevents us from displaying a message with `:echo`.
    call timer_start(0, {-> feedkeys(':', 'int')})
    return ''
endfu

fu! s:set_keysyms(enable) abort "{{{3
    if a:enable
        exe "set <m-a>=\ea"
        exe "set <m-b>=\eb"
        exe "set <m-d>=\ed"
        exe "set <m-e>=\ee"
        exe "set <m-f>=\ef"
        exe "set <m-m>=\em"
        exe "set <m-n>=\en"
        exe "set <m-p>=\ep"
        exe "set <m-s>=\es"
        exe "set <m-t>=\et"
        exe "set <m-u>=\eu"
        exe "set <m-v>=\ev"
        exe "set <m-y>=\ey"
    else
        exe "set <m-a>="
        exe "set <m-b>="
        exe "set <m-d>="
        exe "set <m-e>="
        exe "set <m-f>="
        exe "set <m-m>="
        exe "set <m-n>="
        exe "set <m-p>="
        exe "set <m-s>="
        exe "set <m-t>="
        exe "set <m-u>="
        exe "set <m-v>="
        exe "set <m-y>="
    endif
endfu
call s:set_keysyms(1)

fu! s:toggle_keysyms_in_terminal() abort "{{{3
    nno <buffer> <expr> <nowait> : <sid>enable_keysyms_on_command_line()

    augroup toggle_keysyms_in_terminal
        au! * <buffer>
        au CursorMoved <buffer> call s:set_keysyms(0)
        au BufLeave    <buffer> call s:set_keysyms(1)
    augroup END
endfu

fu! s:toggle_meta_keys() abort "{{{3
    let is_unset = execute('sil! set <M-p>') =~# 'E846'

    call s:set_keysyms(is_unset)

    " '' → execute NON-silently
    call timer_start(0, { -> execute(
                        \            "echom '[Fix Macro] Meta keys '."
                        \            .(is_unset ? string('Enabled') : string('Disabled')),
                        \            ''
                        \           )
                        \ })

    " Why do we use a timer to display our message?{{{
    " Why not simply echo it now?
    "
    "         echom '[Fix Macro] Meta keys '.(is_unset ? 'Enabled' : 'Disabled')
    "         echo ''
    "
    " Because, it seems that `set <M-key>` redraws the command-line after
    " we echo the next message. Therefore, it's erased, and we can't read it.
    " We could echo a 2nd empty message to prevent Vim from redrawing the
    " command-line:
    "
    "         echom '[Fix Macro] Meta keys '.(is_unset ? 'Enabled' : 'Disabled')
    "         echo ''
    "
    " But then, we would have to hit Enter to exit the prompt.
    "
    " MWE (Minimal Working Example) to reproduce the pb:
    "
    "     :set fdm=manual | echo 'hello'           ✔
    "     :set <M-a>=     | echo 'hello'           ✘
    "     :set <M-a>=     | echo "hello\nworld"    ✔
    "     }}}
endfu

" command {{{2
" This command can be useful to temporarily disable meta keys before replaying a
" macro.
com! -bar ToggleMetaKeys call s:toggle_meta_keys()

" autocommand {{{2
augroup handle_keysyms
    au!
    au BufWinEnter * if &buftype ==# 'terminal'
                    \|     call s:set_keysyms(0)
                    \|     call s:toggle_keysyms_in_terminal()
                    \| endif
augroup END

" mapping {{{2

" Issue: Why the next mapping?{{{
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
"     :ToggleMetaKeys
"
" … then reenable them once the macro has been used (`:ToggleMetaKeys` again).
" This is the purpose of the next mapping.
"}}}
nmap <expr> @ <sid>do_not_break_macro_replay()

" Do NOT use `<nowait>`.
" If we hit `@?`, the previous mapping must not be used. It wouldn't work.
" Why?
" Because the `rhs` that it would return begins like the `lhs` (@).
" This prevents the necessary recursiveness (:h recursive_mapping; exception).
