/proc/range_continue(v)
    for(var/i=1,i<=v,i++)
        switch(i)
            if(1 to 2)
                v--
            else
                continue
    return v
/proc/exact_continue(v)
    for(var/i=1,i<=v,i++)
        switch(i)
            if(1)
                v--
            else
                continue
    return v
/proc/string_goto(v)
    again:
    switch(v)
        if("x")
            return 1
        else
            goto again
/proc/range_protected_continue(v)
    for(var/i=1,i<=v,i++)
        try
            switch(i)
                if(1 to 2)
                    v--
                else
                    continue
        catch
            return 0
    return v
/proc/plain_default(v)
    switch(v)
        if(1 to 2)
            return 1
    return 0
