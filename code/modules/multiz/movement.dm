/mob/verb/up()
	set name = "Move Upwards"
	set category = VERB_CAT_IC_GAME

	if(zMove(UP))
		to_chat(src, span_notice("You move upwards."))

/mob/verb/down()
	set name = "Move Down"
	set category = VERB_CAT_IC_GAME

	if(zMove(DOWN))
		to_chat(src, span_notice("You move down."))

/mob/proc/zMove(direction)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(eyeobj)
		return eyeobj.zMove(direction)
	if(istype(loc,/obj/mecha))
		var/obj/mecha/mech = loc
		return mech.relaymove(src,direction)
	if(isliving(src) && istype(loc, /obj/machinery/atmospherics/pipe/zpipe))
		var/obj/machinery/atmospherics/pipe/zpipe/pipe = loc
		return pipe.ventcrawl_z(src, direction)

	var/swim_modifier = 1
	var/climb_modifier = 1
	if(ishuman(src))
		var/mob/living/carbon/human/MS = src
		swim_modifier = MS.species.swim_mult
		climb_modifier = MS.species.climb_mult

	if(!can_ztravel())
		to_chat(src, span_warning("You lack means of travel in that direction."))
		return

	var/turf/start = loc
	if(!istype(start))
		to_chat(src, span_notice("You are unable to move from here."))
		return 0

	var/turf/destination = (direction == UP) ? GetAbove(src) : GetBelow(src)
	if(!destination)
		to_chat(src, span_notice("There is nothing of interest in this direction."))
		return 0

	if(is_incorporeal())
		forceMove(destination)
		return 1

	var/obj/structure/ladder/ladder = locate_on(start, /obj/structure/ladder)
	if((direction == UP ? ladder?.target_up : ladder?.target_down) && (ladder?.allowed_directions & direction))
		if(src.may_climb_ladders(ladder))
			return ladder.climbLadder(src, (direction == UP ? ladder.target_up : ladder.target_down))

	if(!start.CanZPass(src, direction))
		to_chat(src, span_warning("\The [start] is in the way."))
		return 0

	if(direction == DOWN)
		if(isdiveablewater(start) && !destination.density)
			var/pull_up_time = max((3 SECONDS + (src.movement_delay() * 10) * swim_modifier), 1)
			to_chat(src, span_notice("You start diving underwater..."))
			src.audible_message(span_notice("[src] begins to dive under the water."), runemessage = "splish splosh")
			perform_op(src, src, "zmove_timed", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("duration" = pull_up_time, "direction" = direction, "start" = start, "destination" = destination, "done_message" = "You reach the sea floor.", "needs_flight" = FALSE, "fail_message" = span_warning("You stopped swimming downwards.")))
			return 0

		else if(!destination.CanZPass(src, direction)) // one for the down and non-special case
			to_chat(src, span_warning("\The [destination] blocks your way."))
			return 0

	else if(!destination.CanZPass(src, direction)) // and one for up
		to_chat(src, span_warning("\The [destination] blocks your way."))
		return 0


	var/area/area = get_area(src)
	if(area.get_gravity() && !can_overcome_gravity())
		if(direction == UP)
			var/obj/structure/lattice/lattice = locate_on(destination, /obj/structure/lattice)
			var/obj/structure/catwalk/catwalk = locate_on(destination, /obj/structure/catwalk)

			if(lattice)
				var/pull_up_time = max((5 SECONDS + (src.movement_delay() * 10) * climb_modifier), 1)
				to_chat(src, span_notice("You grab \the [lattice] and start pulling yourself upward..."))
				src.audible_message(span_notice("[src] begins climbing up \the [lattice]."), runemessage = "clank clang")
				perform_op(src, src, "zmove_timed", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("duration" = pull_up_time, "direction" = direction, "start" = start, "destination" = destination, "done_message" = "You pull yourself up.", "needs_flight" = FALSE, "fail_message" = span_warning("You gave up on pulling yourself up.")))
				return 0

			else if(isdiveablewater(destination))
				var/pull_up_time = max((5 SECONDS + (src.movement_delay() * 10) * swim_modifier), 1)
				to_chat(src, span_notice("You start swimming upwards..."))
				src.audible_message(span_notice("[src] begins to swim towards the surface."), runemessage = "splish splosh")
				perform_op(src, src, "zmove_timed", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("duration" = pull_up_time, "direction" = direction, "start" = start, "destination" = destination, "done_message" = "You reach the surface.", "needs_flight" = FALSE, "fail_message" = span_warning("You stopped swimming upwards.")))
				return 0

			else if(catwalk?.hatch_open)
				var/pull_up_time = max((5 SECONDS + (src.movement_delay() * 10) * climb_modifier), 1)
				to_chat(src, span_notice("You grab the edge of \the [catwalk] and start pulling yourself upward..."))
				var/old_dest = destination
				destination = get_step(destination, dir) // mob's dir
				if(!destination?.Enter(src, old_dest))
					to_chat(src, span_notice("There's something in the way up above in that direction, try another."))
					return 0
				src.audible_message(span_notice("[src] begins climbing up \the [lattice]."), runemessage = "clank clang")
				perform_op(src, src, "zmove_timed", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("duration" = pull_up_time, "direction" = direction, "start" = start, "destination" = destination, "done_message" = "You pull yourself up.", "needs_flight" = FALSE, "fail_message" = span_warning("You gave up on pulling yourself up.")))
				return 0

			// Explicit check if the destination turf allows full passing
			else if(!destination.CanZPass(src, direction))
				to_chat(src, span_warning("Something solid above stops you from passing."))
				return 0

			else if(isliving(src)) // . Are they a mob, and are they currently flying??
				var/mob/living/H = src
				if(H.flying)
					if(H.incapacitated(INCAPACITATION_ALL))
						to_chat(src, span_notice("You can't fly in your current state."))
						H.stop_flying() //Should already be done, but just in case.
						return 0
					var/fly_time = max(7 SECONDS + (H.movement_delay() * 10), 1) //So it's not too useful for combat. Could make this variable somehow, but that's down the road.
					to_chat(src, span_notice("You begin to fly upwards..."))
					H.audible_message(span_notice("[H] begins to flap \his wings, preparing to move upwards!"), runemessage = "flap flap")
					perform_op(H, H, "zmove_timed", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("duration" = fly_time, "direction" = direction, "start" = start, "destination" = destination, "done_message" = "You fly upwards.", "needs_flight" = TRUE, "fail_message" = span_warning("You stopped flying upwards.")))
					return 0
				else
					to_chat(src, span_warning("Gravity stops you from moving upward."))
					return 0 // .

			else
				to_chat(src, span_warning("Gravity stops you from moving upward."))
				return 0

	return zmove_finish(direction, start, destination)

