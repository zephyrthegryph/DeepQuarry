/datum/access/proc/secret(x)
    set SpacemanDMM_private_proc = TRUE
    return x
/datum/access/child
/datum/required/proc/run()
    set SpacemanDMM_should_call_parent = TRUE
    return 0
