/datum/access/child
    secret(value)
        return ..(value)
    proc/allowed(datum/access/exact)
        exact.guarded(1)
        secret(1)
