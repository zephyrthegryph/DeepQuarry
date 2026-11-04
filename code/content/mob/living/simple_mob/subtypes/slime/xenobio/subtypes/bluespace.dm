// Tier 3

/mob/living/simple_mob/slime/xenobio/bluespace/get_mechanics_info(list/additional_information)
	return ..(list("This slime will teleport to attack something if it is within a range of seven tiles. The teleport has a cooldown of five seconds.") + additional_information)

/mob/living/simple_mob/slime/xenobio/bluespace
	desc ="Trapping this slime in a cell is generally futile, as it can teleport at will."
	color = null
	slime_color = "bluespace"
	icon_state_override = "bluespace"
	coretype = /obj/item/slime_extract/bluespace
	player_msg = "You can <b>teleport at will</b> to a specific tile by clicking on it at range. This has a five second cooldown."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/bluespace,
			/mob/living/simple_mob/slime/xenobio/bluespace,
			/mob/living/simple_mob/slime/xenobio/yellow,
			/mob/living/simple_mob/slime/xenobio/yellow
		)

	special_attack_min_range = 3
	special_attack_max_range = 7
	special_attack_cooldown = 5 SECONDS

/mob/living/simple_mob/slime/xenobio/bluespace/do_special_attack(atom/A, stance)
	// Teleport attack.
	if(!A)
		to_chat(src, span_warning("There's nothing to teleport to."))
		return FALSE

	var/list/nearby_things = range(1, A)
	var/list/valid_turfs = list()

	// All this work to just go to a non-dense tile.
	for(var/turf/potential_turf in nearby_things)
		var/valid_turf = TRUE
		if(potential_turf.density)
			continue
		for(var/atom/movable/AM in potential_turf)
			if(AM.density)
				valid_turf = FALSE
		if(valid_turf)
			valid_turfs.Add(potential_turf)

	if(!(valid_turfs.len))
		to_chat(src, span_warning("There wasn't an unoccupied spot to teleport to."))
		return FALSE

	var/turf/target_turf = pick(valid_turfs)
	var/turf/T = get_turf(src)



	T.visible_message(span_notice("\The [src] vanishes!"))
	fx_sparks(T, 5)

	forceMove(target_turf)
	play_sfx(target_turf, SFX_EFFECTS_PHASEIN, 0.5)
	to_chat(src, span_notice("You teleport to \the [target_turf]."))

	target_turf.visible_message(span_warning("\The [src] appears!"))
	fx_sparks(target_turf, 5)

	if(Adjacent(A))
		attack_target(A)
