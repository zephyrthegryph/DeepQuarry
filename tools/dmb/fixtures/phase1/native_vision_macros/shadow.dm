#undef SEE_BLACKNESS
/datum/shadow
    var/SEE_BLACKNESS = 9
/datum/shadow/proc/read()
    return SEE_BLACKNESS
/proc/root_read()
    return SEE_BLACKNESS
