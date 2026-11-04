/datum/species/unathi
	name = SPECIES_UNATHI
	name_plural = "Unathi"
	icobase = 'icons/mob/human_races/r_lizard_vr.dmi'
	deform = 'icons/mob/human_races/r_def_lizard_vr.dmi'
	tail_animation = 'icons/mob/species/unathi/tail_vr.dmi'
	tail = "sogtail"
	vore_belly_default_variant = "L"
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws, /datum/unarmed_attack/bite/sharp)
	primitive_form = SPECIES_MONKEY_UNATHI
	darksight = 3
	ambiguous_genders = TRUE
	factor_baseline = alist(STAT_METABOLISM_MULT = 0.85, STAT_SLOWDOWN = 0.5, STAT_INCOMING_PHYSICAL = 0.85, STAT_INCOMING_THERMAL = 0.85)
	total_health = 125
	item_slowdown_mod = 0.25
	mob_size = MOB_MEDIUM
	blood_volume = 840
	bloodloss_rate = 0.75
	num_alternate_languages = 3
	secondary_langs = list(LANGUAGE_UNATHI)
	name_language = LANGUAGE_UNATHI
	species_language = LANGUAGE_UNATHI
	health_hud_intensity = 2.5
	chem_strength_alcohol = 1.25
	throwforce_absorb_threshold = 10
	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	min_age = 40 // Unathi lore minimal adult age.
	max_age = 260

	economic_modifier = 10

	species_sounds = "Lizard" // Species sounds

	pain_verb_1p = list("hiss", "growl")
	pain_verb_3p = list("hisses", "growls")

	blurb = "Heavily reptilian in appearance, the Unathi hail from the Uueoa-Esa system, roughly translated as 'Burning Mother'. \
			Their home planet, Moghes, is an arid climate with hot rocky plains and deserts, and a temperate band of swamps and savannas with \
			massive saltwater lakes being the closest equivalent to oceans. This environment bred a very hardy people who value ideals of honesty, \
			virtue, proficiency and bravery above all else, frequently even one's own life. These same values lend them culturally to imperialistic \
			politics, as well as often being viewed as haughty and arrogant by other interstellar species.<br><br>\
			On the stage of the interstellar political realm the Unathi are noteworthy contenders, the Moghes Hegemony possesses vast technological and \
			material prowess when compared to human contemporaries such as the Sol-Procyon Commonwealth or Ares Confederation. The Hegemony War nearly one \
			hundred years ago is a prime example of this, having engaged in brutal warfare that ultimately fell to a stalemate between all involved parties. \
			Nowadays relations remain cool and somewhat tense, although this does not prevent individual Unathi from finding reasonable career success within Human space."

	catalogue_data = list(/datum/category_item/catalogue/fauna/unathi)

	cold_level_1 = 280 //Default 260 - Lower is better
	cold_level_2 = 220 //Default 200
	cold_level_3 = 130 //Default 120

	breath_cold_level_1 = 260	//Default 240 - Lower is better
	breath_cold_level_2 = 200	//Default 180
	breath_cold_level_3 = 120	//Default 100

	heat_level_1 = 420 //Default 360 - Higher is better
	heat_level_2 = 480 //Default 400
	heat_level_3 = 1100 //Default 1000

	breath_heat_level_1 = 450	//Default 380 - Higher is better
	breath_heat_level_2 = 530	//Default 450
	breath_heat_level_3 = 1400	//Default 1250

	minimum_breath_pressure = 18	//Bigger, means they need more air

	body_temperature = T20C

	spawn_flags = SPECIES_CAN_JOIN
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR | HAS_EYE_COLOR

	flesh_color = "#34AF10"
	blood_color = "#b3cbc3"
	base_color = "#066000"
	color_mult = 1

	reagent_tag = IS_UNATHI

	move_trail = /obj/effect/decal/cleanable/blood/tracks/claw

	has_limbs = list(
		BP_TORSO =  list("path" = /obj/item/organ/external/chest/unathi),
		BP_GROIN =  list("path" = /obj/item/organ/external/groin/unathi),
		BP_HEAD =   list("path" = /obj/item/organ/external/head/unathi),
		BP_L_ARM =  list("path" = /obj/item/organ/external/arm),
		BP_R_ARM =  list("path" = /obj/item/organ/external/arm/right),
		BP_L_LEG =  list("path" = /obj/item/organ/external/leg),
		BP_R_LEG =  list("path" = /obj/item/organ/external/leg/right),
		BP_L_HAND = list("path" = /obj/item/organ/external/hand),
		BP_R_HAND = list("path" = /obj/item/organ/external/hand/right),
		BP_L_FOOT = list("path" = /obj/item/organ/external/foot),
		BP_R_FOOT = list("path" = /obj/item/organ/external/foot/right)
		)

	//No kidneys or appendix
	has_organ = list(
		O_HEART =		/obj/item/organ/internal/heart/unathi,
		O_LUNGS =		/obj/item/organ/internal/lungs/unathi,
		O_LIVER =		/obj/item/organ/internal/liver/unathi,
		O_SPLEEN =		/obj/item/organ/internal/spleen,
		O_BRAIN =		/obj/item/organ/internal/brain/unathi,
		O_EYES =		/obj/item/organ/internal/eyes/unathi,
		O_STOMACH =		/obj/item/organ/internal/stomach/unathi,
		O_INTESTINE =	/obj/item/organ/internal/intestine/unathi
		)


	heat_discomfort_level = 320 // 46c (higher than normal humans) Don't spam red text if you're slightly warm.
	heat_discomfort_strings = list(
		"You feel soothingly warm.",
		"You feel the heat sink into your bones.",
		"You feel warm enough to take a nap."
		)

	cold_discomfort_level = 288.15 // 15c Give a little bit of wiggle room here come on.
	cold_discomfort_strings = list(
		"You feel chilly.",
		"You feel sluggish and cold.",
		"Your scales bristle against the cold."
		)

	default_emotes = list(
		/datum/decl/emote/human/swish,
		/datum/decl/emote/human/wag,
		/datum/decl/emote/human/sway,
		/datum/decl/emote/human/qwag,
		/datum/decl/emote/human/fastsway,
		/datum/decl/emote/human/swag,
		/datum/decl/emote/human/stopsway
	)

	footstep = FOOTSTEP_MOB_CLAW

	inherent_verbs = list(/mob/living/carbon/human/proc/tie_hair)
	wikilink="https://wiki.chompstation13.net/index.php?title=Unathi" //CHOMPSedit: link to our wiki

/datum/species/unathi/equip_survival_gear(mob/living/carbon/human/H)
	..()
	H.equip_to_slot_or_del(new /obj/item/clothing/shoes/sandal(H),SLOT_ID_SHOES)
