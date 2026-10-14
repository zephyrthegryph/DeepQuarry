/proc/probe()
    try
        throw new /exception("control")
    catch(var/exception/caught)
        return caught.name
