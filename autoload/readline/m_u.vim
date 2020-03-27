fu readline#m_u#main() abort
    " if a preview window is present in the tab page, scroll half a page up
    sil! if window#has_preview() || window#has_popup()
        sil! call window#scroll_preview_or_popup('c-u')
    else
        " otherwise, upcase the text up to the end of the current/next word
        call readline#change_case_save(1)
        set opfunc=readline#change_case_word
        norm! g@l
    endif
endfu

