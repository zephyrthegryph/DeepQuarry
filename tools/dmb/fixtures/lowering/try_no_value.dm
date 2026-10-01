/proc/try_no_value(var/x)
    try
        if(x) throw "bad"
        return 1
    catch
        return 2
