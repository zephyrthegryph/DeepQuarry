/////////////////////
/////SPIDER RACE/////
/////////////////////
/datum/species/spider //These actually look pretty damn spooky!
	name = SPECIES_VASILISSAN
	name_plural = "Vasilissans"
	icobase = 'icons/mob/human_races/r_spider.dmi'
	deform = 'icons/mob/human_races/r_def_spider.dmi'
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws, /datum/unarmed_attack/bite/sharp)
	darksight = 8		//Can see completely in the dark. They are spiders, after all. Not that any of this matters because people will be using custom race.
	// Small speedboost, as they've got a bunch of legs. Or something. I dunno.
	factor_baseline = alist(STAT_SLOWDOWN = -0.15, STAT_INCOMING_PHYSICAL = 0.8, STAT_INCOMING_THERMAL = 1.15)
	throwforce_absorb_threshold = 10

	num_alternate_languages = 3
	species_language = LANGUAGE_VESPINAE
	secondary_langs = list(LANGUAGE_VESPINAE)
	color_mult = 1
	tail = "tail" //Spider tail.
	icobase_tail = 1

	species_component = list(/datum/trait_state/weaver)

	inherent_verbs = list(
	/mob/living/carbon/human/proc/tie_hair)

	min_age = 18
	max_age = 80

	blurb = "Vasilissans are a tall, lanky, spider like people. \
	Each having four eyes, an extra four, large legs sprouting from their back, and a chitinous plating on their body, and the ability to spit webs \
	from their mandible lined mouths.  They are a recent discovery by Nanotrasen, only being discovered roughly seven years ago.  \
	Before they were found they built great cities out of their silk, being united and subjugated in warring factions under great Star Queens  \
	Who forced the working class to build huge, towering cities to attempt to reach the stars, which they worship as gems of great spiritual and magical significance."

	wikilink = "https://wiki.vore-station.net/Vasilissans"

	catalogue_data = list(/datum/category_item/catalogue/fauna/vasilissan)

	hazard_low_pressure = 20 //Prevents them from dying normally in space. Special code handled below.
	cold_level_1 = -1    // All cold debuffs are handled below in environment_effects
	cold_level_2 = -1
	cold_level_3 = -1


	flags = NO_MINOR_CUT
	spawn_flags = SPECIES_CAN_JOIN
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR | HAS_EYE_COLOR

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	flesh_color = "#AFA59E" //Gray-ish. Not sure if this is really needed, but eh.
	base_color 	= "#333333" //Blackish-gray
	blood_color = "#0952EF" //Spiders have blue blood.

	climb_mult = 0.75

/datum/species/spider/environment_effects(mob/living/carbon/human/H)
	if(H.stat == DEAD) // If they're dead they won't need anything.
		return

	if(H.body_temperature() <= 260) //If they're really cold, they go into stasis.
		var/coldshock = 0
		if(H.body_temperature() <= 260 && H.body_temperature() >= 200) //Chilly.
			coldshock = 4 //This will begin to knock them out until they run out of oxygen and suffocate or until someone finds them.
			H.status_set(STAT_BLURRY, 5) //Blurry vision in the cold.
		if(H.body_temperature() <= 199 && H.body_temperature() >= 100) //Extremely cold. Even in somewhere like the server room it takes a while for bodytemp to drop this low.
			coldshock = 8
			H.status_set(STAT_BLURRY, 5)
		if(H.body_temperature() <= 99) //Insanely cold.
			coldshock = 16
			H.status_set(STAT_BLURRY, 5)
		H.adjust_shock(coldshock, "spider cold") //cold hurts and gives them pain messages, eventually weakening and paralysing, but doesn't damage.
	..()
