/proc/flow_stack_local(value)
    var/result = value
    return result

/proc/flow_stack_step(atom/movable/target, direction)
    step(target, direction)

/proc/flow_stack_catch(value)
    var/saved = value
    try
        throw "caught"
    catch(var/error)
        return error || saved

/proc/flow_stack_catch_loop(list/values)
    try
        for(var/value in values)
            if(value)
                throw "caught"
    catch(var/error)
        return error
