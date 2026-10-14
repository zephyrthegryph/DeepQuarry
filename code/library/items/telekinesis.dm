// Content supplies telekinetic readiness; the engine supplies reach and space gates.

#define TK_RANGE TK_MAXRANGE

// ---- telekinesis ----

CAPABILITY_DEF(telekinesis, CAP_TELEKINESIS, key = NONE)

/// A provider of AFF_MANIPULATE with a reach of TK_RANGE tiles and line_of_sight = TRUE: any hand op on a target it can see in range. No tool or
/// attack affordances; compartments and requirements still apply.
/datum/capability/def/telekinesis/entries()
	return list(provides(AFF_MANIPULATE | AFF_TELEKINESIS, reach = TK_RANGE, line_of_sight = TRUE))

/// The key tk_refresh() publishes (the reads of the tk_ready() condition).
#define TK_KEY "telekinesis_ready"

/// Can this mob reach out with its mind now? A TK mutation, or powered kinesis gloves (has_telegrip()), and not through a remote view (the old adapter refused
/// that too: a remote viewer that could TK would act from two places). A condition: it reads and writes nothing.
/mob/proc/tk_ready(datum/act/A)
	return has_telegrip() && !is_remote_viewing()

/// The telekinesis provider of a mob while it is tk_ready(): the telekinesis() provider, held by a condition instead of a grant, so a mutation or the power of
/// a pair of gloves needs no bookkeeping (the condition is read when the provider set is read). AFF_TELEKINESIS marks it for the tk() binding; a hand op
/// needs only AFF_MANIPULATE, so it does any hand op on a target in range and in sight, used only when nothing nearer reaches. A mutation added or removed, or
/// a glove's power spent, calls tk_refresh().
/proc/telekinetic_reach()
	return when(TYPE_PROC_REF(/mob, tk_ready), provides(AFF_MANIPULATE | AFF_TELEKINESIS, reach = TK_RANGE, line_of_sight = TRUE), reads = list(TK_KEY))

/// The telekinesis state of this mob changed: its provider set did, and the menus cached on it are stale.
/mob/proc/tk_refresh()
	if(QDELETED(src))
		return
	provider_set_changed(src)
	publish_change(src, TK_KEY)
