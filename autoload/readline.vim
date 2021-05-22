vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# FIXME: `Del` is broken with some composing characters.{{{
#
# Sometimes, our functions return `Del`.
# Most of the time, it works as expected; but watch this:
#
#     Ë͙͙̬̹͈͔̜́̽D̦̩̱͕͗̃͒̅̐I̞̟̣̫ͯ̀ͫ͑ͧT̞Ŏ͍̭̭̞͙̆̎̍R̺̟̼͈̟̓͆
#
# Press, `Del` while the cursor is at the beginning of the word, in a buffer; it
# works.  Now,  do the same  on the command-line; you'll  have to press  the key
# `51` times!  `51` is the output of `strchars('Ë͙͙̬̹͈͔̜́̽D̦̩̱͕͗̃͒̅̐I̞̟̣̫ͯ̀ͫ͑ͧT̞Ŏ͍̭̭̞͙̆̎̍R̺̟̼͈̟̓͆')`, btw.
# Because of this, some readline functions  don't work with these types of text,
# while on the command-line, like `M-d` and `C-w`.
#
# https://github.com/vim/vim/issues/6134
#}}}

# Could I change Vim's undo granularity automatically (via autocmds)?{{{
#
# Yes, see this: https://vi.stackexchange.com/a/2377/17449
#}}}
#   What would it allow me to do?{{{
#
# You could recover the state of the buffer after deleting some text.
# For example, you could recover the state (2) in the following edition:
#
#     " state (1)
#     hello world|
#                ^
#                cursor
#     " press: C-w
#
#     " state (2)
#     hello |
#     " press: p e o p l e
#
#     " state (3)
#     hello people|
#}}}
#   Why don't you use this code?{{{
#
# Because:
#
#    - either you  break the undo sequence  just *before* the next  insertion of a
#    character, after a sequence of deletion
#
#    - or you break it just *after*
#
# If you break it just before, then  when you insert a register after a sequence
# of deletions,  the last  character of  the register  is changed  (deleted then
# replaced by the 1st):
#
#     $ vim -Nu NONE -S <(cat <<'EOF'
#         vim9script
#         @a = 'abc'
#         set backspace=start
#         var deleting: bool
#         au InsertLeave * deleting = 0
#         au InsertCharPre * BreakUndoAfterDeletions()
#         def BreakUndoAfterDeletions()
#             if !deleting
#                 return
#             endif
#             feedkeys("\<bs>\<c-g>u" .. v:char, 'in')
#             deleting = false
#         enddef
#         ino <expr> <c-w> C_w()
#         def g:C_w(): string
#             deleting = true
#             return "\<c-w>"
#         enddef
#     EOF
#     )
#     " press: i C-w
#     " press: C-r a
#     " 'aba' is inserted instead of 'abc' ✘
#
# And if you break it just after,  then a custom abbreviation may be expanded in
# the middle of a word you type:
#
#     $ vim -Nu NONE -S <(cat <<'EOF'
#         vim9script
#         set backspace=start
#         inorea al la
#         var deleting: bool = false
#         au InsertLeave * deleting = false
#         au InsertCharPre * BreakUndoAfterDeletions()
#         def BreakUndoAfterDeletions()
#             if !deleting
#                 return
#             endif
#             feedkeys("\<c-g>u", 'in')
#             deleting = false
#         enddef
#         ino <expr> <c-w> C_w()
#         def g:C_w(): string
#             deleting = true
#             return "\<c-w>"
#         enddef
#     EOF
#     )
#     " press: i C-w
#     " press: v a l SPC
#     " 'al' is replaced by 'la' ✘
#     " this happens because `c-g u` has been executed after `v` and before `al`
#
# In any case, no  matter what you do, Vim's behavior  when editing text becomes
# less predictable.  I don't like that.
#}}}

# Init {{{1

import Catch from 'lg.vim'

