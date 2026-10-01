/datum/probe
    var/datum/probe/child
    var/list/values
/proc/assign(datum/probe/a,key,value)
    a?.child?.values[key] = value
