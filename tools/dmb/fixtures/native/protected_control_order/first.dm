/proc/nested_return()
    try
        try
            return 17
        catch(var/inner)
            return 90
    catch(var/outer)
        return 91
    return 92

/proc/caught_loop_transfers()
    var/result = ""
    for(var/i = 1 to 4)
        try
            throw i
        catch(var/caught)
            if(caught == 2)
                continue
            if(caught == 4)
                break
            result += "[caught];"
    return result
