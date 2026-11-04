/datum/species/teshari
	name = SPECIES_TESHARI
	micro_carry = TRUE
	name_plural = "Tesharii"
	blurb = "A race of feathered raptors who developed alongside the Skrell, inhabiting \
	the polar tundral regions outside of Skrell territory. Extremely fragile, they developed \
	hunting skills that emphasized taking out their prey without themselves getting hit. They \
	are known for their communalism and pack based family structures."
	wikilink="https://wiki.chompstation13.net/index.php?title=Teshari" // link to our wiki
	catalogue_data = list(/datum/category_item/catalogue/fauna/teshari)

	num_alternate_languages = 3
	secondary_langs = list(LANGUAGE_SCHECHI, LANGUAGE_SKRELLIAN)
	name_language = LANGUAGE_SCHECHI
	species_language = LANGUAGE_SCHECHI

	min_age = 18
	max_age = 80

	economic_modifier = 6 //I noticed this and the other mods were not the same, but we use ECO_MODIFIER for our calculation instead on virgo. In case anyone finds this and wonders why tesh are getting 60% of the pay (they aren't)

	health_hud_intensity = 3

	species_sounds = "Teshari"
	center_offset = 0

	blood_color = "#D514F7"
	flesh_color = "#5F7BB0"
	base_color = "#001144"
	color_mult = 1
	tail = "seromitail"
	icobase_tail = 1
	reagent_tag = IS_TESHARI

	move_trail = /obj/effect/decal/cleanable/blood/tracks/paw

	icobase = 'icons/mob/human_races/r_teshari_vr.dmi'
	deform = 'icons/mob/human_races/r_teshari_vr.dmi'
	damage_overlays = 'icons/mob/human_races/masks/dam_teshari.dmi'
	damage_mask = 'icons/mob/human_races/masks/dam_mask_teshari.dmi'
	blood_mask = 'icons/mob/human_races/masks/blood_teshari.dmi'
	suit_storage_icon = 'icons/inventory/suit_store/mob_teshari.dmi'
	vore_belly_default_variant = "T" //Teshari belly sprite

	fire_icon_state = "generic" // Humanoid is too big for them and spriting a new one is really annoying.

	factor_baseline = alist(STAT_SLOWDOWN = -1)
	snow_movement = -2	// Ignores light snow
	item_slowdown_mod = 2	// Tiny birds don't like heavy things
	total_health = 75
	mob_size = MOB_MEDIUM
	pass_flags = PASSTABLE
	holder_type = /obj/item/holder/micro
	has_vibration_sense = TRUE
	blood_volume = 400
	hunger_factor = 0.2
	soft_landing = TRUE
	agility = 90

	ambiguous_genders = TRUE
	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	spawn_flags = SPECIES_CAN_JOIN
	appearance_flags = HAS_HAIR_COLOR | HAS_SKIN_COLOR | HAS_EYE_COLOR

	body_temperature = 270

	cold_level_1 = 180	//Default 260
	cold_level_2 = 130	//Default 200
	cold_level_3 = 70	//Default 120

	breath_cold_level_1 = 180	//Default 240 - Lower is better
	breath_cold_level_2 = 100	//Default 180
	breath_cold_level_3 = 60	//Default 100

	heat_level_1 = 330	//Default 360
	heat_level_2 = 370	//Default 400
	heat_level_3 = 600	//Default 1000

	breath_heat_level_1 = 350	//Default 380 - Higher is better
	breath_heat_level_2 = 400	//Default 450
	breath_heat_level_3 = 800	//Default 1250

	heat_discomfort_level = 295
	heat_discomfort_strings = list(
		"Your feathers prickle in the heat.",
		"You feel uncomfortably warm.",
		"Your hands and feet feel hot as your body tries to regulate heat",
		)
	cold_discomfort_level = 180
	cold_discomfort_strings = list(
		"You feel a bit chilly.",
		"You fluff up your feathers against the cold.",
		"You move your arms closer to your body to shield yourself from the cold.",
		"You press your ears against your head to conserve heat",
		"You start to feel the cold on your skin",
		)

	minimum_breath_pressure = 12	//Smaller, so needs less air

	has_limbs = list(
		BP_TORSO =  list("path" = /obj/item/organ/external/chest),
		BP_GROIN =  list("path" = /obj/item/organ/external/groin),
		BP_HEAD =   list("path" = /obj/item/organ/external/head/teshari),
		BP_L_ARM =  list("path" = /obj/item/organ/external/arm),
		BP_R_ARM =  list("path" = /obj/item/organ/external/arm/right),
		BP_L_LEG =  list("path" = /obj/item/organ/external/leg),
		BP_R_LEG =  list("path" = /obj/item/organ/external/leg/right),
		BP_L_HAND = list("path" = /obj/item/organ/external/hand/teshari),
		BP_R_HAND = list("path" = /obj/item/organ/external/hand/right/teshari),
		BP_L_FOOT = list("path" = /obj/item/organ/external/foot/teshari),
		BP_R_FOOT = list("path" = /obj/item/organ/external/foot/right/teshari)
		)

	has_organ = list(
		O_HEART =		/obj/item/organ/internal/heart,
		O_LUNGS =		/obj/item/organ/internal/lungs,
		O_VOICE =		/obj/item/organ/internal/voicebox,
		O_LIVER =		/obj/item/organ/internal/liver,
		O_KIDNEYS =		/obj/item/organ/internal/kidneys,
		O_SPLEEN =		/obj/item/organ/internal/spleen,
		O_BRAIN =		/obj/item/organ/internal/brain,
		O_EYES =		/obj/item/organ/internal/eyes,
		O_STOMACH =		/obj/item/organ/internal/stomach,
		O_INTESTINE =	/obj/item/organ/internal/intestine
		)

	unarmed_types = list(
		/datum/unarmed_attack/claws,
		/datum/unarmed_attack/bite/sharp,
		/datum/unarmed_attack/stomp/weak
		)

	inherent_verbs = list(
		/mob/living/proc/hide,
		/mob/living/proc/toggle_pass_table
		)

	default_emotes = list(
		/datum/decl/emote/audible/teshsqueak,
		/datum/decl/emote/audible/teshchirp,
		/datum/decl/emote/audible/teshtrill
	)

	footstep = FOOTSTEP_MOB_TESHARI

/datum/species/teshari/equip_survival_gear(mob/living/carbon/human/H)
	..()
	H.equip_to_slot_or_del(new /obj/item/clothing/shoes/sandal(H),SLOT_ID_SHOES)
