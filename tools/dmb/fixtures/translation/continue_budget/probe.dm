/var/list/force516=alist()
/proc/effect()
    return 1
/proc/while_join(flag)
    while(flag)
        if(flag==2)
            effect()
        else
            effect()
        flag--
    return flag
/proc/while_tail_join(flag)
    while(flag)
        if(flag==2)
            effect()
        else
            effect()
    return flag
/proc/for_continue(flag)
    for(var/i=0,i<flag,i++)
        if(i==2)
            continue
        effect()
    return flag
/proc/while_continue(flag)
    while(flag)
        if(flag==2)
            flag--
            continue
        effect()
        flag--
    return flag
