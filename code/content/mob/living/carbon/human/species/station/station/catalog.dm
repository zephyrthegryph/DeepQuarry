/datum/species/nevrean
	name = SPECIES_NEVREAN
	name_plural = "Nevreans"
	icobase = 'icons/mob/human_races/r_nevrean.dmi'
	deform = 'icons/mob/human_races/r_def_nevrean.dmi'
	tail = "tail"
	icobase_tail = 1
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws, /datum/unarmed_attack/bite/sharp)
	soft_landing = TRUE
	num_alternate_languages = 3
	secondary_langs = list(LANGUAGE_BIRDSONG)
	name_language = LANGUAGE_BIRDSONG
	species_language = LANGUAGE_BIRDSONG
	color_mult = 1
	inherent_verbs = list(/mob/living/proc/flying_toggle,
		/mob/living/proc/flying_vore_toggle,
		/mob/living/proc/start_wings_hovering,
		/mob/living/carbon/human/proc/tie_hair)
	min_age = 18
	max_age = 110

	blurb = "Nevreans are a race of avian and dinosaur-like creatures living on Tal. They belong to a group of races that hails from Eltus, \
	in the Vilous system. Unlike sergals whom they share a star system with, their species is a very peaceful one. They possess remarkable \
	intelligence and very skillful hands that are put use for constructing precision instruments, but tire-out fast when repeatedly working \
	over and over again. Consequently, they struggle to make copies of same things. Both genders have a voice that echoes a lot. Their natural \
	tone oscillates between tenor and soprano. They are excessively noisy when they quarrel in their native language."

	wikilink="https://wiki.vore-station.net/Backstory#Nevrean"

	catalogue_data = list(/datum/category_item/catalogue/fauna/nevrean)

	primitive_form = SPECIES_MONKEY_NEVREAN

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	spawn_flags = SPECIES_CAN_JOIN
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR | HAS_EYE_COLOR

	flesh_color = "#AFA59E"
	base_color = "#333333"

	heat_discomfort_strings = list(
		"Your fur prickles in the heat.",
		"You feel uncomfortably warm.",
		"Your overheated skin itches."
		)

/datum/species/vulpkanin
	name = SPECIES_VULPKANIN
	name_plural = "Vulpkanin"
	blurb = "Vulpkanin are a species of sharp-witted canine-pideds residing on the planet Altam just barely within the \
	dual-star Vazzend system. Their politically de-centralized society and independent natures have led them to become a species and \
	culture both feared and respected for their scientific breakthroughs. Discovery, loyalty, and utilitarianism dominates their lifestyles \
	to the degree it can cause conflict with more rigorous and strict authorities. They speak a guttural language known as 'Canilunzt' \
	which has a heavy emphasis on utilizing tail positioning and ear twitches to communicate intent."
	icobase = 'icons/mob/human_races/r_vulpkanin.dmi'
	deform = 'icons/mob/human_races/r_vulpkanin.dmi'
	secondary_langs = list(LANGUAGE_CANILUNZT)
	name_language = LANGUAGE_CANILUNZT
	species_language = LANGUAGE_CANILUNZT
	primitive_form = SPECIES_MONKEY_VULPKANIN
	tail = "vulptail"
	tail_animation = 'icons/mob/species/vulpkanin/tail.dmi'
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws, /datum/unarmed_attack/bite/sharp)
	darksight = 5
	num_alternate_languages = 3
	color_mult = 1
	inherent_verbs = list(/mob/living/carbon/human/proc/lick_wounds,
		/mob/living/carbon/human/proc/tie_hair)

	pain_verb_1p = list("yelp", "growl")
	pain_verb_3p = list("yelps", "growls")

	species_sounds = "Canine"

	wikilink="https://wiki.vore-station.net/Backstory#Vulpkanin"

	catalogue_data = list(/datum/category_item/catalogue/fauna/vulpkanin)

	//Furry fox-like animals shouldn't start freezing at 5 degrees celsius.
	//Minor cold is resisted, but not severe frost.
	cold_discomfort_level = 263 //Not as good at surviving the frost as tajara, but still better than humans.

	cold_level_1 = 243 //Default 260, other values remain at default. Starts taking damage at -30 celsius. Default tier 2 is -70 and tier 3 is -150


	breath_cold_level_1 = 220 // Default 240, lower is better.

	//While foxes can survive in deserts, that's handled by zorren. It's a good contrast that our vulp find heat a little uncomfortable.

	heat_discomfort_level = 295 //Just above standard 20 C to avoid heat message spam, same as Taj

	heat_level_1 = 345 //Default 360
	heat_level_2 = 390 //Default 400
	heat_level_3 = 900 //Default 1000

	breath_heat_level_1 = 370	//Default 380 - Higher is better
	breath_heat_level_2 = 445	//Default 450
	breath_heat_level_3 = 1125	//Default 1250

	primitive_form = SPECIES_MONKEY_VULPKANIN

	spawn_flags = SPECIES_CAN_JOIN
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR | HAS_EYE_COLOR

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	flesh_color = "#966464"
	base_color = "#B43214"

	min_age = 18
	max_age = 80

	heat_discomfort_strings = list(
		"Your fur prickles in the heat.",
		"You feel uncomfortably warm.",
		"Your overheated skin itches."
		)

