/proc/probe(list/items)
    goto inside
    for(var/item in items)
        inside:
        return item
    return 0
