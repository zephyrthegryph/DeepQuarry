/proc/pair_list(list/L)
    var/result = 0
    for(var/I, V in L)
        result += I + V
    return result
/proc/pair_alist(list/L)
    var/result = 0
    for(var/key, value in alist("x" = L))
        result += value
    return result
