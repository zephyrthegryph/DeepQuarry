/datum/namespace_probe
    proc/first()
        return 1
    proc/second()
        return 2
    verb/third()
        return 3

/proc/proc_group()
    return /datum/namespace_probe/proc
/proc/verb_group()
    return /datum/namespace_probe/verb
/proc/proc_types()
    return typesof(/datum/namespace_probe/proc)
/proc/verb_types()
    return typesof(/datum/namespace_probe/verb)
/proc/new_verb()
    return new /datum/namespace_probe/verb/third()
/proc/new_proc()
    return new /datum/namespace_probe/proc/first()
/world/New()
    ..()
    var/list/procs = proc_types()
    var/list/verbs = verb_types()
    var/datum/namespace_probe/probe = new
    var/total = 0
    for(var/path in procs)
        total += call(probe, path)()
    world.log << "PROC_NAMESPACE [procs.len] [verbs.len] [total]"
    del(world)
