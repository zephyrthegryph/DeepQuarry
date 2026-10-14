/proc/probe()
    var/value = 1
    try
        throw 2
    catch(var/value)
        return value
