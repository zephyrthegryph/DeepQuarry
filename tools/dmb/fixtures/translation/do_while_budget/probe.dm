/proc/mark(v)
    return v
/proc/simple(v)
    do
        v--
    while(v)
    return v
/proc/false_tail(v)
    do
        v--
    while(0)
    return v
/proc/true_tail(v)
    do
        if(v)
            break
    while(1)
    return v
/proc/effectful(v)
    do
        v--
    while(mark(v))
    return v
/proc/continue_tail(v)
    do
        v--
        if(v==2)
            continue
    while(v)
    return v
/proc/nested(v)
    do
        var/x=v
        do
            x--
        while(x)
        v--
    while(v)
    return v
/proc/protected(v)
    try
        do
            v--
        while(v)
    catch
        return 0
    return v
/proc/body_try(v)
    do
        try
            v--
        catch
            return 0
    while(v)
    return v
/proc/conditional_goto(v)
    label:
    v--
    if(v)
        goto label
    return v
/proc/conditional_continue(v)
    while(v)
        v--
        if(v)
            continue
    return v

/proc/managed()
    return list(1)
/proc/null_tail(v)
    managed()
    do
        v--
    while(null)
    return v
/proc/const_null_tail(v)
    var/const/N=null
    managed()
    do
        v--
    while(N)
    return v
/proc/const_zero_tail(v)
    var/const/N=0
    managed()
    do
        v--
    while(N)
    return v
/proc/const_null_outside()
    var/const/N=null
    managed()
    return N
/proc/iterator_body(list/L)
    for(var/x in L)
        do
            x--
        while(x)
    return 0
/proc/protected_continue(v)
    try
        do
            v--
            if(v==2)
                continue
        while(v)
    catch
        return 0
    return v
/proc/const_true_unreachable(v)
    do
        v--
        if(v)
            continue
        break
    while(1)
    return v

/proc/const_true_continue(v)
    do
        v--
        if(!v)
            break
        if(v==2)
            continue
        v--
    while(1)
    return v
