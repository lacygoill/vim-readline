if exists('g:loaded_readline')
    finish
endif
let g:loaded_readline = 1

" TODO:     Try to remove the `<expr>` argument in all the mappings.{{{
"
" Because of the  latter, we sometimes have to  invoke `execute('redraw')` which
" is ugly.
" We also have to invoke timers because of it.
"
" Note that  if you  remove `<expr>`, you  will have to  use `<c-r>=`  in insert
" mode, and probably have to invoke `feedkeys()` from command-line mode.
"}}}
" TODO:     Try to implement these:{{{
"
"    - kill-region (zle)                ???
"    - quote-region (zle)               M-"
"    - yank-nth-arg                     M-C-y
"
" Source:
" `man zshzle`
" https://www.gnu.org/software/bash/manual/html_node/Bindable-Readline-Commands.html (best?)
" https://cnswww.cns.cwru.edu/php/chet/readline/readline.html
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
" FIXME:    Can't insert [áâäåæçéíîïðôõù]  {{{
"
" A mapping using a meta key prevents the insertion of some special characters
" for example:
"
"         1. ino <m-b> …
"         2. i_â
"         moves cursor one word backward~
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
"     C-v ^ a
"     â~
"
" Use digraph:
"
"     C-k a a
"     â~
"
" Use replace mode:
"
"     r ^ a
"     â~
"
" Use abbreviation
"
" Use equivalence class in a search command
" }}}

" AUTOCMD {{{1

unlet! s:did_shoot
au CmdlineEnter,InsertEnter * ++once
    \ if !get(s:, 'did_shoot', 0)
    \ |     let s:did_shoot = 1
    \ |     sil! call readline#add_to_undolist()
    \ | endif

