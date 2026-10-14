/proc/target(value = 7)
    return value
var/global/value = target()
/proc/probe()
    var/local_value = value
    return target(value = local_value)
