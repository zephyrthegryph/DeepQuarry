/proc/choose(n)
    return n + 1
/datum/probe/proc/choose(n)
    return n + 100
/datum/probe/proc/results()
    return list(::choose(1), choose(1), global.choose(1), ::choose(n = 2), ::choose(arglist(list(4))), global.choose(arglist(list(5))))
/world/New()
    ..()
    var/datum/probe/P = new
    var/list/values = P.results()
    world.log << "DQ_SCOPE [values[1]] [values[2]] [values[3]] [values[4]] [values[5]] [values[6]]"
    shutdown()
