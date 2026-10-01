/obj/base
    layer = 7
    appearance_flags = 3
    plane = 12
    vis_flags = 3
/obj/base/proc_only/proc/action()
    return 1
/obj/base/proc_only/leaf/action()
    return ..()
