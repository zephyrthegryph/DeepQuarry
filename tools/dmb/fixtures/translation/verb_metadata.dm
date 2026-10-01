/obj/verb/action()
    set src in view()
    set category = "Parent"
/obj/sub/action()
    set src in view(1)
    set category = "Child"
    return 1
