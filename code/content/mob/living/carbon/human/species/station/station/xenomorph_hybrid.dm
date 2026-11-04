/datum/species/xenomorph_hybrid
	name = SPECIES_XENOMORPH_HYBRID
	name_plural = "Xenomorph Hybrids"
	icobase = 'icons/mob/human_races/r_xenomorph_hybrid.dmi'
	deform = 'icons/mob/human_races/r_xenomorph_hybrid.dmi'
	tail = "tail"
	icobase_tail = 1
	ambiguous_genders = TRUE
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/claws/strong/xeno, /datum/unarmed_attack/bite/strong/xeno) // Innate claws and bite.

	total_health = 150 // Larger health pool.
	// Fire does not mix well with their silicon carapace. (burn)
	// Resistant to toxins. (toxins)
	trauma_mod = 0.3 // Highly resistant to pain.
	// Highly resistant to pain. (pain)
	rad_removal_mod = 1.5 // Radiation leaves the body much faster.
	chem_strength_heal = 0.1 // Acidic blood neutralizes most injected and ingested beneficial chemicals.
	// Very physically active species, thus requiring more nutritional intake.
	factor_baseline = alist(STAT_METABOLISM_MULT = 1.3, STAT_INCOMING_THERMAL = 2, STAT_INCOMING_TOXIC = 0.5, STAT_INCOMING_PAIN = 0.3)
	chem_strength_alcohol = 1.2 // They don't handle their drinks very well.
	throwforce_absorb_threshold = 10 // Thrown objects don't do as much.
	darksight = 10 // Full view darksight.
	soft_landing = TRUE // Nimble, flexible and tough enough to walk off falls from greater heights.

	cold_level_1 = 150	//Default 260
	cold_level_2 = 100	//Default 200
	cold_level_3 = 50	//Default 120

	breath_cold_level_1 = 140	//Default 240
	breath_cold_level_2 = 90	//Default 180
	breath_cold_level_3 = 40	//Default 100

	heat_level_1 = 380	//Default 360
	heat_level_2 = 420	//Default 400
	heat_level_3 = 1020	//Default 1000

	breath_heat_level_1 = 390	//Default 380
	breath_heat_level_2 = 460	//Default 450
	breath_heat_level_3 = 1260	//Default 1250

	heat_discomfort_level = 320 // 46 Celsius, not so comfortable in high temperatures.
	heat_discomfort_strings = list(
		"The heat bites through our chitin.",
		"The warmth irritates our body.",
		"The balmy air feels like an oven."
		)

	cold_discomfort_level = 200 // -73 Celsius, very comfortable in below freezing temperatures.
	cold_discomfort_strings = list(
		"The cold bites through our chitin.",
		"Ice forms on our exoskeleton.",
		"The freezing air induces a shiver."
		)

	hazard_low_pressure = HAZARD_LOW_PRESSURE*0 // Xenomorph Hybrids are immune to space, but still need to breathe.
	warning_low_pressure = WARNING_LOW_PRESSURE*0

	mob_size = MOB_MEDIUM // Technically doesn't even need this but still adding the override just in case.
	num_alternate_languages = 3
	name_language = LANGUAGE_XENOLINGUA
	species_language = LANGUAGE_XENOLINGUA
	secondary_langs = list(LANGUAGE_XENOLINGUA, LANGUAGE_HIVEMIND)
	assisted_langs = list(LANGUAGE_EAL, LANGUAGE_SKRELLIAN, LANGUAGE_ROOTLOCAL, LANGUAGE_ROOTGLOBAL, LANGUAGE_VOX, LANGUAGE_PROMETHEAN) // Can use the Hivemind language.
	color_mult = 1
	health_hud_intensity = 1.5

	economic_modifier = 5 // While they aren't true Xenomorphs, they still draw a lot of social stigma, and are generally mistreated and underpaid as a result.
	rarity_value = 4 // Very rare to find these guys on human stations.

	spawn_flags = SPECIES_CAN_JOIN
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR | HAS_EYE_COLOR

	flesh_color = "#242424"
	blood_color = "#00C202"
	base_color = "#242424"

	blurb = "Xenomorph Hybrids are a strange amalgamation of xenomorph and alternative-species DNA of \
	disputed origin. While hybrids share many traits with their species's namesake, the vast majority \
	are no less docile or aggressive than the vast majority of spacefaring races. Even still, their unsettling appearance, \
	demeanour and innate xenomorph-inherited abilities are enough to draw widespread ire and distrust."

	min_age = 18
	max_age = 150

	move_trail = /obj/effect/decal/cleanable/blood/tracks/claw
	icodigi = 'icons/mob/human_races/r_digi_xeno.dmi'

	species_sounds = "Xeno"
	gender_specific_species_sounds = FALSE

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

	// Some Xeno parts included.
	has_organ = list(
		O_HEART =    	/obj/item/organ/internal/heart/grey/colormatch,
		O_LUNGS =    	/obj/item/organ/internal/lungs/grey/colormatch,
		O_LIVER =    	/obj/item/organ/internal/liver/grey/colormatch,
		O_BRAIN =   	/obj/item/organ/internal/brain/grey/colormatch,
		O_EYES =     	/obj/item/organ/internal/eyes/grey/colormatch,
		O_KIDNEYS =		/obj/item/organ/internal/kidneys/grey/colormatch,
		O_STOMACH =		/obj/item/organ/internal/stomach,
		O_INTESTINE =	/obj/item/organ/internal/intestine,
		O_PLASMA =   	/obj/item/organ/internal/xenos/plasmavessel/weak, // Less plasma capacity.
		O_HIVE =     	/obj/item/organ/internal/xenos/hivenode, // Lets them speak Hivemind and open resin doors.
		O_RESIN =		/obj/item/organ/internal/xenos/resinspinner/weak, // Weaker weed nodes with less spread range.
		O_EGG =         /obj/item/organ/internal/xenos/eggsac // Fluff organ.
		)

	var/weeds_plasma_rate = 3 	// Plasma regen. Much lower than actual xenos. Faster on weeds.
	var/weeds_heal_rate = 0.5   // Health regen on weeds. No healing unless resting.

