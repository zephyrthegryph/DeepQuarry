/datum/rn_owner
    var/datum/rn_owner/child
/datum/rn_owner/proc/read(value)
    return value
/proc/rn_mutate(var/datum/rn_owner/a, var/datum/rn_owner/b)
    return a.child.read((a.child=b))

