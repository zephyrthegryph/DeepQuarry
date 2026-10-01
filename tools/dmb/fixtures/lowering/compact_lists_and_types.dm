/proc/list_strings()
    return list("one", "two", "three")
/proc/list_refs(a,b)
    return list(a,b)
/proc/typed(a)
    return istype(a, /obj)
/proc/angles(a,b)
    return tan(a) + arctan(b)

/proc/angle2(a,b)
    return arctan(a,b)

