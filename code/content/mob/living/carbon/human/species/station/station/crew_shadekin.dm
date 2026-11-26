/*
/datum/species/teshari/handle_falling(mob/living/carbon/human/H, atom/hit_atom, damage_min, damage_max, silent, planetary)

	// Tesh can glide to save themselves from some falls. Basejumping bird
	// without dq_get_parachute(src), or falling bird without free wings, goes splat.

	// Are we landing from orbit, or handcuffed/unconscious/tied to something?
	if(planetary || !istype(H) || H.incapacitated(INCAPACITATION_DEFAULT|INCAPACITATION_DISABLED))
		return ..()

	// Are we landing on a turf? Not sure how this could not be the case, but let's be safe.
	var/turf/landing = get_turf(hit_atom)
	if(!istype(landing))
		return ..()

	if(H?.buckled_to())
		if(!silent)
			to_chat(H, span_warning("You try to spread your wings to slow your fall, but what you're buckled to weighs you down!"))
		return ..()

	// Is there enough air to flap against?
	var/datum/gas_mixture/environment = landing.return_air()
	if(!environment || environment.return_pressure() < (ONE_ATMOSPHERE * 0.75))
		if(!silent)
			to_chat(H, span_warning("You spread your wings to slow your fall, but the air is too thin!"))
		return ..()

	// Are we wearing a space suit?
	if(H.wear_suit)
		for(var/blacklisted_type in flight_suit_blacklisted_types)
			if(istype(H.wear_suit, blacklisted_type))
				if(!silent)
					to_chat(H, span_warning("You try to spread your wings to slow your fall, but \the [H.wear_suit] is in the way!"))
				return ..()

	// Do we have working wings?
	for(var/bp in flight_bodyparts)
		var/obj/item/organ/external/E = H.organs_by_name[bp]
		if(!istype(E) || !E.is_usable() || E.is_broken() || E.is_stump())
			if(!silent)
				to_chat(H, span_warning("You try to spread your wings to slow your fall, but they won't hold your weight!"))
			return ..()

	// Handled!
	if(!silent)
		to_chat(H, span_notice("You catch the air in your wings and greatly slow your fall."))
		landing.visible_message(span_infoplain(span_bold("\The [H]") + " glides down from above, landing safely."))
		H.status_at_least(STAT_STUNNED, 1)
		play_sfx(H, SFX_RUSTLE, extrarange = 0)
	return TRUE
*/



/datum/species/crew_shadekin
	name = SPECIES_SHADEKIN_CREW
	name_plural = "Black-Eyed Shadekin"
	icobase = 'icons/mob/human_races/r_shadekin_vr.dmi'
	deform = 'icons/mob/human_races/r_shadekin_vr.dmi'
	tail = "tail"
	icobase_tail = 1
	blurb = "Very little is known about these creatures. They appear to be largely mammalian in appearance. \
	Seemingly very rare to encounter, there have been widespread myths of these creatures the galaxy over, \
	but next to no verifiable evidence to their existence. However, they have recently been more verifiably \
	documented in the Virgo system, following a mining bombardment of Virgo 3. The crew of NSB Adephagia have \
	taken to calling these creatures 'Shadekin', and the name has generally stuck and spread. "		//TODO: Something more fitting for black-eyes
	wikilink = "https://wiki.vore-station.net/Shadekin"
	catalogue_data = list(/datum/category_item/catalogue/fauna/shadekin)

	language = LANGUAGE_SHADEKIN
	name_language = LANGUAGE_SHADEKIN
	species_language = LANGUAGE_SHADEKIN
	secondary_langs = list(LANGUAGE_SHADEKIN)
	num_alternate_languages = 3
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws, /datum/unarmed_attack/bite/sharp)
	rarity_value = 5	//INTERDIMENSIONAL FLUFFERS

	inherent_verbs = list(/mob/proc/adjust_hive_range)

	siemens_coefficient = 0
	darksight = 10

	factor_baseline = alist(STAT_SLOWDOWN = 0.5, STAT_INCOMING_PHYSICAL = 1.25, STAT_INCOMING_THERMAL = 1.25)
	item_slowdown_mod = 1.5

	total_health = 75
	// Frail (brute)
	// Furry (burn)
	blood_volume = 500
	hunger_factor = 0.2

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

	flags =  NO_DNA | NO_SLEEVE
	spawn_flags = SPECIES_IS_RESTRICTED // SPECIES_CAN_JOIN | SPECIES_IS_WHITELISTED | SPECIES_WHITELIST_SELECTABLE disabled maybe forever
	reagent_tag = IS_SHADEKIN		// for shadekin-unqiue chem interactions

	flesh_color = "#FFC896"
	blood_color = "#A10808"
	base_color = "#f0f0f0"
	color_mult = 1


	speech_bubble_appearance = "ghost"

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	breath_type = null
	poison_type = null
	water_breather = TRUE //They do not quite breathe...

	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_SKIN_COLOR | HAS_UNDERWEAR

	move_trail = /obj/effect/decal/cleanable/blood/tracks/paw

	has_organ = list(
		O_HEART =		/obj/item/organ/internal/heart,
		O_VOICE = 		/obj/item/organ/internal/voicebox,
		O_LIVER =		/obj/item/organ/internal/liver,
		O_KIDNEYS =		/obj/item/organ/internal/kidneys,
		O_SPLEEN =		/obj/item/organ/internal/spleen,
		O_BRAIN =		/obj/item/organ/internal/brain,
		O_EYES =		/obj/item/organ/internal/eyes,
		O_STOMACH =		/obj/item/organ/internal/stomach,
		O_INTESTINE =	/obj/item/organ/internal/intestine
		)

	has_limbs = list(
		BP_TORSO =  list("path" = /obj/item/organ/external/chest, "variant" = LIMB_VARIANT_CREWKIN_CORE),
		BP_GROIN =  list("path" = /obj/item/organ/external/groin, "variant" = LIMB_VARIANT_CREWKIN_CORE),
		BP_HEAD =   list("path" = /obj/item/organ/external/head, "variant" = LIMB_VARIANT_CREWKIN_HEAD),
		BP_L_ARM =  list("path" = /obj/item/organ/external/arm, "variant" = LIMB_VARIANT_CREWKIN_LIMB),
		BP_R_ARM =  list("path" = /obj/item/organ/external/arm/right, "variant" = LIMB_VARIANT_CREWKIN_LIMB),
		BP_L_LEG =  list("path" = /obj/item/organ/external/leg, "variant" = LIMB_VARIANT_CREWKIN_LIMB),
		BP_R_LEG =  list("path" = /obj/item/organ/external/leg/right, "variant" = LIMB_VARIANT_CREWKIN_LIMB),
		BP_L_HAND = list("path" = /obj/item/organ/external/hand, "variant" = LIMB_VARIANT_CREWKIN_EXTREMITY),
		BP_R_HAND = list("path" = /obj/item/organ/external/hand/right, "variant" = LIMB_VARIANT_CREWKIN_EXTREMITY),
		BP_L_FOOT = list("path" = /obj/item/organ/external/foot, "variant" = LIMB_VARIANT_CREWKIN_EXTREMITY),
		BP_R_FOOT = list("path" = /obj/item/organ/external/foot/right, "variant" = LIMB_VARIANT_CREWKIN_EXTREMITY)
		)

	species_component = list(/datum/trait_state/radiation_effects/besk)

/datum/species/crew_shadekin/get_bodytype()
	return SPECIES_SHADEKIN