augroup MyGranularUndo | au!
    # Why resetting `concat_next_kill`?{{{
    #
    #     :one two
    #     C-w Esc
    #     :three
    #     C-w
    #     C-y
    #     threetwo    ✘~
    #     C-y
    #     three       ✔~
    #}}}

    # Why `[^=]` instead of `*`?{{{
    #
    # We have some readline mappings in  insert mode and command-line mode whose
    # rhs uses `c-r =`.
    # When they are invoked, we shouldn't reset those variables.
    # Otherwise:
    #
    #     " press C-d
    #     echo b|ar
    #           ^
    #           cursor
    #
    #     " press C-d
    #     echo br
    #
    #     " press C-d
    #     echo b
    #
    #     " press C-_ (✔)
    #     echo br
    #
    #     " press C-_ (✘ we should get bar)
    #     echo br
    #}}}
    #   And why do you also include `>`?{{{
    #
    # When we quit debug mode after hitting a breakpoint, there is noise related
    # to these autocmds:
    #
    #     Entering Debug mode.  Type "cont" to continue.
    #     CmdlineLeave Autocommands for "[^=]"
    #     cmd: concat_next_kill = false
    #     >
    #     CmdlineLeave Autocommands for "[^=]"
    #     cmd: undolist_c = [] | mark_c = 0
    #     >
    #     CmdlineLeave Autocommands for "[^=]"
    #     cmd: mark_c = 0
    #}}}
    #   Won't it cause an issue when we leave the expression command-line?{{{
    #
    # Usually, we enter the expression command-line from command-line mode,
    # so the variables will be reset after we leave the regular command-line.
    #
    # But yeah, after entering the command-line from insert mode or command-line
    # mode, then getting back to the previous mode, we'll have an outdated undolist,
    # which won't be removed until we get back to normal mode.
    #
    # It should rarely happen, as I don't use the expression register frequently.
    # And when it does happen, the real  issue will only occur if we press `C-_`
    # enough to get back to this outdated undolist.
    #
    # It doesn't seem a big deal atm.
    #}}}
    #   Could `<cmd>` help?{{{
    #
    # It does, but we can't always use it.
    # Sometimes,  we  still  need  `<c-r>=`  or `<c-\>e`,  both  of  which  fire
    # `CmdlineEnter`.
    #}}}
    au CmdlineLeave [^=>] concat_next_kill = false
    # reset undolist and marks when we leave insert/command-line mode
    au CmdlineLeave [^=>] undolist_c = [] | mark_c = 0
    au InsertLeave * undolist_i = [] | mark_i = 0
augroup END

var deleting: bool = false

const FAST_SCROLL_IN_PUM: number = 5

var mark_i: number
var mark_c: number

var undolist_i: list<list<any>>
var undolist_c: list<list<any>>

# When we kill with:
#
#    - M-d: the text is appended  to the top of the kill ring
#    - C-w: the text is prepended "
#    - C-u: the text is prepended "
#    - C-k: the text is appended  "
#
# Exceptions:
# C-k + C-u  →  C-u (only the text killed by C-u goes into the top of the kill ring)
# C-u + C-k  →  C-k ("                       C-k                                   )
#
# Basically, we should *not* concat 2 consecutive big kills.
var last_kill_was_big: bool
var concat_next_kill: bool
var kill_ring_i: list<string>
var kill_ring_c: list<string>

var did_yank_or_pop: bool

# Interface {{{1
def readline#addToUndolist() #{{{2
    augroup AddToUndolist | au!
        au User AddToUndolistC AddToUndolist('c', getcmdline(), getcmdpos())
        au User AddToUndolistI AddToUndolist('i', getline('.'), col('.'))
    augroup END
enddef

def AddToUndolist( #{{{2
    mode: string,
    line: string,
    pos: number
)
    var undolist: list<list<any>> = mode == 'i' ? undolist_i : undolist_c
    var undo_len: number = len(undolist)
    if undo_len > 100
        # limit the size of the undolist to 100 entries
        remove(undolist, 0, undo_len - 101)
    endif
    if mode == 'i'
        undolist_i += [[line, pos]]
    else
        # Might need an offset for the cursor position to be correct after undoing `C-w`.
        var ppos: number = pos
        # The guard is necessary for the cursor position to be correct after undoing `M-d`.
        if pos != len(line) + 1
            ppos = pos - 1
        endif
        undolist_c += [[line, ppos]]
    endif
enddef

def readline#backwardChar(): string
    concat_next_kill = false

    # SPC + C-h = close wildmenu
    return Mode() == 'i'
        ?     "\<c-g>U\<left>"
        :     (wildmenumode() ? "\<space>\<c-h>" : '') .. "\<left>"
enddef

def readline#backwardDeleteChar(): string #{{{2
    var line: string
    var pos: number
    [line, pos] = Mode()->SetupAndGetInfo(true, false, false)
    return "\<c-h>"
enddef

def readline#backwardKillWord(): string #{{{2
    var mode: string = Mode()
    var isk_save: string = &l:isk
    var bufnr: number = bufnr('%')

    # All functions using a `try` conditional causes an issue when we hit a breakpoint while debugging an issue.{{{
    #
    #     $ vim /tmp/vim.vim +'breakadd func vim#refactor#heredoc#main'
    #     " press `=rh` (to run `:RefHeredoc`)
    #     >n
    #     " press `M-b`
    #     :return  made pending~
    #     :return  resumed~
    #
    # Solution: Inspect the type of command-line with `getcmdtype()`.
    # If it's `>`, don't use `try`.
    #
    # ---
    #
    # This solution entails  that there is a risk that  some option (e.g. 'isk')
    # is not properly restored, but that's a risk I'm willing to take.
    # If we're hitting a  breakpoint, it means that sth is  broken; and when sth
    # is broken, we often restart.
    # IOW this issue will have almost no effect in practice.
    #}}}
    if getcmdtype() == '>'
        return BackwardKillWord(mode)
    else
        try
            return BackwardKillWord(mode)
        catch
            Catch()
            return ''
        finally
            setbufvar(bufnr, '&isk', isk_save)
        endtry
    endif
    return ''