/// A timed z-move (the "zmove_timed" op of /mob): diving, climbing, swimming or flying from `start` to `destination`.
/mob/proc/zmove_time(datum/act/op/A)
	return A.arg("duration")

/// A timed z-move cancelled: the mob says so.
/mob/proc/zmove_timed_interrupted(datum/act/op/A)
	to_chat(src, A.arg("fail_message"))

/// A timed z-move completed: move.
/mob/proc/zmove_timed_done(datum/act/op/A)
	if(A.arg("needs_flight"))
		var/mob/living/H = src
		if(!istype(H) || !H.flying) // Flying up: the mob must still be flying at the end.
			to_chat(src, span_warning("You stopped flying upwards."))
			return
	to_chat(src, span_notice(A.arg("done_message")))
	var/direction = A.arg("direction")
	if(zmove_finish(direction, A.arg("start"), A.arg("destination")))
		to_chat(src, span_notice(direction == UP ? "You move upwards." : "You move down."))

/// The end of a z-move: blockers at the destination, then the move and whatever is pulled along.
/mob/proc/zmove_finish(direction, turf/start, turf/destination)
	for(var/atom/A in turf_contents_of_type(destination, /atom))
		if(!A.CanPass(src, start, 1.5, 0))
			to_chat(src, span_warning("\The [A] blocks you."))
			return 0
	if(!Move(destination))
		return 0
	if(isliving(src))
		var/list/atom/movable/pulling = list()
		var/mob/living/L = src
		var/atom/movable/L_pulling = L?.pulling_target()
		if(L_pulling && !L_pulling.anchored)
			pulling |= L_pulling
		for(var/obj/item/grab/G in list(L.get_equipped_item(SLOT_ID_HAND_L), L.get_equipped_item(SLOT_ID_HAND_R)))
			pulling |= G?.grab_target()
		if(direction == UP)
			audible_message(span_notice("[src] moves up."))
		else if(direction == DOWN)
			audible_message(span_notice("[src] moves down."))
		for(var/atom/movable/P in pulling)
			P.forceMove(destination)
	return 1

/mob/proc/can_overcome_gravity()
	return FALSE

/mob/living/can_overcome_gravity()
	return dq_get_hovering(src)

/mob/living/carbon/human/can_overcome_gravity()
	. = ..()
	if(!.)
		return species && species.can_overcome_gravity(src)

/mob/observer/zMove(direction)
	var/turf/destination = (direction == UP) ? GetAbove(src) : GetBelow(src)
	if(destination)
		forceMove(destination)
	else
		to_chat(src, span_notice("There is nothing of interest in this direction."))

/mob/observer/eye/zMove(direction)
	var/turf/destination = (direction == UP) ? GetAbove(src) : GetBelow(src)
	if(destination)
		setLoc(destination)
	else
		to_chat(src, span_notice("There is nothing of interest in this direction."))

/mob/proc/can_ztravel()
	return 0

/mob/living/zMove(direction)
	// ZAS zpipes and ventcrawling deleted with the LINDA migration.
	// LINDA's vent equivalents (vendored under code/atmospherics/
	// machinery/) need their own multiz traversal hook wired in.
	return ..()

/mob/observer/can_ztravel()
	return TRUE

/mob/living/can_ztravel()
	if(incapacitated())
		return FALSE
	return (dq_get_hovering(src) || is_incorporeal())

/mob/living/simple_mob/can_ztravel()
	if(incapacitated())
		return FALSE

	if(dq_get_hovering(src) || is_incorporeal())
		return TRUE

	if(Process_Spacemove())
		return TRUE

	if(has_hands)
		return TRUE

/mob/living/carbon/human/can_ztravel()
	if(incapacitated())
		return FALSE

	if(dq_get_hovering(src) || is_incorporeal())
		return TRUE

	if(flying) // . Allows movement up/down with wings.
		return TRUE

	if(Process_Spacemove())
		return TRUE

	if(Check_Shoegrip())	//scaling hull with magboots
		for(var/turf/simulated/T in trange(1,src))
			if(T.density)
				return TRUE

/mob/living/silicon/robot/can_ztravel()
	if(incapacitated() || is_dead())
		return FALSE

	if(dq_get_hovering(src))
		return TRUE

	if(Process_Spacemove()) //Checks for active jetpack
		return TRUE

	for(var/turf/simulated/T in trange(1,src)) //Robots get "magboots"
		if(T.density)
			return TRUE

/mob/living/silicon/pai/can_ztravel()
	if(incapacitated())
		return FALSE

	if(Process_Spacemove())
		return TRUE

	if(!restrained())
		return TRUE

// TODO - Leshana Experimental

//Execution by grand piano!
/atom/movable/proc/get_fall_damage()
	return 42

//If atom stands under open space, it can prevent fall, or not
/atom/proc/can_prevent_fall(atom/movable/mover, turf/coming_from)
	return (!CanPass(mover, coming_from))

////////////////////////////



//FALLING STUFF

