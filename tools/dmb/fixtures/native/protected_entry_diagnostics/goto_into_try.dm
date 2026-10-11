/proc/probe()
    goto inside
    try
        inside:
        return 7
    catch(var/caught)
        return caught