enddef

def BackwardKillWord(mode: string): string
    var line: string
    var pos: number
    [line, pos] = SetupAndGetInfo(mode, true, false, true)
    var pat: string =
        # word before cursor
        '\k*'
        # there may be some non-word text between the word and the cursor
        .. '\%(\%(\k\@!.\)\+\)\='
        # the cursor
        .. '\%' .. pos .. 'c'

    var killed_text: string = line->matchstr(pat)
    AddToKillRing(killed_text, mode, false, false)

    # Do *not* feed `<BS>` directly, because sometimes it would delete too much text.
    # It might happen when the cursor is after a sequence of whitespace (1 BS = &sw chars deleted).
    # Instead, feed `<Left><Del>`.
    return BreakUndoBeforeDeletions(mode)
         .. repeat((mode == 'i' ? "\<c-g>U" : '') .. "\<left>\<del>",
                    strcharlen(killed_text))
enddef

def readline#beginningOfLine(): string #{{{2
    concat_next_kill = 0
    if Mode() == 'c'
        return "\<home>"
    endif
    var col: number = col('.')
    var after_first_nonws = col >= getline('.')->match('\S') + 1
    var pat: string = after_first_nonws
        ?     '\S.*\%' .. col .. 'c'
        :     '\%' .. col .. 'c\s*\ze\S'
    var count: number = getline('.')->matchstr(pat)->strcharlen()
    # on a very long line, the `repeat(...)` sequence might be huge and too slow for Vim to type
    if count > &columns
        return "\<home>"
    endif
    return repeat("\<c-g>U" .. (after_first_nonws ? "\<left>" : "\<right>"), count)
enddef

def readline#changeCaseSetup(upcase = false): string #{{{2
# Warning: If you change the name of these functions:{{{
#
#    - `readline#changeCaseSetup()`
#    - `readline#changeCaseWord()`
#
# Make sure to also change them when they're referenced in
# `window#popup#scroll()`.
#}}}
    change_case_up = upcase
    if Mode() == 'n'
        &opfunc = 'readline#changeCaseWord'
        return 'g@l'
    endif
    return ''
enddef
var change_case_up: bool

def readline#changeCaseWord(type = ''): string #{{{2
    var mode: string = Mode()
    var isk_save: string = &l:isk
    var bufnr: number = bufnr('%')
    if getcmdtype() == '>'
        return ChangeCaseWord(mode)
    else
        try
            return ChangeCaseWord(mode)
        catch
            return Catch()
        finally
            setbufvar(bufnr, '&isk', isk_save)
        endtry
    endif
    return ''
enddef

def ChangeCaseWord(mode: string): string
    var line: string
    var pos: number
    [line, pos] = SetupAndGetInfo(mode, true, true, true)
    var pat: string = '\k*\%' .. pos .. 'c\zs\%(\k\+\|.\{-}\<\k\+\>\|\%(\k\@!.\)\+\)'
    var word: string = line->matchstr(pat)

    if mode == 'c'
        if pos > strlen(line)
            return line
        else
            var new_cmdline: string = line
                ->substitute(pat, change_case_up ? '\U&' : '\L&', '')
            setcmdpos(pos + strlen(word))
            return new_cmdline
        endif
    elseif mode == 'i'
        var length: number = strcharlen(word)
        return repeat("\<del>", length) .. (change_case_up ? toupper(word) : tolower(word))
    elseif mode == 'n'
        var new_line: string = line
            ->substitute(pat, (change_case_up ? '\U&' : '\L&'), '')
        var new_pos: number = match(line, pat .. '\zs') + 1
        setline('.', new_line)
        cursor(0, new_pos)
    endif
    return ''
enddef

def readline#deleteChar(): string #{{{2
    var mode: string = Mode()
    var line: string
    var pos: number
    [line, pos] = SetupAndGetInfo(mode, true, true, false)

    if mode == 'c'
        # If the cursor is at the end of the command-line, we want `C-d` to keep
        # its normal behavior  which is to list names that  match the pattern in
        # front of the  cursor.  However, if it's before the  end, we want `C-d`
        # to delete the character after it.

        if getcmdpos() > strlen(line) && getcmdtype() =~ '[:>@=]'
            # Before  pressing `C-d`,  we  first redraw  to  erase the  possible
            # listed  completion suggestions.   This makes  consecutive listings
            # more readable.
            # MWE:
            #       :h dir       C-d
            #       :h dire      C-d
            #       :h directory C-d
            redraw
            feedkeys("\<c-d>", 'in')
        else
            feedkeys("\<del>", 'in')
        endif
        return line
    endif

    #    - if the pum is visible, and there are enough matches to scroll a page down, scroll
    #    - otherwise, if we're *before* the end of the line, delete next character
    #    - "                   *at* the end of the line,     delete the newline
    var seq: string = pumvisible() && complete_info(['items']).items->len() > FAST_SCROLL_IN_PUM
        ?     repeat("\<c-n>", FAST_SCROLL_IN_PUM)
        : col('.') <= getline('.')->strlen()
        ?     "\<del>"
        :     "\<c-g>j\<home>\<bs>"
    feedkeys(seq, 'in')
    return ''
