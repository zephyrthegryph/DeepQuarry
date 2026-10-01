/obj/sample
    New(var/x,var/y)
        ..()
/proc/dynamic_new(var/T,var/x)
    return new T(x)
/proc/dynamic_new_noargs(var/T)
    return new T()
/proc/dynamic_new_two(var/T,var/x,var/y)
    return new T(x,y)