augroup operate_and_get_next
    au!
    " Why a timer?{{{
    "
    " To avoid remembering commands which  we haven't executed manually like the
    " ones in mappings.
    "}}}
    au CmdlineEnter : call timer_start(0, {-> readline#operate_and_get_next#remember('on_leave')})
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

" Why don't you use an `<expr>` mapping?{{{
"
" We can't use `<expr>` because of an issue with Nvim.
" After pressing  the lhs, you would  need to insert an  additional character to
" cause a redraw; otherwise, you would not see the new text.
"
" It's probably due to:
" https://github.com/neovim/neovim/issues/9006
"
" Besides, using `<expr>` would make the code of `readline#undo()` a little more
" complicated.
"}}}
cno          <unique>  <c-_>  <c-\>ereadline#undo('c')<cr>
ino  <silent><unique>  <c-_>  <c-r>=readline#undo('i')<cr>

" C-a        beginning-of-line {{{3

cno  <expr><unique>  <c-a>  readline#beginning_of_line('c')
ino  <expr><unique>  <c-a>  readline#beginning_of_line('i')

" restore default i_C-a
" insert previously inserted text
ino  <c-x><c-a>  <c-a>

" restore default c_C-a
" dump all candidates on the command-line
cno  <unique>  <c-x><c-a>  <c-a>

" also, create custom C-x C-d
" capture all candidates in the unnamed register
cno  <expr>  <c-x><c-d>  '<c-a>'.timer_start(0, {-> setreg('"', getcmdline(), 'l') + feedkeys('<c-c>', 'in') })[-1]

" C-b        backward-char {{{3

cno  <expr><unique>  <c-b>  readline#backward_char('c')
ino  <expr><unique>  <c-b>  readline#backward_char('i')

" C-d        delete-char {{{3

" Do NOT use `<expr>` for these mappings!{{{
"
" You would need to invoke feedkeys from a timer because `:redraw` has no effect
" during a textlock and this doesn't work well in Neovim.
"}}}
cno  <silent><unique>  <c-d>  <c-r>=readline#delete_char('c')<cr>
ino  <silent><unique>  <c-d>  <c-r>=readline#delete_char('i')<cr>

" C-e        end-of-line {{{3

ino  <expr><unique>  <c-e>  readline#end_of_line()

" C-f        forward-char {{{3

let &cedit = ''
cno  <expr><unique>  <c-f>  readline#forward_char('c')
ino  <expr><unique>  <c-f>  readline#forward_char('i')

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

" C-o        operate-and-get-next {{{3

" Also called `accept-line-and-down-history` by zle.
cno  <expr>  <c-o>  readline#operate_and_get_next#main()

" C-t        transpose-chars {{{3

cno  <expr><unique>  <c-t>  readline#transpose_chars('c')
ino  <expr><unique>  <c-t>  readline#transpose_chars('i')

" C-u        unix-line-discard {{{3

cno  <expr><unique>  <c-u>  readline#unix_line_discard('c')
ino  <expr><unique>  <c-u>  readline#unix_line_discard('i')

" C-w        backward-kill-word {{{3

cno  <expr><unique>  <c-w>  readline#backward_kill_word('c')
ino  <expr><unique>  <c-w>  readline#backward_kill_word('i')

" C-x C-e    edit-and-execute-command {{{3

" Restore default C-f on the command-line (using C-x C-e){{{
" Isn't `q:` enough?
"
" No.
" What if  we're in the middle  of a command, and  we don't want to  escape then
" press `q:`? And  what if  we're on  the expression  command-line,  opened from
" insert mode?  There's no default key  binding to access the expression command
" line window (no `q=`).
"}}}
" Why C-x C-e?{{{
"
" To stay consistent with  how we open the editor to edit the  command-line in a
" shell.
"}}}
" Why not simply assigning "\<c-x>\<c-e>" to 'cedit'?{{{
"
" I think this option accepts only 1 key.
" If you give it 2 keys, it will only consider the 1st one.
" So, here's what will  happen if you press C-x:
"
"   - Vim waits for more keys to be typed because we have mappings beginning with C-x
"   - we press C-g
"   - assuming C-x C-g is not mapped to anything Vim will open the command-line window ✘
"
"     Not because `&cedit = "\<c-x>\<c-g>"` (which  is not the case anyway), but
"     because the 1st key in '&cedit' matches the previous key we pressed.
"
"     This is wrong, Vim should open the command-line window ONLY when we press C-x C-e.
"}}}
cno  <expr><unique>  <c-x><c-e>  readline#edit_and_execute_command()

" C-x C-x    exchange-point-and-mark {{{3

" See also: https://gist.github.com/lacygoill/c8ccf30dfac6393f737e3fa4efccdf9d
cno  <expr><unique>  <c-x><c-x>  readline#exchange_point_and_mark('c')
ino  <expr><unique>  <c-x><c-x>  readline#exchange_point_and_mark('i')

" C-y        yank {{{3

" Whenever we delete some multi-character text, with:
"
"    - M-d
"    - C-w
"    - C-k
"    - C-u
"
" ... we should be able to paste it with C-y, like in readline.

ino  <expr><unique>  <c-y>  readline#yank('i', 0)
cno  <expr><unique>  <c-y>  readline#yank('c', 0)
" }}}2
" META {{{2
" M-b/f      forward-word    backward-word {{{3

" We can't use this:
"
"     cno <m-b> <s-left>
"     cno <m-f> <s-right>
"
" Because it seems to consider `-` as part of a word.
" `M-b`, `M-f` would move too far compared to readline.

"                                              ┌  close wildmenu
"                                              │
cno  <expr><unique>  <m-b> (wildmenumode() ? '<space><c-h>' : '').readline#move_by_words('c', 0, 0)
cno  <expr><unique>  <m-f> (wildmenumode() ? '<space><c-h>' : '').readline#move_by_words('c', 1, 0)

ino  <expr><unique>  <m-b>  readline#move_by_words('i', 0, 0)
ino  <expr><unique>  <m-f>  readline#move_by_words('i', 1, 0)

" M-i        capitalize-word {{{3

" The next 3 mappings are commented, because we don't need them anymore.
" But if  one day you modify  the lhs of the  mappings which change the  case of
" words, and decide to  use `M-u` as a prefix (e.g. `M-u u`,  `M-u i`, `M-u o`),
" make sure to uncomment them.
" Necessary in Nvim.{{{
"
" Otherwise, if you press `M-u`, followed by a "wrong" key, you'll get unexpected results.
"
" MWE:
"
"     $ nvim /tmp/file
"     itest
"     Esc
"     M-u l
"
" `l` is "wrong" because we don't have any `M-u l` key binding, and Nvim removes the text.
"}}}
"     nno <m-u> <nop>
" Same issue.{{{
"
" Besides, in Vim, if you press `M-u l`, Vim inserts a weird character:
"
"     õl
"     ^
"}}}
"     noremap! <m-u> <nop>
" Necessary in Nvim.{{{
"
" Without, if you press `M-u l` in visual mode, Nvim makes you quit visual mode,
" and prints a message such as "5 lines changed".
"
" In Vim, `M-u l` in visual mode  simply widens the selection  one character to
" the right.
"}}}
"     xno <m-u> <nop>

cno          <unique>  <m-i>  <c-r>=readline#move_by_words('c', 1, 1)<cr>
ino  <silent><unique>  <m-i>  <c-r>=readline#move_by_words('i', 1, 1)<cr>

nno  <silent><unique>  <m-i>  :<c-u>set opfunc=readline#move_by_words<cr>g@l
xno  <silent><unique>  <m-i>  :<c-u>sil keepj keepp
\                             '<,'>s/\v%V.{-}\zs(\k)(\k*%V\k?)/\u\1\L\2/ge<cr>

" M-u M-o    change-case-word {{{3

cno          <unique>  <m-o>  <c-r>=readline#change_case_save(0).readline#change_case_word('', 'c')<cr>
ino  <silent><unique>  <m-o>  <c-r>=readline#change_case_save(0).readline#change_case_word('', 'i')<cr>
xno  <silent><unique>  <m-o>  :<c-u>sil keepj keepp '<,'>s/\%V[A-Z]/\l&/ge<cr>
nno  <silent><unique>  <m-o>  :<c-u>call readline#change_case_save(0)<bar>set opfunc=readline#change_case_word<cr>g@l
"                                                                             ^{{{
"                                                                        don't write `_`
" It would break the repetition of the edit with the dot command.
"}}}

cno          <unique>  <m-u>  <c-r>=readline#change_case_save(1).readline#change_case_word('', 'c')<cr>
ino  <silent><unique>  <m-u>  <c-r>=readline#change_case_save(1).readline#change_case_word('', 'i')<cr>
xno          <unique>  <m-u>  U
nno  <silent><unique>  <m-u>  :<c-u>call readline#m_u()<cr>

" M-d        kill-word {{{3

" Delete until the beginning of the next word.
" In bash, M-d does the same, and is bound to the function kill-word.

cno  <expr><unique>  <m-d>  readline#kill_word('c')
ino  <expr><unique>  <m-d>  readline#kill_word('i')

" M-n/p      down up {{{3

" We can't simply write `<Down>` in the rhs.{{{
"
" It would make  Vim close the wildmenu,  and insert a literal  Tab character (a
" Tab because the value of `'wc'` is 9).
"
" See:
"
" https://groups.google.com/d/msg/vim_dev/xf5TRb4uR4Y/djk2dq2poaQJ
" http://stackoverflow.com/a/14849216
"
" ---
"
" Alternative:
"
" Temporarily reset `'wcm'`, to make sure that it has the same value as `'wc'`:
"
"     cmap <expr><unique> <m-n>                         <sid>readline_down()
"     cno                 <plug>(readline-down)         <down>
"     cno  <expr>         <plug>(readline-restore-wcm)  <sid>restore_wcm()
"
"     fu! s:readline_down() abort
"         let s:wcm_save = &wcm
"         let &wcm = &wc
"         return "\<plug>(readline-down)\<plug>(readline-restore-wcm)"
"     endfu
"
"     fu! s:restore_wcm() abort
"         let &wcm = get(s:, 'wcm_save', 9)
"         return ''
"     endfu
"}}}
cno  <expr><unique>  <m-n>  feedkeys("\<down>", 't')[-1]

" history-search-backward
" history-search-forward
cno  <unique>  <m-p>  <up>

" M-t        transpose-words {{{3

cno          <unique>  <m-t>  <c-r>=readline#transpose_words('', 'c')<cr>
ino  <silent><unique>  <m-t>  <c-r>=readline#transpose_words('', 'i')<cr>
nno  <silent><unique>  <m-t>  :<c-u>set opfunc=readline#transpose_words<cr>g@l

" M-y        yank-pop {{{3

cno  <expr><unique>  <m-y>  readline#yank('c', 1)

" Disabled in Vim, because we press `ù` by accident too frequently.
" When it happens, we invoke `readline#yank()` which is extremely distracting.
" It completely changes the text we've typed.
if has('nvim')
    ino  <expr><unique>  <m-y>  readline#yank('i', 1)
endif
" }}}1
" OPTIONS {{{1

if !has('nvim')
    " don't use `c-w` as a prefix to execute commands manipulating the window in
    " which a  terminal buffer  is displayed; `c-w`  should delete  the previous
    " word; use `c-g` instead
    set termwinkey=<c-g>
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
"  ┌ no need to teach anything for nvim or gVim (they already know)
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
    "    1. It's probably useless.
    "    2. If the Ex command prints a message, it will be automatically erased.
    if char is# ':'
        return '@:'
    endif

    " Warning:{{{
    " `do_not_break_macro_replay()` will NOT work when you do this:
    "
    "     norm! @q
    "
    " ... instead, you must do this:
    "
    "     norm @q
"}}}
    call s:set_keysyms(0)

    set updatetime=5
    unlet! s:did_shoot
    au CursorHold,CursorHoldI * ++once
        \ if !get(s:, 'did_shoot', 0)
        \ |     let s:did_shoot = 1
        \ |     sil! call s:set_keysyms(1)
        \ |     sil! let &ut = s:original_ut
        \ | endif

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
        exe "set <m-h>=\eh"
        exe "set <m-i>=\ei"
        exe "set <m-j>=\ej"
        exe "set <m-k>=\ek"
        exe "set <m-l>=\el"
        exe "set <m-m>=\em"
        exe "set <m-n>=\en"
        exe "set <m-o>=\eo"
        exe "set <m-p>=\ep"
        exe "set <m-t>=\et"
        exe "set <m-u>=\eu"
        exe "set <m-y>=\ey"
    else
        exe "set <m-a>="
        exe "set <m-b>="
        exe "set <m-d>="
        exe "set <m-e>="
        exe "set <m-f>="
        exe "set <m-g>="
        exe "set <m-h>="
        exe "set <m-i>="
        exe "set <m-j>="
        exe "set <m-k>="
        exe "set <m-l>="
        exe "set <m-m>="
        exe "set <m-n>="
        exe "set <m-o>="
        exe "set <m-p>="
        exe "set <m-t>="
        exe "set <m-u>="
        exe "set <m-y>="
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
    let is_unset = execute('set <M-p>', 'silent!') is# "\n"

    call s:set_keysyms(is_unset)

    " Flush any delayed screen updates before printing the message.
    " See `:h :echo-redraw`.
    " MWE: {{{
    "
    "     :set fdm=manual | echo 'hello'           ✔
    "     :set <M-a>=     | echo 'hello'           ✘
    "     :set <M-a>=     | echo "hello\nworld"    ✔
    "}}}
    redraw
    echom '[Fix Macro] Meta keys '.(is_unset ? 'Enabled' : 'Disabled')
endfu

" command {{{2
" This command can be useful to temporarily disable meta keys before replaying a
" macro.
com! -bar ToggleMetaKeys call s:toggle_meta_keys()

" autocommand {{{2
augroup handle_keysyms
    au!
    au TerminalOpen  *  call s:set_keysyms(0)
                   \ |  call s:toggle_keysyms_in_terminal()
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
" See here for more info: https://github.com/tpope/vim-rsi/issues/13
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
