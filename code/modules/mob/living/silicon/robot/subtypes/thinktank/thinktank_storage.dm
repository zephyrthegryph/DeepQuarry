/mob/living/silicon/robot/platform/on_death(gibbed)

	if(gibbed)

		if(recharging)
			var/obj/item/recharging_atom = om_resolve(recharging)
			if(istype(recharging_atom) && !QDELETED(recharging_atom) && recharging_atom.loc == src)
				recharging_atom.dropInto(loc)
				recharging_atom.throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),rand(1,3),30)
			recharging = null

		if(length(stored_atoms))
			for(var/stored_ref in stored_atoms)
				var/atom/movable/dropping = om_resolve(stored_ref)
				if(istype(dropping) && !QDELETED(dropping) && dropping.loc == src)
					dropping.dropInto(loc)
					dropping.throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),rand(1,3),30)
			stored_atoms = null

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
		LAZYDISTINCTADD(stored_atoms, om_handle(storing))

/mob/living/silicon/robot/platform/proc/drop_stored_atom(atom/movable/ejecting, mob/user)

	if(!ejecting && length(stored_atoms))
		var/stored_ref = stored_atoms[1]
		ejecting = om_resolve(stored_ref)
		if(!ejecting)
			LAZYREMOVE(stored_atoms, stored_ref)

	LAZYREMOVE(stored_atoms, om_handle(ejecting))
	if(istype(ejecting) && !QDELETED(ejecting) && ejecting.loc == src)
		ejecting.dropInto(loc)
		if(user == src)
			visible_message(span_infoplain(span_bold("\The [src]") + " ejects \the [ejecting] from its cargo compartment."))
		else
			user.visible_message(span_infoplain(span_bold("\The [user]") + " pulls \the [ejecting] from \the [src]'s cargo compartment."))

/mob/living/silicon/robot/platform/attack_ai(mob/user)
	if(isrobot(user) && user.Adjacent(src))
		return try_remove_cargo(user)
	return ..()

/mob/living/silicon/robot/platform/proc/try_remove_cargo(mob/user)
	if(!length(stored_atoms) || !istype(user))
		return FALSE
	var/remove_ref = stored_atoms[length(stored_atoms)]
	var/atom/movable/removing = om_resolve(remove_ref)
	if(!istype(removing) || QDELETED(removing) || removing.loc != src)
		LAZYREMOVE(stored_atoms, remove_ref)
	else
		user.visible_message(span_infoplain(span_bold("\The [user]") + " begins unloading \the [removing] from \the [src]'s cargo compartment."))
		om_do_after(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(try_remove_cargo_platform_done), done_args = list(user, removing))
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

/mob/living/silicon/robot/platform/MouseDrop_T(atom/movable/dropping, mob/living/user)
	if(!istype(user) || !istype(dropping) || user.incapacitated())
		return FALSE
	if(!can_mouse_drop(dropping, user) || !can_store_atom(dropping, user))
		return FALSE
	if(user == src)
		visible_message(span_infoplain(span_bold("\The [src]") + " begins loading \the [dropping] into its cargo compartment."))
	else
		user.visible_message(span_infoplain(span_bold("\The [user]") + " begins loading \the [dropping] into \the [src]'s cargo compartment."))
	om_do_after(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(MouseDrop_T_platform_done), done_args = list(dropping, user))
	return FALSE

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
