/var/list/force516=alist()
/proc/try_head_continue(flag)
    try
        while(TRUE)
            if(flag)
                flag=0
                continue
            throw "boundary"
    catch(var/exception/E)
        return E
/proc/try_prefixed_continue(flag)
    try
        var/prefix=0
        while(TRUE)
            if(flag)
                flag=0
                continue
            throw prefix
    catch(var/exception/E)
        return E
/proc/try_natural_tail(flag)
    try
        while(flag)
            flag--
        return flag
    catch(var/exception/E)
        return E
/proc/try_nested_continue(flag)
    try
        while(flag)
            try
                flag--
                continue
            catch(var/exception/inner)
                return inner
        return flag
    catch(var/exception/E)
        return E
/proc/try_indexed_continue(list/items)
    try
        for(var/item in items)
            if(item)
                continue
        return items
    catch(var/exception/E)
        return E
/proc/try_loop_break(flag)
    try
        while(flag)
            if(flag==2)
                break
            flag--
        return flag
    catch(var/exception/E)
        return E
/proc/try_head_goto(flag)
    try
        again:
        if(flag)
            flag=0
            goto again
        throw "boundary"
    catch(var/exception/E)
        return E
/proc/try_forward_goto(flag)
    try
        if(flag)
            goto done
        throw "skip"
        done:
        return flag
    catch(var/exception/E)
        return E
/proc/try_unprotected_goto(flag)
    if(flag)
        goto done
    flag=2
    done:
    return flag
