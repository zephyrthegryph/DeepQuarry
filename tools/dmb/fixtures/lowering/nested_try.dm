/proc/nested_try(var/x)
    var/pre = 1
    try
        try
            if(x) throw "inner"
        catch(var/e)
            world.log << e
    catch(var/e)
        world.log << e
    return pre
