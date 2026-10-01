/var/list/force516=alist()
/proc/effect()
    return 1
/proc/backward(flag)
    again:
    effect()
    if(flag)
        flag=0
        goto again
    return flag
/proc/forward(flag)
    if(flag)
        effect()
        goto done
    effect()
    done:
    return flag
/proc/switch_forward(flag)
    switch(flag)
        if(1)
            effect()
            goto done
        else
            return 0
    done:
    return flag
/proc/nested(flag)
    while(flag)
        again:
        effect()
        if(flag==2)
            flag=1
            goto again
        if(flag==1)
            goto done
        flag--
    done:
    return flag
/proc/immediate(flag)
    goto next
    next:
    return flag
/proc/conditional(flag)
    if(flag)
        goto next
    next:
    return flag
/proc/ordinary_if(flag)
    if(flag)
        effect()
    else
        effect()
    return flag
/proc/natural_loop(flag)
    while(flag)
        effect()
        flag--
    return flag
/proc/protected_goto(flag)
    try
        again:
        effect()
        if(flag)
            flag=0
            goto again
        throw "boundary"
    catch(var/exception/E)
        return E
