/proc/probe()
    for(var/list/value = list(7); value; value = null)
        value.Add(11)
        return value[2]
    return 0