enddef

def readline#editAndExecuteCommand() #{{{2
    cedit_save = &cedit
    &cedit = "\<c-x>"
    feedkeys(&cedit, 'in')
    au CmdWinEnter * ++once &cedit = cedit_save
enddef
var cedit_save: string

def readline#endOfLine(): string #{{{2
    concat_next_kill = false
    var count: number = col('$') - col('.')
    if count > &columns
        return "\<end>"
    endif
    return repeat("\<c-g>U\<right>", count)
enddef

def readline#exchangePointAndMark(): string #{{{2
    var mode: string = Mode()

    var line: string
    var pos: number
    [line, pos] = SetupAndGetInfo(mode, false, false, false)
    var new_pos: number = mode == 'i' ? mark_i : mark_c

    var old_pos: number = line->strpart(0, pos - 1)->strcharlen()
    var motion: string
    if mode == 'i'
        motion = new_pos > old_pos
            ?     "\<c-g>U\<right>"
            :     "\<c-g>U\<left>"
    endif

    if mode == 'i'
        mark_i = old_pos
    else
        mark_c = old_pos
    endif
    return mode == 'c'
        ?     "\<c-b>" .. repeat("\<right>", new_pos)
        :     repeat(motion, abs(new_pos - old_pos))
enddef

def readline#forwardChar(): string #{{{2
    concat_next_kill = false
    return Mode() == 'c'
        ?    (wildmenumode() ? "\<space>\<c-h>" : '') .. "\<right>"
        : col('.') > getline('.')->strlen()
        ?     ''
        :     "\<c-g>U\<right>"
    # Go the right if we're in the middle of the line (custom), or fix the
    # indentation if we're at the end (default)
enddef

def readline#killLine(): string #{{{2
    var mode: string = Mode()
    var line: string
    var pos: number
    [line, pos] = SetupAndGetInfo(mode, true, false, false)

    var killed_text: string = strpart(line, pos - 1)
    AddToKillRing(killed_text, mode, true, true)

    # Warning: it may take a long time on a mega long soft-wrapped line if `'so'` is different than 0{{{
    #
    # MWE:
    #
    #     $ vim -Nu NONE \
    #     +'setl wrap so=3|ino <expr> <c-k><c-k> repeat("<del>", 11000)' \
    #     +"%d|pu =repeat(['0123456789'], 1000)|%j|0pu_|exe 'norm! j'|startinsert" /tmp/file
    #     " press C-k C-k: the line is deleted only after 2 or 3 seconds
    #}}}
    return BreakUndoBeforeDeletions(mode)
        .. repeat("\<del>", strcharlen(killed_text))
enddef

def readline#killWord(): string #{{{2
    var mode: string = Mode()
    var isk_save: string = &l:isk
    var bufnr: number = bufnr('%')
    if getcmdtype() == '>'
        return KillWord(mode)
    else
        try
            return KillWord(mode)
        catch
            return Catch()
        finally
            setbufvar(bufnr, '&isk', isk_save)
        endtry
    endif
    return ''
enddef

def KillWord(mode: string): string
    var line: string
    var pos: number
    [line, pos] = SetupAndGetInfo(mode, true, false, true)
    var pat: string =
    # from  the cursor  until the  end of  the current  word; if  the cursor  is
    # outside of a word, the pattern still matches, because we use `*`, not `+`
    '\k*\%' .. pos .. 'c'
        .. '\zs\%('
        # or all the non-word text we're in
        .. '\k\+'
        .. '\|'
        # or the next word if we're outside of a word
        .. '.\{-}\<\k\+\>'
        .. '\|'
        # the rest of the word after the cursor
        .. '\%(\k\@!.\)\+'
        .. '\)'

    var killed_text: string = line->matchstr(pat)
    AddToKillRing(killed_text, mode, true, false)

    return BreakUndoBeforeDeletions(mode)
        .. repeat("\<del>", strcharlen(killed_text))
enddef

