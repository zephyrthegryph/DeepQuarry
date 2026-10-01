/datum/item
/datum/holder
    var/datum/item/entry
/proc/probe(datum/holder/H)
    H.entry = new()
/proc/probe_type(datum/holder/H)
    return istype(H.entry)
