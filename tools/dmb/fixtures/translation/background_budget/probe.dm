/proc/background_while(v)
    set background=1
    while(v)
        v--
        if(v) continue
    return v
/proc/background_do(v)
    set background=1
    do
        v--
        if(v) continue
    while(v)
    return v
/proc/background_try(v)
    set background=1
    while(v)
        try
            v--
            if(v) continue
        catch
            return 0
    return v
/proc/background_nested(v)
    set background=1
    while(v)
        for(var/i=1,i<=v,i++)
            if(i==2) continue
        v--
    return v
/proc/explicit_sleep(v)
    set background=1
    while(v)
        sleep(-1)
        v--
    return v
/datum/base/proc/work(v)
    set background=1
    while(v)
        v--
        if(v) continue
    return v
/datum/child
    parent_type=/datum/base
/datum/child/work(v)
    while(v)
        v--
        if(v) continue
    return v
/proc/not_background(v)
    while(v)
        v--
    return v
