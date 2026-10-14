/datum/name_shadow
    var/cpu = 1
/proc/probe(datum/name_shadow/world)
    var/static/name = nameof(world.cpu)
    return name
