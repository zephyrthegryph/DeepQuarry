/datum/access
    proc/secret(value)
        set SpacemanDMM_private_proc = TRUE
        return value
    proc/guarded(value)
        set SpacemanDMM_protected_proc = TRUE
        return value
    proc/own_calls(datum/access/exact, datum/access/child/derived)
        exact.secret(derived.secret(1))
        derived.secret(exact.secret(1))
        guarded(0)
/list/proc/New(size)
    set SpacemanDMM_private_proc = TRUE
/datum/access/proc/own_secret()
    set SpacemanDMM_private_proc = TRUE
    return 0