//Holds fall checks that should not be overriden by children
/atom/movable/proc/fall()
	if(!isturf(loc))
		return

	var/turf/below = GetBelow(src)
	if(!below)
		return

	if(isspace(below))
		return

	var/turf/T = loc

	if(isdiveablewater(T))
		return

	if(!T.CanZPass(src, DOWN) || !below.CanZPass(src, DOWN))
		return

	// No gravity in space, apparently.
	var/area/area = get_area(src)
	if(!area.get_gravity())
		return

	if(throwing)
		return
	// . Flight on mobs.
	if(isliving(src))
		var/mob/living/L = src // . Flight on mobs.
		if(L.flying) //Some other checks are done in the wings_toggle proc
			if(L.nutrition > 0.5)
				L.adjust_nutrition(-0.5) //You use up -0.5 nutrition per TILE and tick of flying above open spaces. If people wanna flap their wings in the hallways, shouldn't penalize them for it.
			if(L.incapacitated(INCAPACITATION_ALL))
				L.stop_flying()
				//Just here to see if the person is KO'd, stunned, etc. If so, it'll move onto can_fall.
			else if(L.nutrition < 300 && L.nutrition > 299.4) //290 would be risky, as metabolism could mess it up. Let's do 289.
				to_chat(L, span_danger("You are starting to get fatigued... You probably have a good minute left in the air, if that. Even less if you continue to fly around! You should get to the ground soon!")) //Ticks are, on average, 3 seconds. So this would most likely be 90 seconds, but lets just say 60.
				L.adjust_nutrition(-0.5)
				return
			else if(L.nutrition < 100 && L.nutrition > 99.4)
				to_chat(L, span_danger("You're seriously fatigued! You need to get to the ground immediately and eat before you fall!"))
				return
			else if(L.nutrition < 10) //Should have listened to the warnings!
				to_chat(L, span_danger("You lack the strength to keep yourself up in the air..."))
				L.stop_flying()
			else
				return
		if(LAZYLEN(L?.grabbed_by_list())) //If you're grabbed (presumably by someone flying) let's not have you fall. This also allows people to grab onto you while you jump over a railing to prevent you from falling!
			return

	if(can_fall() && can_fall_to(below))
		// We spawn here to let the current move operation complete before we start falling. fall() is normally called from
		// Entered() which is part of Move(), by spawn()ing we let that complete.  But we want to preserve if we were in client movement
		// or normal movement so other move behavior can continue.
		var/mob/M = src
		var/is_client_moving = (ismob(M) && M.client && M.client.moving)
		if(is_client_moving) M.client.moving = 1
		handle_fall(below)
		if(is_client_moving) M.client.moving = 0
		// TODO - handle fall on damage!

//For children to override
/atom/movable/proc/can_fall()
	if(anchored)
		return FALSE
	return TRUE

/obj/effect/can_fall()
	return FALSE

/obj/effect/decal/cleanable/can_fall()
	return TRUE

// These didn't fall anyways but better to nip this now just incase.
/atom/movable/lighting_overlay/can_fall()
	return FALSE

// Mechas are anchored, so we need to override.
/obj/mecha/can_fall()
	return TRUE

// VOREstation edit - Falling vehicles.
/obj/vehicle/can_fall()
	return TRUE
// VOREstation edit end

/obj/item/pipe/can_fall()
	. = ..()

	if(anchored)
		return FALSE

	var/turf/below = GetBelow(src)
	// zpipe type deleted; only check disposal pipes for now.
	if(locate_on(below, /obj/structure/disposalpipe/up))
		return FALSE

/mob/living/can_fall()
	if(is_incorporeal())
		return FALSE
	if(dq_get_hovering(src))
		return FALSE
	return ..()

/mob/living/carbon/human/can_fall()
	if(..())
		return species?.can_fall(src)

// Another check that we probably can just merge into can_fall exept for messing up overrides
/atom/movable/proc/can_fall_to(turf/landing)
	// Check if there is anything in our turf we are standing on to prevent falling.
	for(var/obj/O in contents_of(loc))
		if(!O.CanFallThru(src, landing))
			return FALSE
	// See if something in turf below prevents us from falling into it.
	for(var/atom/A in turf_contents_of_type(landing, /atom))
		if(ismob(A))
			continue
		if(!A.CanPass(src, loc, 1, 0))
			return FALSE
	return TRUE

// Check if this atom prevents things standing on it from falling. Return TRUE to allow the fall.
/obj/proc/CanFallThru(atom/movable/mover as mob|obj, turf/target as turf)
	if(!isturf(mover.loc)) // EDIT. We clearly didn't have enough backup checks.
		return FALSE //If this ain't working Ima be pissed.
	return TRUE

// Things that prevent objects standing on them from falling into turf below
/obj/structure/catwalk/CanFallThru(atom/movable/mover as mob|obj, turf/target as turf)
	if((target.z < z) && !hatch_open)
		return FALSE // TODO - Technically should be density = TRUE and flags |= ON_BORDER
	if(!isturf(mover.loc))
		return FALSE // Only let loose floor items fall. No more snatching things off people's hands.
	else
		return TRUE

// So you'll slam when falling onto a catwalk
/obj/structure/catwalk/CheckFall(atom/movable/falling_atom)
	return falling_atom.fall_impact(src)

/obj/structure/lattice/CanFallThru(atom/movable/mover as mob|obj, turf/target as turf)
	if(target.z >= z)
		return TRUE // We don't block sideways or upward movement.
	else if(istype(mover) && mover.checkpass(PASSGRILLE))
		return TRUE // Anything small enough to pass a grille will pass a lattice
	if(!isturf(mover.loc))
		return FALSE // Only let loose floor items fall. No more snatching things off people's hands.
	else
		return FALSE // TODO - Technically should be density = TRUE and flags |= ON_BORDER

// So you'll slam when falling onto a grille
/obj/structure/lattice/CheckFall(atom/movable/falling_atom)
	if(istype(falling_atom) && falling_atom.checkpass(PASSGRILLE))
		return FALSE
	return falling_atom.fall_impact(src)

// Actually process the falling movement and impacts.
/atom/movable/proc/handle_fall(turf/landing)
	var/turf/oldloc = loc

	// Now lets move there!
	if(!Move(landing, direct = dir)) //infinite fall fix
		return 1

	// Detect if we made a silent landing.
	var/atom/A = find_fall_target(oldloc, landing)
	if(special_fall_handle(A) || !A || !A.check_impact(src))
		return
	fall_impact(A)

/atom/movable/proc/special_fall_handle(atom/A)
	return FALSE

/mob/living/carbon/human/special_fall_handle(atom/A)
	if(species)
		return species.fall_impact_special(src, A)
	return FALSE

/atom/movable/proc/find_fall_target(turf/oldloc, turf/landing)
	if(isopenspace(oldloc))
		oldloc.visible_message(span_notice("\The [src] falls down through \the [oldloc]!"), span_notice("You hear something falling through the air."))

	// If the turf has density, we give it first dibs
	if (landing.density && landing.CheckFall(src))
		return landing

	// First hit objects in the turf!
	for(var/atom/movable/A in turf_contents_of_type(landing, /atom/movable))
		if(A != src && A.CheckFall(src))
			return A

	// If none of them stopped us, then hit the turf itself
	if(landing.CheckFall(src))
		return landing

