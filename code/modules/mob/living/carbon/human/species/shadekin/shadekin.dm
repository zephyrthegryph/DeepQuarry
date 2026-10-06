/datum/species/shadekin
	name = SPECIES_SHADEKIN
	name_plural = "Shadekin"
	icobase = 'icons/mob/human_races/r_shadekin_vr.dmi'
	deform = 'icons/mob/human_races/r_shadekin_vr.dmi'
	tail = "tail"
	icobase_tail = 1
	blurb = "Very little is known about these creatures. They appear to be largely mammalian in appearance. \
	Seemingly very rare to encounter, there have been widespread myths of these creatures the galaxy over, \
	but next to no verifiable evidence to their existence. However, they have recently been more verifiably \
	documented in the Virgo system, following a mining bombardment of Virgo 3. The crew of NSB Adephagia have \
	taken to calling these creatures 'Shadekin', and the name has generally stuck and spread. "		//TODO: Something that's not wiki copypaste
	wikilink = "https://wiki.vore-station.net/Shadekin"
	catalogue_data = list(/datum/category_item/catalogue/fauna/shadekin)

	language = LANGUAGE_SHADEKIN
	name_language = LANGUAGE_SHADEKIN
	species_language = LANGUAGE_SHADEKIN
	secondary_langs = list(LANGUAGE_SHADEKIN)
	num_alternate_languages = 3
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws/shadekin, /datum/unarmed_attack/bite/sharp/shadekin)
	rarity_value = 15	//INTERDIMENSIONAL FLUFFERS

	inherent_verbs = list(/mob/proc/adjust_hive_range)

	siemens_coefficient = 1
	darksight = 10

	factor_baseline = alist(BF_SLOWDOWN = -0.5, BF_INCOMING_PHYSICAL = 0.7, BF_INCOMING_THERMAL = 1.2)
	item_slowdown_mod = 0.5

	// Naturally sturdy. (brute)
	// Furry (burn)

	warning_low_pressure = 50
	hazard_low_pressure = -1

	warning_high_pressure = 300
	hazard_high_pressure = INFINITY

	cold_level_1 = -1	//Immune to cold
	cold_level_2 = -1
	cold_level_3 = -1

	heat_level_1 = 850	//Resistant to heat
	heat_level_2 = 1000
	heat_level_3 = 1150

	flags =  NO_DNA | NO_SLEEVE | NO_MINOR_CUT | NO_INFECT
	spawn_flags = SPECIES_CAN_JOIN | SPECIES_IS_WHITELISTED | SPECIES_WHITELIST_SELECTABLE

	reagent_tag = IS_SHADEKIN		// for shadekin-unqiue chem interactions

	flesh_color = "#FFC896"
	blood_color = "#A10808"
	base_color = "#f0f0f0"
	color_mult = 1


	death_message = "phases to somewhere far away!"
	speech_bubble_appearance = "ghost"

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	virus_immune = 1

	breath_type = null
	poison_type = null
	water_breather = TRUE	//They don't quite breathe

	vision_flags = SEE_SELF|SEE_MOBS
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_SKIN_COLOR | HAS_EYE_COLOR | HAS_UNDERWEAR

	move_trail = /obj/effect/decal/cleanable/blood/tracks/paw

	has_organ = list(
		O_HEART =		/obj/item/organ/internal/heart,
		O_VOICE = 		/obj/item/organ/internal/voicebox,
		O_LIVER =		/obj/item/organ/internal/liver,
		O_KIDNEYS =		/obj/item/organ/internal/kidneys,
		O_SPLEEN =		/obj/item/organ/internal/spleen,
		O_BRAIN =		/obj/item/organ/internal/brain/shadekin,
		O_EYES =		/obj/item/organ/internal/eyes,
		O_STOMACH =		/obj/item/organ/internal/stomach,
		O_INTESTINE =	/obj/item/organ/internal/intestine
		)

	has_limbs = list(
		BP_TORSO =  list("path" = /obj/item/organ/external/chest),
		BP_GROIN =  list("path" = /obj/item/organ/external/groin),
		BP_HEAD =   list("path" = /obj/item/organ/external/head/shadekin),
		BP_L_ARM =  list("path" = /obj/item/organ/external/arm),
		BP_R_ARM =  list("path" = /obj/item/organ/external/arm/right),
		BP_L_LEG =  list("path" = /obj/item/organ/external/leg),
		BP_R_LEG =  list("path" = /obj/item/organ/external/leg/right),
		BP_L_HAND = list("path" = /obj/item/organ/external/hand),
		BP_R_HAND = list("path" = /obj/item/organ/external/hand/right),
		BP_L_FOOT = list("path" = /obj/item/organ/external/foot),
		BP_R_FOOT = list("path" = /obj/item/organ/external/foot/right)
		)

	species_component = list(/datum/shadekin/full, /datum/trait_state/radiation_effects/radiation_immune) // Enabling full shadekin & no-power radiation component.
	component_requires_late_recalc = TRUE

