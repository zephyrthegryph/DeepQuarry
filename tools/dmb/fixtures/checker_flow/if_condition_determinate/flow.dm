/proc/branches(a)
    if(0)
        if(1)
            a=1
    else if(1)
        a=2
    else if(0)
        a=3
    else
        a=4
/proc/syntactic(a)
    if(a)
        a=1
    if(1 || a)
        a=2
    if(1 == 1)
        a=3
    if((0))
        a=4
/proc/skipped(a)
    return
    if(1)
        a=1