/mob/living/carbon/human/find_fall_target(turf/landing)
	if(species)
		var/atom/A = species.find_fall_target_special(src, landing)
		if(A)
			return A
	return ..()

//CheckFall landing.fall_impact(src)

// ## THE FALLING PROCS ###

// Called on everything that falling_atom might hit. Return TRUE if you're handling it so find_fall_target() will stop checking.
/atom/proc/CheckFall(atom/movable/falling_atom)
	if(density && !(flags & ON_BORDER))
		return TRUE

// If you are hit: how is it handled.
// Return TRUE if the generic fall_impact should be called
// Return FALSE if you handled it yourself or if there's no effect from hitting you
/atom/proc/check_impact(atom/movable/falling_atom)
	if(density && !(flags & ON_BORDER))
		return TRUE

// By default all turfs are gonna let you hit them regardless of density.
/turf/CheckFall(atom/movable/falling_atom)
	return TRUE

/turf/check_impact(atom/movable/falling_atom)
	return TRUE

// Obviously you can't really hit open space.
/turf/simulated/open/CheckFall(atom/movable/falling_atom)
	return FALSE

/turf/simulated/open/check_impact(atom/movable/falling_atom)
	return FALSE

// Or actual space.
/turf/space/CheckFall(atom/movable/falling_atom)
	return FALSE

/turf/space/check_impact(atom/movable/falling_atom)
	return FALSE

// Can't fall onto ghosts
/mob/observer/dead/CheckFall()
	return FALSE

/mob/observer/dead/check_impact()
	return FALSE


// Called by CheckFall when we actually hit something. Various Vars will be described below
// hit_atom is the thing we fall on
// damage_min is the smallest amount of damage a thing (currently only mobs and mechs) will take from falling
// damage_max is the largest amount of damage a thing (currently only mobs and mechs) will take from falling.
// If silent is True, the proc won't play sound or give a message.
// If planetary is True, it's harder to stop the fall damage

/atom/movable/proc/fall_impact(atom/hit_atom, damage_min = 0, damage_max = 10, silent = FALSE, planetary = FALSE)
	if(!silent)
		visible_message("\The [src] falls from above and slams into \the [hit_atom]!", "You hear something slam into \the [hit_atom].")
	for(var/atom/movable/A in contents_of(src))
		A.fall_impact(hit_atom, damage_min, damage_max, silent = TRUE)

// Take damage from falling and hitting the ground
/mob/living/fall_impact(atom/hit_atom, damage_min = 0, damage_max = 5, silent = FALSE, planetary = FALSE)
	var/turf/landing = get_turf(hit_atom)
	var/safe_fall = FALSE
	if(dq_get_softfall(src) || (isanimal(src) && src.mob_size <= MOB_SMALL))
		safe_fall = TRUE
	if(planetary && src.CanParachute())
		if(!silent)
			act_message(src, landing, MSG_SELF(span_danger("You land on %T%!")), \
				MSG_OTHERS(span_warning("%U% glides in from above and lands on %T%!")), \
				MSG_BLIND("You hear something land %T%."))
		return
	else if(!planetary && safe_fall) // Falling one floor and falling one atmosphere are very different things
		if(!silent)
			act_message(src, landing, MSG_SELF(span_danger("You land on %T%!")), \
				MSG_OTHERS(span_warning("%U% falls from above and lands on %T%!")), \
				MSG_BLIND("You hear something land %T%."))
		return
	else
		if(!silent)
			if(planetary)
				act_message(src, landing, MSG_SELF(span_danger(span_large(" You fall out of the sky and crash into %T%!"))), \
					MSG_OTHERS(span_danger(span_large("%U% falls out of the sky and crashes into %T%!"))), \
					MSG_BLIND("You hear something slam into %T%."))
				var/turf/T = get_turf(landing)
				explosion(T, 0, 1, 2)
			else
				act_message(src, landing, MSG_SELF(span_danger("You fall off and hit %T%!")), \
					MSG_OTHERS(span_warning("%U% falls from above and slams into %T%!")), \
					MSG_BLIND("You hear something slam into %T%."))
			if(has_trait(src, TRAIT_HEAVY_LANDING))
				play_sfx(src, SFX_EFFECTS_METEORIMPACT, volume = 75, extrarange = 3)
			else
				play_sfx(src, SFX_PUNCH, 0.5, extrarange = -1)

		// Because wounds heal rather quickly, 10 (the default for this proc) should be enough to discourage jumping off but not be enough to ruin you, at least for the first time.
		// Hits 10 times, because apparently targeting individual limbs lets certain species survive the fall from atmosphere
		if(has_trait(src, TRAIT_HEAVY_LANDING))
			for(var/i = 1 to 10)
				injure(INJURY_BLUNT, rand((damage_min * 2), (damage_max * 2)), ran_zone(), landing)
			status_at_least(STAT_WEAKENED, 20)
			if(istype(landing, /turf/simulated/floor) && prob(50))
				var/turf/simulated/floor/our_crash = landing
				our_crash.break_tile()
		else
			for(var/i = 1 to 10)
				injure(INJURY_BLUNT, rand(damage_min, damage_max), ran_zone(), landing)
			status_at_least(STAT_WEAKENED, 4)
	// There is really no situation where smacking into a floor and possibly dying horribly would NOT result in you dropping your remote view... It's also safer then assuming they should persist.
	reset_perspective()

/mob/living/carbon/human/fall_impact(atom/hit_atom, damage_min, damage_max, silent, planetary)
	if(!species?.handle_falling(src, hit_atom, damage_min, damage_max, silent, planetary))
		..()
		if(weight > 325 || size_multiplier > 1.75)
			explosion(get_turf(hit_atom), -1, 0, 0)
			var/turf/simulated/floor/hit_turf = get_turf(hit_atom)
			if(istype(hit_turf))
				hit_turf.break_tile()
//Using /atom/movable instead of /obj/item because I'm not sure what all humans can pick up or wear
// dq_get_parachute(src), dq_get_hovering(src), dq_get_softfall(src), dq_get_parachuting(src) live in code/datums/sparse_vars/movable_misc.dm

/atom/movable/proc/isParachute()
	return dq_get_parachute(src)

//This is what makes the dq_get_parachute(src) items know they've been used.
//I made it /atom/movable so it can be retooled for other things (mobs, mechs, etc), though it's only currently called in human/CanParachute().
/atom/movable/proc/handleParachute()
	return

