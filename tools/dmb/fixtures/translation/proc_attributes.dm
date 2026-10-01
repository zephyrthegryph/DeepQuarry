/proc/fixture_default()
    return
/proc/fixture_waitfor()
    set waitfor = FALSE
    return
/proc/fixture_background()
    set background = TRUE
    return
/mob/verb/fixture_hidden()
    set hidden = TRUE
    return
/mob/verb/fixture_popup()
    set popup_menu = FALSE
    return
/mob/verb/fixture_instant()
    set instant = TRUE
    return
/mob/verb/fixture_all()
    set waitfor = FALSE
    set hidden = TRUE
    set popup_menu = FALSE
    set background = TRUE
    set instant = TRUE
    set invisibility = 7
    return
/mob/verb/fixture_background_nowait()
    set waitfor = FALSE
    set background = TRUE
    return
