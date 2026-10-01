/datum/filter_child

/atom/filter_child

/atom/movable/filter_child

/mob/filter_child

/obj/filter_child

/turf/filter_child

/area/filter_child

/proc/filter_datum_root(list/valid)
    var/datum/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_datum_child(list/valid)
    var/datum/filter_child/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_atom_root(list/valid)
    var/atom/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_atom_child(list/valid)
    var/atom/filter_child/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_atom_movable_root(list/valid)
    var/atom/movable/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_atom_movable_child(list/valid)
    var/atom/movable/filter_child/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_mob_root(list/valid)
    var/mob/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_mob_child(list/valid)
    var/mob/filter_child/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_obj_root(list/valid)
    var/obj/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_obj_child(list/valid)
    var/obj/filter_child/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_turf_root(list/valid)
    var/turf/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_turf_child(list/valid)
    var/turf/filter_child/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_area_root(list/valid)
    var/area/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_area_child(list/valid)
    var/area/filter_child/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_builtin_list(list/valid)
    var/list/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_builtin_savefile(list/valid)
    var/savefile/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_builtin_image(list/valid)
    var/image/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_builtin_icon(list/valid)
    var/icon/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_builtin_sound(list/valid)
    var/sound/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_builtin_matrix(list/valid)
    var/matrix/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_builtin_regex(list/valid)
    var/regex/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_builtin_client(list/valid)
    var/client/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value

/proc/filter_explicit_file(list/valid)
    var/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value as file in input)
        .++
    return value

/proc/filter_explicit_icon(list/valid)
    var/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value as icon in input)
        .++
    return value

/proc/filter_explicit_sound(list/valid)
    var/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value as sound in input)
        .++
    return value

/proc/filter_explicit_anything(list/valid)
    var/obj/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value as anything in input)
        .++
    return value
/proc/filter_annotation_anything(list/valid)
    var/obj/filter_child/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value as anything in input)
        .++
    return value

/proc/filter_annotation_obj(list/valid)
    var/obj/filter_child/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value as obj in input)
        .++
    return value

/proc/filter_annotation_num(list/valid)
    var/obj/filter_child/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value as num in input)
        .++
    return value

/proc/filter_annotation_union(list/valid)
    var/obj/filter_child/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value as num|obj in input)
        .++
    return value


/datum/filter_reparent_obj
    parent_type = /obj/filter_child
/datum/filter_reparent_movable
    parent_type = /atom/movable/filter_child
/proc/filter_reparent_obj(list/valid)
    var/datum/filter_reparent_obj/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value
/proc/filter_reparent_movable(list/valid)
    var/datum/filter_reparent_movable/value
    var/list/input = valid.Copy()
    input += list(1, null, "invalid trailing entry")
    for(value in input)
        .++
    return value
