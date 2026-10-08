/obj/structure/bed/chair/wheelchair
	name = "wheelchair"
	desc = "You sit in this. Either by will or force."
	icon = 'icons/obj/wheelchair.dmi'
	icon_state = "wheelchair"
	anchored = FALSE
	buckle_movable = 1
	can_pad = FALSE
	can_unpad = FALSE
	can_dismantle = FALSE

	var/folded_type = /obj/item/wheelchair
	var/driving = 0
	var/bloodiness
	var/min_mob_buckle_size = MOB_SMALL
	var/max_mob_buckle_size = MOB_LARGE

/obj/structure/bed/chair/wheelchair/Initialize(mapload, new_material, new_padding_material)
	. = ..()

/obj/structure/bed/chair/wheelchair/motor
	name = "electric wheelchair"
	desc = "A motorized wheelchair controlled with a joystick on one armrest"
	icon_state = "motorchair"
	folded_type = /obj/item/wheelchair/motor

/obj/structure/bed/chair/wheelchair/smallmotor
	name = "small electric wheelchair"
	desc = "A small motorized wheelchair, it looks around the right size for a Teshari"
	icon_state = "teshchair"
	min_mob_buckle_size = MOB_SMALL
	max_mob_buckle_size = MOB_MEDIUM
	folded_type = /obj/item/wheelchair/motor/small

/obj/structure/bed/chair/wheelchair/look_parts(datum/look/look)
	var/drawn_state = look.state_so_far(src)
	look.overlay(look_cached_image("[initial(icon)]-[drawn_state]-overlay", initial(icon), "[drawn_state]_overlay", null, MOB_PLANE, ABOVE_MOB_LAYER))

/obj/structure/bed/chair/wheelchair/set_dir()
	. = ..()
	if(.)
		if(has_buckled_mobs())
			for(var/mob/living/L as anything in src?.buckled_mob_list())
				L.set_dir(dir)

/obj/structure/bed/chair/wheelchair/relaymove(mob/user, direction)
	// Redundant check?
	// pulling_target() is a live read of the link, so this re-fetches it after every link_break() rather than trusting a cached local.
	var/mob/living/pulling = src?.pulling_target()
	if(user.stat || user.has_status(STAT_STUNNED) || user.has_status(STAT_WEAKENED) || user.has_status(STAT_PARALYZED) || user.lying || user.restrained())
		if(user==pulling)
			link_break(src, LK_PULLING, pulling)
			to_chat(user, span_warning("You lost your grip!"))
		return
	if(has_buckled_mobs() && pulling && (user in src?.buckled_mob_list()))
		if(pulling.stat || pulling.has_status(STAT_STUNNED) || pulling.has_status(STAT_WEAKENED) || pulling.has_status(STAT_PARALYZED) || pulling.lying || pulling.restrained())
			link_break(src, LK_PULLING, pulling)
			pulling = src?.pulling_target()
	if(user?.pulling_target() && (user == pulling))
		link_break(src, LK_PULLING, pulling)
		return
	if(propelled)
		return
	if(pulling && (get_dist(src, pulling) > 1))
		var/mob/living/was_pulling = pulling
		link_break(src, LK_PULLING, pulling)
		pulling = src?.pulling_target()
		if(user==was_pulling)
			return
	if(pulling && (get_dir(src.loc, pulling.loc) == direction))
		to_chat(user, span_warning("You cannot go there."))
		return
	if(pulling && has_buckled_mobs() && (user in src?.buckled_mob_list()))
		to_chat(user, span_warning("You cannot drive while being pushed."))
		return

	// Let's roll
	driving = 1
	var/turf/T = null
	//--1---Move occupant---1--//
	if(has_buckled_mobs())
		for(var/mob/living/L as anything in src?.buckled_mob_list())
			// Transient, not a relation change.
			L.skip_buckled_move_redirect = TRUE
			step(L, direction)
			L.skip_buckled_move_redirect = FALSE
	//--2----Move driver----2--//
	if(pulling)
		T = pulling.loc
		if(get_dist(src, pulling) >= 1)
			step(pulling, get_dir(pulling.loc, src.loc))
	//--3--Move wheelchair--3--//
	step(src, direction)
	if(has_buckled_mobs()) // Make sure it stays beneath the occupant
		var/mob/living/L = src?.buckled_mob_list()[1]
		Move(L.loc)
	set_dir(direction)
	if(pulling) // Driver
		if(pulling.loc == src.loc) // We moved onto the wheelchair? Revert!
			pulling.forceMove(T)
		else
			after(src, 0, PROC_REF(check_pulled_along))
	if(bloodiness)
		create_track()
	driving = 0

/obj/structure/bed/chair/wheelchair/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	play_sfx(src, SFX_EFFECTS_ROLL, 0.75)
	if(has_buckled_mobs())
		for(var/mob/living/occupant as anything in src?.buckled_mob_list())
			if(!driving)
				// Transient, not a relation change.
				occupant.skip_buckled_move_redirect = TRUE
				occupant.Move(src.loc)
				occupant.skip_buckled_move_redirect = FALSE
				if (occupant && (src.loc != occupant.loc))
					if (propelled)
						for (var/mob/O in src.loc)
							if (O != occupant)
								Bump(O)
					else
						unbuckle_mob()
				var/mob/living/pulling = src?.pulling_target()
				if (pulling && (get_dist(src, pulling) > 1))
					var/mob/living/was_pulling = pulling
					link_break(src, LK_PULLING, pulling)
					to_chat(was_pulling, span_warning("You lost your grip!"))
			else
				if (occupant && (src.loc != occupant.loc))
					src.forceMove(occupant.loc) // Failsafe to make sure the wheelchair stays beneath the occupant after driving