/datum/species/harpy
	name = SPECIES_RAPALA
	name_plural = "Rapala"
	icobase = 'icons/mob/human_races/r_harpy_vr.dmi'
	deform = 'icons/mob/human_races/r_def_harpy_vr.dmi'
	tail = "tail"
	icobase_tail = 1
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/punch, /datum/unarmed_attack/bite)
	num_alternate_languages = 3
	secondary_langs = list(LANGUAGE_UNATHI)
	species_language = LANGUAGE_UNATHI
	name_language = LANGUAGE_UNATHI
	color_mult = 1
	genders = list(MALE, FEMALE, PLURAL, NEUTER)
	inherent_verbs = list(/mob/living/proc/flying_toggle,/mob/living/proc/flying_vore_toggle,/mob/living/proc/start_wings_hovering,/mob/living/carbon/human/proc/tie_hair)

	min_age = 19 //not a typo, Rapala consider adult age to be 19
	max_age = 80

	soft_landing = TRUE

	base_color = "#EECEB3"

	blurb = "A coincidentally humanlike species, Rapala are a client species of the Unathi that have \
	no genetic relation to humans in spite of the similar appearance. They have an unusual gene pairing of \
	XX and XY, and VW and WW. They are capable of in atmosphere flight and have organs \
	that make them more naturally attuned to learning the piloting of aircraft and spaceflight. Rapala \
	society is hierarchical and communal, although not every individual will agree with this status quo."

	wikilink="https://wiki.vore-station.net/Backstory#Rapala"

	catalogue_data = list(/datum/category_item/catalogue/fauna/rapala)

	spawn_flags = SPECIES_CAN_JOIN
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR | HAS_EYE_COLOR


	heat_discomfort_strings = list(
		"Your feathers prickle in the heat.",
		"You feel uncomfortably warm.",
		"Your overheated skin itches."
		)

//These species are not really species but are just there for custom species selection

/datum/species/fl_zorren
	name = SPECIES_FENNEC
	name_plural = "Fennec"
	icobase = 'icons/mob/human_races/r_fennec_vr.dmi'
	deform = 'icons/mob/human_races/r_def_fennec.dmi'
	tail = "tail"
	icobase_tail = 1
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws, /datum/unarmed_attack/bite/sharp)
	num_alternate_languages = 3
	secondary_langs = list(LANGUAGE_TERMINUS)
	name_language = LANGUAGE_TERMINUS
	species_language = LANGUAGE_TERMINUS
	inherent_verbs = list(/mob/living/carbon/human/proc/lick_wounds,/mob/living/proc/shred_limb,/mob/living/carbon/human/proc/tie_hair)

	min_age = 18
	max_age = 80

	species_sounds = "Vulpine"

	spawn_flags = SPECIES_IS_RESTRICTED
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR | HAS_EYE_COLOR
	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	flesh_color = "#AFA59E"
	base_color = "#333333"
	blood_color = "#240bc4"
	color_mult = 1

	heat_discomfort_strings = list(
		"Your fur prickles in the heat.",
		"You feel uncomfortably warm.",
		"Your overheated skin itches."
		)

/datum/species/xenohybrid
	name = SPECIES_XENOHYBRID
	name_plural = "Xenomorphs"
	icobase = 'icons/mob/human_races/r_xenomorph.dmi'
	deform = 'icons/mob/human_races/r_def_xenomorph.dmi'
	tail = "tail"
	icobase_tail = 1
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws, /datum/unarmed_attack/bite/sharp)
	darksight = 4 //Better hunters in the dark.
	hunger_factor = 0.1 //In exchange, they get hungry a tad faster.
	num_alternate_languages = 3

	min_age = 18
	max_age = 80

	blurb = "Xenomorphs hybrids are a mixture of xenomorph DNA and some other humanoid species. \
	Xenomorph hyrids mostly have had had their natural aggression removed due to the gene modification process \
	although there are some exceptions, such as when they are harmed. Most xenomorph hybrids are female, due to their natural xenomorph genes, \
	but there are multiple exceptions. All xenomorph hybrids have had their ability to lay eggs containing facehuggers \
	removed if they had the ability to, although hybrids that previously contained this ability is extremely rare."
	// No wiki page for xenohybrids at present


	spawn_flags = SPECIES_IS_RESTRICTED
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR | HAS_EYE_COLOR
	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	blood_color = "#12ff12"
	flesh_color = "#201730"
	base_color = "#201730"

	heat_discomfort_strings = list(
		"Your chitin feels extremely warm.",
		"You feel uncomfortably warm.",
		"Your chitin feels hot."
		)

