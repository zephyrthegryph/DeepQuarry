/datum/holder
	var/slot

/proc/get_holder() as /datum/holder
	return new /datum/holder()

/proc/slot_name()
	var/datum/holder/h = get_holder()
	h.slot = 1
	return nameof(h.slot)

/world/New()
	slot_name()
