/datum/species/human
	name = SPECIES_HUMAN
	name_plural = "Humans"
	icobase = 'icons/mob/human_races/r_human_vr.dmi'
	deform = 'icons/mob/human_races/r_def_human_vr.dmi'
	primitive_form = SPECIES_MONKEY
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/punch, /datum/unarmed_attack/bite)
	blurb = "Humanity originated in the Sol system, and over the last five centuries has spread \
	colonies across a wide swathe of space. They hold a wide range of forms and creeds.<br/><br/> \
	While the central Sol government maintains control of its far-flung people, powerful corporate \
	interests, rampant cyber and bio-augmentation and secretive factions make life on most human \
	worlds tumultous at best."
	wikilink="https://wiki.chompstation13.net/index.php?title=Humans"
	catalogue_data = list(/datum/category_item/catalogue/fauna/humans)
	num_alternate_languages = 3
	species_language = LANGUAGE_SOL_COMMON
	secondary_langs = list(LANGUAGE_SOL_COMMON, LANGUAGE_TERMINUS)
	name_language = null // Use the first-name last-name generator rather than a language scrambler
	assisted_langs = list(LANGUAGE_EAL, LANGUAGE_SKRELLIAN, LANGUAGE_ROOTLOCAL, LANGUAGE_ROOTGLOBAL, LANGUAGE_VOX, LANGUAGE_PROMETHEAN)

	min_age = 18
	max_age = 130
	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	economic_modifier = 10

	health_hud_intensity = 1.5
	base_color = "#EECEB3"
	color_mult = 1


	spawn_flags = SPECIES_CAN_JOIN
	appearance_flags = HAS_HAIR_COLOR | HAS_SKIN_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_EYE_COLOR

	has_organ = list(
		O_HEART =		/obj/item/organ/internal/heart,
		O_LUNGS =		/obj/item/organ/internal/lungs,
		O_VOICE = 		/obj/item/organ/internal/voicebox,
		O_LIVER =		/obj/item/organ/internal/liver,
		O_KIDNEYS =		/obj/item/organ/internal/kidneys,
		O_BRAIN =		/obj/item/organ/internal/brain,
		O_APPENDIX = 	/obj/item/organ/internal/appendix,
		O_SPLEEN = 		/obj/item/organ/internal/spleen,
		O_EYES =		/obj/item/organ/internal/eyes,
		O_STOMACH =		/obj/item/organ/internal/stomach,
		O_INTESTINE =	/obj/item/organ/internal/intestine
		)

	species_sounds = "Human Male"
	gender_specific_species_sounds = TRUE
	species_sounds_male = "Human Male"
	species_sounds_female = "Human Female"

	inherent_verbs = list(
		/mob/living/carbon/human/proc/tie_hair)

/datum/species/human/get_bodytype(mob/living/carbon/human/H)
	return SPECIES_HUMAN

/datum/species/human/vatgrown
	spawn_flags = SPECIES_IS_RESTRICTED

/datum/species/human/vatgrown
	spawn_flags = SPECIES_IS_RESTRICTED

// === merged from station_chomp.dm during hard-fork de-suffix. Placed in this file because it
// is the highest-positioned definer in the override chain for the members it
// sets, so every override stays after its base definition (resolution preserved). ===
//Note that at the time of this PR we are simply disabling everything new to discuss keeping versus scrapping later.

/datum/species/human/gravworlder
	spawn_flags = SPECIES_IS_RESTRICTED

/datum/species/human/spacer
	spawn_flags = SPECIES_IS_RESTRICTED
