/proc/read(savefile/S)
    var/value
    S["entry"] >> value
    return value
/proc/read_root(savefile/S)
    var/value
    S >> value
    return value
/proc/write(savefile/S, value)
    S["entry"] << value
/proc/assign(savefile/S, value)
    S["entry"] = value
/proc/index_read(savefile/S)
    return S["entry"]
/datum/holder
    var/value
/proc/read_field(savefile/S, datum/holder/H)
    S["entry"] >> H.value
/proc/read_index(savefile/S, list/L)
    S["entry"] >> L[1]
/proc/get_holder()
    return new /datum/holder
/proc/read_dynamic_field(savefile/S)
    S["entry"] >> get_holder().value
