/// XENOCHIMERA
/datum/species/xenochimera //Scree's race.
	name = SPECIES_XENOCHIMERA
	name_plural = "Xenochimeras"
	icobase = 'icons/mob/human_races/r_xenochimera.dmi'
	deform = 'icons/mob/human_races/r_def_xenochimera.dmi'
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws/chimera, /datum/unarmed_attack/bite/sharp)
	darksight = 8		//critters with instincts to hide in the dark need to see in the dark - about as good as tajara.
	// scuttly, but not as scuttly as a tajara or a teshari.
	factor_baseline = alist(STAT_SLOWDOWN = -0.2, STAT_INCOMING_PHYSICAL = 0.8, STAT_INCOMING_THERMAL = 1.15)
	base_species = "Xenochimera"
	selects_bodytype = SELECTS_BODYTYPE_CUSTOM
	has_vibration_sense = TRUE

	num_alternate_languages = 3
	species_language = null
	secondary_langs = list("Sol Common")
	tail = "tail"
	icobase_tail = 1
	inherent_verbs = list(
		/mob/living/carbon/human/proc/sonar_ping,
		/mob/living/carbon/human/proc/tie_hair,
		/mob/living/carbon/human/proc/lick_wounds,
		/mob/living/carbon/human/proc/shapeshifter_reassemble)		//Xenochimera get all the special verbs since they can't select traits.
		// Lick Wounds Verb, reform verb

	virus_immune = 1 // They practically ARE one.
	min_age = 18
	max_age = 80

	species_sounds = "Unset" // Chimera get a default/safety of unset, going off their icon base if there's none overriding.

	blurb = "Some amalgamation of different species from across the universe,with extremely unstable DNA, making them unfit for regular cloners. \
	Widely known for their voracious nature and violent tendencies when stressed or left unfed for long periods of time. \
	Most, if not all chimeras possess the ability to undergo some type of regeneration process, at the cost of energy."

	wikilink = "https://wiki.vore-station.net/Xenochimera"

	catalogue_data = list(/datum/category_item/catalogue/fauna/xenochimera)

	hazard_low_pressure = -1 //Prevents them from dying normally in space. Special code handled below.
	cold_level_1 = -1     // All cold debuffs are handled below in environment_effects
	cold_level_2 = -1
	cold_level_3 = -1


	spawn_flags = SPECIES_CAN_JOIN | SPECIES_IS_WHITELISTED | SPECIES_WHITELIST_SELECTABLE//Whitelisted as restricted is broken.
	flags = NO_SLEEVE | NO_DNA | NO_INFECT // | NO_DEFIB // Dying as a chimera is, quite literally, a death sentence. Well, if it wasn't for their revive, that is. Leaving NO_DEFIB there for the future/in case reversion to old 'chimera no-defib.
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR | HAS_EYE_COLOR

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	has_organ = list(    //Same organ list as tajarans, except for their SPECIAL BRAIN.
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

	flesh_color = "#AFA59E"
	base_color 	= "#333333"
	blood_color = "#14AD8B"

	reagent_tag = IS_CHIMERA

	species_component = list(/datum/xenochimera)

/datum/species/xenochimera/environment_effects(mob/living/carbon/human/H)
	//Cold/pressure effects when not regenerating
	if(!isturf(H.loc))
		return
	var/datum/gas_mixture/environment = H.loc.return_air()
	if(!environment)
		return
	var/pressure2 = environment.return_pressure()
	var/adjusted_pressure2 = H.calculate_affecting_pressure(pressure2)

	//Very low pressure damage
	if(adjusted_pressure2 <= 20)
		H.injure(INJURY_BLUNT, LOW_PRESSURE_DAMAGE) // Decompression
	//they handle areas where they can't breathe better than most, but it still lowers their effective health as well as all the other bad stuff that comes with unbreathable environments
	if(H.oxygen_debt() >= 50)
		H.set_does_not_breathe(TRUE)

	//Cold hurts and gives them pain messages, eventually weakening and paralysing, but doesn't damage or trigger feral.
	//NB: 'body_temperature' used here is the 'setpoint' species var
	var/temp_diff = body_temperature - H.body_temperature()
	if(temp_diff >= 50)
		H.adjust_shock(temp_diff/20, "xenochimera cold") // Divided by 20 is the same as previous numbers, but a full scale
		H.status_at_least(STAT_BLURRY, 5)
	..()

/datum/species/xenochimera/get_race_key()
	var/datum/species/real = GLOB.all_species[base_species]
	return real.race_key