/datum/species/shadekin/handle_death(mob/living/carbon/human/H)
	var/special_handling = TRUE // varswitch for downstream // Enable.
	H.dq_do_clear_dark_maws(H, null, null) //clear dark maws on death or similar
	var/datum/shadekin/SK = H.get_shadekin_state()
	if(!special_handling || (SK && SK.no_retreat))
		after(H, 0.1 SECONDS, TYPE_PROC_REF(/mob/living/carbon/human, species_death_vanish))
	else
		if(!SK)
			return
		if(SK.respite_activating)
			return TRUE
		var/area/current_area = get_area(H)
		if((SK.in_dark_respite) || H.has_body_effect(/datum/body_effect/dark_respite) || current_area.flag_check(AREA_LIMIT_DARK_RESPITE))
			return
		if(!LAZYLEN(GLOB.latejoin_thedark))
			log_and_message_admins("[H] died outside of the dark but there were no valid floors to warp to")
			return

		act_message(H, null, others = "<b>%U%</b> phases to somewhere far away!")
		var/obj/effect/temp_visual/shadekin/phase_out/phaseanimout = new /obj/effect/temp_visual/shadekin/phase_out(H.loc)
		phaseanimout.dir = H.dir
		SK.respite_activating = TRUE

		H.drop_l_hand()
		H.drop_r_hand()

		SK.shadekin_set_energy(0)
		SK.in_dark_respite = TRUE
		H.invisibility = INVISIBILITY_SHADEKIN

		// Dark respite mends three quarters of every injury.
		H.mend(TREAT_BURN_CARE, H.injury_load(INJURY_CATEGORY_THERMAL) * 0.75)
		H.mend(TREAT_TISSUE_REPAIR, H.injury_load(INJURY_CATEGORY_PHYSICAL) * 0.75)
		H.mend(TREAT_ANTITOXIN, H.injury_load(INJURY_CATEGORY_TOXIC) * 0.75)
		H.mend(TREAT_GENETIC_REPAIR, H.injury_load(INJURY_CATEGORY_GENETIC) * 0.75)
		H.germ_level = 0 //Take away the germs, or we'll die AGAIN
		H.vessel.add_reagent(REAGENT_ID_BLOOD,blood_volume-H.vessel.total_volume)
		for(var/obj/item/organ/external/bp in H.organs)
			bp.bandage()
			bp.disinfect()
		for(var/obj/item/organ/internal/I in H.internal_organ_list()) //other wise their organs stay mush
			H.mend(TREAT_RESTORATION, I.max_damage, I)
			I.restore_status()
			if(I.organ_tag == O_EYES)
				H.set_sdisabilities(H.sdisabilities & (~BLIND))
			if(I.organ_tag == O_LUNGS)
				H.SetLosebreath(0)
		H.set_nutrition(0)
		H.invisibility = INVISIBILITY_SHADEKIN
		BITRESET(H.hud_updateflag, HEALTH_HUD)
		BITRESET(H.hud_updateflag, STATUS_HUD)
		BITRESET(H.hud_updateflag, LIFE_HUD)

		if(istype(H.loc, /obj/belly))
			//Yay digestion... presumably...
			var/obj/belly/belly = H.loc
			add_attack_logs(belly.owner, H, "Digested in [lowertext(belly.name)]")
			to_chat(belly.owner, span_notice("\The [H.name] suddenly vanishes within your [belly.name]"))
			H.forceMove(pick(GLOB.latejoin_thedark))
			if(SK.in_phase)
				H.phase_in(get_turf(H), SK)
			else
				var/obj/effect/temp_visual/shadekin/phase_in/phaseanim = new /obj/effect/temp_visual/shadekin/phase_in(H.loc)
				phaseanim.dir = H.dir
			H.invisibility = initial(H.invisibility)
			SK.respite_activating = FALSE
			belly.owner.handle_belly_update()
			H.clear_fullscreen("belly")
			H.belly_overlay_tgui?.hide() // hide TGUI belly overlay
			if(H.hud_used)
				if(!H.hud_used.hud_shown)
					H.toggle_hud_vis()
			H.stop_sound_channel(CHANNEL_PREYLOOP)
			H.apply_body_effect(/datum/body_effect/dark_respite, 10 MINUTES)
			H.muffled = FALSE
			H.forced_psay = FALSE

			after(H, 5 MINUTES, TYPE_PROC_REF(/mob/living, can_leave_dark))
		else
			H.apply_body_effect(/datum/body_effect/dark_respite, 25 MINUTES)

			after(H, 1 SECOND, TYPE_PROC_REF(/mob/living, enter_the_dark))

			after(H, 15 MINUTES, TYPE_PROC_REF(/mob/living, can_leave_dark))

		return TRUE