def readline#moveByWords(type: any = '', capitalize = false): string #{{{2
#                              ^^^
#                              we sometimes abuse the variable to pass a boolean
# Implementing this function was tricky, it has to handle:{{{
#
#    - multibyte characters (éàî)
#    - multicell characters (tab)
#    - composing characters  ( ́)
#}}}
    if typename(type) == 'string' && type == ''
        &opfunc = 'readline#moveByWords'
        return 'g@l'
    endif
    var isk_save: string = &l:isk
    var bufnr: number = bufnr('%')
    if getcmdtype() == '>'
        return call(MoveByWords, [type, capitalize])
    else
        try
            return call(MoveByWords, [type, capitalize])
        # the `catch` clause prevents errors from being echoed
        # if you try to throw the exception manually (echo v:exception, echo
        # v:throwpoint), nothing will be displayed, so don't bother
        catch
            return Catch()
        finally
            setbufvar(bufnr, '&isk', isk_save)
        endtry
    endif
    return ''
enddef

def MoveByWords(arg_is_fwd: any, arg_capitalize: bool): string
    var mode: string
    var is_fwd: bool
    var capitalize: bool
    # When  this  function will  be  invoked  from  normal mode,  the  first
    # argument won't be the current mode, but the type of a text-object.
    # We need to pass the mode manually in this case (`'n'`).
    if typename(arg_is_fwd) == 'string'
        [mode, is_fwd, capitalize] = ['n', true, true]
    else
        [mode, is_fwd, capitalize] = [Mode(), arg_is_fwd, arg_capitalize]
    endif

    var line: string
    var pos: number
    #                                   ┌ if, in addition to moving the cursor forward,{{{
    #                                   │ we're going to capitalize,
    #                                   │ we want to add the current line to the undolist
    #                                   │ to be able to undo
    #                                   │
    #                                   ├────────┐}}}
    [line, pos] = SetupAndGetInfo(mode, capitalize, true, true)
    var pat: string
    if is_fwd
        # all characters from the beginning of the line until the last
        # character of the nearest *next* word (current one if we're in a word,
        # or somewhere *after* otherwise)
        # Why `\%#=1`?{{{
        #
        # https://github.com/vim/vim/pull/7572#issuecomment-753563155
        #}}}
        pat = '\%#=1.*\%' .. pos .. 'c\%(.\{-1,}\>\|.*\)'
        #                                           │
        #          if there's no word where we are, ┘
        # nor after us, then go on until the end of the line
    else
        # all characters from the beginning of the line until the first
        # character of the nearest *previous* word (current one if we're in a
        # word, or somewhere *before* otherwise)
        pat = '.*\ze\<.\{-1,}\%' .. pos .. 'c'
    endif
    var new_pos: number = matchend(line, pat)
    if new_pos == -1
        return "\<home>"
    endif

    # Here's how it works in readline:{{{
    #
    #    1. it looks for the keyword character after the cursor
    #
    #       The latter could be right after, or further away.
    #       Which means the capitalization doesn't necessarily uppercase
    #       the first character of a word.
    #
    #    2. it replaces it with its uppercase counterpart
    #
    #    3. it replaces all subsequent characters until a non-keyword character
    #       with their lowercase counterparts
    #}}}
    if capitalize
        var new_line: string = line
            ->substitute(
                '\%' .. pos .. 'c.\{-}\zs\(\k\)\(.\{-}\)\%' .. (new_pos + 1) .. 'c',
                '\u\1\L\2',
                ''
            )
        if mode == 'c'
            setcmdpos(new_pos + 1)
            return new_line
        else
            setline('.', new_line)
        endif
    endif

    var new_pos_char: number = charidx(line, new_pos)
    if new_pos_char == -1
        return "\<end>"
    endif
    # necessary to move correctly on a line such as:
    #          ́ foo  ́ bar
    var pos_char: number = line->strpart(0, pos - 1)->strcharlen()
    var diff: number = pos_char - new_pos_char
    var building_motion: string = mode == 'i'
        ?     diff > 0 ? "\<c-g>U\<left>" : "\<c-g>U\<right>"
        :     diff > 0 ? "\<left>" : "\<right>"

    # Why `feedkeys()`?{{{
    #
    # Needed  to move  the cursor at  the end  of the word  when we  want to
    # capitalize it in normal mode.
    #}}}
    var seq: string = repeat(building_motion, abs(diff))
    return mode == 'i'
        ? seq
        : (feedkeys(seq, 'in') ? '' : '')
enddef

def readline#setMark() #{{{2
    if Mode() == 'i'
        mark_i = charcol('.') - 1
    else
        mark_c = getcmdline()->strpart(0, getcmdpos() - 1)->strcharlen()
    endif
enddef

def readline#transposeChars(): string #{{{2
    var mode: string = Mode()
    var line: string
    var pos: number
    [line, pos] = SetupAndGetInfo(mode, true, true, false)
    # Test on this:
    #
    #     âêîôû
    if pos > strlen(line)
        var deleted_char: string = line[-2]
        return mode == 'i'
            ?     "\<c-g>U\<left>\<bs>\<c-g>U\<right>" .. deleted_char
            :     "\<left>\<bs>\<right>" .. deleted_char

    elseif pos > 1
        # Alternative: `line->strpart(0, pos - 1)[-1]`
        # It's (very) slightly slower though.
        var deleted_char: string = line[line->charidx(pos - 1) - 1]
        return mode == 'i'
            ?     "\<bs>\<c-g>U\<right>" .. deleted_char
            :     "\<bs>\<right>" .. deleted_char

    else
        return ''
    endif
