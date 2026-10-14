/proc/probe()
    var/x = 1
    for(var/x, value in list("a" = 2))
        return value
