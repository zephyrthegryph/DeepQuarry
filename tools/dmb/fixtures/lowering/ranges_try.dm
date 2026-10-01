/proc/range_case(x)
    switch(x)
        if(1 to 3) return 10
        if(5 to 7) return 20
    return 0
/proc/catcher(x)
    try
        if(x) throw "oops"
        return 1
    catch(var/exception/e)
        return e
