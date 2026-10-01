/proc/indexed_or(var/list/values, var/key, var/value)
    return values[key] ||= value

/proc/indexed_and(var/list/values, var/key, var/value)
    return values[key] &&= value

/proc/indexed_preincrement(var/list/values, var/key)
    return ++values[key]

/proc/indexed_predecrement(var/list/values, var/key)
    return --values[key]

/datum/logical_receiver/proc/value()
    return 7

/proc/indexed_or_method(var/list/values, var/key, var/datum/logical_receiver/other)
    return values[key] ||= other.value()
