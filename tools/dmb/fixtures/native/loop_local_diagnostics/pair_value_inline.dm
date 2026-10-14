/proc/probe()
    var/value = 1
    for(var/key, value in list("a" = 2)) return value
