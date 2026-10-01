/datum/safe_methods
    proc/method(value)
        return value
/proc/safe_named(datum/safe_methods/a)
    return a?.method(value=1)
/proc/safe_arglist(datum/safe_methods/a,list/values)
    return a?.method(arglist(values))
