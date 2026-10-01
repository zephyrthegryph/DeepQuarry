/datum/probe
    var/datum/probe/child
    var/list/values
    proc/get_values()
        return values
    proc/get_typed(path)
        return values
    proc/take(value)
        return value
/proc/nested(datum/probe/outer,datum/probe/a,key)
    return outer.take(a?.get_values()?[key])
/proc/nested_typed(datum/probe/outer,datum/probe/a,key)
    return outer.take(a?.child?.get_typed(/datum/probe)?[key])
