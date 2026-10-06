/obj/item/bork_medigun/linked
	var/obj/item/medigun_backpack/medigun_base_unit

// the base unit's icon and wearer update.
/obj/item/bork_medigun/linked/lifecycle_prerelease()
	..()
	if(medigun_base_unit())
		var/obj/item/bork_medigun/medigun = medigun_base_unit().get_medigun()
		//ensure the base unit's icon updates
		if(medigun == src)
			medigun = null
			medigun_base_unit().replace_icon()
			if(ismob(loc))
				var/mob/user = loc
				user.update_inv_back()

/obj/item/bork_medigun/linked/forceMove(atom/destination, direction, movetime) //Forcemove override, ugh
	if(destination == medigun_base_unit() || destination == medigun_base_unit().loc || isturf(destination))
		. = doMove(destination, 0, 0)
		if(isturf(destination))
			for(var/atom/A as anything in destination) // If we can't scan the turf, see if we can scan anything on it, to help with aiming.
				if(istype(A,/obj/structure/closet ))
					break

/obj/item/bork_medigun/linked/proc/check_charge(charge_amt)
	return (medigun_base_unit().bcell && medigun_base_unit().bcell.check_charge(charge_amt))

/obj/item/bork_medigun/linked/proc/checked_use(charge_amt)
	return (medigun_base_unit().bcell && medigun_base_unit().bcell.checked_use(charge_amt))

CAPABILITIES(/obj/item/bork_medigun/linked)
	op("cancel_healing", in_hand(), then(PROC_REF(healing_cancelled)))

/// Preserve the linked device's existing two-hand update and cancellation state.
/obj/item/bork_medigun/linked/proc/healing_cancelled(datum/act/op/A)
	if(medigun_base_unit().is_twohanded())
		update_twohanding()
	if(busy)
		busy = MEDIGUN_CANCELLED
	return OP_OK

/obj/item/bork_medigun/linked/proc/should_stop(mob/living/target, mob/living/user, active_hand)
	if(!target || !user || (!active_hand && medigun_base_unit().is_twohanded()) || !istype(target) || !istype(user) || busy < MEDIGUN_BUSY)
		return TRUE

	if((user.get_active_hand() != active_hand || wielded == 0) && medigun_base_unit().is_twohanded())
		to_chat(user, span_warning("Please keep your hands free!"))
		return TRUE

	if(user.is_incorporeal())
		return TRUE

	if(user.incapacitated(INCAPACITATION_DEFAULT | INCAPACITATION_KNOCKDOWN | INCAPACITATION_DISABLED | INCAPACITATION_KNOCKOUT | INCAPACITATION_STUNNED | INCAPACITATION_RESTRAINED))
		return TRUE

	if(user.stat)
		return TRUE

	if(HAS_SYNTHETIC_BIOLOGY(target))
		to_chat(user, span_warning("Target is not organic."))
		return TRUE

	if(!(target in range(beam_range, user)) || (!(target in view(10, user)) && !(medigun_base_unit().smodule.get_rating() >= 5)))
		to_chat(user, span_warning("You are too far away from \the [target] to heal them, Or they are not in view. Get closer."))
		return TRUE

	if(!isliving(target))
		return TRUE

	if(!ishuman(target))
		return TRUE

	return FALSE

/obj/item/bork_medigun/linked/afterattack(atom/target, mob/user, proximity_flag)
	// Things that invalidate the scan immediately.
	if(isturf(target))
		for(var/atom/A as anything in target) // If we can't scan the turf, see if we can scan anything on it, to help with aiming.
			if(isliving(A))
				target = A
				break
	if(!istype(medigun_base_unit(), /obj/item/medigun_backpack/cmo))
		update_twohanding()
	if(busy && !(target == current_target()) && isliving(target))
		to_chat(user, span_warning("\The [src] is already targeting something."))
		return

	if(!ishuman(target))
		return

	if(!medigun_base_unit().smanipulator)
		to_chat(user, span_warning("\The [src] Blinks a red error light, Manipulator missing."))
		return
	if(!medigun_base_unit().scapacitor)
		to_chat(user, span_warning("\The [src] Blinks a blue error light, capacitor missing."))
		return
	if(!medigun_base_unit().slaser)
		to_chat(user, span_warning("\The [src] Blinks an orange error light, laser missing."))
		return
	if(!medigun_base_unit().smodule)
		to_chat(user, span_warning("\The [src] Blinks a pink error light, scanning module missing."))
		return
	if(!check_charge(5))
		to_chat(user, span_warning("\The [src] doesn't have enough charge left to do that."))
		return
	if(get_dist(target, user) > beam_range)
		to_chat(user, span_warning("You are too far away from \the [target] to affect it. Get closer."))
		return

	if(target == current_target() && busy)
		busy = MEDIGUN_CANCELLED
		return
	if(target == user)
		to_chat(user, span_warning("Cant heal yourself."))
		return
	if(!(target in range(beam_range, user)) || (!(target in view(10, user)) && !medigun_base_unit().smodule))
		to_chat(user, span_warning("You are too far away from \the [target] to heal them, Or they are not in view. Get closer."))
		return

	rel_set(src, nameof(current_target), target)
	busy = MEDIGUN_BUSY
	update_icon()
	var/myicon = "medbeam_basic"
	var/mycolor = "#037ffc"
	var/datum/beam/scan_beam = user.Beam(target, icon = 'icons/obj/borkmedigun.dmi', icon_state = myicon, time = 6000)
	var/filter = filter(type = "outline", size = 1, color = mycolor)
	var/list/box_segments = list()
	play_sfx(src, SFX_WEAPONS_WAVE, volume = 50)
	var/mob/living/carbon/human/H = target
	to_chat(user, span_notice("Locking on to [H]"))
	to_chat(H, span_warning("[user] is targetting you with their medigun"))
	if(user.client)
		box_segments = draw_box(target, beam_range, user.client)
		color_box(box_segments, mycolor, 5)
	process_medigun(H, user, filter)

	action_cancelled = FALSE
	busy = MEDIGUN_IDLE
	rel_clear(src, nameof(current_target))

	// Now clean up the effects.
	update_icon()
	QDEL_NULL(scan_beam)
	target.filters -= filter
	if(user.client) // If for some reason they logged out mid-scan the box will be gone anyways.
		delete_box(box_segments, user.client)

