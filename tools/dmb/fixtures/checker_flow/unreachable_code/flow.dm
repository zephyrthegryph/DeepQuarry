/proc/sibling(a)
    return
    if(a)
        a=1
    a=2
/proc/arms(a)
    if(1)
        a=1
    else if(0)
        a=2
    else
        a=3
/proc/ordinary(a)
    while(a)
        return
    a=1
/proc/range_probe(a)
    for(var/i=1 to 1)
        return
    a=1
/proc/all_cases(a)
    switch(a)
        if(1)
            return
        else
            return
    a=1
/proc/throws(a)
    throw a
    a=1
