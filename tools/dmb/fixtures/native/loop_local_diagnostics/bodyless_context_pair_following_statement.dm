/proc/foo()
    return 7

/proc/probe()
    for(var/key, value in list("a" = 2))
    foo()
