if exists('g:autoloaded_readline#operate_and_get_next')
    finish
endif
let g:autoloaded_readline#operate_and_get_next = 1

let s:HISTORY_MAX_SIZE = 10

fu! readline#operate_and_get_next#main() abort "{{{1
    let cmdline = getcmdline()
    let history = get(s:, 'cmdline_history', [])
    let s:pos_in_history = (index(history, cmdline) + 1) % len(history)
    if len(history) == 0
        return ''
    endif
    let seq = history[s:pos_in_history]
    return "\<cr>:".seq
endfu

fu! readline#operate_and_get_next#remember(when) abort "{{{1
    if mode() isnot# 'c'
        return
    endif
    if a:when is# 'on_leave'
        augroup remember_command
            au!
            au CmdlineLeave : call readline#operate_and_get_next#remember('now')
            au CmdlineLeave : exe 'au! remember_command' | aug! remember_command
        augroup END
    else
        let cmdline = getcmdline()
        let history = get(s:, 'cmdline_history', [])
        if cmdline is# ''
            return
        endif
        let s:cmdline_history = history + [cmdline]
        if len(history) > s:HISTORY_MAX_SIZE
            call remove(s:cmdline_history, 0)
        endif
    endif
endfu

