/datum/proc/get_thing()
    return src
/proc/add(datum/D, n)
    D:get_thing().count += n
    return D
