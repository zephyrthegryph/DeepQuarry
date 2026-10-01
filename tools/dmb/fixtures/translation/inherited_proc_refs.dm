/datum/ref_parent/proc/check()
    return 3
/datum/ref_parent/child/proc/upward_ref()
    return /datum/ref_parent/child.proc/check
/datum/ref_parent/child/proc/inferred_name()
    return nameof(.proc/check)