/datum/species/altevian
	name = SPECIES_ALTEVIAN
	name_plural = "Altevians"
	icobase = 'icons/mob/human_races/r_altevian.dmi'
	deform = 'icons/mob/human_races/r_altevian.dmi'
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws, /datum/unarmed_attack/bite/sharp)
	num_alternate_languages = 3
	secondary_langs = list(LANGUAGE_TAVAN)
	species_language = LANGUAGE_TAVAN
	name_language = null
	color_mult = 1
	inherent_verbs = list(/mob/living/carbon/human/proc/tie_hair)

	min_age = 18
	max_age = 80

	species_sounds = "Mouse"

	blurb = "The Altevian are a species of tall, rodent humanoids that are akin to rats for their features. \
	The Altevian, unlike most species, do not have a home planet, nor system, adopting a fully nomadic lifestyle \
	for their survival across the stars. Instead, they have opted to live in massive super capital-class colony-ships \
	with a flagship as their place they would call home."

	wikilink="https://wiki.vore-station.net/Altevian"

	catalogue_data = list(/datum/category_item/catalogue/fauna/altevian)

	spawn_flags = SPECIES_CAN_JOIN
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR | HAS_EYE_COLOR

	flesh_color = "#AFA59E"
	base_color = "#777777"

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	factor_baseline = alist(STAT_INCOMING_THERMAL = 1.15)
	hunger_factor = 0.04
	can_zero_g_move = TRUE

	heat_discomfort_strings = list(
		"Your fur prickles in the heat.",
		"You feel uncomfortably warm.",
		"Your overheated skin itches."
		)

	has_limbs = list(
		BP_TORSO =  list("path" = /obj/item/organ/external/chest),
		BP_GROIN =  list("path" = /obj/item/organ/external/groin),
		BP_HEAD =   list("path" = /obj/item/organ/external/head),
		BP_L_ARM =  list("path" = /obj/item/organ/external/arm),
		BP_R_ARM =  list("path" = /obj/item/organ/external/arm/right),
		BP_L_LEG =  list("path" = /obj/item/organ/external/leg),
		BP_R_LEG =  list("path" = /obj/item/organ/external/leg/right),
		BP_L_HAND = list("path" = /obj/item/organ/external/hand),
		BP_R_HAND = list("path" = /obj/item/organ/external/hand/right),
		BP_L_FOOT = list("path" = /obj/item/organ/external/foot),
		BP_R_FOOT = list("path" = /obj/item/organ/external/foot/right)
		)

/datum/species/werebeast
	name = SPECIES_WEREBEAST
	name_plural = "Werebeasts"
	icobase = 'icons/mob/human_races/r_werebeast.dmi'
	deform = 'icons/mob/human_races/r_werebeast.dmi'
	icon_template = 'icons/mob/human_races/r_werebeast.dmi'
	tail = "tail"
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws, /datum/unarmed_attack/bite/sharp)
	total_health = 200
	factor_baseline = alist(STAT_METABOLISM_MULT = 2, STAT_INCOMING_PHYSICAL = 0.85, STAT_INCOMING_THERMAL = 0.85)
	item_slowdown_mod = 0.25
	hunger_factor = 0.4
	darksight = 8
	mob_size = MOB_LARGE
	num_alternate_languages = 3
	secondary_langs = list(LANGUAGE_CANILUNZT)
	name_language = LANGUAGE_CANILUNZT
	species_language = LANGUAGE_CANILUNZT
	primitive_form = SPECIES_MONKEY_VULPKANIN
	color_mult = 1
	icon_height = 64
	can_climb = TRUE
	climbing_delay = 1

	min_age = 18
	max_age = 200

	species_sounds = "Canine"

	blurb = "Big buff werewolves. These are a limited functionality event species that are not balanced for regular gameplay. Adminspawn only."

	wikilink="N/A"

	catalogue_data = list(/datum/category_item/catalogue/fauna/vulpkanin)

	spawn_flags		 = SPECIES_CAN_JOIN | SPECIES_IS_WHITELISTED | SPECIES_WHITELIST_SELECTABLE
	appearance_flags = HAS_HAIR_COLOR | HAS_SKIN_COLOR | HAS_EYE_COLOR

	flesh_color = "#AFA59E"
	base_color = "#777777"

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	heat_discomfort_strings = list(
		"Your fur prickles in the heat.",
		"You feel uncomfortably warm.",
		"Your overheated skin itches."
		)

	has_limbs = list(
		BP_TORSO =  list("path" = /obj/item/organ/external/chest),
		BP_GROIN =  list("path" = /obj/item/organ/external/groin),
		BP_HEAD =   list("path" = /obj/item/organ/external/head/werebeast),
		BP_L_ARM =  list("path" = /obj/item/organ/external/arm),
		BP_R_ARM =  list("path" = /obj/item/organ/external/arm/right),
		BP_L_LEG =  list("path" = /obj/item/organ/external/leg),
		BP_R_LEG =  list("path" = /obj/item/organ/external/leg/right),
		BP_L_HAND = list("path" = /obj/item/organ/external/hand),
		BP_R_HAND = list("path" = /obj/item/organ/external/hand/right),
		BP_L_FOOT = list("path" = /obj/item/organ/external/foot),
		BP_R_FOOT = list("path" = /obj/item/organ/external/foot/right)
		)

