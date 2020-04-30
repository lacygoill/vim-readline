if exists('g:loaded_readline')
    finish
endif
let g:loaded_readline = 1

" TODO: Try to implement these:{{{
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
" FIXME: In gVim, can't insert some accented characters (e.g. `â`). {{{
"
" Read  our  notes about  mappings  to  better  understand  the issue  and  find
" workarounds.  Bear in mind that no workaround is perfect.
"
" ---
"
" Same issue in a terminal buffer.
" }}}

" Fix readline commands in a terminal buffer.{{{
"
" When you press `M-b`, the terminal writes `Esc` + `b` in the typeahead buffer.
" And since  we're going to run  `:set <M-b>=^[b`, Vim translates  this sequence
" into `<M-b>` which is identical to `â` (`:echo "\<m-b>"`).
" So, Vim sends `â` to the shell running in the terminal buffer instead of `Esc` + `b`.
" This breaks all  readline commands; to fix this, we  use Terminal-Job mappings
" to make  Vim relay the  correct sequences to the  shell (the ones  it received
" from the terminal, unchanged).
"
" https://github.com/vim/vim/issues/2397
"
" ---
"
" The issue affects gVim, but not Nvim.
" The issue affects Vim iff one of these statements is true:
"
"    - you run `:set <M-b>=^[b`
"    - you use `:h modifyOtherKeys`
"}}}
if !has('nvim')
    for s:key in map(range(char2nr('a'), char2nr('z')) + range(char2nr('A'), char2nr('Z')), 'nr2char(v:val)')
        exe 'tno <m-'..s:key..'> <esc>'..s:key
    endfor
    unlet! s:key
endif

" Autocmds {{{1

augroup install_add_to_undolist
    au!
    au CmdlineEnter,InsertEnter *
        \   exe 'au! install_add_to_undolist'
        \ | call readline#add_to_undolist()
augroup END

