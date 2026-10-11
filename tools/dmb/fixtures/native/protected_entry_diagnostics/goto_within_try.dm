/proc/probe()
    try
        goto inside
        inside:
        return 7
    catch(var/caught)
        return caught
