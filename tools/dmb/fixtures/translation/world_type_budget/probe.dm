/obj/sub
/mob/sub
/datum/sub
/proc/object_root(result)
    for(var/obj/O)
        result=O
    return result
/proc/object_sub(result)
    for(var/obj/sub/O)
        result=O
    return result
/proc/mob_root(result)
    for(var/mob/O)
        result=O
    return result
/proc/turf_root(result)
    for(var/turf/O)
        result=O
    return result
/proc/area_root(result)
    for(var/area/O)
        result=O
    return result
/proc/atom_root(result)
    for(var/atom/O)
        result=O
    return result
/proc/datum_sub(result)
    for(var/datum/sub/O)
        result=O
    return result
/proc/datum_root(result)
    for(var/datum/O)
        result=O
    return result
