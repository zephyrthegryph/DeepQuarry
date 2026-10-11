/proc/root_obj(list/L)
    var/n = 0
    for(var/obj/A in L)
        n++
    return n
/proc/root_mob(list/L)
    var/n = 0
    for(var/mob/A in L)
        n++
    return n
/proc/root_turf(list/L)
    var/n = 0
    for(var/turf/A in L)
        n++
    return n
/proc/root_area(list/L)
    var/n = 0
    for(var/area/A in L)
        n++
    return n
/proc/root_movable(list/L)
    var/n = 0
    for(var/atom/movable/A in L)
        n++
    return n
