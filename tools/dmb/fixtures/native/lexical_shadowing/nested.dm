/proc/shadow_probe()
    var/value = 7
    if(1)
        var/value = 9
        if(value != 9)
            return -1
    return value
