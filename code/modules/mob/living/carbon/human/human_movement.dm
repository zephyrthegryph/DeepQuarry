#define HUMAN_LOWEST_SLOWDOWN -3

/mob/living/carbon/human/movement_delay(oldloc, direct)

	. = 0

	if(living_rules_of(src).force_max_speed)
		return HUMAN_LOWEST_SLOWDOWN

	// Haste: ignore slowdown and move really fast. Calling ..() here adds slowdown.
	if(src.haste)
		return HUMAN_LOWEST_SLOWDOWN

	// Every body factor source at once: species and traits, modifiers,
	// afflictions, reagents (stimulants are negative), form and worn gear.
	. += src.slowdown

	if(istype(loc, /turf/space))
		return ..() - 1

	// Pain slows you down. The body's pain already folds in wounds, agony,
	// species sensitivity and analgesia; ~1.2 pain per point of damage, so
	// this is roughly "percent of the species' health lost". Max 4 slowdown.
	if(species.total_health)
		var/amount_hurt = current_pain() * 100 / (1.2 * species.total_health)
		if(amount_hurt >= 25) //In enough pain for it to be significant?
			. += CLAMP((amount_hurt / 25), 0, 4)

	var/hungry = (500 - nutrition_of(src)) / 5 //Fixed 500 here instead of our huge MAX_NUTRITION
	if(hungry >= 70)
		. += hungry/50

	if(get_feralness() >= 10) //crazy feral animals give less and less of a shit about pain and hunger as they get crazier
		var/species_slowdown = species.baseline_factor(STAT_SLOWDOWN)
		. = max(species_slowdown, species_slowdown+((.-species_slowdown)/(get_feralness()/10))) // As feral scales to damage, this amounts to an effective +1 slowdown cap
		if(shock_stage >= 10)
			. -= CLAMP((shock_stage / 40), 0.25, 1.5) //Feral creatures get halved shock penalty.

	if(riding_datum) //Bit of slowdown for taur rides if rider is bigger or fatter than mount.
		var/datum/riding/R = riding_datum
		var/mob/living/L = R.ridden()
		for(var/mob/living/M in L?.buckled_mob_list())
			if(ishuman(M))
				var/mob/living/carbon/human/H = M
				if(H.size_multiplier > L.size_multiplier)
					. += 1

	if(istype(src?.buckled_to(), /obj/structure/bed/chair/wheelchair))
		for(var/organ_name in list(BP_L_HAND, BP_R_HAND, BP_L_ARM, BP_R_ARM))
			var/obj/item/organ/external/E = get_organ(organ_name)
			if(!E || E.is_stump())
				. += 4
			else if(E.splinted && E.splinted.loc != E)
				. += 0.5
			else if(E.is_fractured())
				. += 1.5
	else
		. += max(2 * stance_damage, 0) //Handles missing feet/legs

	if(shock_stage >= 10)
		. += CLAMP((shock_stage / 20), 0.5, 3) //Slowly become slower the longer you're in traumatic shock. Simulates adrenaline wearing off. Entering soft crit immediately sets shock_stage to 61.

	if(has_mutation(FAT))
		. += 1.5

	if (body_temperature() < species.cold_level_1)
		. += (species.cold_level_1 - body_temperature()) / 10 * 1.75

	// Turf related slowdown
	var/turf/T = get_turf(src)
	. += calculate_turf_slowdown(T, direct)

	// Item related slowdown.
	var/item_tally = src.item_encumbrance

	// Dragging heavy objects will also slow you down, similar to above.
	var/atom/movable/pulling = src?.pulling_target()
	if(pulling)
		if(istype(pulling, /obj/item))
			var/obj/item/pulled = pulling
			item_tally += max(pulled.worn_factor(STAT_ITEM_ENCUMBRANCE), 0)
		else if(ishuman(pulling))
			var/mob/living/carbon/human/H = pulling
			var/their_slowdown = max(H.item_encumbrance, 1)
			item_tally = max(item_tally, their_slowdown) // If our slowdown is less than theirs, then we become as slow as them (before species modifires).

	if(item_tally > 0) //ALT-ENCUMBERANCE
		item_tally *= species.item_slowdown_mod //ALT-ENCUMBERANCE

	. += item_tally

	// Sedatives add to penalties, stimulants cut them (STAT_PENALTY_SCALE).
	if(. > 0)
		. *= src.penalty_scale

	//mRun means we don't get slowdown: axe every penalty, keep speed buffs.
	if(has_mutation(mRun))
		. = min(., 0)

	if(has_trait(src, UNUSUAL_RUNNING) && !get_active_hand() && !get_inactive_hand()) //better not have any items on you mfer
		. -= 0.5 // ok vibe check passed, take this small movement buff and leave

	. = max(HUMAN_LOWEST_SLOWDOWN, . + CONFIG_GET(number/human_delay))	// Minimum return should be the same as force_max_speed
	. += ..()

