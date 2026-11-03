
#if DM_BUILD == 1666 && SPACEMAN_DMM
/datum/probe/proc/context_guarded(datum/probe/borrowed)
    set_slot_flags(slot_flags & ~1)
    borrowed.holder
#else
/datum/probe/proc/context_guarded(client/borrowed)
    slot_flags & ~1
    borrowed.holder
#endif