enddef

def readline#transposeWords(type = ''): string #{{{2
    var mode: string = Mode()
    if type == '' && mode == 'n'
        &opfunc = 'readline#transposeWords'
        return 'g@l'
    endif
    var isk_save: string = &l:isk
    var bufnr: number = bufnr('%')
    if getcmdtype() == '>'
        return TransposeWords(mode)
    else
        try
            return TransposeWords(mode)
        catch
            return Catch()
        finally
            setbufvar(bufnr, '&isk', isk_save)
        endtry
    endif
    return ''
enddef

def TransposeWords(mode: string): string
    var line: string
    var pos: number
    [line, pos] = SetupAndGetInfo(mode, true, true, true)
    # We're looking for 2 words which are separated by non-word characters.
    # Why non-word characters, and not whitespace?{{{
    #
    # Because transposition works even when 2 words are separated by special
    # characters such as backticks:
    #
    #     foo``|``bar    ⇒    bar````foo
    #          ^
    #          cursor
    #}}}
    var pat: string = '\(\<\k\+\>\)\(\%(\k\@!.\)\+\)\(\<\k\+\>\)'

    # What's this concat (\&) for?{{{
    #
    # It will be used  at the end, once Vim thinks it has  found a match for
    # two words.
    # It  checks that  the cursor  isn't on  the first  word.  For  example, the
    # cursor being represented by the bar:
    #
    #     e|cho foo
    #
    # ... there should be no transposition (to mimic readline)
    #}}}
    var not_on_first: string = '\%(\<\k*\%' .. pos .. 'c\k\+\>\)\@!\&'

    # The cursor must not be before the 2 words:{{{
    #
    #         foo | bar baz
    #               ├─────┘
    #               └ don't transpose those 2
    #}}}
    var not_before: string = '\%(\%' .. pos .. 'c.*\)\@<!'

    # The cursor must not be after the 2 words,{{{
    # unless it is  inside a sequence of non-words characters  at the end of
    # the line:
    #
    #     foo bar | baz
    #     ├─────┘
    #     └ don't transpose those 2
    #
    # *or*  it is  after  them,  *but* there  are  only non-word  characters
    # between them and the end of the line:
    #
    #     foo bar !?`,;:.
    #            ├──────┘
    #            └ the cursor may be anywhere in here
    #}}}
    var not_after: string = '\%(\%(.*\%' .. pos .. 'c\)\@!\|\%(\%(\k\@!.\)*$\)\@=\)'

    # final pattern
    pat = not_on_first .. not_before .. pat .. not_after

    var new_pos: number = matchend(line, '.*\%(' .. pat .. '\)')
    var rep: string = '\3\2\1'
    var new_line: string = line->substitute(pat, rep, '')

    if mode == 'c'
        setcmdpos(new_pos + 1)
        return new_line
    else
        setline('.', new_line)
        cursor(0, new_pos + 1)
    endif
    return ''
enddef

def readline#undo(): string #{{{2
    var mode: string = Mode()
    if mode == 'i' && empty(undolist_i)
    || mode == 'c' && empty(undolist_c)
        return ''
    endif
    var old_line: string
    var old_pos: number
    [old_line, old_pos] = remove(mode == 'i' ? undolist_i : undolist_c, -1)
    UndoRestoreCursor = () => {
        if mode == 'i'
            cursor(0, old_pos)
        else
        # `setcmdpos()` doesn't work from `CmdlineChanged`.{{{
        #
        # It only works when editing the command-line.
        #
        # ---
        #
        # Note that we  only need to restore the position  in 1 particular case:
        # when there  is no text  after the cursor.   That happens e.g.  when we
        # smash `M-d`;  once there is  no word to  delete anymore, if  you press
        # `C-_` to undo the last deletion of  a word, you'll see that the cursor
        # is not restored where you want.
        #
        # I guess  we could check whether  there is some text  after the cursor,
        # before invoking `feedkeys()`.  For now, I prefer to not overcomplicate
        # the  code.  You  might  want  to add  this  check  later (*maybe*  for
        # slightly better performance on long command-lines).
        #
        # You might wonder why we only need  to restore the cursor position in 1
        # particular case.   I think  it's just a  property of  `:h c_CTRL-\_e`.
        # When you  edit the command-line  with the latter, the  cursor probably
        # remains unchanged; *unless*,  your cursor was at the end  of the line.
        # In which case, Vim probably tries to be smart, and think that you want
        # your cursor to be at the end of the new command-line (just like it was
        # at the end of the old one).
        #}}}
            feedkeys( "\<c-b>" .. repeat("\<right>", strpart(old_line, 0, old_pos)->strcharlen()), 'n')
        endif
    }
    if mode == 'c'
        au CmdlineChanged * ++once UndoRestoreCursor()
        return old_line
    else
        au TextChangedI * ++once UndoRestoreCursor()
        setline('.', old_line)
    endif
    return ''
