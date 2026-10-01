/obj/dmb_fixture/verb/normal()
    return

/obj/dmb_fixture/verb/hidden()
    set hidden = 1
    return

/obj/dmb_fixture/verb/invisible()
    set invisibility = 42
    return

/obj/dmb_fixture/verb/visible_level_zero()
    set invisibility = 0
    return

/obj/dmb_fixture/verb/background()
    set background = 1
    return

/obj/dmb_fixture/verb/instant()
    set instant = 1
    return

/obj/dmb_fixture/verb/nonwaiting()
    set waitfor = 0
    return