augroup operate_and_get_next
    au!
    " Why a timer?{{{
    "
    " To avoid remembering commands which  we haven't executed manually like the
    " ones in mappings.
    "}}}
    au CmdlineEnter : call timer_start(0, {-> readline#operate_and_get_next#remember('on_leave')})
augroup END

" Mappings {{{1
" Try to always preserve breaking undo sequence.{{{
"
" Most of these mappings take care of not breaking the undo sequence (`C-g U`).
" It means we can repeat an edition with the redo command, even if we use them.
" If you add another mapping, try to not break the undo sequence. Thanks.
"}}}
" Ctrl {{{2
" C-@        set-mark {{{3

" If you don't use `C-@` in the insert mode mapping, disable the key.{{{
"
" By default, in insert mode, `C-@` (`:h ^@`) inserts the last inserted text and
" leaves insert mode.
" Usually, in  a terminal `C-SPC`  produces `C-@`.  So,  when we hit  `C-SPC` by
" accident (which occurs frequently), we insert the last inserted text.
" We don't want that, so previously we disabled the mapping in our vimrc:
"
"     ino <c-@> <nop>
"
" There's no need for that anymore, since we use `C-@` for setting a mark, which
" is harmless: it doesn't insert / remove any text in the buffer.
" But if for some reason, you choose another key, or remove the mapping entirely,
" make sure to disable these keys again.
"}}}
noremap! <expr><unique> <c-@> readline#set_mark()
" For some reason, there's no conflict between this mapping and `i_C-j` in vimrc.{{{
"
" Even though `C-j` produces `C-@` (C-v C-j → c-@).
"
" MWE:
"
"     ino  <c-j>  foo
"     ino  <c-@>  bar
"
"     press C-j in insert mode  →  foo
"     press C-@ "               →  bar
"
" Summary:
" `C-j`, `C-SPC`, `C-@` all seem to produce the same keycode `C-@` when inserted literally.
" But in  practice, the only conflict  which we must take  into consideration is
" between `C-j`/`C-SPC` and `C-@`.
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
cno         <unique> <c-_> <c-\>e readline#undo()<cr>
ino <silent><unique> <c-_> <c-r>=readline#undo()<cr>

" C-a        beginning-of-line {{{3

noremap! <expr><unique> <c-a> readline#beginning_of_line()

" C-b        backward-char {{{3

noremap! <expr><unique> <c-b> readline#backward_char()

" C-d        delete-char {{{3

" Do NOT use `<expr>` for these mappings!{{{
"
" You would need to invoke feedkeys from a timer because `:redraw` has no effect
" during a textlock and this doesn't work well in Neovim.
"}}}
noremap! <silent><unique> <c-d> <c-r>=readline#delete_char()<cr>

" C-e        end-of-line {{{3

ino <expr><unique> <c-e> readline#end_of_line()

" C-f        forward-char {{{3

let &cedit = ''
noremap! <expr><unique> <c-f> readline#forward_char()

" C-h        backward-delete-char {{{3

noremap! <expr><unique> <c-h> readline#backward_delete_char()

" C-k        kill-line {{{3

cno <expr><unique> <c-k> readline#kill_line()

" We need to restore the insertion of digraph functionality on the command-line.
cno <unique> <c-x>k <c-k>

" In insert mode, we want C-k to keep its original behavior (insert digraph).
" It makes more sense than bind it to a `kill-line` function, because inserting
" digraph is more frequent than killing a line.
"
" But doing so, we lose the possibility to delete everything after the cursor.
" To restore this functionality, we map it to `C-k C-k`.
ino <expr><unique> <c-k><c-k> readline#kill_line()

" C-o        operate-and-get-next {{{3

" Also called `accept-line-and-down-history` by zle.
cno <expr><unique> <c-o> readline#operate_and_get_next#main()

" C-t        transpose-chars {{{3

noremap! <expr><unique> <c-t> readline#transpose_chars()

" C-u        unix-line-discard {{{3

noremap! <expr><unique> <c-u> readline#unix_line_discard()

" C-w        backward-kill-word {{{3

noremap! <expr><unique> <c-w> readline#backward_kill_word()

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
" So, here's what will happen if you press `C-x`:
"
"   - Vim waits for more keys to be typed because we have mappings beginning with `C-x`
"   - we press `C-g`
"   - assuming `C-x C-g` is not mapped to anything Vim will open the command-line window ✘
"
"     Not because `&cedit = "\<c-x>\<c-g>"` (which  is not the case anyway), but
"     because the 1st key in `&cedit` matches the previous key we pressed.
"
"     This is wrong, Vim should open the command-line window *only* when we press `C-x C-e`.
"}}}
cno <expr><unique> <c-x><c-e> readline#edit_and_execute_command()

" C-x C-x    exchange-point-and-mark {{{3

" See also: https://gist.github.com/lacygoill/c8ccf30dfac6393f737e3fa4efccdf9d
noremap! <expr><unique> <c-x><c-x> readline#exchange_point_and_mark()

" C-y        yank {{{3

" Whenever we delete some multi-character text, with:
"
"    - M-d
"    - C-w
"    - C-k
"    - C-u
"
" ... we should be able to paste it with `C-y`, like in readline.

" Nvim does not support `SafeState` yet
if !has('nvim')
    noremap! <expr><unique> <c-y> readline#yank(0)
endif
" }}}2
" Meta {{{2
" M-b/f      forward-word    backward-word {{{3

" We can't use this:
"
"     cno <m-b> <s-left>
"     cno <m-f> <s-right>
"
" Because it seems to consider `-` as part of a word.
" `M-b`, `M-f` would move too far compared to readline.

"                                               ┌  close wildmenu
"                                               │
sil! call lg#map#meta('b', '(wildmenumode() ? "<space><c-h>" : "")..readline#move_by_words(0, 0)', 'c', 'eu')
sil! call lg#map#meta('f', '(wildmenumode() ? "<space><c-h>" : "")..readline#move_by_words(1, 0)', 'c', 'eu')

sil! call lg#map#meta('b', 'readline#move_by_words(0, 0)', 'i', 'eu')
sil! call lg#map#meta('f', 'readline#move_by_words(1, 0)', 'i', 'eu')

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

sil! call lg#map#meta('i', '<c-r>=readline#move_by_words(1, 1)<cr>', 'c', 'u')
sil! call lg#map#meta('i', '<c-r>=readline#move_by_words(1, 1)<cr>', 'i', 'su')

sil! call lg#map#meta('i', ':<c-u>set opfunc=readline#move_by_words<cr>g@l', 'n', 'su')
sil! call lg#map#meta('i', ':<c-u>sil keepj keepp *s/\%V.\{-}\zs\(\k\)\(\k*\%V\k\=\)/\u\1\L\2/ge<cr>', 'x', 'su')

" M-u M-o    change-case-word {{{3

sil! call lg#map#meta('o', '<c-r>=readline#change_case_save(0)..readline#change_case_word()<cr>', 'c', 'u')
sil! call lg#map#meta('o', '<c-r>=readline#change_case_save(0)..readline#change_case_word()<cr>', 'i', 'su')
sil! call lg#map#meta('o', ':<c-u>sil keepj keepp *s/\%V[A-Z]/\l&/ge<cr>', 'x', 'su')

sil! call lg#map#meta('o', ':<c-u>call readline#change_case_save(0)<bar>set opfunc=readline#change_case_word<cr>g@l', 'n', 'su')
" Don't replace `g@l` with `g@_`.{{{
"
" It would break the repetition of an edit with the redo command.
" This is because `g@_` resets the cursor position at the start of the line.
" We don't want that; we want the cursor  to stay where it is when our opfunc is
" invoked.  The  latter inspects  the cursor column  position via  `col('.')` in
" `s:setup_and_get_info()`.
"
" ---
"
" Besides, `M-u` is a custom command, not an operator.
" We only  use an  opfunc to  make the  command repeatable;  in such  cases, you
" should always use `g@l`.
"}}}

sil! call lg#map#meta('u', '<c-r>=readline#change_case_save(1)..readline#change_case_word()<cr>', 'c', 'u')
sil! call lg#map#meta('u', '<c-r>=readline#change_case_save(1)..readline#change_case_word()<cr>', 'i', 'su')
sil! call lg#map#meta('u', 'U', 'x', 'u')
sil! call lg#map#meta('u', ':<c-u>call readline#m_u#main()<cr>', 'n', 'su')

" M-d        kill-word {{{3

" Delete until the beginning of the next word.
" In bash, M-d does the same, and is bound to the function kill-word.

sil! call lg#map#meta('d', 'readline#kill_word()', '!', 'eu')

" M-n/p      history-search-forward/backward {{{3

sil! call lg#map#meta('n', '<down>', 'c', 'u')
sil! call lg#map#meta('p', '<up>', 'c', 'u')

" M-t        transpose-words {{{3

sil! call lg#map#meta('t', '<c-r>=readline#transpose_words()<cr>', 'c', 'u')
sil! call lg#map#meta('t', '<c-r>=readline#transpose_words()<cr>', 'i', 'su')
sil! call lg#map#meta('t', ':<c-u>set opfunc=readline#transpose_words<cr>g@l', 'n', 'su')

" M-y        yank-pop {{{3

" Nvim does not support `SafeState` yet
if !has('nvim')
    sil! call lg#map#meta('y', 'readline#yank(1)', '!', 'eu')
endif

