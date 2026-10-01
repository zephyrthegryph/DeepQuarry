/proc/count_objs()
    var/n = 0
    for(var/obj/O in world)
        n++
    return n

/proc/count_all_objs()
    var/n = 0
    for(var/obj/O)
        n++
    return n

