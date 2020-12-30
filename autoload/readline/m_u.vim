fu readline#m_u#main() abort
    " if a preview window is present in the tab page, scroll half a page up
    sil! if window#util#hasPreview() || window#util#latestPopup()
        sil! call window#popup#scroll('c-u')
    else
        " otherwise, upcase the text up to the end of the current/next word
        call readline#change_case_setup(1)
        set opfunc=readline#change_case_word
        norm! g@l
    endif
endfu

