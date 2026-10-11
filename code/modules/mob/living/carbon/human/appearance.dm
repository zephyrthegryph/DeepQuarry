/mob/living/carbon/human/proc/change_appearance(flags = APPEARANCE_ALL_HAIR,
												mob/user = src,
												check_species_whitelist = 1,
												list/species_whitelist = list(),
												list/species_blacklist = list(),
												datum/tgui_state/state = GLOB.tgui_self_state)
	var/datum/tgui_module/appearance_changer/self_deleting/AC = new(src, src, check_species_whitelist, species_whitelist, species_blacklist)
	AC.flags = flags
	AC.tgui_interact(user, custom_state = state)

/mob/living/carbon/human/proc/change_species(new_species)
	if(!new_species)
		return

	if(species == new_species)
		return

	if(!(new_species in GLOB.all_species))
		return

	set_species(new_species)
	reset_hair()
	return 1

/mob/living/carbon/human/proc/change_gender(gender)
	if(src.gender == gender)
		return

	src.gender = gender
	// reset_hair() // Remove - Don't just randomize hair on gender swaps for prometheans.
	update_dna()
	update_icons_body()
	return 1

/mob/living/carbon/human/proc/change_gender_identity(identifying_gender)
	if(src.identifying_gender == identifying_gender)
		return

	src.identifying_gender = identifying_gender
	return 1

/mob/living/carbon/human/proc/change_hair(hair_style)
	if(!hair_style)
		return

	if(looks.hair_style == hair_style)
		return

	if(!(hair_style in GLOB.hair_styles_list))
		return

	looks.set_hair_style(hair_style)

	update_hair()
	return 1

/mob/living/carbon/human/proc/change_hair_gradient(hair_gradient)
	if(!hair_gradient)
		return

	if(looks.grad_style == hair_gradient)
		return

	if(!(hair_gradient in GLOB.hair_gradients))
		return

	looks.set_grad_style(hair_gradient)

	update_hair()
	return 1

/mob/living/carbon/human/proc/change_facial_hair(facial_hair_style)
	if(!facial_hair_style)
		return

	if(looks.facial_style == facial_hair_style)
		return

	if(!(facial_hair_style in GLOB.facial_hair_styles_list))
		return

	looks.set_facial_style(facial_hair_style)

	update_hair()
	return 1

/mob/living/carbon/human/proc/reset_hair()
	var/list/valid_hairstyles = generate_valid_hairstyles()
	var/list/valid_facial_hairstyles = generate_valid_facial_hairstyles()

	if(valid_hairstyles.len)
		looks.set_hair_style(pick(valid_hairstyles))
	else
		//this shouldn't happen
		looks.set_hair_style("Bald")

	if(valid_facial_hairstyles.len)
		looks.set_facial_style(pick(valid_facial_hairstyles))
	else
		//this shouldn't happen
		looks.set_facial_style("Shaved")

	update_hair()

/mob/living/carbon/human/proc/change_eye_color(colour)
	if(!looks.set_eyes_color(colour))
		return

	update_eyes()
	update_icons_body()
	return 1

/mob/living/carbon/human/proc/change_hair_color(colour)
	if(!looks.set_hair_color(colour))
		return

	update_hair()
	return 1

/mob/living/carbon/human/proc/change_grad_color(colour)
	if(!looks.set_grad_color(colour))
		return

	update_hair()
	return 1

/mob/living/carbon/human/proc/change_facial_hair_color(colour)
	if(!looks.set_facial_color(colour))
		return

	update_hair()
	return 1

/mob/living/carbon/human/proc/change_skin_color(colour)
	if(!(species.appearance_flags & HAS_SKIN_COLOR) || !looks.set_skin_color(colour))
		return

	force_update_limbs()
	update_icons_body()
	return 1

/mob/living/carbon/human/proc/change_skin_tone(tone)
	if(looks.skin_tone == tone || !(species.appearance_flags & HAS_SKIN_TONE))
		return

	looks.set_skin_tone(tone)

	force_update_limbs()
	update_icons_body()
	return 1

/mob/living/carbon/human/proc/update_dna()
	check_dna()
	dna.ResetUIFrom(src) // Do not call ready_dna here: it resets ALL SE blocks, wiping trait gene state
	sync_organ_dna()

/mob/living/carbon/human/proc/generate_valid_species(check_whitelist = 1, list/whitelist = list(), list/blacklist = list())
	var/list/valid_species = new()
	for(var/current_species_name in GLOB.all_species)
		var/datum/species/current_species = GLOB.all_species[current_species_name]

		if(check_whitelist && CONFIG_GET(flag/usealienwhitelist) && !check_rights_for(src.client, R_ADMIN|R_EVENT)) //If we're using the whitelist, make sure to check it!
			if(!(current_species.spawn_flags & SPECIES_CAN_JOIN))
				continue
			if(whitelist.len && !(current_species_name in whitelist))
				continue
			if(blacklist.len && (current_species_name in blacklist))
				continue
			if((current_species.spawn_flags & SPECIES_IS_WHITELISTED) && !is_alien_whitelisted(src.client, current_species))
				continue

		valid_species += current_species_name

	return valid_species

/mob/living/carbon/human/proc/generate_valid_hairstyles(check_gender = 1)

	var/use_species = species.get_bodytype(src)
	var/obj/item/organ/external/head/H = get_organ(BP_HEAD)
	if(H) use_species = H.data.get_species_bodytype(src)

	var/list/valid_hairstyles = new()
	for(var/hairstyle in GLOB.hair_styles_list)
		var/datum/sprite_accessory/S = GLOB.hair_styles_list[hairstyle]

		if(S.name == DEVELOPER_WARNING_NAME)
			continue

		if(check_gender && gender != NEUTER)
			if(gender == MALE && S.gender == FEMALE)
				continue
			else if(gender == FEMALE && S.gender == MALE)
				continue

		if(!(use_species in S.species_allowed))
			continue

		if(!S.can_be_selected && (!client || !check_rights_for(client, R_HOLDER)))
			continue

		if(S.ckeys_allowed && !(ckey in S.ckeys_allowed)) // add - ckey whitelist check
			continue // add - ckey whitelist check

		valid_hairstyles += hairstyle

	return valid_hairstyles

/mob/living/carbon/human/proc/generate_valid_facial_hairstyles()

	var/use_species = species.get_bodytype(src)
	var/obj/item/organ/external/head/H = get_organ(BP_HEAD)
	if(H) use_species = H.data.get_species_bodytype(src)

	var/list/valid_facial_hairstyles = new()
	for(var/facialhairstyle in GLOB.facial_hair_styles_list)
		var/datum/sprite_accessory/S = GLOB.facial_hair_styles_list[facialhairstyle]

		if(S.name == DEVELOPER_WARNING_NAME)
			continue

		if(gender != NEUTER)
			if(gender == MALE && S.gender == FEMALE)
				continue
			else if(gender == FEMALE && S.gender == MALE)
				continue

		if(!(use_species in S.species_allowed))
			continue

		if(!S.can_be_selected && (!client || !check_rights_for(client, R_HOLDER)))
			continue

		if(S.ckeys_allowed && !(ckey in S.ckeys_allowed)) // add - ckey whitelist check
			continue // add - ckey whitelist check

		valid_facial_hairstyles += facialhairstyle

	return valid_facial_hairstyles

/mob/living/carbon/human/proc/force_update_limbs()
	for(var/obj/item/organ/external/O in organs)
		O.sync_colour_to_human(src)
	update_icons_body(FALSE)
