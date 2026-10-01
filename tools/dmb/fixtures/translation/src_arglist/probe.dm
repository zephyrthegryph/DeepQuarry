/datum/proc/foo(value)
    return value
/datum/proc/bar(list/L)
    return foo(arglist(L))
/proc/baz(value)
    return value
/proc/qux(list/L)
    return baz(arglist(L))