enddef
var UndoRestoreCursor: func

def readline#unixLineDiscard(): string #{{{2
    var mode: string = Mode()
    if pumvisible() && complete_info(['items']).items->len() > FAST_SCROLL_IN_PUM
        return repeat("\<c-p>", FAST_SCROLL_IN_PUM)
    endif

    var line: string
    var pos: number
    [line, pos] = SetupAndGetInfo(mode, true, false, false)

    if mode == 'c'
        line->strpart(0, pos - 1)->AddToKillRing('c', false, true)
    else

        AddDeletedTextToKillRing = () =>
            line
            ->strpart(0, pos - 1)
            # In insert mode, `C-u` does not necessarily delete the text all the way back to column 0.{{{
            #
            # It might stop somewhere before.
            # For  example, if  `'backspace'` contains  the `start`  item, `C-u`
            # stops at the column where you've started inserting text.
            #
            # That's why, we can't simply add  all the text before the cursor in
            # the kill  ring.  If there's still  some text between column  0 and
            # the cursor, it must be removed first.
            #}}}
            ->strpart(col('.') - 1)
            ->AddToKillRing('i', false, true)

        au TextChangedI * ++once AddDeletedTextToKillRing()
    endif

    return BreakUndoBeforeDeletions(mode) .. "\<c-u>"
enddef
var AddDeletedTextToKillRing: func

def readline#yank(want_to_pop = false): string #{{{2
    var mode: string = Mode()
    if pumvisible()
        return "\<c-y>"
    endif
    var kill_ring: list<string> = mode == 'i' ? kill_ring_i : kill_ring_c
    if want_to_pop && (!did_yank_or_pop || len(kill_ring) < 2)
        || !want_to_pop && kill_ring->empty()
        return ''
    endif

    # set flag telling that `C-y` or `M-y` has just been pressed
    did_yank_or_pop = true
    var line: string
    var pos: number
    [line, pos] = SetupAndGetInfo(mode, true, true, false)
    var length: number
    if want_to_pop
        length = strcharlen(kill_ring[-1])
        insert(kill_ring, remove(kill_ring, -1), 0)
    endif
    if exists('#ResetDidYankOrPop')
        au! ResetDidYankOrPop
        aug! ResetDidYankOrPop
    endif
    au SafeState * ++once ResetDidYankOrPop()
    @- = kill_ring[-1]
    return (want_to_pop
        ?    repeat((mode == 'i' ? "\<c-g>U" : '') .. "\<left>\<del>", length)
        :    '')
        .. "\<c-r>-"
enddef

def ResetDidYankOrPop()
    # In the shell, as soon as you move the cursor, `M-y` doesn't do anything anymore.
    # We want the same behavior in Vim.
    augroup ResetDidYankOrPop | au!
        # Do *not* use a long list of events (`CursorMovedI`, `CmdlineChanged`, ...).{{{
        #
        #     au CursorMovedI,CmdlineChanged,InsertLeave,CursorMoved *
        #
        # It would not be as reliable as `SafeState`.
        # E.g., when you  move your cursor on the command-line,  the flag should
        # be reset, but there is no `CmdlineMoved` event.
        # Besides, finding the  right list of events may be  tricky; you have to
        # consider special cases, such as pressing `C-c` to leave insert mode.
        #}}}
        au SafeState * ++once did_yank_or_pop = false
    augroup END
enddef
#}}}1
# Util {{{1
def AddToKillRing( #{{{2
    text: string,
    mode: string,
    after: bool,
    this_kill_is_big: bool
)
    if concat_next_kill
        if mode == 'i'
            kill_ring_i[-1] = after
                ?     kill_ring_i[-1] .. text
                :     text .. kill_ring_i[-1]
        else
            kill_ring_c[-1] = after
                ?     kill_ring_c[-1] .. text
                :     text .. kill_ring_c[-1]
        endif
    else
        if mode == 'i' && kill_ring_i == ['']
            kill_ring_i = [text]
        elseif mode == 'c' && kill_ring_c == ['']
            kill_ring_c = [text]
        else
            var kill_ring: list<string> = mode == 'i' ? kill_ring_i : kill_ring_c
            # the kill ring  is never reset in readline; we  should not reset it
            # either but I don't like letting it  grow too much, so we keep only
            # the last 10 killed text
            if len(kill_ring) > 10
                kill_ring->remove(0, len(kill_ring) - 9)
            endif
            kill_ring
                # before adding sth in the kill-ring, check whether it's already
                # there, and if it is, remove it
                ->filter((_, v: string): bool => v != text)
                ->add(text)
        endif
    endif
    SetConcatNextKill(mode, this_kill_is_big)
