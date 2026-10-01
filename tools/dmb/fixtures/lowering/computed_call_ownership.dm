/world
/datum/ownership
    var/datum/ownership/child
    proc/result(a=1,b=2)
        return list(a,b)
/proc/getter(datum/ownership/O)
    return O
/proc/computed_empty(datum/ownership/O)
    getter(O).result()
/proc/computed_positional(datum/ownership/O)
    getter(O).result(1,2)
/proc/computed_named(datum/ownership/O)
    getter(O).result(b=3,a=4)
/proc/computed_arglist(datum/ownership/O,list/L)
    getter(O).result(arglist(L))
/proc/computed_conditional(a,datum/ownership/O,datum/ownership/P)
    (a ? O : P).result()
/proc/computed_short(a,datum/ownership/O)
    (a || O).result()
/proc/computed_value(datum/ownership/O)
    return getter(O).result()
/proc/computed_safe(datum/ownership/O)
    getter(O)?.result()
/proc/direct_child(datum/ownership/O)
    O.child.result()
/proc/direct_owner(datum/ownership/O)
    O.result()
/proc/direct_multiline(datum/ownership/O)
    O.result(
        1,
        2
    )
    return 1
