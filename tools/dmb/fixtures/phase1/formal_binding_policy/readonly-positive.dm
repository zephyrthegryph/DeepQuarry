/datum/probe
    var/value = 0
/datum/probe/proc/member(const/value)
    src.value = 3
    return value
/proc/payload(const/list/values)
    values[1] = 7
    return values
