/datum/species/skrell
	name = SPECIES_SKRELL
	name_plural = "Skrell"
	icobase = 'icons/mob/human_races/r_skrell_vr.dmi'
	deform = 'icons/mob/human_races/r_def_skrell_vr.dmi'
	primitive_form = SPECIES_MONKEY_SKRELL
	unarmed_types = list(/datum/unarmed_attack/punch)
	blurb = "An amphibious species, Skrell come from the star system known as Qerr'Vallis, which translates to 'Star of \
	the royals' or 'Light of the Crown'.<br/><br/>Skrell are a highly advanced and logical race who live under the rule \
	of the Qerr'Katish, a caste within their society which keeps the empire of the Skrell running smoothly. Skrell are \
	herbivores on the whole and tend to be co-operative with the other species of the galaxy, although they rarely reveal \
	the secrets of their empire to their allies."
	wikilink="https://wiki.chompstation13.net/index.php?title=Skrell" // link to our wiki
	catalogue_data = list(/datum/category_item/catalogue/fauna/skrell)
	num_alternate_languages = 3
	secondary_langs = list(LANGUAGE_SKRELLIAN, LANGUAGE_SCHECHI)
	name_language = LANGUAGE_SKRELLIAN
	species_language = LANGUAGE_SKRELLIAN
	assisted_langs = list(LANGUAGE_EAL, LANGUAGE_ROOTLOCAL, LANGUAGE_ROOTGLOBAL, LANGUAGE_VOX, LANGUAGE_PROMETHEAN)
	health_hud_intensity = 2
	chem_strength_alcohol = 0.2

	water_movement = -3

	min_age = 19 // Lore-based adulthood age for this species is greater than 18.
	max_age = 130

	economic_modifier = 10

	darksight = 4
	flash_mod = 1.2
	chemOD_mod = 0.9

	blood_reagents = REAGENT_ID_COPPER
	bloodloss_rate = 1.5

	ambiguous_genders = TRUE

	spawn_flags = SPECIES_CAN_JOIN
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR

	flesh_color = "#8CD7A3"
	blood_color = "#0081CD"
	base_color = "#006666"
	color_mult = 1

	cold_level_1 = 280 //Default 260 - Lower is better
	cold_level_2 = 220 //Default 200
	cold_level_3 = 130 //Default 120

	breath_cold_level_1 = 250	//Default 240 - Lower is better
	breath_cold_level_2 = 190	//Default 180
	breath_cold_level_3 = 120	//Default 100

	heat_level_1 = 420 //Default 360 - Higher is better
	heat_level_2 = 480 //Default 400
	heat_level_3 = 1100 //Default 1000

	breath_heat_level_1 = 400	//Default 380 - Higher is better
	breath_heat_level_2 = 500	//Default 450
	breath_heat_level_3 = 1350	//Default 1250

	reagent_tag = null //I am going to just NUKE reagent_tag omfg...This is ridiculous
	allergens = null

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	water_breather = TRUE
	water_movement = -4 //Negates shallow. Halves deep.

	has_limbs = list(
		BP_TORSO =  list("path" = /obj/item/organ/external/chest),
		BP_GROIN =  list("path" = /obj/item/organ/external/groin),
		BP_HEAD =   list("path" = /obj/item/organ/external/head/skrell),
		BP_L_ARM =  list("path" = /obj/item/organ/external/arm),
		BP_R_ARM =  list("path" = /obj/item/organ/external/arm/right),
		BP_L_LEG =  list("path" = /obj/item/organ/external/leg),
		BP_R_LEG =  list("path" = /obj/item/organ/external/leg/right),
		BP_L_HAND = list("path" = /obj/item/organ/external/hand),
		BP_R_HAND = list("path" = /obj/item/organ/external/hand/right),
		BP_L_FOOT = list("path" = /obj/item/organ/external/foot),
		BP_R_FOOT = list("path" = /obj/item/organ/external/foot/right)
		)

	has_organ = list(
		O_HEART =		/obj/item/organ/internal/heart/skrell,
		O_LUNGS =		/obj/item/organ/internal/lungs/skrell,
		O_VOICE = 		/obj/item/organ/internal/voicebox/skrell,
		O_LIVER =		/obj/item/organ/internal/liver/skrell,
		O_KIDNEYS =		/obj/item/organ/internal/kidneys/skrell,
		O_BRAIN =		/obj/item/organ/internal/brain/skrell,
		O_APPENDIX = 	/obj/item/organ/internal/appendix/skrell,
		O_SPLEEN = 		/obj/item/organ/internal/spleen/skrell,
		O_EYES =		/obj/item/organ/internal/eyes/skrell,
		O_STOMACH =		/obj/item/organ/internal/stomach/skrell,
		O_INTESTINE =	/obj/item/organ/internal/intestine/skrell
		)

	default_emotes = list(
		/datum/decl/emote/audible/warble,
		/datum/decl/emote/audible/lwarble,
		/datum/decl/emote/audible/croon,
		/datum/decl/emote/audible/croak
	)
	inherent_verbs = list(/mob/living/carbon/human/proc/tie_hair, /mob/living/carbon/human/proc/water_stealth, /mob/living/carbon/human/proc/underwater_devour)

/datum/species/skrell/can_breathe_water()
	return TRUE

/datum/species/skrell
	spawn_flags = SPECIES_CAN_JOIN
	icobase = 'icons/mob/human_races/r_skrell_vr.dmi'
	deform = 'icons/mob/human_races/r_def_skrell_vr.dmi'
	color_mult = 1
	min_age = 20
	inherent_verbs = list(/mob/living/carbon/human/proc/tie_hair, /mob/living/carbon/human/proc/water_stealth, /mob/living/carbon/human/proc/underwater_devour)
	reagent_tag = null
	allergens = null
	assisted_langs = list(LANGUAGE_EAL, LANGUAGE_ROOTLOCAL, LANGUAGE_ROOTGLOBAL, LANGUAGE_VOX, LANGUAGE_PROMETHEAN)
	genders = list(MALE, FEMALE, PLURAL, NEUTER)
	wikilink="https://wiki.vore-station.net/Skrell"

	water_breather = TRUE
	water_movement = -4 //Negates shallow. Halves deep.