CAPABILITIES(/obj/structure/bed/chair/wheelchair)
	configure(buckle(smallest = nameof(min_mob_buckle_size), largest = nameof(max_mob_buckle_size)))
	op("touch", hand(), label("Use"), priority(above("buckle.unbuckle")), then(PROC_REF(touched)))

/// A hand on the chair: drops the one pulling it, or frees whoever is sitting in it.
/obj/structure/bed/chair/wheelchair/proc/touched(datum/act/op/A)
	var/mob/living/user = A.actor
	if (src?.pulling_target())
		MouseDrop(user)
	else
		if(has_buckled_mobs())
			for(var/mob/living/occupant in src.buckled_mob_list())
				user_unbuckle_mob(occupant, user)
	return OP_OK

/obj/structure/bed/chair/wheelchair/click_ctrl(mob/user)
	if(in_range(src, user))
		if(!ishuman(user))	return
		if(has_buckled_mobs() && (user in src?.buckled_mob_list()))
			to_chat(user, span_warning("You realize you are unable to push the wheelchair you sit in."))
			return
		var/mob/living/pulling = src?.pulling_target()
		if(!pulling)
			if(user?.pulling_target())
				user.stop_pulling()
			pull_link(user)
			user.set_dir(get_dir(user, src))
			to_chat(user, "You grip \the [name]'s handles.")
		else
			to_chat(user, "You let go of \the [name]'s handles.")
			link_break(src, LK_PULLING, pulling)
		return

/obj/structure/bed/chair/wheelchair/Bump(atom/A)
	..()
	if(!has_buckled_mobs())	return

	var/mob/living/pulling = src?.pulling_target()
	if(propelled || (pulling && pulling.combat_mode))
		var/mob/living/occupant = unbuckle_mob()

		if (pulling && pulling.combat_mode)
			occupant.throw_at(A, 3, 3, pulling)
		else if (propelled)
			occupant.throw_at(A, 3, propelled)

		var/def_zone = ran_zone()
		var/blocked = occupant.armor_against(INJURY_BLUNT, def_zone)
		occupant.throw_at(A, 3, propelled)
		occupant.apply_effect(6, STUN, blocked)
		occupant.apply_effect(6, WEAKEN, blocked)
		occupant.apply_effect(6, STUTTER, blocked)
		occupant.injure(INJURY_BLUNT, 10, def_zone, src, flags = INJURE_ARMORED)
		play_sfx(src, SFX_WEAPONS_PUNCH1)
		if(isliving(A))
			var/mob/living/victim = A
			def_zone = ran_zone()
			blocked = victim.armor_against(INJURY_BLUNT, def_zone)
			victim.apply_effect(6, STUN, blocked)
			victim.apply_effect(6, WEAKEN, blocked)
			victim.apply_effect(6, STUTTER, blocked)
			victim.injure(INJURY_BLUNT, 10, def_zone, src, flags = INJURE_ARMORED)
		if(pulling)
			act_message(pulling, occupant, others = span_danger("%U% has thrusted \the [name] into \the [A], throwing %T% out of it!"))

			add_attack_logs(pulling,occupant,"Crashed their [name] into [A]")
		else
			act_message(occupant, A, others = span_danger("%U% crashed into %T%!"))

/obj/structure/bed/chair/wheelchair/proc/create_track()
	var/obj/effect/decal/cleanable/blood/tracks/B = new(loc)
	var/newdir = get_dir(get_step(loc, dir), loc)
	if(newdir == dir)
		B.set_dir(newdir)
	else
		newdir = newdir | dir
		if(newdir == 3)
			newdir = 1
		else if(newdir == 12)
			newdir = 4
		B.set_dir(newdir)
	bloodiness--

/obj/structure/bed/chair/wheelchair/MouseDrop(over_object, src_location, over_location)
	..()
	var/mob/user = usr
	if(!istype(user))
		return
	if((over_object == user && (in_range(src, user) || user.contents.Find(src))))
		if(!ishuman(user))	return
		if(has_buckled_mobs())	return 0
		act_message(user, null, others = "%U% collapses \the [src.name].")
		var/obj/item/wheelchair/R = new folded_type(get_turf(src))
		R.name = src.name
		R.color = src.color
		expire(0)
		return

/obj/structure/bed/chair/wheelchair/proc/check_pulled_along()
	var/mob/living/pulling = src?.pulling_target()
	if(!pulling)
		return
	if(get_dist(src, pulling) > 1) // We are too far away? Losing control.
		link_break(src, LK_PULLING, pulling)
	pulling = src?.pulling_target()
	if(pulling)
		pulling.set_dir(get_dir(pulling, src)) // When everything is right, face the wheelchair
