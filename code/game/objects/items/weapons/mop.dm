REGISTRY_MEMBERSHIP(/obj/item/mop, REGISTRY_MOPS)

/*
 * Mop
 */
/obj/item/mop
	name = "mop"
	desc = "The world of janitalia wouldn't be complete without a mop."
	icon = 'icons/obj/janitor.dmi'
	icon_state = "mop"
	force = 3.0
	throwforce = 10.0
	throw_speed = 5
	throw_range = 10
	w_class = ITEMSIZE_NORMAL
	flags = NOCONDUCT
	attack_verb = list("mopped", "bashed", "bludgeoned", "whacked")
	///How long it takes to mop a tile.
	var/mop_time = 4 SECONDS

MSG_DEF(mop/cleaning, null, span_warning("%U% begins to clean the floor."))
MSG_DEF_SELF(mop/dry, "Your mop is dry!")

CAPABILITIES(/obj/item/mop)
	reagents(30)
	op("mop", at_target(/turf), at_target(/obj/effect/decal/cleanable), at_target(/obj/effect/overlay), at_target(/obj/effect/rune), begins(MSG(mop/cleaning)), starts(PROC_REF(mop_started)), wait(PROC_REF(mop_duration)), then(PROC_REF(mopped)))

/// A dry mop starts nothing.
/obj/item/mop/proc/mop_started(datum/act/op/A)
	if(reagents.total_volume < 1)
		return /datum/msg/mop/dry
	return null

/obj/item/mop/proc/mop_duration(datum/act/A)
	return mop_time

/obj/item/mop/proc/mopped(datum/act/op/A)
	var/mob/user = A.actor
	var/turf/T = get_turf(A.target)
	if(T)
		T.wash(CLEAN_SCRUB)
		reagents.trans_to_turf(T, 1, 10)
		var/mob/living/cleaner = user
		emit_contract_event(CONTRACT_EVENT_SANITATION_COMPLETED, list(
			"department" = DEPARTMENT_CIVILIAN,
			"target_id" = REF(T),
			"method" = "manual_mop",
			"cleaned_units" = 1,
			"detail" = "Cleaned [T] with [src].",
		), "sanitation:[REF(T)]:[world.time]", src, cleaner)
	user.balloon_alert(user, "you have finished mopping!")
	return OP_OK

// NOTE: the /obj/effect/attackby(mop/soap) no-op override lives in mop_deploy.dm (included later, so it
// wins under DM's last-include-wins). A duplicate here was silently discarded — and is a hard
// DuplicateProcDefinition error under OpenDream — so it has been removed.

/*
 * Advanced Mop
 */
/obj/item/mop/advanced
	name = "advanced mop"
	desc = "No stain will go unclean."
	icon = 'icons/obj/janitor.dmi'
	icon_state = "adv_mop"
	force = 3.5
	throwforce = 10.5
	throw_speed = 4
	throw_range = 10
	w_class = ITEMSIZE_NORMAL
	flags = NOCONDUCT
	attack_verb = list("mopped", "bashed", "bludgeoned", "whacked")
	mop_time = 2 SECONDS
