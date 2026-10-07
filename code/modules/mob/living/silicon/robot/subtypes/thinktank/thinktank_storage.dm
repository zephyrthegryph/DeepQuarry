/mob/living/silicon/robot/platform/on_death(gibbed)

	if(gibbed)

		if(recharging)
			var/obj/item/recharging_atom = recharging
			rel_clear(src, nameof(recharging))
			if(!QDELETED(recharging_atom) && recharging_atom.loc == src)
				recharging_atom.dropInto(loc)
				recharging_atom.throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),rand(1,3),30)

		if(length(stored_atoms))
			var/list/dropping_atoms = stored_atoms.Copy()
			rel_clear(src, nameof(stored_atoms))
			for(var/atom/movable/dropping as anything in dropping_atoms)
				if(!QDELETED(dropping) && dropping.loc == src)
					dropping.dropInto(loc)
					dropping.throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),rand(1,3),30)

	. = ..()

/mob/living/silicon/robot/platform/proc/can_store_atom(atom/movable/storing, mob/user)

	if(!istype(storing))
		var/storing_target = (user == src) ? "yourself" : "\the [src]"
		to_chat(user, span_warning("You cannot store that inside [storing_target]."))
		return FALSE

	if(!isturf(storing.loc))
		return FALSE

	if(storing.anchored || !storing.simulated)
		to_chat(user, span_warning("\The [storing] won't budge!"))
		return FALSE

	if(storing == src)
		var/storing_target = (user == src) ? "yourself" : "\the [src]"
		to_chat(user, span_warning("You cannot store [storing_target] inside [storing_target]!"))
		return FALSE

	if(length(stored_atoms) >= max_stored_atoms)
		var/storing_target = (user == src) ? "Your" : "\The [src]'s"
		to_chat(user, span_warning("[storing_target] cargo compartment is full."))
		return FALSE

	if(ismob(storing))
		var/mob/M = storing
		if(M.mob_size >= mob_size)
			var/storing_target = (user == src) ? "your storage compartment" : "\the [src]"
			to_chat(user, span_warning("\The [storing] is too big for [storing_target]."))
			return FALSE

	for(var/store_type in can_store_types)
		if(istype(storing, store_type))
			. = TRUE
			break

	if(.)
		for(var/store_type in cannot_store_types)
			if(istype(storing, store_type))
				. = FALSE
				break
	if(!.)
		var/storing_target = (user == src) ? "yourself" : "\the [src]"
		to_chat(user, span_warning("You cannot store \the [storing] inside [storing_target]."))

/mob/living/silicon/robot/platform/proc/store_atom(atom/movable/storing, mob/user)
	if(istype(storing))
		storing.forceMove(src)
		rel_add(src, nameof(stored_atoms), storing)

/mob/living/silicon/robot/platform/proc/drop_stored_atom(atom/movable/ejecting, mob/user)

	if(!ejecting && length(stored_atoms))
		ejecting = stored_atoms[1]

	rel_remove(src, nameof(stored_atoms), ejecting)
	if(istype(ejecting) && !QDELETED(ejecting) && ejecting.loc == src)
		ejecting.dropInto(loc)
		if(user == src)
			act_message(src, ejecting, others = span_infoplain(span_bold("%U%") + " ejects %T% from its cargo compartment."))
		else
			act_message(user, ejecting, others = span_infoplain(span_bold("%U%") + " pulls %T% from \the [src]'s cargo compartment."))

/// Old attack_ai: an adjacent cyborg unloads cargo; otherwise the next silicon Use / default.
/mob/living/silicon/robot/platform/proc/platform_silicon_unload(datum/act/op/A)
	var/mob/user = A.actor
	if(user.Adjacent(src))
		try_remove_cargo(user)
		return OP_OK
	return OP_DECLINE

/mob/living/silicon/robot/platform/proc/try_remove_cargo(mob/user)
	if(!length(stored_atoms) || !istype(user))
		return FALSE
	var/atom/movable/removing = stored_atoms[length(stored_atoms)]
	if(QDELETED(removing) || removing.loc != src)
		rel_remove(src, nameof(stored_atoms), removing)
	else
		act_message(user, removing, others = span_infoplain(span_bold("%U%") + " begins unloading %T% from \the [src]'s cargo compartment."))
		task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(try_remove_cargo_platform_done), done_args = list(user, removing))
	return TRUE

/mob/living/silicon/robot/platform/proc/try_remove_cargo_platform_done(mob/user, atom/movable/removing)
	if(!(!QDELETED(removing) && removing.loc == src))
		return
	drop_stored_atom(removing, user)

/datum/interaction/ability/self/robot_eject_cargo
	id = ABILITY_ID_ROBOT_EJECT_CARGO
	name = "Eject cargo"
	category = ABILITY_CAT_UTILITY
	requires = list(
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_not_incapacitated, "you are not in any state to do that"),
		REQ_ON(PRED_ACTOR, /mob/living/silicon/robot/platform/proc/dq_pred_has_stored_atoms, "you have nothing in your cargo compartment"),
	)
	effect = /mob/living/silicon/robot/platform/proc/dq_do_eject_cargo

/datum/interaction/ability/self/robot_eject_cargo/applies_to(atom/target)
	return istype(target, /mob/living/silicon/robot/platform)

/mob/living/proc/dq_pred_not_incapacitated(mob/living/actor, atom/target, obj/item/held)
	return !actor.incapacitated() || "you are not in any state to do that"

/mob/living/silicon/robot/platform/proc/dq_pred_has_stored_atoms(mob/living/silicon/robot/platform/actor, atom/target, obj/item/held)
	return length(actor.stored_atoms) || "you have nothing in your cargo compartment"

/// Drop something from your internal storage.
/mob/living/silicon/robot/platform/proc/dq_do_eject_cargo(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	drop_stored_atom(user = src)
	return TRUE

/// Old MouseDrop_T: start loading the dropped thing into cargo. A refused drop still falls to the
/// cyborg's drag block, as the old override never reached the base drag-buckle.
/mob/living/silicon/robot/platform/proc/platform_interaction_drag(datum/act/op/A)
	var/mob/living/user = A.actor
	var/atom/movable/dropping = A.held
	if(!istype(user) || !istype(dropping) || user.incapacitated())
		return OP_DECLINE
	if(!can_mouse_drop(dropping, user) || !can_store_atom(dropping, user))
		return OP_DECLINE
	if(user == src)
		act_message(src, dropping, others = span_infoplain(span_bold("%U%") + " begins loading %T% into its cargo compartment."))
	else
		act_message(user, dropping, others = span_infoplain(span_bold("%U%") + " begins loading %T% into \the [src]'s cargo compartment."))
	task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(MouseDrop_T_platform_done), done_args = list(dropping, user))
	return OP_OK

/mob/living/silicon/robot/platform/proc/MouseDrop_T_platform_done(atom/movable/dropping, mob/living/user)
	if(!(can_mouse_drop(dropping, user) && can_store_atom(dropping, user)))
		return
	store_atom(dropping, user)

/mob/living/silicon/robot/platform/proc/can_mouse_drop(atom/dropping, mob/user)
	if(!istype(user) || !istype(dropping) || QDELETED(dropping) || QDELETED(user) || QDELETED(src))
		return FALSE
	if(user.incapacitated() || !Adjacent(user) || !dropping.Adjacent(user))
		return FALSE
	return TRUE
