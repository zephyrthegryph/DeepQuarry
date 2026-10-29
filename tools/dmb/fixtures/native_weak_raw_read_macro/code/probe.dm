#define CAPABILITIES(T) T/proc/capabilities()
#define TRUE 1
/datum/owner
    var/datum/owner/target
CAPABILITIES(/datum/owner)
    ref_one(nameof(target), weak = TRUE)
/datum/owner/child
/datum/unrelated
    var/datum/target
/datum/owner/proc/read(datum/owner/H, datum/unrelated/U, unknown, list/datum/owner/L)
    target
    src.target
    H.target
    L[1].target
    H.target = null
    var/text = "[H.target]"
    target.ping()
    nameof(target)
    nameof(H.target)
    nameof(list(H.target, H.target.name))
    target()
    H.target()
    U.target
    unknown.target
/datum/owner/proc/shadow()
    target
    var/target
/proc/make_owner() as /datum/owner
    return null
/proc/from_return()
    make_owner().target

#define READ_TARGET(x) x.target
/proc/macro_read(datum/owner/H)
    READ_TARGET(H)

/proc/owner_result() as /datum/owner
    return null
/proc/no_hint() as /datum/owner
    return null
/datum/owner/proc/no_hint()
    return null
/datum/owner/proc/method_fallback(datum/owner/H, unknown)
    H.owner_result().target
    H.no_hint().target
    unknown.owner_result().target
