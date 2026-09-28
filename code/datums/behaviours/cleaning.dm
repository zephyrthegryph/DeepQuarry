/// Cleans the tile a movable moves onto (was /datum/element/cleaning). A shared behaviour
/// singleton on the moved event. Attach with om_attach(AM, /datum/om/behaviour/cleaning).
/datum/om/behaviour/cleaning
	handles = list(/datum/om/event/moved)

/datum/om/behaviour/cleaning/on_moved(atom/movable/source, datum/om/event/moved/event)
	var/atom/movable/AM = source
	var/turf/tile = AM.loc
	if(!isturf(tile))
		return

	tile.wash(CLEAN_WASH)

	for(var/atom/cleaned as anything in tile)
		if(isitem(cleaned))
			var/obj/item/cleaned_item = cleaned
			if(cleaned_item.w_class <= ITEMSIZE_SMALL)
				cleaned_item.wash(CLEAN_SCRUB)
			continue
		if(istype(cleaned, /obj/effect/decal/cleanable))
			var/obj/effect/decal/cleanable/cleaned_decal = cleaned
			cleaned_decal.wash(CLEAN_SCRUB)
		if(!ishuman(cleaned))
			continue
		var/mob/living/carbon/human/cleaned_human = cleaned
		if(cleaned_human.lying)
			cleaned_human.wash(CLEAN_SCRUB)
			to_chat(cleaned_human, span_danger("[AM] washes your face!"))
