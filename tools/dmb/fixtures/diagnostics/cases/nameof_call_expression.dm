/datum/holder
	var/slot

/proc/get_holder() as /datum/holder
	return new /datum/holder()

/proc/slot_name()
	return nameof(get_holder().slot)

/world/New()
	slot_name()
