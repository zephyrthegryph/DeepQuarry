/datum/receiver
    var/static/known
/proc/probe()
    return nameof(/datum/receiver::known)
