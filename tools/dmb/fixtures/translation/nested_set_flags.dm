/obj/item/proc/nested_background()
    spawn(0)
        set background = 1
        return 1
/obj/item/proc/nested_waitfor()
    spawn(0)
        set waitfor = 0
        return 1
/obj/item/proc/outer_background()
    set background = 1
    return 1
