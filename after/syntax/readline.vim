" Redefine the `readlineComment` group to include our custom `readlineCommentTitle` item.{{{
"
" The latter is defined in `lg#styled_comment#syntax()`:
"
"     ~/.vim/plugged/vim-lg-lib/autoload/lg/styled_comment.vim
"}}}
syn clear readlineComment
syn region readlineComment start=/#/ end=/$/  display contained oneline contains=readlineTodo,@Spell,readlineCommentTitle

