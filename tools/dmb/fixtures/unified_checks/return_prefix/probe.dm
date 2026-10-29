/datum/target
/proc/early()
    set SpacemanDMM_return_type = /datum/target
    return null
/proc/late()
    . = null
    set SpacemanDMM_return_type = /datum/target
    return null
/proc/probe()
    early().absent_early
    late().absent_late
