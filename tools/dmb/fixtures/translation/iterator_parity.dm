/proc/iterator_untyped(list/L)
    for(var/item in L)
        if(item)
            return item
    return null

/proc/iterator_anything(list/L)
    for(var/item as anything in L)
        if(item)
            return item
    return null

/proc/iterator_union(list/L)
    for(var/item as mob|obj|turf|area in L)
        return item
    return null

/proc/iterator_numbers(list/L)
    for(var/item as num|text|null in L)
        return item
    return null

/proc/iterator_nested(list/L)
    var/count = 0
    for(var/outer as anything in L)
        for(var/inner as anything in L)
            if(inner)
                break
            continue
        count++
    return count

/proc/iterator_labelled(list/L)
    var/count = 0
    outer_loop:
        for(var/outer as anything in L)
            for(var/inner as anything in L)
                if(inner)
                    continue outer_loop
                count++
    return count

/proc/iterator_range_nested(list/L)
    var/count = 0
    outer_loop:
        for(var/outer as anything in L)
            for(var/n in 1 to 3)
                for(var/inner as anything in L)
                    if(inner)
                        continue outer_loop
                    count++
    return count

/proc/iterator_clients()
    for(var/client/C)
        for(var/client/D)
            return D
        return C
    return null

/datum/iterator_probe

/proc/iterator_typed(list/L)
    for(var/datum/iterator_probe/item in L)
        return item
    return null

/proc/iterator_world_type()
    for(var/datum/iterator_probe/item)
        return item
    return null
