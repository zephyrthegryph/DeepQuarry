/area/child
/obj/child
/mob/child
/datum/child
    var/x
/proc/root_area(list/L)
    var/n=0
    for(var/area/A in L)
        n+=A.x
    return n
/proc/root_obj(list/L)
    var/n=0
    for(var/obj/A in L)
        n+=A.x
    return n
/proc/root_mob(list/L)
    var/n=0
    for(var/mob/A in L)
        n+=A.x
    return n
/proc/root_turf(list/L)
    var/n=0
    for(var/turf/A in L)
        n+=A.x
    return n
/proc/root_movable(list/L)
    var/n=0
    for(var/atom/movable/A in L)
        n+=A.x
    return n
/proc/root_atom(list/L)
    var/n=0
    for(var/atom/A in L)
        n+=A.x
    return n
/proc/subtype_area(list/L)
    var/n=0
    for(var/area/child/A in L)
        n+=A.x
    return n
/proc/subtype_obj(list/L)
    var/n=0
    for(var/obj/child/A in L)
        n+=A.x
    return n
/proc/subtype_mob(list/L)
    var/n=0
    for(var/mob/child/A in L)
        n+=A.x
    return n
/proc/subtype_datum(list/L)
    var/n=0
    for(var/datum/child/A in L)
        n+=A.x
    return n
/proc/anything_area(list/L)
    var/n=0
    for(var/area/A as anything in L)
        n+=A.x
    return n
/proc/orange_mob(atom/center)
    var/n=0
    for(var/mob/A in orange(1,center))
        n+=A.x
    return n
/proc/orange_turf(atom/center)
    var/n=0
    for(var/turf/A in orange(1,center))
        n+=A.x
    return n
/proc/orange_area(atom/center)
    var/n=0
    for(var/area/A in orange(1,center))
        n+=A.x
    return n
/proc/orange_untyped(atom/center)
    var/n=0
    for(var/A in orange(1,center))
        n++
    return n
/proc/orange_anything(atom/center)
    var/n=0
    for(var/area/A as anything in orange(1,center))
        n+=A.x
    return n
/proc/orange_subtype(atom/center)
    var/n=0
    for(var/area/child/A in orange(1,center))
        n+=A.x
    return n
/proc/orange_choice(flag,list/L,atom/center)
    var/n=0
    for(var/area/A in (flag ? L : orange(1,center)))
        n+=A.x
    return n
/proc/orange_one()
    var/n=0
    for(var/mob/A in orange(1))
        n+=A.x
    return n
/proc/orange_default()
    var/n=0
    for(var/mob/A in orange())
        n+=A.x
    return n
/proc/orange_list(atom/center)
    return orange(1,center)
