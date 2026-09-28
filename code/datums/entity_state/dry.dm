/// Dries the floor (and blood) under the wearer at every step. Attached to dry galoshes.
/// (Was /datum/component/dry; a stateless behaviour singleton.)
/datum/om/behaviour/dry
	handles = list(/datum/om/event/before/shoes_step_action)

/datum/om/behaviour/dry/on_event(datum/E, datum/om/event/event)
	if(!istype(event, /datum/om/event/before/shoes_step_action))
		return
	if(!istype(E, /obj/item/clothing/shoes))
		return
	var/turf/simulated/T = get_turf(E)
	var/obj/effect/decal/cleanable/blood/B = locate_within(T, /obj/effect/decal/cleanable/blood)

	if(istype(T))
		T.wet_floor_finish()
	if(B)
		B.dry()
