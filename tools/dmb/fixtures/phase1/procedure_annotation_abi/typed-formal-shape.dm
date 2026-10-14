/datum/item
    var/amount = 7
/proc/index_new(datum/item/values[])
    values[1] = new
    return values[1]
/proc/list_member(datum/item/values[])
    return values.len
/proc/object_list(obj/values[])
    return values
/proc/mob_list(mob/values[])
    return values
/proc/untyped_list(values[])
    values[1] = new
