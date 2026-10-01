var/global/datum/shared_scope/GLOB
/datum/shared_scope
    var/global/list/shared = list(7)
/proc/read()
    return GLOB.shared
/proc/write(value)
    GLOB.shared = value
/proc/read_length()
    return GLOB.shared.len
