/obj/probe
/proc/world_prompt()
    return input("x") as obj in world
/proc/usr_prompt()
    return input("x") as obj in usr
/proc/view_prompt()
    return input("x") as obj in view(5)
/proc/oview_prompt()
    return input("x") as obj in oview(7)
/proc/view_zero()
    return input("x") as obj in view(0)
/proc/view_default()
    return input("x") as obj in view()
/proc/view_dynamic(n)
    return input("x") as obj in view(n)
/proc/contents_prompt()
    return input("x") as obj in world.contents
/obj/probe/proc/src_prompt()
    return input("x") as obj in src