/datum/species/xenomorph_hybrid/environment_effects(mob/living/carbon/human/H)

	var/turf/T = H.loc
	if(!T) return
	var/datum/gas_mixture/environment = T.return_air()
	if(!environment) return

	if(LINDA_GAS_AMT(environment, GAS_PHORON) > 0 || locate_on(T, /obj/effect/alien/weeds))
		if(!regenerate(H))
			var/obj/item/organ/internal/xenos/plasmavessel/P = H.organ_in(O_PLASMA)
			if(istype(P))
				P.adjust_plasma(weeds_plasma_rate)
	..()

/datum/species/xenomorph_hybrid/proc/regenerate(mob/living/carbon/human/H)
	var/heal_rate = weeds_heal_rate
	var/mend_prob = 10 // Much lower than regular xenos. Bumped from 5 to 10 as medical changes allowed all carbons to passively heal damage after a long delay.
	if (!H.resting)
		heal_rate = 0 // No passive health regen without resting.
		mend_prob = 0 // No passive health regen without resting.

	// First, heal internal organs.
	for(var/obj/item/organ/internal/I in H.internal_organ_list())
		if(I.damage > 0)
			H.mend(TREAT_RESTORATION, heal_rate, I)
			if (prob(5))
				to_chat(H, span_alien("We feel a soothing sensation within our [I.parent_organ]..."))
			return 1

	// Next, heal external damage.
	if (H.injury_load(INJURY_CATEGORY_PHYSICAL) || H.injury_load(INJURY_CATEGORY_THERMAL) || H.oxygen_debt() || H.injury_load(INJURY_CATEGORY_TOXIC))
		H.mend(TREAT_TISSUE_REPAIR, heal_rate)
		H.mend(TREAT_BURN_CARE, heal_rate)
		H.mend(TREAT_OXYGENATION, heal_rate)
		H.mend(TREAT_ANTITOXIN, heal_rate)
		if (prob(5))
			to_chat(H, span_alien("A soothing sensation falls over our body..."))
		return 1

	// Lastly, mend broken bones. May remove this if it's abused.
	for(var/obj/item/organ/external/E in H.damaged_limbs())
		if(E.is_fractured())
			if (prob(mend_prob))
				if (E.mend_fracture())
					to_chat(H, span_alien("We feel something reshape and mend within our [E.name]..."))
			return 1

	return 0
