if exists('g:loaded_readline')
    finish
endif
let g:loaded_readline = 1

" TODO:     Try to implement these:{{{
"
"     • kill-region (zle)                ???
"     • quote-region (zle)               M-"
"     • operate-and-get-next             C-o
"     • yank-nth-arg                     M-C-y
"
" Source:
"     man zshzle
"     https://www.gnu.org/software/bash/manual/html_node/Bindable-Readline-Commands.html (best?)
"     https://cnswww.cns.cwru.edu/php/chet/readline/readline.html
"}}}
" TODO:     Use `vim-submode` to make `M-u` enter a submode {{{
" in which `c`, `l`, `u` change the  case of words. It would make them easier to
" repeat. Do the same for the shell.
"}}}
" FIXME:    M-a inserts â in terminal gVim {{{
"
" Same thing for other M-…
" If you start Vim without any initialization, it doesn't work at all.
" It should work, like it does in Vim's terminal.
"
" Why does gVim insert  `â`, when we start it with our  vimrc, instead of doing
" nothing like it does by default?
" Because we give the value 'M' to 'guioptions', which removes the 'm' flag.
"
" https://github.com/vim/vim/issues/2397
"}}}
" FIXME:    Can't insert ù â î ô  {{{

" A mapping using a meta key prevents the insertion of some special characters
" for example:
"
"         1. ino <m-b> …
"         2. i_â
"                → moves cursor one word backward
"
" Why?
" Because, for  some reason,  Vim doesn't make the difference between `Esc b` and `â`.
" So, when we press `i_â`, Vim thinks we've pressed `M-b`.
"
" Disabling the meta keys with `:ToggleMetaKeys` doesn't fix this issue, because
" the pb doesn't come from the meta key being set, but simply from the mapping.

" For the same reason, `ù` triggers the `M-y` mapping.  So, when you press `ù`
" in insert mode, instead of inserting `ù`, you will invoke `yank()`.



" Solutions:
"
" Use literal insertion:
"
"     C-v ^ a    →    â
"
" Use digraph:
"
"     C-k a a    →    â
"
" Use replace mode:
"
"     r ^ a     →    â
"
" Use abbreviation
"
" Use equivalence class in a search command

" FIXME:    How to make `M-u c` repeatable? {{{1

" Also, why must we press `.` twice to repeat `M-u u` and `M-u l`?
" Also, why does it fail sometimes (Vim deletes some line(s) instead)?

" AUTOCMD {{{1

augroup my_lazy_loaded_readline
    au!
    au CmdlineEnter * call readline#install_cmdline_transformation_pre()
    \|                exe 'au! my_lazy_loaded_readline'
    \|                aug! my_lazy_loaded_readline
augroup END

" MAPPINGS {{{1
" Try to always preserve breaking undo sequence.{{{
"
" Most of these mappings take care of not breaking undo sequence (C-g U).
" It means we can repeat an edition with the dot command, even if we use them.
" If you add another mapping, try to not break undo sequence. Thanks.
"}}}
" CTRL {{{2
" C-@        set-mark {{{3

" If you don't use `C-@` in the insert mode mapping, disable the key.{{{
"
" By default,  in insert mode,  C-@ (:h ^@) inserts  the last inserted  text and
" leaves insert mode.
" Usually, in a  terminal C-SPC produces C-@. So, when we  hit C-SPC by accident
" (which occurs frequently), we insert the last inserted text.
" We don't want that, so we previously, in `vimrc`, we disabled the mapping:
"
"     ino <c-@>     <nop>

" There's no need for that anymore, since we use `C-@` for setting a mark, which
" is harmless: it doesn't insert / remove any text in the buffer.
" But if for some reason, you choose another key, or remove the mapping entirely,
" make sure to disable these keys again.
"}}}
cno  <expr><unique>  <c-@>  readline#set_mark('c')
ino  <expr><unique>  <c-@>  readline#set_mark('i')
" For some reason, there's no conflict between this mapping and `i_C-j` in vimrc.{{{
" Even though `C-j` produces `C-@` (C-v C-j → c-@).
" MWE:
"
"     ino  <c-j>  foo
"     ino  <c-@>  bar
"
"     press C-j in insert mode  →  foo
"     press C-@ "               →  bar
"
" Summary:
" C-j  C-SPC  C-@  all seem to produce the same keycode C-@ when inserted literally.
" But in practice, the only conflict which we must take into consideration is between
" C-j/C-SPC and C-@.
"}}}

" C-_        undo {{{3

cno  <expr><unique>  <c-_>  readline#undo('c')
ino  <expr><unique>  <c-_>  readline#undo('i')

" C-a        beginning-of-line {{{3

cno  <expr><unique>  <c-a>  readline#beginning_of_line('c')
ino  <expr><unique>  <c-a>  readline#beginning_of_line('i')

" restore default C-a
" dump all candidates on the command-line
cno  <unique>  <c-x><c-a>  <c-a>