/mob/living/proc/enter_the_dark()
	var/datum/shadekin/SK = get_shadekin_state()
	if(!SK)
		return
	SK.respite_activating = FALSE
	SK.in_dark_respite = TRUE

	forceMove(pick(GLOB.latejoin_thedark))
	invisibility = initial(invisibility)
	SK.respite_activating = FALSE

/mob/living/proc/can_leave_dark()
	var/datum/shadekin/SK = get_shadekin_state()
	if(!SK)
		return
	SK.in_dark_respite = FALSE
	to_chat(src, span_notice("You feel like you can leave the Dark again"))

/datum/species/shadekin/get_bodytype()
	return SPECIES_SHADEKIN

/datum/species/shadekin/get_random_name()
	return "shadekin"

/datum/species/shadekin/post_spawn_special(mob/living/carbon/human/H)
	.=..()

	var/datum/shadekin/SK = H.get_shadekin_state()
	if(!SK)
		CRASH("A shadekin [H] somehow is missing their shadekin component post-spawn!")

	// Per-mob value: written to H's private species copy, never the shared one.
	var/eye_health = total_health
	switch(SK.eye_color)
		if(BLUE_EYES)
			eye_health = 75
		if(RED_EYES)
			eye_health = 150
		if(PURPLE_EYES)
			eye_health = 150
		if(YELLOW_EYES)
			eye_health = 50
		if(GREEN_EYES)
			eye_health = 100
		if(ORANGE_EYES)
			eye_health = 125

	if(H.species.total_health != eye_health)
		var/datum/species/private_species = proto_private(H, nameof(H.species))
		private_species.total_health = eye_health
	H.endurance = eye_health

/datum/species/shadekin/produceCopy(list/traits, mob/living/carbon/human/H, custom_base, reset_dna = TRUE) // Traitgenes reset_dna flag required, or genes get reset on resleeve
	var/datum/species/shadekin/new_copy = ..()
	new_copy.total_health = total_health

	return new_copy

/// A species death that leaves only the carried items.
/mob/living/carbon/human/proc/species_death_vanish()
	for(var/obj/item/W in contents_of(src))
		drop_from_inventory(W)
	dissolved(src)
