var/global/list/control_trace = list()
/proc/control_defaults(a = 3, b = 4, c = 5)
    return a * 100 + b * 10 + c
/proc/control_named()
    return list(control_defaults(c = 8), control_defaults(arglist(list("c" = 8))), control_defaults(1, b = 2), control_defaults(null, null, 9))
/proc/control_iteration()
    var/list/values = list(1, 2, 3)
    var/total = 0
    for(var/value in values)
        total = total * 10 + value
        if(value == 1)
            values -= 2
            values += 4
    return total
/proc/control_switch(value)
    switch(value)
        if(1, 3 to 5, 7)
            return 11
        else
            return 22
/proc/control_async()
    set waitfor = FALSE
    control_trace += "start"
    sleep(1)
    control_trace += "end"
    return 9
/proc/control_spawn()
    var/value = 1
    spawn(0)
        control_trace += "spawn[value]"
    value = 2
    sleep(1)
/world/New()
    ..()
    var/list/defaults = control_named()
    world.log << "CONTROL_SYNC [defaults.Join(",")] [control_iteration()] [control_switch(0)] [control_switch(1)] [control_switch(4)] [control_switch(7)]"
    control_trace += "before"
    control_async()
    control_trace += "after"
    control_spawn()
    sleep(2)
    world.log << "CONTROL_ASYNC [control_trace.Join(",")]"
    del(world)