//Checks if the thing is allowed to survive a fall from space
/atom/movable/proc/CanParachute()
	return dq_get_parachuting(src)

//For humans, this needs to be a wee bit more complicated
/mob/living/carbon/human/CanParachute()
	//Certain slots don't really need to be checked for dq_get_parachute(src) ability, i.e. pockets, ears, etc. If this changes, just add them to the loop, I guess?
	//This is done in Priority Order, so items lower down the list don't call handleParachute() unless they're actually used.
	if(get_equipped_item(SLOT_ID_BACK) && get_equipped_item(SLOT_ID_BACK).isParachute())
		get_equipped_item(SLOT_ID_BACK).handleParachute()
		return TRUE
	if(get_equipped_item(SLOT_ID_SUIT_STORAGE) && get_equipped_item(SLOT_ID_SUIT_STORAGE).isParachute())
		get_equipped_item(SLOT_ID_SUIT_STORAGE).handleParachute()
		return TRUE
	if(get_equipped_item(SLOT_ID_BELT) && get_equipped_item(SLOT_ID_BELT).isParachute())
		get_equipped_item(SLOT_ID_BELT).handleParachute()
		return TRUE
	if(get_equipped_item(SLOT_ID_SUIT) && get_equipped_item(SLOT_ID_SUIT).isParachute())
		get_equipped_item(SLOT_ID_SUIT).handleParachute()
		return TRUE
	if(get_equipped_item(SLOT_ID_UNIFORM) && get_equipped_item(SLOT_ID_UNIFORM).isParachute())
		get_equipped_item(SLOT_ID_UNIFORM).handleParachute()
		return TRUE
	else
		return dq_get_parachuting(src)

//Mech Code
/obj/mecha/handle_fall(turf/landing)
	// First things first, break any lattice
	var/obj/structure/lattice/lattice = locate(/obj/structure/lattice, loc)
	if(lattice)
		// Lattices seem a bit too flimsy to hold up a massive exosuit.
		lattice.visible_message(span_danger("\The [lattice] collapses under the weight of \the [src]!"))
		destroyed(lattice, src, BRUTE)

	// Then call parent to have us actually fall
	return ..()

/obj/mecha/fall_impact(atom/hit_atom, damage_min = 15, damage_max = 30, silent = FALSE, planetary = FALSE)
	// Anything on the same tile as the landing tile is gonna have a bad day.
	for(var/mob/living/L in contents_of(hit_atom))
		act_message(src, L, others = span_danger("%U% crushes %T% as it lands on them!"))
		L.injure(INJURY_BLUNT, rand(70, 100), null, src)
		L.status_at_least(STAT_WEAKENED, 8)

	var/turf/landing = get_turf(hit_atom)

	if(planetary && src.CanParachute())
		if(!silent)
			visible_message(span_warning("\The [src] glides in from above and lands on \the [landing]!"), \
				span_danger("You land on \the [landing]!"), \
				"You hear something land \the [landing].")
		return
	else if(!planetary && dq_get_softfall(src)) // Falling one floor and falling one atmosphere are very different things
		if(!silent)
			visible_message(span_warning("\The [src] falls from above and lands on \the [landing]!"), \
				span_danger("You land on \the [landing]!"), \
				"You hear something land \the [landing].")
		return
	else
		if(!silent)
			if(planetary)
				visible_message(span_danger(span_large("\A [src] falls out of the sky and crashes into \the [landing]!")), \
					span_danger(span_large(" You fall out of the skiy and crash into \the [landing]!")), \
					"You hear something slam into \the [landing].")
				var/turf/T = get_turf(landing)
				explosion(T, 0, 1, 2)
			else
				visible_message(span_warning("\The [src] falls from above and slams into \the [landing]!"), \
					span_danger("You fall off and hit \the [landing]!"), \
					"You hear something slam into \the [landing].")
			play_sfx(src, SFX_PUNCH, 0.5, extrarange = -1)

	// And now to hurt the mech.
	if(!planetary)
		take_damage(rand(damage_min, damage_max))
	else
		for(var/atom/movable/A in contents_of(src))
			A.fall_impact(hit_atom, damage_min, damage_max, silent = TRUE)
		destroyed(src, null, BRUTE)

	// And hurt the floor.
	if(istype(hit_atom, /turf/simulated/floor))
		var/turf/simulated/floor/ground = hit_atom
		ground.break_tile()


// === merged from movement_vr.dm during hard-fork de-suffix (verified no override-order change) ===

/mob/living/handle_fall(turf/landing)
	var/mob/living/drop_mob = locate(/mob/living, landing)

	if(locate_on(landing, /obj/structure/stairs))
		for(var/atom/A in turf_contents_of_type(landing, /atom))
			if(!A.CanPass(src, src.loc))
				return FALSE
		Move(landing)
		if(isliving(src))
			var/mob/living/L = src
			var/atom/movable/L_pulling = L?.pulling_target()
			if(L_pulling)
				L_pulling.forceMove(landing)
		return TRUE

	for(var/obj/O in contents_of(loc))
		if(!O.CanFallThru(src, landing))
			return TRUE

	if(guard(src, GUARD_FALL, drop_mob, null, landing))
		return

	if(drop_mob && drop_mob != src)
		///Varible to tell if we take damage or not for falling.
		var/safe_fall = FALSE
		if(dq_get_softfall(drop_mob) || (isanimal(drop_mob) && drop_mob.mob_size <= MOB_SMALL))
			safe_fall = TRUE

		if(ishuman(drop_mob))
			var/mob/living/carbon/human/H = drop_mob
			if(H.species.soft_landing)
				safe_fall = TRUE

		forceMove(get_turf(drop_mob))
		if(!safe_fall)
			drop_mob.status_at_least(STAT_WEAKENED, 8)
			status_at_least(STAT_WEAKENED, 8)
			play_sfx(src, SFX_PUNCH, 0.5, extrarange = -1)
			var/tdamage
			for(var/i = 1 to 5)	//Twice as less damage because cushioned fall, but both get damaged.
				tdamage = rand(0, 5)
				if(has_trait(drop_mob, TRAIT_HEAVY_LANDING))
					tdamage = tdamage * 1.5
				drop_mob.injure(INJURY_BLUNT, tdamage, ran_zone(), src)
				injure(INJURY_BLUNT, tdamage, ran_zone(), drop_mob)
			if(has_trait(drop_mob, TRAIT_HEAVY_LANDING))
				act_message(drop_mob, src, others = span_danger("%U% crashes down onto %T%!"))
			else
				act_message(drop_mob, src, others = span_danger("%U% falls onto %T%!"))
		else
			act_message(drop_mob, src, others = span_notice("%U% safely brushes past %T% as they land."))

	// Then call parent to have us actually fall
	return ..()
