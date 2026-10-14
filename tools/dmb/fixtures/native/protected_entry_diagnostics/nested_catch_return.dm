/proc/probe()
    try
        try
            throw 7
        catch(var/inner)
            return inner
    catch(var/outer)
        return outer
