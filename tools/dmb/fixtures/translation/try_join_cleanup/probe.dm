/proc/join_helper(x)
    return x
/proc/join_if_else(x)
    try
        if(x)
            join_helper("yes")
        else
            join_helper("no")
    catch(var/e)
        return e
/proc/join_nested_if(x,y)
    try
        if(x)
            if(y)
                join_helper("both")
        else if(y)
            join_helper("other")
    catch(var/e)
        return e
/proc/join_nested_try(x)
    try
        try
            if(x)
                join_helper("yes")
            else
                join_helper("no")
        catch(var/e)
            join_helper(e)
        throw "outer"
    catch(var/e)
        return e
/proc/join_ternary(x)
    try
        join_helper(x ? "yes" : "no")
    catch(var/e)
        return e
/proc/join_goto_out(x)
    try
        if(x)
            goto done
        join_helper("protected")
    catch(var/e)
        return e
    done:
    return "outside"
