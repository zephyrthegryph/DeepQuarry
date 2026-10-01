/datum/probe_globals
    var/list/mob_list = list()
var/global/datum/probe_globals/GLOB = new
/proc/probe_const(const/hexa)
    return hexa
/proc/probe_var_const(var/const/hexa)
    return hexa
/proc/probe_in(mob/M in GLOB.mob_list)
    return M
/proc/probe_in_call(mob/M in living_mobs(1))
    return M
/proc/living_mobs(n)
    return list()
