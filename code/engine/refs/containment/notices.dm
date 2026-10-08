/// From /datum/om/event/slot_inserted.
/datum/notice/slot_inserted
	var/thing
	var/slot_id

/datum/notice/slot_inserted/fill(thing, slot_id)
	src.thing = thing
	src.slot_id = slot_id

/// From /datum/om/event/slot_removed.
/datum/notice/slot_removed
	var/thing
	var/slot_id

/datum/notice/slot_removed/fill(thing, slot_id)
	src.thing = thing
	src.slot_id = slot_id
