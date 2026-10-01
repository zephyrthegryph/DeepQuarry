/proc/fixture_target()
    return 7

/datum/proc_parent
    var/target

/datum/proc_parent/child
    target = /proc/fixture_target
