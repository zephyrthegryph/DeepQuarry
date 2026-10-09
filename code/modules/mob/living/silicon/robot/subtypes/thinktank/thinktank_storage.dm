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

/// An empty hand or an adjacent cyborg can unload while the cover is closed, the recharging port is empty and something is stored.
/mob/living/silicon/robot/platform/proc/cargo_unloadable(datum/act/op/A)
	return read_once(!opened && !recharging) && length(stored_atoms) > 0

/// Old attack_ai: an adjacent cyborg unloads cargo; otherwise the next silicon Use / default.
/mob/living/silicon/robot/platform/proc/cargo_unloadable_by_silicon(datum/act/op/A)
	var/mob/user = A.actor
	return read_once(istype(user, /mob/living/silicon/robot) && user.Adjacent(src)) && length(stored_atoms) > 0

/// What the others see when the last stored thing starts to come out.
/mob/living/silicon/robot/platform/proc/cargo_unloading_text(datum/act/op/A)
	var/atom/movable/removing = stored_atoms[length(stored_atoms)]
	return msg_text(null, span_infoplain(span_bold("%U%") + " begins unloading [removing] from [src]'s cargo compartment."))

/// The last stored thing comes out.
/mob/living/silicon/robot/platform/proc/platform_unloaded(datum/act/op/A)
	if(!length(stored_atoms))
		return OP_FAILED
	var/atom/movable/removing = stored_atoms[length(stored_atoms)]
	if(QDELETED(removing) || removing.loc != src)
		return OP_FAILED
	drop_stored_atom(removing, A.actor)
	return OP_OK

MSG_DEF_SELF(platform_ability/not_able, "you are not in any state to do that")
MSG_DEF_SELF(platform_ability/no_cargo, "you have nothing in your cargo compartment")

CAPABILITY_DEF(platform_cargo, CAP_PLATFORM_CARGO, key = NONE)

/datum/capability/def/platform_cargo/entries()
	return list(
		op("eject_cargo", label("Eject cargo"), menu(button = "Eject cargo", bind = "ability_robot_eject_cargo"), needs(req_self()),
			needs(req(TYPE_PROC_REF(/mob/living/silicon/robot/platform, can_act_to_eject), because = MSG(platform_ability/not_able)),
				req(TYPE_PROC_REF(/mob/living/silicon/robot/platform, has_stored_atoms), because = MSG(platform_ability/no_cargo))),
			then(TYPE_PROC_REF(/mob/living/silicon/robot/platform, ability_eject_cargo))))

/mob/living/silicon/robot/platform/proc/can_act_to_eject(datum/act/op/A)
	return !incapacitated()

/mob/living/silicon/robot/platform/proc/has_stored_atoms(datum/act/op/A)
	return length(stored_atoms) > 0

/// Drop something from your internal storage.
/mob/living/silicon/robot/platform/proc/ability_eject_cargo(datum/act/op/A)
	drop_stored_atom(user = src)
	return OP_OK

/// Old MouseDrop_T: a drop that can be stored starts the loading. A refused drop still falls to the cyborg's drag block, as the old override never reached
/// the base drag-buckle. This is the silent form of can_store_atom().
/mob/living/silicon/robot/platform/proc/cargo_loadable(datum/act/op/A)
	var/mob/living/user = A.actor
	var/atom/movable/dropping = A.held
	return read_once(istype(user) && istype(dropping) && !user.incapacitated() && can_mouse_drop(dropping, user) && can_store_quiet(dropping))

/mob/living/silicon/robot/platform/proc/can_store_quiet(atom/movable/storing)
	if(!istype(storing) || !isturf(storing.loc) || storing.anchored || !storing.simulated || storing == src)
		return FALSE
	if(length(stored_atoms) >= max_stored_atoms)
		return FALSE
	if(ismob(storing))
		var/mob/M = storing
		if(M.mob_size >= mob_size)
			return FALSE
	for(var/store_type in can_store_types)
		if(istype(storing, store_type))
			for(var/refused_type in cannot_store_types)
				if(istype(storing, refused_type))
					return FALSE
			return TRUE
	return FALSE

/// What the others see when the loading starts.
/mob/living/silicon/robot/platform/proc/cargo_loading_text(datum/act/op/A)
	if(A.actor == src)
		return msg_text(null, span_infoplain(span_bold("%U%") + " begins loading %I% into its cargo compartment."))
	return msg_text(null, span_infoplain(span_bold("%U%") + " begins loading %I% into [src]'s cargo compartment."))

/mob/living/silicon/robot/platform/proc/platform_loaded(datum/act/op/A)
	var/mob/living/user = A.actor
	var/atom/movable/dropping = A.held
	if(!(can_mouse_drop(dropping, user) && can_store_atom(dropping, user)))
		return OP_FAILED
	store_atom(dropping, user)
	return OP_OK

/mob/living/silicon/robot/platform/proc/can_mouse_drop(atom/dropping, mob/user)
	if(!istype(user) || !istype(dropping) || QDELETED(dropping) || QDELETED(user) || QDELETED(src))
		return FALSE
	if(user.incapacitated() || !Adjacent(user) || !dropping.Adjacent(user))
		return FALSE
	return TRUE
