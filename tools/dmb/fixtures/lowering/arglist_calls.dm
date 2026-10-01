/proc/arglist_callee(var/a,var/b)
    return a+b
/proc/arglist_caller(var/list/L)
    return arglist_callee(arglist(L))
/obj/sample
    proc/value(var/a,var/b)
        return a+b
/obj/sample/child
    value(var/a,var/b)
        return ..(arglist(list(a,b)))
