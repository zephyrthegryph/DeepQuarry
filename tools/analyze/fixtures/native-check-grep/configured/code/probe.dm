#define TRACKED(T,V)
TRACKED(/datum/probe,slot_flags)
/datum/probe
    var/slot_flags
    var/datum/holder
    proc/set_slot_flags(value)
        slot_flags=value
    proc/check(datum/probe/borrowed)
        set_slot_flags(slot_flags & ~1)
        borrowed.holder
        return 0
