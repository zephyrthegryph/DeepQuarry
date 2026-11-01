/datum/access/child
    secret(value)
        return ..(value)
    proc/allowed(datum/access/exact)
        exact.guarded(1)
        secret(1)
/datum/access/child/proc/own_secret()
    set SpacemanDMM_private_proc = TRUE
    return 0
