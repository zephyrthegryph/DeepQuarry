/datum/initial_owner
    var/value = 7
/proc/computed_initial()
    return initial(new /datum/initial_owner().value)
/proc/computed_saved()
    return issaved(new /datum/initial_owner().value)
