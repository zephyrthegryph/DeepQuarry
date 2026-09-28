/datum/component/dry

/datum/component/dry/Initialize()
	if(!isatom(parent))
		return COMPONENT_INCOMPATIBLE
	if(istype(parent, /obj/item/clothing/shoes))
		RegisterSignal(parent, COMSIG_SHOES_STEP_ACTION, PROC_REF(step_dry))

/datum/component/dry/proc/step_dry(obj/item/clothing/shoes/source)
	SIGNAL_HANDLER

	var/turf/simulated/T = get_turf(parent)
	var/obj/effect/decal/cleanable/blood/B = locate(/obj/effect/decal/cleanable/blood) in T

	if(istype(T))
		T.wet_floor_finish()
	if(B)
		B.dry()