/datum/species/sparkledog //Exists primarily as an april fools joke, along with everything tied to it!
	name = SPECIES_SPARKLE
	name_plural = "Sparklies"
	icobase = 'icons/mob/human_races/r_sparkle.dmi'
	icobase_tail = 1
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws, /datum/unarmed_attack/bite/sharp)
	factor_baseline = alist(STAT_SLOWDOWN = -0.5, STAT_INCOMING_PHYSICAL = 1.5, STAT_INCOMING_THERMAL = 1.5, STAT_INCOMING_TOXIC = 0.5)
	radiation_mod = 0
	bloodloss_rate = 1.5
	flash_mod =     2
	siemens_coefficient = 10

	darksight = 2

	num_alternate_languages = 3
	language = LANGUAGE_SPARKLE
	species_language = LANGUAGE_SPARKLE
	secondary_langs = list(LANGUAGE_SPARKLE, LANGUAGE_SOL_COMMON)
	color_mult = 1
	assisted_langs = list(LANGUAGE_EAL, LANGUAGE_ROOTLOCAL, LANGUAGE_ROOTGLOBAL, LANGUAGE_VOX, LANGUAGE_PROMETHEAN)
	inherent_verbs = list(/mob/living/carbon/human/proc/tie_hair, /mob/living/proc/toggle_sparkles, /mob/living/proc/healing_rainbows, /mob/living/carbon/human/proc/play_dead)
	min_age = 18
	max_age = 21

	pass_flags = PASSTABLE

	blurb = "Th3 ultimate lifeform, th3 l@st of th3 sp@rkl3 d0gg0s. M0r3 p0w3rful th@nn @ny 0th3r sp3ci3s in th3 3ntir3 un1v3rs3!!! When 3v3ryth1ng is crashing d0wn, y0u c@nn always r3ly 0n th3m to s@v3 th3 d@y. N0 0n3 3ls3 h@s th@t k1nd of str3ngth. R@wr XD #sp@rkl3d0gg0 #s@v1ngth3d@y #n0b0dyc@r3s"

	wikilink="https://wiki.vore-station.net/"

	primitive_form = SPECIES_MONKEY_VULPKANIN

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	spawn_flags = SPECIES_CAN_JOIN | SPECIES_IS_WHITELISTED | SPECIES_WHITELIST_SELECTABLE
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_EYE_COLOR

	flesh_color = "#ffffff"
	base_color = "#ffffff"
	blood_color = "#ff00d9"

/datum/species/fl_zorren
	item_slowdown_mod = 1.2
	factor_baseline = alist(STAT_SLOWDOWN = -0.2, STAT_INCOMING_PHYSICAL = 1.1, STAT_INCOMING_THERMAL = 0.9)

	cold_level_1 = 270 //Default 260 - Lower is better
	cold_level_2 = 210 //Default 200
	cold_level_3 = 120 //Default 120

	breath_cold_level_1 = 250	//Default 240 - Lower is better
	breath_cold_level_2 = 190	//Default 180
	breath_cold_level_3 = 100	//Default 100

	heat_level_1 = 400 //Default 360 - Higher is better
	heat_level_2 = 460 //Default 400
	heat_level_3 = 1080 //Default 1000

	breath_heat_level_1 = 430	//Default 380 - Higher is better
	breath_heat_level_2 = 510	//Default 450
	breath_heat_level_3 = 1200	//Default 1250

/datum/species/shadekin_yw
	spawn_flags = SPECIES_IS_RESTRICTED
