/datum/proc/foo(a)
    return a
/proc/probe(datum/D,list/L)
    return D.foo(arglist(L))
/proc/probe_colon(datum/D,list/L)
    return D:foo(arglist(L))
/proc/probe_colon_plain(datum/D)
    return D:foo(7)
