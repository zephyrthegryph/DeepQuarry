/obj/sample
    New(var/foo,var/bar)
        ..()
/proc/new_arglist(var/list/L)
    return new /obj/sample(arglist(L))
/proc/new_arglist_dynamic(var/T,var/list/L)
    return new T(arglist(L))
