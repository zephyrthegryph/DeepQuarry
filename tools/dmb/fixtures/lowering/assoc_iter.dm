/proc/assoc_iter_test(var/list/L)
    var/s = 0
    for(var/k, v in L)
        s += v
    return s
