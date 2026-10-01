/proc/sum_stepped()
    var/s = 0
    for(var/i in 1 to 5 step 2)
        s += i
    return s
