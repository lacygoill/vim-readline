vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# TODO: Try to implement these:{{{
#
#    - kill-region (zle)                ???
#    - quote-region (zle)               M-"
#    - yank-nth-arg                     M-C-y
#
# Source:
# `man zshzle`
# https://www.gnu.org/software/bash/manual/html_node/Bindable-Readline-Commands.html (best?)
# https://cnswww.cns.cwru.edu/php/chet/readline/readline.html
#}}}

import MapMeta from 'lg/map.vim'

# Autocmds {{{1

augroup InstallAddToUndolist | autocmd!
    autocmd CmdlineEnter,InsertEnter * execute 'autocmd! InstallAddToUndolist'
        | readline#addToUndolist()
augroup END

augroup OperateAndGetNext | autocmd!
    # Why a timer?{{{
    #
    # To avoid remembering commands which  we haven't executed manually like the
    # ones in mappings.
    #}}}
    autocmd CmdlineEnter : timer_start(0, (_) => readline#operateAndGetNext#remember('onLeave'))
augroup END

# Mappings {{{1
# Try to always preserve breaking undo sequence.{{{
#
# Most of these mappings take care of not breaking the undo sequence (`C-g U`).
# It means we can repeat an edition with the dot command, even if we use them.
# If you add another mapping, try to not break the undo sequence.  Thanks.
#}}}
# Ctrl {{{2
# C-@        set-mark {{{3

# If you don't use `C-@` in the insert mode mapping, disable the key.{{{
#
# By default, in insert mode, `C-@`  (`:help ^@`) inserts the last inserted text
# and leaves insert mode.
# Usually, in  a terminal `C-SPC`  produces `C-@`.  So,  when we hit  `C-SPC` by
# accident (which occurs frequently), we insert the last inserted text.
# We don't want that, so previously we disabled the mapping in our vimrc:
#
#     inoremap <C-@> <Nop>
#
# There's no need for that anymore, since we use `C-@` for setting a mark, which
# is harmless: it doesn't insert / remove any text in the buffer.
# But if for some reason, you choose another key, or remove the mapping entirely,
# make sure to disable these keys again.
#}}}
noremap! <unique> <C-@> <Cmd>if !get(g:, 'debugging') <Bar> call readline#setMark() <Bar> endif<CR>
# For some reason, there's no conflict between this mapping and `i_C-j` in vimrc.{{{
#
# Even though `C-j` produces `C-@` (C-v C-j → C-@).
#
# MWE:
#
#     inoremap  <C-J>  foo
#     inoremap  <C-@>  bar
#
#     press C-j in insert mode  →  foo
#     press C-@ "               →  bar
#
# Summary:
# `C-j`, `C-SPC`, `C-@` all seem to produce the same key code `C-@` when inserted literally.
# But in  practice, the only conflict  which we must take  into consideration is
# between `C-j`/`C-SPC` and `C-@`.
#}}}

# C-_        undo {{{3

# Why don't you use an `<expr>` mapping?{{{
#
# Using  `<expr>`  would  make  the  code of  `readline#undo()`  a  little  more
# complicated.
#}}}
cnoremap <unique> <C-_> <C-\>e !get(g:, 'debugging') ? readline#undo() : getcmdline()<CR>
inoremap <unique> <C-_> <Cmd>call readline#undo()<CR>

# C-a        beginning-of-line {{{3

noremap! <expr><unique> <C-A> !get(g:, 'debugging') ? readline#beginningOfLine() : '<C-B>'

# C-b        backward-char {{{3

noremap! <expr><unique> <C-B> !get(g:, 'debugging') ? readline#backwardChar() : '<Left>'

# C-d        delete-char {{{3

# Do *not* use `<expr>` for these mappings!{{{
#
# You would  need to invoke `feedkeys()`  from a timer because  `:redraw` has no
# effect during a textlock.
#}}}
cnoremap <unique> <C-D> <C-\>e !get(g:, 'debugging')
    \ ? readline#deleteChar()
    \ : getcmdline() .. (!!feedkeys("\<lt>del>", 'in') ? '' : '')<CR>
inoremap <unique> <C-D> <Cmd>call readline#deleteChar()<CR>

# C-e        end-of-line {{{3

inoremap <expr><unique> <C-E> readline#endOfLine()

# C-f        forward-char {{{3

&cedit = ''
noremap! <expr><unique> <C-F> !get(g:, 'debugging') ? readline#forwardChar() : '<Right>'

# C-h        backward-delete-char {{{3

noremap! <expr><unique> <C-H> !get(g:, 'debugging') ? readline#backwardDeleteChar() : '<C-H>'

# C-k        kill-line {{{3

cnoremap <expr><unique> <C-K> !get(g:, 'debugging')
    \ ? readline#killLine()
    \ : repeat('<Del>', getcmdline()->strlen() - getcmdpos() + 1)

# We need to restore the insertion of digraph functionality on the command-line.
cnoremap <unique> <C-X>k <C-K>

# In insert mode, we want C-k to keep its original behavior (insert digraph).
# It makes more sense than bind it to a `kill-line` function, because inserting
# digraph is more frequent than killing a line.
#
# But doing so, we lose the possibility to delete everything after the cursor.
# To restore this functionality, we map it to `C-k C-k`.
inoremap <expr><unique> <C-K><C-K> readline#killLine()

# C-o        operate-and-get-next {{{3

# Also called `accept-line-and-down-history` by zle.
cnoremap <expr><unique> <C-O> !get(g:, 'debugging') ? readline#operateAndGetNext#main() : ''

# C-t        transpose-chars {{{3

noremap! <expr><unique> <C-T> !get(g:, 'debugging') ? readline#transposeChars() : ''

# C-u        unix-line-discard {{{3

noremap! <expr><unique> <C-U> !get(g:, 'debugging') ? readline#unixLineDiscard() : '<C-U>'

# C-w        backward-kill-word {{{3

noremap! <expr><unique> <C-W> !get(g:, 'debugging') ? readline#backwardKillWord() : '<C-W>'

# C-x C-e    edit-and-execute-command {{{3

# Restore default C-f on the command-line (using C-x C-e){{{
# Isn't `q:` enough?
#
# No.
# What if  we're in the middle  of a command, and  we don't want to  escape then
# press `q:`? And  what if  we're on  the expression  command-line,  opened from
# insert mode?  There's no default key  binding to access the expression command
# line window (no `q=`).
#}}}
# Why C-x C-e?{{{
#
# To stay consistent with  how we open the editor to edit the  command-line in a
# shell.
#}}}
# Why not simply assigning "\<C-X>\<C-E>" to 'cedit'?{{{
#
# I think this option accepts only 1 key.
# If you give it 2 keys, it will only consider the 1st one.
# So, here's what will happen if you press `C-x`:
#
#   - Vim waits for more keys to be typed because we have mappings beginning with `C-x`
#   - we press `C-g`
#   - assuming `C-x C-g` is not mapped to anything Vim will open the command-line window ✘
#
#     Not because `&cedit = "\<C-X>\<C-G>"` (which  is not the case anyway), but
#     because the 1st key in `&cedit` matches the previous key we pressed.
#
#     This is wrong, Vim should open the command-line window *only* when we press `C-x C-e`.
#}}}
cnoremap <unique> <C-X><C-E> <Cmd>call readline#editAndExecuteCommand()<CR>

# C-x C-x    exchange-point-and-mark {{{3

# See also: https://gist.github.com/lacygoill/c8ccf30dfac6393f737e3fa4efccdf9d
noremap! <expr><unique> <C-X><C-X> !get(g:, 'debugging') ? readline#exchangePointAndMark() : ''

# C-y        yank {{{3

# Whenever we delete some multi-character text, with:
#
#    - M-d
#    - C-w
#    - C-k
#    - C-u
#
# ... we should be able to paste it with `C-y`, like in readline.

noremap! <expr><unique> <C-Y> !get(g:, 'debugging') ? readline#yank() : ''
# }}}2
# Meta {{{2
# M-b/f      forward-word    backward-word {{{3

# We can't use this:
#
#     cnoremap <M-B> <S-Left>
#     cnoremap <M-F> <S-Right>
#
# Because it seems to consider `-` as part of a word.
# `M-b`, `M-f` would move too far compared to readline.

var rhs: string = '!get(g:, "debugging")'
    # `SPC C-h` closes the wildmenu if it's open
    .. ' ? (wildmenumode() ? "<Space><C-H>" : "") .. readline#moveByWords(v:false, v:false)'
    .. ' : "<S-Left>"'

execute MapMeta('cnoremap <expr><unique> <M-B> ' .. rhs)
execute MapMeta('cnoremap <expr><unique> <M-F> '
    .. rhs->substitute('false', 'true', '')
          ->substitute('left', 'right', ''))

execute MapMeta('inoremap <expr><unique> <M-B> readline#moveByWords(v:false, v:false)')
execute MapMeta('inoremap <expr><unique> <M-F> readline#moveByWords(v:true, v:false)')

# M-i        capitalize-word {{{3

# If you want to use `M-u` as a prefix, remember to `<Nop>` it.{{{
#
#     nnoremap <M-U> <Nop>
#     noremap! <M-U> <Nop>
#     xnoremap <M-U> <Nop>
#}}}


execute MapMeta('cnoremap <unique>'
    .. ' <M-I>'
    .. ' <C-\>e !get(g:, "debugging")'
    .. ' ? readline#moveByWords(v:true, v:true)'
    .. ' : getcmdline()<CR>')

execute MapMeta('inoremap <silent><unique>'
    .. ' <M-I>'
    .. ' <C-R>=readline#moveByWords(v:true, v:true)<CR>')

execute MapMeta('nnoremap <expr><unique> <M-I> readline#moveByWords()')
execute MapMeta('xnoremap <unique> <M-I>'
    .. ' <C-\><C-N><Cmd>silent keepjumps keeppatterns'
    .. ' :* substitute/\%V.\{-}\zs\(\k\)\(\k*\%V\k\=\)/\u\1\L\2/ge<CR>')

# M-u M-o    change-case-word {{{3

execute MapMeta('cnoremap <unique> '
    .. ' <M-O>'
    .. ' <C-\>e !get(g:, "debugging")'
    .. ' ? readline#changeCaseSetup() .. readline#changeCaseWord()'
    .. ' : getcmdline()<CR>')

execute MapMeta('inoremap <silent><unique>'
    .. ' <M-O>'
    .. ' <C-R>=readline#changeCaseSetup() .. readline#changeCaseWord()<CR>')

execute MapMeta('xnoremap <unique>'
    .. ' <M-O>'
    .. ' <C-\><C-N><Cmd>silent keepjumps keeppatterns :* substitute/\%V[A-Z]/\l&/ge<CR>')

execute MapMeta('nnoremap <expr><unique> <M-O> readline#changeCaseSetup()')

execute MapMeta('cnoremap <unique>'
    .. ' <M-U>'
    .. ' <C-\>e !get(g:, "debugging")'
    .. ' ? readline#changeCaseSetup(v:true) .. readline#changeCaseWord()'
    .. ' : getcmdline()<CR>')

execute MapMeta('inoremap <silent><unique>'
    .. ' <M-U>'
    .. ' <C-R>=readline#changeCaseSetup(v:true) .. readline#changeCaseWord()<CR>')

execute MapMeta('xnoremap <unique> <M-U> U')
# Do *not* install a mapping for `M-u` in normal mode.{{{
#
# It would not work, or it would break another mapping which we already install in:
#
#     ~/.vim/pack/mine/opt/window/plugin/window.vim
#
# Don't worry; the latter is able to uppercase a word.
#}}}

# M-d        kill-word {{{3

# Delete until the beginning of the next word.
# In bash, M-d does the same, and is bound to the function kill-word.

execute MapMeta('noremap! <expr><unique>'
    .. ' <M-D>'
    .. ' !get(g:, "debugging") ? readline#killWord() : ""')

# M-n/p      history-search-forward/backward {{{3

execute MapMeta('cnoremap <unique> <M-N> <Down>')
execute MapMeta('cnoremap <unique> <M-P> <Up>')

# M-t        transpose-words {{{3

execute MapMeta('cnoremap <unique>'
    .. ' <M-T>'
    .. ' <C-\>e !get(g:, "debugging")'
    .. ' ? readline#transposeWords()'
    .. ' : getcmdline()<CR>')

execute MapMeta('inoremap <silent><unique>'
    .. ' <M-T>'
    .. ' <C-R>=readline#transposeWords()<CR>')

execute MapMeta('nnoremap <expr><unique>'
    .. ' <M-T>'
    .. ' readline#transposeWords()')

# M-y        yank-pop {{{3

execute MapMeta('noremap! <expr><unique>'
    .. ' <M-Y>'
    .. ' !get(g:, "debugging") ? readline#yank(v:true) : ""')

