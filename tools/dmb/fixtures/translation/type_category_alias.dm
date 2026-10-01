/datum/obj_alias
    parent_type = /obj
/datum/mob_alias
    parent_type = /mob
/datum/area_alias
    parent_type = /area
/datum/turf_alias
    parent_type = /turf
/obj/datum_alias
    parent_type = /datum
/datum/holder
    var/a = /datum/obj_alias
    var/b = /datum/mob_alias
    var/c = /datum/area_alias
    var/d = /datum/turf_alias
    var/e = /obj/datum_alias
/proc/aliases()
    return list(/datum/obj_alias,/datum/mob_alias,/datum/area_alias,/datum/turf_alias,/obj/datum_alias)
/client/tagged
    parent_type = /datum
/datum/image_alias
    parent_type = /image
/proc/primitive_aliases()
    return list(/client/tagged,/datum/image_alias,/image,/mutable_appearance,/list,/savefile)
/proc/alias_args(datum/obj_alias/A, datum/mob_alias/B, datum/turf_alias/C, obj/datum_alias/D)
    return list(A,B,C,D)
/datum/holder
    var/type_value = /datum/obj_alias{name="modified alias"}
