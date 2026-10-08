

/atom/movable
	var/can_buckle = FALSE
	var/buckle_movable = 0
	var/buckle_dir = 0
	var/buckle_lying = -1 //bed-like behavior, forces mob.lying = buckle_lying if != -1
	var/buckle_require_restraints = 0 //require people to be handcuffed before being able to buckle. eg: pipes
	var/max_buckled_mobs = 1


/// Re-checked on the answer: still next to it, and the pick is still buckled to it.
/datum/prompt/choice/unbuckle_who
	title = "Unbuckle Who?"
	question = "Who do you wish to unbuckle?"
	timeout = 0
	ask_flags = ASK_ADJACENT | ASK_CAPABLE

/datum/prompt/choice/unbuckle_who/recheck_extra()
	var/atom/movable/AM = subject || owner
	return (istype(AM) && (value in AM.buckled_mob_list())) ? null : "not buckled"

/atom/movable/proc/unbuckle_chosen(datum/act/request/A)
	if(A.answer)
		user_unbuckle_mob(A.answer.value, A.request.answerer)

/atom/movable/hand_gate(mob/living/user)
	. = ..()

	if(can_buckle && has_buckled_mobs())
		var/list/mobs = src?.buckled_mob_list()
		if(mobs.len > 1)
			open_request(src, /datum/prompt/choice/unbuckle_who, PROC_REF(unbuckle_chosen), answerer = user, choices = mobs)
			return TRUE
		else
			if(user_unbuckle_mob(mobs[1], user))
				return TRUE

/obj/proc/attack_alien(mob/user as mob) //For calling in the event of Xenomorph or other alien checks.
	return


/atom/movable
	/// Dragging a mob onto this buckles it (when can_buckle) or climbs it. FALSE for mobs that are
	/// mounted another way (riding animals use their mount verb) and so ignore the drag.
	var/drag_buckle = TRUE

TRACKED(/atom/movable, can_buckle)
TRACKED(/atom/movable, drag_buckle)

