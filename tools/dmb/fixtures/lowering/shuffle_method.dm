/proc/shuffle_method(var/list/L,var/i)
    L.Swap(i, rand(i,L.len))
    return L