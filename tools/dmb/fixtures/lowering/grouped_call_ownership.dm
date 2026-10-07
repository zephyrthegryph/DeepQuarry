/world
/datum/ownership
    proc/result()
        return list(1)
    proc/group_self()
        ((result()))
/proc/getter(datum/ownership/O)
    return O
/proc/group_direct(datum/ownership/O)
    ((O.result()))
/proc/group_computed(datum/ownership/O)
    ((getter(O).result()))