/// Every movable's default drag (op "drag_buckle", in CAPABILITIES(/atom/movable), code/modules/lighting/lighting_atom.dm): a mob dragged onto it is
/// buckled to it, while something can be buckled to it (climbing is the climb capability's own drag; a buckle() seat answers first, at its own tier).
/atom/movable/proc/interaction_drag_buckle(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/M = A.held
	if(istype(M) && user_buckle_mob(M, user))
		return OP_OK
	return OP_DECLINE

/atom/movable/proc/has_buckled_mobs()
	return LAZYLEN(src?.buckled_mob_list())




/atom/movable/proc/buckle_mob(mob/living/M, forced = FALSE, check_loc = TRUE)
	if(check_loc && M.loc != loc)
		return FALSE

	if(!can_buckle_check(M, forced))
		return FALSE

	if(M == src)
		stack_trace("Recursive buckle warning: [M] being buckled to self.")
		return

	return buckle_link(M)

/// Writes the buckle link (the sparse pair LK_BUCKLED_TO / LK_BUCKLED_MOBS) and does what buckling someone does to them and to the seat. The link itself
/// frees the rider when the seat or the rider goes or the rider ends up off the seat's tile (holds_while), and buckle_released() / buckle_vacated() do the
/// cleanup. FALSE when the link was refused.
/atom/movable/proc/buckle_link(mob/living/M)
	if(!link_make(M, LK_BUCKLED_TO, src))
		return FALSE
	M.facing_dir = null
	M.set_dir(buckle_dir ? buckle_dir : dir)
	M.update_canmove()
	M.update_floating(M.Check_Dense_Object())
	if(riding_datum)
		rel_set(riding_datum, nameof(/datum/riding::ridden), src)
		riding_datum.handle_vehicle_offsets()
	M.update_water()
	post_buckle_mob(M)
	M.throw_alert("buckled", /atom/movable/screen/alert/restrained/buckled, new_master = src)
	PUBLISH_CHANGE(M, MOB_KEY_STATUS)
	return TRUE

STAT(/mob/living, buckled, ANY, virtual = TRUE)

/// links(holds_while) of the buckle pair: a rider stays buckled while it is on the seat's tile.
/atom/movable/proc/link_stays_seated(atom/movable/seat)
	return link_in_range(seat, 0)

/// The buckle link broke: the rider is no longer held where it was.
/mob/living/proc/buckle_released(atom/movable/seat)
	set_anchored(initial(anchored))
	update_canmove()
	update_floating(Check_Dense_Object())
	clear_alert("buckled")
	update_water()
	PUBLISH_CHANGE(src, MOB_KEY_STATUS)

/// The seat's side of it: its riding offsets are restored and it hears who left.
/atom/movable/proc/buckle_vacated(mob/living/rider)
	if(riding_datum)
		if(istype(rider))
			riding_datum.restore_position(rider)
		riding_datum.handle_vehicle_offsets()
	post_buckle_mob(istype(rider) ? rider : null)

/atom/movable/proc/unbuckle_mob(mob/living/buckled_mob, force = FALSE)
	if(!buckled_mob) // If we didn't get told which mob needs to get unbuckled, just assume its the first one on the list.
		if(has_buckled_mobs())
			buckled_mob = src?.buckled_mob_list()[1]
		else
			return

	if(buckled_mob && buckled_mob?.buckled_to() == src)
		. = buckled_mob
		// buckle_released() / buckle_vacated() do the actual unbuckling.
		link_break(buckled_mob, LK_BUCKLED_TO, src)

/atom/movable/proc/unbuckle_all_mobs(force = FALSE)
	if(!has_buckled_mobs())
		return
	for(var/m in src?.buckled_mob_list())
		unbuckle_mob(m, force)

//Handle any extras after buckling/unbuckling
//Called on buckle_mob() and unbuckle_mob()
/atom/movable/proc/post_buckle_mob(mob/living/M)
	return

//Wrapper procs that handle sanity and user feedback
/atom/movable/proc/user_buckle_mob(mob/living/M, mob/user, forced = FALSE, silent = FALSE)
	if(!SSticker)
		to_chat(user, span_warning("You can't buckle anyone in before the game starts."))
		return FALSE // Is this really needed?
	if(!user.Adjacent(M) || user.restrained() || user.stat || ispAI(user))
		return FALSE
	if(M in src?.buckled_mob_list())
		to_chat(user, span_warning("\The [M] is already buckled to \the [src]."))
		return FALSE
	if(!can_buckle_check(M, forced, TRUE))
		return FALSE

	var/list/buckled_here = src?.buckled_mob_list()
	if(has_buckled_mobs() && buckled_here.len >= max_buckled_mobs)
		for(var/mob/living/L in buckled_here)
			if(istype(L) && can_stumble_vore(prey = L, pred = M))
				unbuckle_mob(L, TRUE)
				if(M == user)
					act_message(M, L, others = span_warning("%U% sits down on %T%!"))
				else
					act_message(user, M, others = span_warning("%T% is forced to sit down on [L.name] by %U%!"))
				M.begin_instant_nom(user, L, M, M.vore_selected)

	add_fingerprint(user)

	//can't buckle unless you share locs so try to move M to the obj.
	if(M.loc != src.loc)
		if(M.Adjacent(src) && user.Adjacent(src))
			M.forceMove(get_turf(src))

	. = buckle_mob(M, forced)
	play_sfx(src.loc, SFX_EFFECTS_SEATBELT)
	if(.)
		var/reveal_message = list("buckled_mob" = null, "buckled_to" = null)
		if(!silent)
			if(M == user)
				reveal_message["buckled_mob"] = span_notice("You come out of hiding and buckle yourself to [src].")
				reveal_message["buckled_to"] = span_notice("You come out of hiding as [M.name] buckles themselves to you.")
				act_message(M, src, MSG_SELF(span_notice("You buckle yourself to %T%.")), \
					MSG_OTHERS(span_notice("[M.name] buckles themselves to %T%.")), \
					MSG_BLIND(span_notice("You hear metal clanking.")))
			else
				reveal_message["buckled_mob"] = span_notice("You are revealed as you are buckled to [src].")
				reveal_message["buckled_to"] = span_notice("You are revealed as [M.name] is buckled to you.")
				act_message(M, src, MSG_SELF(span_danger("You are buckled to %T% by [user.name]!")), \
					MSG_OTHERS(span_danger("[M.name] is buckled to %T% by [user.name]!")), \
					MSG_BLIND(span_notice("You hear metal clanking.")))

		M.reveal(silent, reveal_message["buckled_mob"]) //Reveal people so they aren't buckled to chairs from behind.
		var/mob/living/L = src
		if(istype(L))
			L.reveal(silent, reveal_message["buckled_to"])

/atom/movable/proc/user_unbuckle_mob(mob/living/buckled_mob, mob/user)
	var/mob/living/M = unbuckle_mob(buckled_mob)
	play_sfx(src.loc, SFX_EFFECTS_SEATBELT)
	if(M)
		if(M != user)
			act_message(M, src, MSG_SELF(span_notice("You were unbuckled from %T% by [user.name].")), \
				MSG_OTHERS(span_notice("[M.name] was unbuckled by [user.name]!")), \
				MSG_BLIND(span_notice("You hear metal clanking.")))
		else
			act_message(M, src, MSG_SELF(span_notice("You unbuckle yourself from %T%.")), \
				MSG_OTHERS(span_notice("[M.name] unbuckled themselves!")), \
				MSG_BLIND(span_notice("You hear metal clanking.")))
		add_fingerprint(user)
	return M

/atom/movable/proc/handle_buckled_mob_movement(atom/old_loc, direct, movetime)
	for(var/mob/living/L as anything in src?.buckled_mob_list())
		if(!L.Move(loc, direct, movetime))
			L.forceMove(loc, direct, movetime)
			L.last_move = last_move
			L.inertia_dir = last_move

		if(!buckle_dir)
			L.set_dir(dir)
		else
			L.set_dir(buckle_dir)

/atom/movable/proc/can_buckle_check(mob/living/M, forced = FALSE, can_do_spont_vore = FALSE)
	if(!istype(M))
		return FALSE

	if((!can_buckle && !forced) || M?.buckled_to() || LAZYLEN(M.pinned) || (max_buckled_mobs == 0) || (buckle_require_restraints && !M.restrained()))
		return FALSE
	if(LAZYLEN(M?.grabbed_by_list()) && !forced)
		to_chat(M, span_boldwarning("You can not buckle while grabbed!"))
		return FALSE

	var/list/buckled_here2 = src?.buckled_mob_list()
	if(has_buckled_mobs() && buckled_here2.len >= max_buckled_mobs) //Handles trying to buckle yourself to the chair when someone is on it
		if(can_do_spont_vore && is_vore_predator(M) && M.vore_selected)
			for(var/mob/living/buckled in buckled_here2)
				if(can_stumble_vore(prey = buckled, pred = M))
					return TRUE
		to_chat(M, span_notice("\The [src] can't buckle any more people."))
		return FALSE

	return TRUE