/mob/CheckFall(atom/movable/falling_atom)
	return falling_atom.fall_impact(src)

/mob/proc/CanZPass(atom/A, direction)
	if(z == A.z) //moving FROM this turf
		return direction == UP //can't go below
	else
		if(direction == UP) //on a turf below, trying to enter
			return 0
		if(direction == DOWN) //on a turf above, trying to enter
			return 1

/turf/simulated/proc/climb_wall()
	set name = "Climb Wall"
	set desc = "Using nature's gifts or technology, scale that wall!"
	set category = VERB_CAT_OBJECT
	set src in oview(1)

	if(!isliving(usr)) return	//Why would ghosts want to climb?
	var/mob/living/L = usr
	var/climbing_delay_min = L.climbing_delay
	var/fall_chance = 0
	var/drop_our_held = FALSE
	var/nutrition_cost = 50 //Climbing up is harder!

	//Checking if there's any point trying to climb
	var/turf/above_wall = GetAbove(src)
	if(L.nutrition <= nutrition_cost)
		to_chat(L, span_warning("You [HAS_SYNTHETIC_BIOLOGY(L) ? "lack the energy" : "are too hungry"] for such strenous activities!"))
		return
	if(!above_wall) //No multiZ
		to_chat(L, span_notice("There's nothing interesting over this cliff!"))
		return
	var/turf/above_mob = GetAbove(L)	//Making sure we got headroom
	if(!above_mob.CanZPass(L, UP))
		to_chat(L, span_warning("\The [above_mob] blocks your way."))
		return
	if(above_wall.density) //We check density rather than type since some walls dont have a floor on top.
		to_chat(L, span_warning("\The [above_wall] blocks your way."))
		return
	if(LAZYLEN(above_wall.contents) > 30) //We avoid checking the contents if it's too cluttered to avoid issues
		to_chat(L, span_warning("\The [above_wall] is too cluttered to climb onto!"))
		return
	for(var/atom/A in turf_contents_of_type(above_wall, /atom))
		if(A.density)
			to_chat(L, span_warning("\The [A.name] blocks your way!"))
			return

	//human mobs got species and can wear special equipment
	//We give them some snowflake treatment as a consequence
	if(ishuman(L))
		var/permit_human = FALSE
		var/mob/living/carbon/human/H = L
		if(H.species.climbing_delay < H.climbing_delay)
			climbing_delay_min = H.species.climbing_delay
		var/list/gear = list(H.get_equipped_item(SLOT_ID_HEAD), H.get_equipped_item(SLOT_ID_MASK), H.get_equipped_item(SLOT_ID_SUIT), H.get_equipped_item(SLOT_ID_UNIFORM),
		H.get_equipped_item(SLOT_ID_GLOVES), H.get_equipped_item(SLOT_ID_SHOES), H.get_equipped_item(SLOT_ID_BELT), H.get_active_hand(), H.get_inactive_hand())
		if(H.can_climb || H.species.can_climb)
			permit_human = TRUE
		for(var/obj/item/I in gear)
			if(I.rock_climbing)
				permit_human = TRUE
				if(I.climbing_delay > climbing_delay_min)
					climbing_delay_min = I.climbing_delay //We get the maximum possible speedup out of worn equipment
		if(!permit_human)
			var/sure = rerun_ask(H, "k824", PROC_REF(climb_wall), args, /datum/prompt/choice, question = "Are you sure you want to try without tools? It's VERY LIKELY you will fall and get hurt. More agile species might have better luck", title = "Second Thoughts", choices = list("Bring it!", "Stay grounded"), buttons = TRUE)
			if(isnull(sure))
				return
			if(!sure || sure == "Stay grounded") return
			fall_chance = clamp(100 - H.species.agility, 40, 90) //This should be 80 for most species. Traceur would reduce to 10%, so clamping higher
	//If not a human mob, must be simple or silicon. They got a var stored on their mob we can check
	else if(!L.can_climb)
		var/sure = rerun_ask(L, "k829", PROC_REF(climb_wall), args, /datum/prompt/choice, question = "Are you sure you want to try without tools? It's VERY LIKELY you will fall and get hurt. More agile species might have better luck", title = "Second Thoughts", choices = list("Bring it!", "Stay grounded"), buttons = TRUE)
		if(isnull(sure))
			return
		if(!sure || sure == "Stay grounded") return
		if(isrobot(L))
			fall_chance = 80 // Robots get no mercy
		else
			fall_chance = 55  //Simple mobs do.
		climbing_delay_min = 2
	//Catslugs are a snowflake case because of references.
	if(istype(L, /mob/living/simple_mob/vore/alienanimals/catslug))
		var/obj/O = L.get_active_hand()
		if(istype(O, /obj/item/material/twohanded/spear))
			var/choice = rerun_ask(L, "k840", PROC_REF(climb_wall), args, /datum/prompt/choice, question = "Use your spear to climb faster? This will drop and break it!", title = "Scug Tactics", choices = list("Yes!", "No"), buttons = TRUE)
			if(isnull(choice))
				return
			if(choice == "Yes!")
				drop_our_held = TRUE
				climbing_delay_min = 0.75

	//We proceed with the actual climbing!
	// ################### CLIMB TIME BELOW: #############################
	// Climb time is 3.75 for scugs with spears (spear is dropped)
	// Climb time is 5 for Master climbers, Vassilians, Well-geared humans
	// Climb time is 9 for Tajara and Professional Climbers
	// Climb time is 17.5 Seconds for amateur climbers
	// Climb time is 20 seconds for scugs without a spear
	// Climb time is 30 for gearless untrained people
	var/climb_time = (5 * climbing_delay_min) SECONDS
	if(fall_chance)
		to_chat(L, span_warning("You begin climbing over \The [src]. Getting a grip is exceedingly difficult..."))
		climb_time += 20 SECONDS
	else
		to_chat(L, span_notice("You begin climbing above \The [src]! "))
		if(climbing_delay_min > 1.25)
			climb_time += 10 SECONDS
		if(climbing_delay_min > 1.0)
			climb_time += 2.5 SECONDS

	if(L.nutrition >= 100 && L.nutrition <= 200)
		to_chat(L, span_notice("Climbing while [HAS_SYNTHETIC_BIOLOGY(L) ? "low on power" : "hungry"] slows you down"))
		climb_time += 1 SECONDS
	else if(L.nutrition >= nutrition_cost && L.nutrition < 100)
		to_chat(L, span_danger("You [HAS_SYNTHETIC_BIOLOGY(L) ? "lack enough power" : "are too hungry"] to climb safely!"))
		climb_time +=3 SECONDS
		if(fall_chance < 30)
			fall_chance = 30
	act_message(L, src, others = span_infoplain(span_bold("%U%") + " begins to climb up on " + span_bold("%T%")), self = span_infoplain("You begin to clumb up on " + span_bold("%T%")), \
		blind = span_infoplain("You hear the sounds of climbing!"), runemessage = "Tap Tap")
	var/grace_time = 4 SECONDS
	to_chat(L, span_warning("If you get interrupted after [(grace_time / (1 SECOND))] seconds of climbing, you will fall and hurt yourself, beware!"))
	perform_op(L, src, "climb_wall", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("duration" = climb_time, "above_mob" = above_mob, "above_wall" = above_wall, "fall_chance" = fall_chance, "drop_our_held" = drop_our_held, "nutrition_cost" = nutrition_cost, "fall_at" = EXPIRY_AT(null, CLOCK_WORLD, 0) + grace_time))

