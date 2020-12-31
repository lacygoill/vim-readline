vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

var HISTORY_MAX_SIZE = 10
var cmdline_history: list<string>

def readline#operate_and_get_next#main(): string #{{{1
    if len(cmdline_history) == 0
        return ''
    endif
    var cmdline = getcmdline()
    var pos_in_history = (index(cmdline_history, cmdline) + 1) % len(cmdline_history)
    var seq = cmdline_history[pos_in_history]
    return "\<cr>:" .. seq
enddef

def readline#operate_and_get_next#remember(when: string) #{{{1
    if mode() != 'c'
        return
    endif
    if when == 'on_leave'
        au CmdlineLeave : ++once readline#operate_and_get_next#remember('now')
    else
        var cmdline = getcmdline()
        if cmdline == ''
            return
        endif
        cmdline_history = cmdline_history + [cmdline]
        if len(cmdline_history) > HISTORY_MAX_SIZE
            remove(cmdline_history, 0)
        endif
    endif
enddef

