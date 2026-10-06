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

CAPABILITIES(/obj/item/mop)
	reagents(30)

/obj/item/mop/afterattack(atom/A, mob/user, proximity)
	if(!proximity) return
	if(istype(A, /turf) || istype(A, /obj/effect/decal/cleanable) || istype(A, /obj/effect/overlay) || istype(A, /obj/effect/rune))
		if(reagents.total_volume < 1)
			user.balloon_alert(user, "your mop is dry!")
			return

		act_message(user, null, others = span_warning("%U% begins to clean \the [get_turf(A)]."))

		task_timed(user, mop_time, target = get_turf(A), receiver = src, on_done = PROC_REF(afterattack_timed_done), done_args = list(A, user))

/obj/item/mop/proc/afterattack_timed_done(atom/A, mob/user)
	var/turf/T = get_turf(A)
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
