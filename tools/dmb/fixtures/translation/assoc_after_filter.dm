/proc/assoc_after_filter(var/list/L)
    for(var/datum/item in L)
        item.type
    for(var/key,value in L)
        return value