" also, create custom C-x C-d
" capture all candidates in the unnamed register
cno  <expr><silent>  <c-x><c-d>  '<c-a>'.timer_start(0, {-> setreg('"', getcmdline(), 'l') + feedkeys('<c-c>', 'int') })[-1]

" C-b        backward-char {{{3

cno  <expr><unique>  <c-b>  readline#backward_char('c')
ino  <expr><unique>  <c-b>  readline#backward_char('i')

" C-d        delete-char {{{3

cno  <expr><unique>  <c-d>  readline#delete_char('c')
ino  <expr><unique>  <c-d>  readline#delete_char('i')

" C-e        end-of-line {{{3

ino  <expr><unique>  <c-e>  readline#end_of_line()

" C-f        forward-char {{{3

cno  <expr><unique>  <c-f>  readline#forward_char('c')
ino  <expr><unique>  <c-f>  readline#forward_char('i')

" Restore default C-f on the command-line (using C-x C-e){{{
" Isn't `q:` enough?
"
" No.
" What if  we're in the middle  of a command, and  we don't want to  escape then
" press `q:`? And  what if  we're on  the expression  command line,  opened from
" insert mode?  There's no default key  binding to access the expression command
" line window (no `q=`).
"}}}
" Why C-x C-e?{{{
"
" To stay consistent with  how we open the editor to edit the  command line in a
" shell.
"}}}
let &cedit = "\<c-x>\<c-e>"

" C-h        backward-delete-char {{{3

cno  <expr><unique>  <c-h>  readline#backward_delete_char('c')
ino  <expr><unique>  <c-h>  readline#backward_delete_char('i')

" C-k        kill-line {{{3

cno  <expr><unique>  <c-k>       readline#kill_line('c')

" We need to restore the insertion of digraph functionality on the command-line.
cno  <unique>  <c-x>k  <c-k>

" In insert mode, we want C-k to keep its original behavior (insert digraph).
" It makes more sense than bind it to a `kill-line` function, because inserting
" digraph is more frequent than killing a line.
"
" But doing so, we lose the possibility to delete everything after the cursor.
" To restore this functionality, we map it to C-k C-k.
ino  <expr><unique>  <c-k><c-k>  readline#kill_line('i')

" C-t        transpose-chars {{{3

cno  <expr><unique>  <c-t>  readline#transpose_chars('c')
ino  <expr><unique>  <c-t>  readline#transpose_chars('i')

" C-u        unix-line-discard {{{3

cno  <expr><unique>  <c-u>  readline#unix_line_discard('c')
ino  <expr><unique>  <c-u>  readline#unix_line_discard('i')

" C-w        backward-kill-word {{{3

cno  <expr><unique>  <c-w>  readline#backward_kill_word('c')
ino  <expr><unique>  <c-w>  readline#backward_kill_word('i')

" C-x C-x    exchange-point-and-mark {{{3

cno  <expr><unique>  <c-x><c-x>  readline#exchange_point_and_mark('c')
ino  <expr><unique>  <c-x><c-x>  readline#exchange_point_and_mark('i')

" C-y        yank {{{3

" Whenever we delete some multi-character text, with:
"
"         • M-d
"         • C-w
"         • C-k
"         • C-u
"
" … we should be able to paste it with C-y, like in readline.

ino  <expr><unique>  <c-y>  readline#yank('i', 0)
cno  <expr><unique>  <c-y>  readline#yank('c', 0)


" META {{{2
" M-b/f      forward-word    backward-word {{{3

" We can't use this:
"
"     cno <m-b> <s-left>
"     cno <m-f> <s-right>
"
" Because it seems to consider `-` as part of a word.
" `M-b`, `M-f` would move too far compared to readline.

"                                              ┌─  close wildmenu
"                                              │
cno  <expr><unique>  <m-b> (wildmenumode() ? '<space><c-h>' : '').readline#move_by_words('c', 0)
cno  <expr><unique>  <m-f> (wildmenumode() ? '<space><c-h>' : '').readline#move_by_words('c', 1)

ino  <expr><unique>  <m-b>  readline#move_by_words('i', 0)
ino  <expr><unique>  <m-f>  readline#move_by_words('i', 1)

" M-u c      capitalize-word {{{3

cno  <expr><unique>  <m-u>c  readline#move_by_words('c', 1, 1)
ino  <expr><unique>  <m-u>c  readline#move_by_words('i', 1, 1)

nmap         <unique>  <m-u>c                   <plug>(capitalize-word)
nno    <expr><silent>  <plug>(capitalize-word)  readline#move_by_words('n', 1, 1)
xno  <silent><unique>  <m-u>c                   :<c-u>sil keepj keepp
\                                               '<,'>s/\v%V.{-}\zs(\k)(\k*%V\k?)/\u\1\L\2/ge<cr>

" M-u l      downcase-word {{{3

cno  <expr><unique>  <m-u>l  readline#upcase_word('c', 1)
ino  <expr><unique>  <m-u>l  readline#upcase_word('i', 1)