/obj/item/bork_medigun/linked/proc/process_medigun(mob/living/carbon/human/H, mob/user, filter, ishealing = FALSE)
	if(should_stop(H, user, user.get_active_hand()))
		return

	task_start(/datum/task/timed/linked_process_medigun, user, user, receiver = src, H = H, filter = filter, ishealing = ishealing, hidden = TRUE)


/datum/task/timed/linked_process_medigun
	duration = 1 SECOND
	flags = IGNORE_USER_LOC_CHANGE
	complete_proc = /obj/item/bork_medigun/linked/proc/process_medigun_timed_done
	var/mob/living/carbon/human/H
	var/filter
	var/ishealing

/// One beam cycle, decided by automated triage: every tag mended is one the patient's
/// treatment demand asks for.
/obj/item/bork_medigun/linked/proc/process_medigun_timed_done(datum/task/timed/linked_process_medigun/task)
	var/mob/living/carbon/human/H = task.H
	var/mob/user = task.actor
	var/filter = task.filter
	var/ishealing = task.ishealing
	var/washealing = ishealing // Did we heal last cycle
	ishealing = FALSE // The default is 'we didn't heal this cycle'
	if(!checked_use(5))
		to_chat(user, span_warning("\The [src] doesn't have enough charge left to do that."))
		return
	if(H.stat == DEAD)
		process_medigun(H, user, filter)
		return
	var/lastier = medigun_base_unit().slaser.get_rating()
	var/list/demand = H.treatment_demand(/datum/diagnostic_profile/automation)
	if(lastier >= 2)
		if(checked_use(5))
			H.apply_body_effect(/datum/body_effect/medbeameffect, 2 SECONDS)
		if(demand?[TREAT_ANALGESIC] && checked_use(5))
			H.mend(TREAT_ANALGESIC, 20)
		if(H.has_status(STAT_WEAKENED) && checked_use(5))
			H.status_adjust(STAT_WEAKENED, -1)
		if(lastier >= 3)
			if(H.has_status(STAT_PARALYZED) && (checked_use(15)))
				H.status_adjust(STAT_PARALYZED, -1)

	if(demand?[TREAT_OXYGENATION])
		if(!checked_use(min(10, 10 * lastier)))
			to_chat(user, span_warning("\The [src] doesn't have enough charge left to do that."))
			return
		if(H.mend(TREAT_OXYGENATION, 10 * lastier))
			ishealing = TRUE

	// The chem tanks: each mends only the tags its mode provides, and
	// only those the patient's triage demands.
	var/treated = medigun_base_unit().treat_demand(H, lastier)
	if(treated)
		checked_use(min(10, treated))
		ishealing = TRUE
	medigun_base_unit().update_icon()

	//Blood regeneration if there is some space
	if(lastier >= 5)
		if(H.vessel.get_reagent_amount("blood") < H.species.blood_volume)
			var/datum/reagent/blood/B = locate_in_list(H.vessel.reagent_list, /datum/reagent/blood) //Grab some blood
			B.volume += min(5, (H.species.blood_volume - H.vessel.get_reagent_amount("blood")))// regenerate blood

	if(ishealing != washealing) // Either we stopped or started healing this cycle
		if(ishealing)
			H.filters += filter
		else
			H.filters -= filter

	process_medigun(H, user, filter, ishealing)

/// Relation view: medigun base unit (reads null once it is gone).
/obj/item/bork_medigun/linked/proc/medigun_base_unit() as /obj/item/medigun_backpack
	return medigun_base_unit
