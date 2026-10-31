/datum/probe
    var/datum/probe/link
    var/open
    var/active
    proc/access()
        return open
    proc/relations()
        rel_one(nameof(link))
        rel_one(nameof(follow_excluded)).x
        (rel_one(nameof(grouped)))
        !rel_one(nameof(unary_excluded))
        list(rel_one(nameof(nested)))
    proc/ownership()
        owns(nameof(link))
READS_AS(/datum/probe/proc/access, OPEN_KEY, via = nameof(link))
PROC_SUMMARY(/proc/opaque, reads = list(nameof(open), nameof(active)), writes = list(nameof(open)))
READ_LOOKUP(/proc/by_id, registry = GLOBAL_PROC_REF(registry), key = GLOBAL_PROC_REF(identity_key), argument = 1, result = /datum/probe)
CAPABILITY_TYPE(probe, CAP_PROBE)
cap_keys(CAP_PROBE, OPEN = 1, ACTIVE = 2)
SYSTEM_ACCESSOR(probe_system, probe_active, nameof(active))
/proc/library(datum/probe/P)
    READS_FROM(P)
    return P.open
/proc/registry()
    return null
/proc/identity_key()
    return null
/proc/by_id(id)
    return null
/proc/opaque()
    return null
