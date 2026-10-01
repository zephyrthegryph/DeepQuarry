/proc/probe(n,s)
    var/total = 0
    for(var/j in 1 to n step s)
        total += j
    return total
