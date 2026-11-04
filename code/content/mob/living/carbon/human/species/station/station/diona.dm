/datum/species/diona

	name = SPECIES_DIONA
	mood_immune = TRUE
	name_plural = "Dionaea"
	icobase = 'icons/mob/human_races/r_diona.dmi'
	deform = 'icons/mob/human_races/r_def_plant.dmi'
	language = LANGUAGE_ROOTLOCAL
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/diona)
	factor_baseline = alist(STAT_SLOWDOWN = 0.5)
	snow_movement = -2 	//Ignore light snow
	water_movement = -4	//Ignore shallow water
	rarity_value = 3
	hud_type = /datum/hud_data/diona
	siemens_coefficient = 0.3
	show_ssd = "completely quiescent"
	health_hud_intensity = 2.5
	item_slowdown_mod = 0.1
	chem_strength_alcohol = 10000	//a little hacky, maybe? but whatever. nobody plays diona anyway.
	throwforce_absorb_threshold = 5

	num_alternate_languages = 3
	name_language = LANGUAGE_ROOTLOCAL
	species_language = LANGUAGE_ROOTLOCAL
	secondary_langs = list(LANGUAGE_ROOTGLOBAL)
	assisted_langs = list(LANGUAGE_VOX)	// Diona are weird, let's just assume they can use basically any language.
	min_age = 18
	max_age = 300

	// P2-D7: light feeding and healing through the shared photosynthesis trait.
	species_component = list(/datum/trait_state/radiation_effects/diona, /datum/trait_state/photosynth/diona)

	economic_modifier = 10

	blurb = "Commonly referred to (erroneously) as 'plant people', the Dionaea are a strange space-dwelling collective \
	species hailing from Epsilon Ursae Minoris. Each 'diona' is a cluster of numerous cat-sized organisms called nymphs; \
	there is no effective upper limit to the number that can fuse in gestalt, and reports exist	of the Epsilon Ursae \
	Minoris primary being ringed with a cloud of singing space-station-sized entities.<br/><br/>The Dionaea coexist peacefully with \
	all known species, especially the Skrell. Their communal mind makes them slow to react, and they have difficulty understanding \
	even the simplest concepts of other minds. Their alien physiology allows them survive happily off a diet of nothing but light, \
	water and other radiation."
	wikilink="https://wiki.chompstation13.net/index.php?title=Diona"
	catalogue_data = list(/datum/category_item/catalogue/fauna/dionaea)

	has_organ = list(
		O_NUTRIENT = /obj/item/organ/internal/diona/nutrients,
		O_STRATA =   /obj/item/organ/internal/diona/strata,
		O_BRAIN = /obj/item/organ/internal/brain/cephalon,
		O_RESPONSE = /obj/item/organ/internal/diona/node,
		O_GBLADDER = /obj/item/organ/internal/diona/bladder,
		O_POLYP =    /obj/item/organ/internal/diona/polyp,
		O_ANCHOR =   /obj/item/organ/internal/diona/ligament
		)

	has_limbs = list(
		BP_TORSO =  list("path" = /obj/item/organ/external/diona/chest),
		BP_GROIN =  list("path" = /obj/item/organ/external/diona/groin),
		BP_HEAD =   list("path" = /obj/item/organ/external/head/no_eyes/diona),
		BP_L_ARM =  list("path" = /obj/item/organ/external/diona/arm),
		BP_R_ARM =  list("path" = /obj/item/organ/external/diona/arm/right),
		BP_L_LEG =  list("path" = /obj/item/organ/external/diona/leg),
		BP_R_LEG =  list("path" = /obj/item/organ/external/diona/leg/right),
		BP_L_HAND = list("path" = /obj/item/organ/external/diona/hand),
		BP_R_HAND = list("path" = /obj/item/organ/external/diona/hand/right),
		BP_L_FOOT = list("path" = /obj/item/organ/external/diona/foot),
		BP_R_FOOT = list("path" = /obj/item/organ/external/diona/foot/right)
		)

	inherent_verbs = list(
		/mob/living/carbon/human/proc/diona_split_nymph,
		/mob/living/carbon/human/proc/regenerate,
		/mob/proc/adjust_hive_range
		)

	warning_low_pressure = 50
	hazard_low_pressure = -1

	cold_level_1 = 50
	cold_level_2 = -1
	cold_level_3 = -1

	heat_level_1 = 2000
	heat_level_2 = 3000
	heat_level_3 = 4000

	body_temperature = T0C + 15		//make the plant people have a bit lower body temperature, why not

	flags = NO_DNA | NO_SLEEVE | IS_PLANT | NO_PAIN | NO_SLIP | NO_MINOR_CUT | NO_DEFIB
	spawn_flags = SPECIES_CAN_JOIN | SPECIES_IS_WHITELISTED | SPECIES_WHITELIST_SELECTABLE // restore whitelist requirement

	blood_color = "#004400"
	flesh_color = "#907E4A"

	reagent_tag = IS_DIONA

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	default_emotes = list(
		/datum/decl/emote/audible/chirp,
		/datum/decl/emote/audible/multichirp
	)

/datum/species/diona/can_understand(mob/other)
	if(istype(other, /mob/living/carbon/alien/diona))
		return TRUE
	return FALSE

/datum/species/diona/equip_survival_gear(mob/living/carbon/human/H)
	if(H.bio.backbag == 1)
		H.equip_to_slot_or_del(new /obj/item/flashlight/flare(H), SLOT_ID_HAND_R)
	else
		H.equip_to_slot_or_del(new /obj/item/flashlight/flare(H.get_equipped_item(SLOT_ID_BACK)), SLOT_ID_IN_BACKPACK)

/datum/species/diona/handle_post_spawn(mob/living/carbon/human/H)
	H.set_gender(NEUTER)
	add_trait(H, UNIQUE_MINDSTRUCTURE, ROUNDSTART_TRAIT)
	return ..()

/datum/species/diona/handle_death(mob/living/carbon/human/H)

	var/mob/living/carbon/alien/diona/S = new(get_turf(H))

	if(H.mind)
		H.mind.transfer_to(S)

	if(HAS_SYNTHETIC_BIOLOGY(H))
		act_message(H, null, others = span_danger("%U% collapses into parts, revealing a solitary diona nymph at the core."))

		remove_inherent_verbs(H) // split and regenerate came from this species
		// This is hard-set to default the body to a normal FBP, without changing anything.
		// proto_replace: src may be H's private copy, still running this proc; deleted below.
		var/datum/species/old_species = proto_replace(H, nameof(H.species), GLOB.all_species[SPECIES_HUMAN])
		H.body?.sync_species_factors()

		for(var/obj/item/organ/internal/diona/Org in H.internal_organ_list()) // Remove Nymph organs.
			ended_with(Org, H)

		if(old_species)
			replaced_by(old_species, H)
		return

	for(var/mob/living/carbon/alien/diona/D in contents_of(H))
		if(D.client)
			D.forceMove(get_turf(H))
		else
			ended_with(D, H)

	act_message(H, null, others = span_danger("%U% splits apart with a wet slithering noise!"))

/datum/species/diona
