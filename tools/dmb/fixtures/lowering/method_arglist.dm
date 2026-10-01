/obj/sample
    proc/value(var/a,var/b)
        return a+b
/proc/method_arglist(var/obj/sample/a,var/list/L)
    return a.value(arglist(L))
/proc/method_named(var/obj/sample/a)
    return a.value(b=2,a=1)
