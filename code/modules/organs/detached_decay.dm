// Detached organs process on their own local decay clock. Attached organ
// processing retains its existing SSobj lifecycle.
/datum/object_model/requirement/organ_detached_decay
	failure_message = "organ decay is inactive"

/datum/object_model/requirement/organ_detached_decay/check(datum/source, mob/actor, atom/target, obj/item/held)
	var/obj/item/organ/O = source
	return O && !O.owner && !O.preserved && !istype(O.loc, /obj/item/mmi) && !(O.status & ORGAN_DEAD)

/datum/object_model/behaviour/organ_detached_decay
	requires = list(/datum/object_model/requirement/organ_detached_decay)
	run_period = LIFE_NOMINAL_SECONDS SECONDS
	run_clock = /datum/object_model/clock_domain/decay

/datum/object_model/behaviour/organ_detached_decay/on_run(datum/source, seconds, list/config)
	var/obj/item/organ/O = source
	if(!O || QDELETED(O) || O.owner || O.preserved || istype(O.loc, /obj/item/mmi) || (O.status & ORGAN_DEAD))
		return 0
	// Activation establishes the next deadline; old SSobj processing first ran
	// on its next subsystem tick rather than synchronously with removal.
	if(seconds <= 0)
		return null
	O.process()
	return null

/datum/object_model/declaration/organ_detached_decay
	target_type = /obj/item/organ

/datum/object_model/declaration/organ_detached_decay/build(datum/object_model/archetype/A)
	A.add(/datum/object_model/behaviour/organ_detached_decay)
