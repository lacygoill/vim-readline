vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

def readline#m_u#main()
    # if a preview window is present in the tab page, scroll half a page up
    sil! if window#util#hasPreview() || window#util#latestPopup()
        sil! window#popup#scroll('c-u')
    else
        # otherwise, upcase the text up to the end of the current/next word
        readline#changeCaseSetup(true)
        set opfunc=readline#changeCaseWord
        norm! g@l
    endif
enddef