/mob/living/carbon/human/Moved()
	. = ..()
	if(embedded_flag)
		handle_embedded_objects() //Moving with objects stuck in you can cause bad times.

	if(sparse_get(src, pose) && sparse_get_or(src, pose_move, FALSE)) //clear pose on movement if choosing to
		sparse_set(src, pose, null)
		sparse_set(src, pose_move, FALSE)
		remove_pose_indicator()

// Similar to above, but for turf slowdown.
/mob/living/carbon/human/proc/calculate_turf_slowdown(turf/T, direct)
	if(!T)
		return 0

	if(T.movement_cost && !stat_value(src, STAT_FLYING)) //If you are stat_value(src, STAT_FLYING) you are probably not affected by the terrain on the ground.
		var/turf_move_cost = T.movement_cost
		if(locate_on(T, /obj/structure/catwalk)) //catwalks prevent turfs from slowing your
			return 0
		if(istype(T, /turf/simulated/floor/water))
			if(species.water_movement)
				turf_move_cost = CLAMP(turf_move_cost + species.water_movement, HUMAN_LOWEST_SLOWDOWN, 15)
			if(istype(get_equipped_item(SLOT_ID_SHOES), /obj/item/clothing/shoes))
				var/obj/item/clothing/shoes/feet = get_equipped_item(SLOT_ID_SHOES)
				if(istype(feet) && feet.water_speed)
					turf_move_cost = CLAMP(turf_move_cost + feet.water_speed, HUMAN_LOWEST_SLOWDOWN, 15)
			. += turf_move_cost
		else if(istype(T, /turf/simulated/floor/outdoors/snow))
			if(species.snow_movement)
				turf_move_cost = CLAMP(turf_move_cost + species.snow_movement, HUMAN_LOWEST_SLOWDOWN, 15)
			if(istype(get_equipped_item(SLOT_ID_SHOES), /obj/item/clothing/shoes))
				var/obj/item/clothing/shoes/feet = get_equipped_item(SLOT_ID_SHOES)
				if(istype(feet) && feet.snow_speed)
					turf_move_cost = CLAMP(turf_move_cost + feet.snow_speed, HUMAN_LOWEST_SLOWDOWN, 15)
			. += turf_move_cost
		else
			turf_move_cost = CLAMP(turf_move_cost, HUMAN_LOWEST_SLOWDOWN, 15)
			. += turf_move_cost

	// Wind makes it easier or harder to move, depending on if you're with or against the wind.
	// I don't like that so I'm commenting it out :)
#undef HUMAN_LOWEST_SLOWDOWN

///Gets whatever jetpack we may have and returns it. Checks back -> rig -> suit storage -> suit
/mob/living/carbon/human/get_jetpack()
	if(get_equipped_item(SLOT_ID_BACK))
		if(istype(get_equipped_item(SLOT_ID_BACK), /obj/item/tank/jetpack))
			return get_equipped_item(SLOT_ID_BACK)
		var/obj/item/rig/rig = get_rig()
		if(istype(rig))
			for(var/obj/item/rig_module/maneuvering_jets/module in rig.installed_modules)
				return module.jets
	if(get_equipped_item(SLOT_ID_SUIT_STORAGE) && istype(get_equipped_item(SLOT_ID_SUIT_STORAGE), /obj/item/tank/jetpack))
		return get_equipped_item(SLOT_ID_SUIT_STORAGE)
	if(get_equipped_item(SLOT_ID_SUIT) && istype(get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/space/void))
		var/obj/item/clothing/suit/space/void/v = get_equipped_item(SLOT_ID_SUIT)
		if(v.tank && istype(v.tank, /obj/item/tank/jetpack))
			return v.tank

/mob/living/carbon/human/Process_Spacemove(check_drift = 0)
	//Can we act?
	if(restrained())	return 0

	if(..()) //Can move due to other reasons, don't use jetpack fuel
		return TRUE

	if(species.can_space_freemove || (species.can_zero_g_move && !istype(get_turf(src), /turf/space)))
		return TRUE

	if(stat_value(src, STAT_FLYING)) //If you're stat_value(src, STAT_FLYING), you glide around!
		return TRUE

	//Do we have a working jetpack?
	var/obj/item/tank/jetpack/thrust = get_jetpack()

	if(thrust)
		if(((!check_drift) || (check_drift && thrust.stabilization_on)) && (!lying) && (thrust.do_thrust(0.01, src)))
			sparse_set_or(src, inertia_dir, 0, 0)
			return TRUE

	return FALSE

// Handle footstep sounds
/mob/living/carbon/human/handle_footstep(turf/T)
	if(get_equipped_item(SLOT_ID_SHOES) && loc == T && get_gravity(loc) && !stat_value(src, STAT_FLYING))
		var/obj/item/shoes = get_equipped_item(SLOT_ID_SHOES)
		PUBLISH_LEGACY(shoes, /datum/notice/shoes_step, src, m_intent)
	return

