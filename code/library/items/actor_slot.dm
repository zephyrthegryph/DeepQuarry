// req_actor_slot_empty(slot, because): the actor wears nothing in that slot. A thing that needs bare fingertips (a fingerprint card) says
// needs(req_actor_slot_empty(SLOT_ID_GLOVES, because = MSG(sample/take_gloves_off))). An actor that is not a human has no such slot and passes.

/proc/req_actor_slot_empty(slot_id, because = null)
	return part_make(/datum/entry/part/req/actor_slot_empty, list("slot" = slot_id, "because" = because))

/datum/entry/part/req/actor_slot_empty
	part_name = "req_actor_slot_empty"

/datum/entry/part/req/actor_slot_empty/holds(datum/act/op/A)
	var/mob/living/carbon/human/H = A.actor
	return !istype(H) || !H.get_equipped_item(src.args["slot"])

/// req_worn_by_actor(slots, because): the holder is worn by the actor in one of those slots (a hardsuit on the back or the belt).
/proc/req_worn_by_actor(list/slot_ids, because = null)
	return part_make(/datum/entry/part/req/worn_by_actor, list("slots" = slot_ids, "because" = because))

/datum/entry/part/req/worn_by_actor
	part_name = "req_worn_by_actor"

/datum/entry/part/req/worn_by_actor/holds(datum/act/op/A)
	var/mob/living/carbon/human/H = A.actor
	if(!istype(H))
		return FALSE
	for(var/slot in src.args["slots"])
		if(H.get_equipped_item(slot) == A.holder)
			return TRUE
	return FALSE
