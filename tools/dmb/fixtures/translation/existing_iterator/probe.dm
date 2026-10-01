/proc/existing_iterator(list/L)
    var/item
    for(item in L)
        item = item + 1
    return item
