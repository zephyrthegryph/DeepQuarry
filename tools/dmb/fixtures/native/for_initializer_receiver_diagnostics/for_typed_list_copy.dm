/proc/probe()
    for(var/list/value = list(7); value; value = null)
        return value.Copy()[1]
    return 0
