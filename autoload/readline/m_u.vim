fu readline#m_u#main() abort
    " if a preview window is present in the tab page, scroll half a page up
    if index(map(range(1, winnr('$')), {_,v -> getwinvar(v, '&pvw')}), 1) >= 0
        call window#scroll_preview('c-u')
    else
        " otherwise, upcase the text up to the end of the current/next word
        call readline#change_case_save(1)
        set opfunc=readline#change_case_word
        norm! g@l
    endif
endfu
