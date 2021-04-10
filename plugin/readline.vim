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

augroup InstallAddToUndolist | au!
    au CmdlineEnter,InsertEnter * exe 'au! InstallAddToUndolist'
        | readline#addToUndolist()
augroup END

augroup OperateAndGetNext | au!
    # Why a timer?{{{
    #
    # To avoid remembering commands which  we haven't executed manually like the
    # ones in mappings.
    #}}}
    au CmdlineEnter : timer_start(0, (_) => readline#operateAndGetNext#remember('on_leave'))
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
# By default, in insert mode, `C-@` (`:h ^@`) inserts the last inserted text and
# leaves insert mode.
# Usually, in  a terminal `C-SPC`  produces `C-@`.  So,  when we hit  `C-SPC` by
# accident (which occurs frequently), we insert the last inserted text.
# We don't want that, so previously we disabled the mapping in our vimrc:
#
#     ino <c-@> <nop>
#
# There's no need for that anymore, since we use `C-@` for setting a mark, which
# is harmless: it doesn't insert / remove any text in the buffer.
# But if for some reason, you choose another key, or remove the mapping entirely,
# make sure to disable these keys again.
#}}}
noremap! <unique> <c-@> <cmd>call readline#setMark()<cr>
# For some reason, there's no conflict between this mapping and `i_C-j` in vimrc.{{{
#
# Even though `C-j` produces `C-@` (C-v C-j → c-@).
#
# MWE:
#
#     ino  <c-j>  foo
#     ino  <c-@>  bar
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
cno <unique> <c-_> <c-\>e readline#undo()<cr>
ino <unique> <c-_> <cmd>call readline#undo()<cr>

# C-a        beginning-of-line {{{3

noremap! <expr><unique> <c-a> readline#beginningOfLine()

# C-b        backward-char {{{3

noremap! <expr><unique> <c-b> readline#backwardChar()

# C-d        delete-char {{{3

# Do *not* use `<expr>` for these mappings!{{{
#
# You would  need to invoke `feedkeys()`  from a timer because  `:redraw` has no
# effect during a textlock.
#}}}
cno <unique> <c-d> <c-\>e readline#deleteChar()<cr>
ino <unique> <c-d> <cmd>call readline#deleteChar()<cr>

# C-e        end-of-line {{{3

ino <expr><unique> <c-e> readline#endOfLine()

# C-f        forward-char {{{3

&cedit = ''
noremap! <expr><unique> <c-f> readline#forwardChar()

# C-h        backward-delete-char {{{3

noremap! <expr><unique> <c-h> readline#backwardDeleteChar()

# C-k        kill-line {{{3

cno <expr><unique> <c-k> readline#killLine()

# We need to restore the insertion of digraph functionality on the command-line.
cno <unique> <c-x>k <c-k>

# In insert mode, we want C-k to keep its original behavior (insert digraph).
# It makes more sense than bind it to a `kill-line` function, because inserting
# digraph is more frequent than killing a line.
#
# But doing so, we lose the possibility to delete everything after the cursor.
# To restore this functionality, we map it to `C-k C-k`.
ino <expr><unique> <c-k><c-k> readline#killLine()

# C-o        operate-and-get-next {{{3

# Also called `accept-line-and-down-history` by zle.
cno <expr><unique> <c-o> readline#operateAndGetNext#main()

# C-t        transpose-chars {{{3

noremap! <expr><unique> <c-t> readline#transposeChars()

# C-u        unix-line-discard {{{3

noremap! <expr><unique> <c-u> readline#unixLineDiscard()

# C-w        backward-kill-word {{{3

noremap! <expr><unique> <c-w> readline#backwardKillWord()

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
# Why not simply assigning "\<c-x>\<c-e>" to 'cedit'?{{{
#
# I think this option accepts only 1 key.
# If you give it 2 keys, it will only consider the 1st one.
# So, here's what will happen if you press `C-x`:
#
#   - Vim waits for more keys to be typed because we have mappings beginning with `C-x`
#   - we press `C-g`
#   - assuming `C-x C-g` is not mapped to anything Vim will open the command-line window ✘
#
#     Not because `&cedit = "\<c-x>\<c-g>"` (which  is not the case anyway), but
#     because the 1st key in `&cedit` matches the previous key we pressed.
#
#     This is wrong, Vim should open the command-line window *only* when we press `C-x C-e`.
#}}}
cno <unique> <c-x><c-e> <cmd>call readline#editAndExecuteCommand()<cr>

# C-x C-x    exchange-point-and-mark {{{3

# See also: https://gist.github.com/lacygoill/c8ccf30dfac6393f737e3fa4efccdf9d
noremap! <expr><unique> <c-x><c-x> readline#exchangePointAndMark()

# C-y        yank {{{3

# Whenever we delete some multi-character text, with:
#
#    - M-d
#    - C-w
#    - C-k
#    - C-u
#
# ... we should be able to paste it with `C-y`, like in readline.

noremap! <expr><unique> <c-y> readline#yank()
# }}}2
# Meta {{{2
# M-b/f      forward-word    backward-word {{{3

# We can't use this:
#
#     cno <m-b> <s-left>
#     cno <m-f> <s-right>
#
# Because it seems to consider `-` as part of a word.
# `M-b`, `M-f` would move too far compared to readline.

#                                 ┌  close wildmenu
#                                 │
MapMeta('b', '(wildmenumode() ? "<space><c-h>" : "") .. readline#moveByWords(v:false, v:false)', 'c', 'eu')
MapMeta('f', '(wildmenumode() ? "<space><c-h>" : "") .. readline#moveByWords(v:true, v:false)', 'c', 'eu')

MapMeta('b', 'readline#moveByWords(v:false, v:false)', 'i', 'eu')
MapMeta('f', 'readline#moveByWords(v:true, v:false)', 'i', 'eu')

# M-i        capitalize-word {{{3

# If you want to use `M-u` as a prefix, remember to `<nop>` it.{{{
#
#     nno <m-u> <nop>
#     noremap! <m-u> <nop>
#     xno <m-u> <nop>
#}}}

MapMeta('i', '<c-\>e readline#moveByWords(v:true, v:true)<cr>', 'c', 'u')
MapMeta('i', '<c-r>=readline#moveByWords(v:true, v:true)<cr>', 'i', 'su')

MapMeta('i', 'readline#moveByWords()', 'n', 'eu')
MapMeta('i', '<c-\><c-n><cmd>sil keepj keepp *s/\%V.\{-}\zs\(\k\)\(\k*\%V\k\=\)/\u\1\L\2/ge<cr>', 'x', 'u')

# M-u M-o    change-case-word {{{3

MapMeta('o', '<c-\>e readline#changeCaseSetup() .. readline#changeCaseWord()<cr>', 'c', 'u')
MapMeta('o', '<c-r>=readline#changeCaseSetup() .. readline#changeCaseWord()<cr>', 'i', 'su')
MapMeta('o', '<c-\><c-n><cmd>sil keepj keepp *s/\%V[A-Z]/\l&/ge<cr>', 'x', 'u')

MapMeta('o', 'readline#changeCaseSetup()', 'n', 'eu')

MapMeta('u', '<c-\>e readline#changeCaseSetup(v:true) .. readline#changeCaseWord()<cr>', 'c', 'u')
MapMeta('u', '<c-r>=readline#changeCaseSetup(v:true) .. readline#changeCaseWord()<cr>', 'i', 'su')
MapMeta('u', 'U', 'x', 'u')
MapMeta('u', '<cmd>call readline#mU#main()<cr>', 'n', 'u')

# M-d        kill-word {{{3

# Delete until the beginning of the next word.
# In bash, M-d does the same, and is bound to the function kill-word.

MapMeta('d', 'readline#killWord()', '!', 'eu')

# M-n/p      history-search-forward/backward {{{3

MapMeta('n', '<down>', 'c', 'u')
MapMeta('p', '<up>', 'c', 'u')

# M-t        transpose-words {{{3

MapMeta('t', '<c-\>e readline#transposeWords()<cr>', 'c', 'u')
MapMeta('t', '<c-r>=readline#transposeWords()<cr>', 'i', 'su')
MapMeta('t', 'readline#transposeWords()', 'n', 'eu')

# M-y        yank-pop {{{3

MapMeta('y', 'readline#yank(v:true)', '!', 'eu')

