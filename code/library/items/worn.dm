// req_not_worn(slot, because): the holder is not on the actor in that slot. A thing you can't work on while it is on your back says
// needs(req_not_worn(SLOT_ID_BACK, because = MSG(parachute/worn))).

/proc/req_not_worn(slot_id, because = null)
	return part_make(/datum/entry/part/req/not_worn, list("slot" = slot_id, "because" = because))

/datum/entry/part/req/not_worn
	part_name = "req_not_worn"

/datum/entry/part/req/not_worn/holds(datum/act/op/A)
	var/atom/holder = A.holder
	var/mob/living/carbon/human/H = A.actor
	return !(istype(H) && isliving(holder.loc) && !H.stat && H.get_equipped_item(src.args["slot"]) == holder)
