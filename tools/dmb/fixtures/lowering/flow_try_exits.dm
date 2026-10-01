/proc/flow_try_outer(n)
    var/total = 0
    try
        for(var/i = 1, i <= n, i++)
            if(i == 1)
                continue
            if(i == 2)
                break
            total += i
    catch(var/e)
        return e
    return total
/proc/flow_try_inner(n)
    var/total = 0
    for(var/i = 1, i <= n, i++)
        try
            if(i == 1)
                continue
            if(i == 2)
                break
            total += i
        catch
            total += 10
    return total
/proc/flow_try_return(n)
    try
        if(n)
            return 1
        throw "caught"
    catch(var/e)
        return e
    return 0
/proc/flow_try_nested(n)
    var/total = 0
    try
        try
            if(n)
                throw "inner"
        catch
            total += 1
        throw "outer"
    catch
        total += 2
    return total
/proc/flow_try_while(n)
    var/i = 0
    try
        while(i < n)
            i++
            if(i == 1)
                continue
            if(i == 2)
                break
    catch(var/e)
        return e
    return i
/proc/flow_nested_exits(n)
    var/total = 0
    for(var/i = 1, i <= n, i++)
        try
            try
                if(i == 1)
                    continue
                if(i == 2)
                    break
                total += i
            catch(var/e)
                total += e
        catch(var/e)
            total += e
    throw "after loop"
/proc/flow_try_goto(n)
    try
        if(n)
            goto after_try
        throw "caught"
    catch(var/e)
        return e
    after_try:
    return 7
/proc/flow_spawn_try(n)
    try
        spawn(n)
            throw "spawned"
        return 1
    catch(var/e)
        return e
/proc/flow_try_ordinary_jump(n)
    var/total = 0
    try
        total = n ? 1 : 2
    catch(var/e)
        return e
    return total