/turf/simulated/proc/climb_wall_time(datum/act/op/A)
	return A.arg("duration")

/turf/simulated/proc/climb_wall_done(datum/act/op/A)
	var/mob/living/L = A.actor
	var/turf/above_mob = A.arg("above_mob")
	var/turf/above_wall = A.arg("above_wall")
	var/fall_chance = A.arg("fall_chance")
	var/drop_our_held = A.arg("drop_our_held")
	var/nutrition_cost = A.arg("nutrition_cost")
	if(prob(fall_chance))
		L.forceMove(above_mob)
		act_message(L, src, others = span_infoplain(span_bold("%U%") + " falls off " + span_bold("%T%")), self = span_danger("You slipped off " + span_bold("%T%")), \
			blind = span_infoplain("you hear a loud thud!"), runemessage = "CRASH!")
	else
		if(drop_our_held)
			L.drop_item(get_turf(L))
		L.forceMove(above_wall)
		act_message(L, src, others = span_infoplain(span_bold("%U%") + " climbed up on " + span_bold("%T%")),	\
			self = span_notice("You successfully scaled " + span_bold("%T%")),	\
			blind = span_infoplain("The sounds of climbing cease."), runemessage = "Tap Tap")
	L.adjust_nutrition(-nutrition_cost)

/// Interrupted past the grace time: the climber falls.
/turf/simulated/proc/climb_wall_interrupted(datum/act/op/A)
	var/mob/living/L = A.actor
	var/turf/above_mob = A.arg("above_mob")
	var/fall_at = A.arg("fall_at")
	if(!L || ELAPSED_SINCE(src, fall_at, CLOCK_WORLD) <= 0)
		return
	L.forceMove(above_mob)
	act_message(L, src, others = span_infoplain(span_bold("%U%") + " falls off " + span_bold("%T%")), self = span_danger("You slipped off " + span_bold("%T%")), \
		blind = span_infoplain("you hear a loud thud!"), runemessage = "CRASH!")

