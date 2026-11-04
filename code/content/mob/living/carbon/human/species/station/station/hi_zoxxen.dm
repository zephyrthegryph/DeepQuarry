/datum/species/hi_zoxxen
	name = SPECIES_ZORREN_HIGH
	name_plural = "Zorren"
	icobase = 'icons/mob/human_races/r_fox_light_vr.dmi'
	deform = 'icons/mob/human_races/r_fox.dmi'
	tail = "tail"
	icobase_tail = 1
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws, /datum/unarmed_attack/bite/sharp)
	num_alternate_languages = 3
	secondary_langs = list(LANGUAGE_TERMINUS)
	name_language = LANGUAGE_TERMINUS
	species_language = LANGUAGE_TERMINUS
	inherent_verbs = list(/mob/living/carbon/human/proc/lick_wounds,
		/mob/living/proc/shred_limb,
		/mob/living/carbon/human/proc/tie_hair)

	min_age = 20
	max_age = 80

	species_sounds = "Vulpine"

	blurb = "The fennec-like, blue-blooded Zorren are native to Virgo 4/Menhir and are descendants of a precursor species \
			that is thought to be responsible for the near-collapse of the biosphere of the planet. \
			With societies organised around hierarchal caste systems (such as the Royal Zorren) or freedom and strength (such as the Free Tribe Zorren), \
			they now slowly recover from their previous hubris and aim to revitalize their planet. While many Zorren live in pre-industrial conditions by necessity, \
			they are an interstellar species known for their pride and stubbornness and doggedly hold out on a Deathworld of their own creation. \
			As local species, they hold moderate sway on local corporations and are hired by NT and other companies, although they find \"Outlander\" culture deeply weird."
	wikilink="https://wiki.chompstation13.net/index.php?title=Zorren" // link to our wiki

	catalogue_data = list(/datum/category_item/catalogue/fauna/zorren)


	spawn_flags = SPECIES_CAN_JOIN
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR | HAS_EYE_COLOR
	flesh_color = "#AFA59E"
	base_color = "#333333"
	blood_color = "#240bc4"
	blood_reagents = REAGENT_ID_COPPER
	reagent_tag = IS_ZORREN
	color_mult = 1
	default_custom_base = SPECIES_ZORREN_HIGH

	selects_bodytype = SELECTS_BODYTYPE_ZORREN

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	heat_discomfort_strings = list(
		"Your fur prickles in the heat.",
		"You feel uncomfortably warm.",
		"Your overheated skin itches."
		)

/datum/species/hi_zoxxen/get_race_key()
	var/datum/species/real = GLOB.all_species[base_species]
	return real.race_key

/datum/species/hi_zoxxen/dark    //alternate sprite base for zorren
	name = SPECIES_ZORREN_DARK
	icobase = 'icons/mob/human_races/r_fox_vr.dmi'
	spawn_flags = SPECIES_IS_RESTRICTED

//So both of this are based off Fennec foxes I belivive. Those are desert critters, giving them more warm focused levels. And for variety giving them minor brute weakness and minor burn resistant
//I also want to make a dig because fennec foxes actually make burrows and such, but I can't figure out how to do it in a way that is both flavorful but not abuseable
/datum/species/hi_zoxxen //zorrens get wierd chemistry because of their past of expirementing on themselves. Check the cataloguer for deathclaws
	chemOD_threshold =		0.75
	factor_baseline = alist(STAT_INCOMING_PHYSICAL = 1.1, STAT_INCOMING_THERMAL = 0.9)
	radiation_mod = 0.5

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
