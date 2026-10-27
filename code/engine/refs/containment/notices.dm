/// From the ledger after a thing entered one of the holder's slots: (atom/movable/thing, slot_id)
/datum/notice/slot_inserted
	var/thing
	var/slot_id

/datum/notice/slot_inserted/fill(thing, slot_id)
	src.thing = thing
	src.slot_id = slot_id

/// From the ledger after a thing left one of the holder's slots: (atom/movable/thing, slot_id)
/datum/notice/slot_removed
	var/thing
	var/slot_id

/datum/notice/slot_removed/fill(thing, slot_id)
	src.thing = thing
	src.slot_id = slot_id