enddef

def BreakUndoBeforeDeletions(mode: string): string #{{{2
    if mode == 'c' || deleting
        return ''
    else
        # If  the execution  has reached  this point,  it means  we're going  to
        # delete some  multi-char text.   But, if  we delete  another multi-char
        # text right after, we don't want to, again, break the undo sequence.
        deleting = true
        # We'll re-enable the  breaking of the undo sequence  before a deletion,
        # the next time we insert a character, or leave insert mode.
        augroup ReadlineResetDeleting | au!
            au InsertLeave,InsertCharPre * exe 'au! ReadlineResetDeleting'
                | deleting = false
        augroup END
        return "\<c-g>u"
    endif
enddef
# Purpose:{{{
#
#    - A is a text we insert
#    - B is a text we insert after A
#    - C is a text we insert to replace B after deleting the latter
#
# Without any custom “granular undo“, we can only visit:
#
#    - ∅
#    - AC
#
# This function presses `C-g  u` the first time we delete  a multi-char text, in
# any given sequence of multi-char deletions.
# This lets us visit AB.
# In the past, we used some code, which broke the undo sequence after a sequence
# of deletions.   It allowed us  to visit A (alone).   We don't use  it anymore,
# because it leads to too many issues.
#}}}

def Mode(): string #{{{2
    var mode: string = mode()
    # if you enter the search command-line from visual mode, `mode()` wrongly returns `v`
    # https://github.com/vim/vim/issues/6127#issuecomment-633119610
    # Why do you compare `mode` to `t`?{{{
    #
    #     $ vim -Nu NONE -S <(cat <<'EOF'
    #         breakadd func Func
    #         fu Func()
    #             call term_start(&shell, {'hidden': 1})->popup_create({})
    #         endfu
    #         call Func()
    #     EOF
    #     )
    #
    #     > n
    #     > echo mode()
    #     t~
    #}}}
    if mode =~ "^[vV\<c-v>t]$"
        return 'c'
    # To suppress this error in `AddToUndolist()`:{{{
    #
    #     E121: Undefined variable: undolist_R~
    #
    # Happens when we press `R` in normal mode followed by `C-y`.
    #}}}
    elseif mode =~ 'R'
        return 'i'
    endif
    return mode
enddef

def SetConcatNextKill(mode: string, this_kill_is_big: bool) #{{{2
    concat_next_kill = this_kill_is_big && last_kill_was_big ? false : true
    last_kill_was_big = this_kill_is_big

    if mode == 'c'
        # Why?{{{
        #
        # After  the next  deletion, it  the command-line  gets empty,  the deletion
        # after that shouldn't be concatenated:
        #
        #     :one C-u
        #     :two C-w
        #     C-y
        #     twoone    ✘~
        #     two       ✔~
        #}}}
        au CmdlineChanged * ++once if getcmdline() =~ '^\s*$'
            |     execute('concat_next_kill = false')
            | endif
        return
    endif

    # If we  delete a  multi-char text,  then move the  cursor *or*  insert some
    # text,  then re-delete  a multi-char  text, the  2 multi-char  texts should
    # *not* be concatenated.
    #
    # FIXME:
    # We  should  make the  autocmd  listen  to  `CursorMovedI`, but  it  would,
    # wrongly, reset  `concat_next_kill` when  we delete  a 2nd  multi-char text
    # right after a 1st one.
    augroup ReadlineResetConcatNextKill | au!
        au InsertCharPre,InsertEnter,InsertLeave * exe 'au! ReadlineResetConcatNextKill'
            | concat_next_kill = false
    augroup END
enddef

def SetupAndGetInfo( #{{{2
    mode: string,
    add_to_undolist: bool,
    reset_concat: bool,
    set_isk: bool
): list<any>

    var line: string
    var pos: number
    [line, pos] = mode == 'c'
        ?     [getcmdline(), getcmdpos()]
        :     [getline('.'), col('.')]

    # `TransposeWords()` may call this function from normal mode
    if add_to_undolist && mode != 'n'
        AddToUndolist(mode, line, pos)
    endif

    if reset_concat && mode != 'n'
        concat_next_kill = false
    endif

    if set_isk
        # Why re-setting 'isk'?{{{
        #
        # readline doesn't consider `-`, `#`, `_` as part of a word,
        # contrary to Vim which may disagree for some of them.
        #
        # Removing them from 'isk' lets us operate on the following “words“:
        #
        #     foo-bar
        #     foo#bar
        #     foo_bar
        #}}}
        # Why not using `-=` instead of `=`?{{{
        #
        # Previously, we used this code:
        #
        #     setl isk-=_ isk-=- isk-=#
        #
        # But sometimes, the mapping behaved strangely.
        # So now, I prefer to give an explicit value to `isk`.
        #}}}
        setl isk=@,48-57,192-255
    endif

    return [line, pos]
enddef

