/proc/arg_identity(x)
    return x

/proc/local_sum(x)
    var/y = 2
    return x + y

/proc/choose(x)
    if(x)
        return 1
    else
        return 2

/proc/countdown(x)
    var/y = 0
    while(x)
        y = y + 1
        x = x - 1
    return y
