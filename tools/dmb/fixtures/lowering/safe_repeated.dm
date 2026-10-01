/proc/safe_repeated(var/atom/a, var/atom/b)
    if(a?.name && b?.name)
        return 1
    return 0