/mob/living/verb/climb_down()
	set name = "Climb down wall"
	set desc = "attempt to climb down the wall you are standing on, in direction you're looking"
	set category = VERB_CAT_IC_GAME

	var/fall_chance = 0	//Increased if we can't actually climb
	var/turf/our_turf = get_turf(src) //floor we're standing on
	var/climbing_delay_min = src.climbing_delay //We take the lowest climbing delay between mob, species and gear.
	var/nutrition_cost = 25	//Descending is easier!


	//Check if we can even try to climb
	if(nutrition <= nutrition_cost)
		to_chat(src, span_warning("You [HAS_SYNTHETIC_BIOLOGY(src) ? "lack the energy" : "are too hungry"] for such strenous activities!"))
		return
	var/turf/below_wall = GetBelow(our_turf)
	if(!below_wall)	//No multiZ
		to_chat(src, span_notice("There's nothing interesting below us!"))
		return
	if(!istype(below_wall,/turf/simulated)) //Our var is on simulated turfs, we must enforce this
		to_chat(src, span_notice("There's nothing useful to grab onto!"))
		return
	var/turf/simulated/climbing_surface = below_wall
	if(!climbing_surface.density) //passable turfs make no sense to climb
		to_chat(src, span_notice("There's nothing climbable below us!"))
		return
	var/turf/front_of_us = get_step(src, dir) //We get the spot we are facing
	if(!front_of_us.CanZPass(src, DOWN)) //Makes sure where we're climbing isnt blocked by a tile or there's a wall below it.
		to_chat(src, span_notice("\The [front_of_us] blocks your way in this direction!"))
		return
	var/turf/destination = GetBelow(front_of_us)
	if(isopenspace(destination)) //We don't allow descending more than 1 Z at a time
		to_chat(src, span_notice("You're too high up to climb down from here! Find a more gentle descent!"))
		return

	//Determining whether we should be able to climb safely and how fast
	if(ishuman(src))
		var/permit_human = FALSE
		var/mob/living/carbon/human/H = src
		if(H.species.climbing_delay < H.climbing_delay)
			climbing_delay_min = H.species.climbing_delay
		var/list/gear = list(H.get_equipped_item(SLOT_ID_HEAD), H.get_equipped_item(SLOT_ID_MASK), H.get_equipped_item(SLOT_ID_SUIT), H.get_equipped_item(SLOT_ID_UNIFORM),
		H.get_equipped_item(SLOT_ID_GLOVES), H.get_equipped_item(SLOT_ID_SHOES), H.get_equipped_item(SLOT_ID_BELT), H.get_active_hand(), H.get_inactive_hand())
		if(H.can_climb || H.species.can_climb)
			permit_human = TRUE
		for(var/obj/item/I in gear)
			if(I.rock_climbing)
				permit_human = TRUE
				if(I.climbing_delay > climbing_delay_min)
					climbing_delay_min = I.climbing_delay //We get the maximum possible speedup out of worn equipment
		if(!permit_human)
			var/sure = rerun_ask(H, "k951", VERB_REF(climb_down), args, /datum/prompt/choice, question = "Are you sure you want to try without tools? It's VERY LIKELY you will fall and get hurt. More agile species might have better luck", title = "Second Thoughts", choices = list("Bring it!", "Stay grounded"), buttons = TRUE)
			if(isnull(sure))
				return
			if(!sure || sure == "Stay grounded") return
			fall_chance = clamp(100 - H.species.agility, 40, 90) //This should be 80 for most species. Traceur would reduce to 10%, so clamping higher
	//If not a human mob, must be simple or silicon. They got a var stored on their mob we can check
	else if(!src.can_climb)
		var/sure = rerun_ask(src, "k956", VERB_REF(climb_down), args, /datum/prompt/choice, question = "Are you sure you want to try without tools? It's VERY LIKELY you will fall and get hurt. More agile species might have better luck", title = "Second Thoughts", choices = list("Bring it!", "Stay grounded"), buttons = TRUE)
		if(isnull(sure))
			return
		if(!sure || sure == "Stay grounded") return
		if(isrobot(src))
			fall_chance = 80 // Robots get no mercy
		else
			fall_chance = 55  //Simple mobs do.
		climbing_delay_min = 2
	//This time, scugs get no snowflake treatment. We're climbing DOWN, not up!

	//We proceed with the actual climbing!
	// ################### CLIMB TIME BELOW: #############################
	// Climb time is 3.75 for scugs with spears (spear is dropped)
	// Climb time is 5 for Master climbers, Vassilians, Well-geared humans
	// Climb time is 9 for Tajara and Professional Climbers
	// Climb time is 17.5 Seconds for amateur climbers
	// Climb time is 20 seconds for scugs without a spear
	// Climb time is 30 for gearless untrained people
	var/climb_time = (5 * climbing_delay_min) SECONDS
	if(fall_chance)
		to_chat(src, span_warning("You begin climbing down along \The [below_wall]. Getting a grip is exceedingly difficult..."))
		climb_time += 20 SECONDS
	else
		to_chat(src, span_notice("You begin climbing down \The [below_wall]! "))
		if(climbing_delay_min > 1.25)
			climb_time += 10 SECONDS
		if(climbing_delay_min > 1.0)
			climb_time += 2.5 SECONDS
	if(nutrition >= 100 && nutrition <= 200)
		to_chat(src, span_notice("Climbing while [HAS_SYNTHETIC_BIOLOGY(src) ? "low on power" : "hungry"] slows you down"))
		climb_time += 1 SECONDS
	else if(nutrition >= nutrition_cost && nutrition < 100)
		to_chat(src, span_danger("You [HAS_SYNTHETIC_BIOLOGY(src) ? "lack enough power" : "are too hungry"] to climb safely!"))
		climb_time +=3 SECONDS
		if(fall_chance < 30)
			fall_chance = 30

	if(!climbing_surface.climbable)
		to_chat(src, span_danger("\The [climbing_surface] is not suitable for climbing! Even for a master climber, this is risky!"))
		if(fall_chance < 75 )
			fall_chance = 75
	act_message(src, below_wall, others = span_infoplain(span_bold("%U%") + " climb down " + span_bold("%T%")),	\
		self = span_infoplain("You begin to descend " + span_bold("%T%")), 	\
		blind = span_infoplain("You hear the sounds of climbing!"), runemessage = "Tap Tap")
	below_wall.audible_message(message = span_infoplain("You hear something climbing up " + span_bold("\The [below_wall]")), runemessage= "Tap Tap")
	var/grace_time = 3 SECONDS
	to_chat(src, span_warning("If you get interrupted after [(grace_time / (1 SECOND))] seconds of climbing, you will fall and hurt yourself, beware!"))
	perform_op(src, src, "climb_down", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("duration" = climb_time, "front_of_us" = front_of_us, "destination" = destination, "below_wall" = below_wall, "fall_chance" = fall_chance, "nutrition_cost" = nutrition_cost, "fall_at" = EXPIRY_AT(null, CLOCK_WORLD, 0) + grace_time))

/// The climb takes as long as the climber's skill and gear say (read once, when the climb starts).
/mob/living/proc/climb_down_time(datum/act/op/A)
	return A.arg("duration")

/mob/living/proc/climb_down_done(datum/act/op/A)
	var/turf/front_of_us = A.arg("front_of_us")
	var/turf/destination = A.arg("destination")
	var/turf/below_wall = A.arg("below_wall")
	var/fall_chance = A.arg("fall_chance")
	var/nutrition_cost = A.arg("nutrition_cost")
	if(prob(fall_chance))
		src.forceMove(front_of_us)
		act_message(src, below_wall, others = span_infoplain(span_bold("%U%") + " falls off " + span_bold("%T%")), \
			self = span_danger("You slipped off " + span_bold("%T%")), \
			blind = span_infoplain("you hear a loud thud!"), runemessage = "CRASH!")
	else
		src.forceMove(destination)
		act_message(src, below_wall, others = span_infoplain(span_bold("%U%") + " climbed down on " + span_bold("%T%")),	\
			self = span_notice("You successfully descended " + span_bold("%T%")),	\
			blind = span_infoplain("The sounds of climbing cease."), runemessage = "Tap Tap")
	adjust_nutrition(-nutrition_cost)
	return OP_OK

/// Interrupted past the grace time: the climber falls.
/mob/living/proc/climb_down_interrupted(datum/act/op/A)
	var/turf/front_of_us = A.arg("front_of_us")
	var/turf/below_wall = A.arg("below_wall")
	var/fall_at = A.arg("fall_at")
	if(ELAPSED_SINCE(src, fall_at, CLOCK_WORLD) <= 0)
		return OP_OK
	src.forceMove(front_of_us)
	act_message(src, below_wall, others = span_infoplain(span_bold("%U%") + " falls off " + span_bold("%T%")), \
		self = span_danger("You slipped off " + span_bold("%T%")), \
		blind = span_infoplain("you hear a loud thud!"), runemessage = "CRASH!")