nmap         <unique>  <m-u>l                 <plug>(downcase-word)
nno    <expr><silent>  <plug>(downcase-word)  readline#upcase_word('n', 1)
xno  <silent><unique>  <m-u>l                 :<c-u>sil keepj keepp '<,'>s/\%V[A-Z]/\l&/ge<cr>

" M-d        kill-word {{{3

" Delete until the beginning of the next word.
" In bash, M-d does the same, and is bound to the function kill-word.

cno  <expr><unique>  <m-d>  readline#kill_word('c')
ino  <expr><unique>  <m-d>  readline#kill_word('i')

" M-n/p      down up {{{3

" For the `M-n` mapping to work, we need to give the same value for 'wildchar'
" and 'wildcharm'. We gave them both the value `<Tab>`.
cno  <unique>  <m-n>  <down>

" For more info:
"
" https://groups.google.com/d/msg/vim_dev/xf5TRb4uR4Y/djk2dq2poaQJ
" http://stackoverflow.com/a/14849216

" history-search-backward
" history-search-forward
cno  <unique>  <m-p>  <up>

" M-t        transpose-words {{{3

cno  <expr><unique>  <m-t>  readline#transpose_words('c')
ino  <expr><unique>  <m-t>  readline#transpose_words('i')

nmap       <unique>  <m-t>                    <plug>(transpose_words)
nno  <expr><silent>  <plug>(transpose_words)  readline#transpose_words('n')

" M-u u      upcase-word {{{3

xno        <unique>  <m-u>u  U
cno  <expr><unique>  <m-u>u  readline#upcase_word('c')
ino  <expr><unique>  <m-u>u  readline#upcase_word('i')

nmap       <unique>  <m-u>u               <plug>(upcase-word)
nno  <expr><silent>  <plug>(upcase-word)  readline#upcase_word('n')

" M-y        yank-pop {{{3

cno  <expr><unique>  <m-y>  readline#yank('c', 1)

" Disabled in Vim, because we press `ù` by accident too frequently.
" When it happens, we invoke `readline#yank()` which is extremely distracting.
" It completely changes the text we've typed.
if has('nvim')
    ino  <expr><unique>  <m-y>  readline#yank('i', 1)
endif

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

let s:original_ut = &ut

" functions {{{2
fu! s:do_not_break_macro_replay() abort "{{{3
    " ask which register we want to replay
    let char = nr2char(getchar(),1)
    " Don't toggle keysyms if we want to reexecute last Ex command.
    " Why?
    "     1. It's probably useless.
    "     2. If the Ex command prints a message, it will be automatically erased.
    if char is# ':'
        return '@:'
    endif

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

    set updatetime=5
    augroup do_not_break_macro_replay
        au!
        au CursorHold,CursorHoldI * call s:set_keysyms(1)
        \|                          let &ut = s:original_ut
        \|                          exe 'au! do_not_break_macro_replay'
        \|                          exe 'aug! do_not_break_macro_replay'
    augroup END

    return '@'.char
endfu

fu! s:enable_keysyms_on_command_line() abort "{{{3
    call s:set_keysyms(1)
    " Do NOT return `:` immediately.
    " The previous function call sets some special options, and for some reason,
    " setting these prevents us from displaying a message with `:echo`.
    call timer_start(0, {-> feedkeys(':', 'in')})
    return ''
endfu

fu! s:set_keysyms(enable) abort "{{{3
    if a:enable
        exe "set <m-a>=\ea"
        exe "set <m-b>=\eb"
        exe "set <m-d>=\ed"
        exe "set <m-e>=\ee"
        exe "set <m-f>=\ef"
        exe "set <m-g>=\eg"
        exe "set <m-m>=\em"
        exe "set <m-n>=\en"
        exe "set <m-p>=\ep"
        exe "set <m-t>=\et"
        exe "set <m-u>=\eu"
        exe "set <m-y>=\ey"
        exe "set <m-z>=\ez"
    else
        exe "set <m-a>="
        exe "set <m-b>="
        exe "set <m-d>="
        exe "set <m-e>="
        exe "set <m-f>="
        exe "set <m-g>="
        exe "set <m-m>="
        exe "set <m-n>="
        exe "set <m-p>="
        exe "set <m-t>="
        exe "set <m-u>="
        exe "set <m-y>="
        exe "set <m-z>="
    endif
endfu

augroup set_keysyms
    au!
    au VimEnter,TermChanged * sil! call s:set_keysyms(1)
augroup END

fu! s:toggle_keysyms_in_terminal() abort "{{{3
    nno  <buffer><expr><nowait>  :  <sid>enable_keysyms_on_command_line()

    " Warning: don't change the name of the augroup{{{
    " without doing the same in:
    "
    "     ~/.vim/plugged/vim-window/autoload/window.vim
    "}}}
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
    au BufWinEnter * if &bt is# 'terminal'
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
nmap  <expr>  @  <sid>do_not_break_macro_replay()

" Do NOT use `<nowait>`.
" If we hit `@?`, the previous mapping must not be used. It wouldn't work.
" Why?
" Because the `rhs` that it would return begins like the `lhs` (@).
" This prevents the necessary recursiveness (:h recursive_mapping; exception).
