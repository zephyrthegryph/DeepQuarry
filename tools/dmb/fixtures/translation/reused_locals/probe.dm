/proc/reused_local(x)
    if(x)
        var/value = 1
        x += value
    else
        var/value = 2
        x += value
    return x
/proc/reused_loop_local(list/L)
    for(var/i in L)
        var/value = i
    for(var/i in L)
        var/value = i
    return 1
