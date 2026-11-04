/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt //Teleporting Cultists


	var/jaunt_warning = 0.5 SECONDS	// How long the jaunt telegraphing is.
	var/jaunt_tile_speed = 20		// How long to wait between each tile. Higher numbers result in an easier to dodge tunnel attack.

// In Theory this Jury Rigged Code form Tunneler Spiders Should Allow Wraiths to Jaunt
	special_attack_min_range = 2
	special_attack_max_range = 6
	special_attack_cooldown = 10 SECONDS

/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt/do_special_attack(atom/A, stance)
	ai_busy_begin()
	// Save where we're gonna go soon.
	var/turf/destination = get_turf(A)
	var/turf/starting_turf = get_turf(src)

	// Telegraph to give a small window to dodge if really close.
	flick("bloodout",A)
	set_icon_state("bloodout")
	after(src, jaunt_warning, PROC_REF(do_special_attack_1), with = list(A, destination, starting_turf), keeps_dead = TRUE) // For the telegraphing.

/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt/proc/do_special_attack_1(atom/A, turf/destination, turf/starting_turf)
	if(!destination || !starting_turf)
		ai_busy_end()
		set_icon_state("bloodin")
		return FALSE

	// Do the dig!
	act_message(src, A, null, MSG_OTHERS(span_danger("%U% sinks into a puddle of blood %T%!")))
	new /obj/effect/decal/cleanable/blood (src.loc)
	if(A)
		flick("blood_out",A)
	set_icon_state("bloodout")

	if(handle_jaunt(destination) == FALSE)
		ai_busy_end()
		if(A)
			flick("bloodin",A)
		set_icon_state("bloodin")
		return FALSE

	// Did we make it?
	if(!(src in destination))
		ai_busy_end()
		set_icon_state("bloodin")
		if(A)
			flick("bloodin",A)
		return FALSE

	var/overshoot = TRUE

	// Test if something is at destination.
	for(var/mob/living/L in turf_contents_of_type(destination, /mob/living))
		if(L == src)
			continue

		act_message(src, L, null, MSG_OTHERS(span_danger("%U% suddenly rises from a pool of blood %T%!")))
		new /obj/effect/decal/cleanable/blood (src.loc)
		play_sfx(L, SFX_WEAPONS_HEAVYSMASH)
		L.apply_body_effect(/datum/body_effect/entangled, 1 SECONDS)
		overshoot = FALSE

	if(!overshoot) // We hit the target, or something, at destination, so we're done.
		ai_busy_end()
		set_icon_state("bloodin")
		if(A)
			flick("bloodin",A)
		return TRUE

	// Otherwise we need to keep going.
	to_chat(src, span_warning("You overshoot your target!"))
	play_sfx(src, SFX_WEAPONS_PUNCHMISS, 3, extrarange = 0)
	var/dir_to_go = get_dir(starting_turf, destination)
	for(var/i = 1 to rand(2, 4))
		destination = get_step(destination, dir_to_go)

	if(handle_jaunt(destination) == FALSE)
		ai_busy_end()
		set_icon_state("bloodin")
		if(A)
			flick("bloodin",A)
		return FALSE

	ai_busy_end()
	set_icon_state("bloodin")
	if(A)
		flick("bloodin",A)
	return FALSE

// Does the jaunt movement
/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt/proc/handle_jaunt(turf/destination)
	var/turf/T = get_turf(src) // Hold our current tile.

	// Regular tunnel loop.
	for(var/i = 1 to get_dist(src, destination))
		if(stat)
			return FALSE // We died or got knocked out on the way.
		if(loc == destination)
			break // We somehow got there early.

		// Update T.
		T = get_step(src, get_dir(src, destination))
		if(T.check_density(ignore_mobs = TRUE))
			to_chat(src, span_critical("You hit something really solid!"))
			play_sfx(src, SFX_PUNCH, 1.5)
			status_at_least(STAT_WEAKENED, 5)
			apply_body_effect(/datum/body_effect/tunneler_vulnerable, 10 SECONDS)
			return FALSE // Hit a wall.

		// Get into the tile.
		forceMove(T)

/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt/should_special_attack(atom/A)
	// Make sure its possible for the wraith to reach the target so it doesn't try to go through a window.
	var/turf/destination = get_turf(A)
	var/turf/starting_turf = get_turf(src)
	var/turf/T = starting_turf
	for(var/i = 1 to get_dist(starting_turf, destination))
		if(T == destination)
			break

		T = get_step(T, get_dir(T, destination))
		if(T.check_density(ignore_mobs = TRUE))
			return FALSE
	return T == destination
