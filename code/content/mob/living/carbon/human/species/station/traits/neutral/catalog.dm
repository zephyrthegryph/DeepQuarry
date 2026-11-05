/datum/trait/neutral
	category = TRAIT_TYPE_NEUTRAL

/datum/trait/neutral/metabolism_up
	name = "Metabolism, Fast"
	desc = "You process ingested and injected reagents faster, but get hungry faster (Teshari speed)."
	cost = 0
	can_take = ORGANICS|SYNTHETICS
	var_changes = list("hunger_factor" = 0.2, "metabolism" = 0.06)
	factors = alist(STAT_METABOLISM_MULT = 1.2) // +20% rate and 4x hunger (Teshari level)
	excludes = list(/datum/trait/neutral/metabolism_down, /datum/trait/neutral/metabolism_apex, /datum/trait/neutral/singularity_metabolism)
	custom_only = FALSE

/datum/trait/neutral/metabolism_down
	name = "Metabolism, Slow"
	desc = "You process ingested and injected reagents slower, but get hungry slower."
	cost = 0
	can_take = ORGANICS|SYNTHETICS
	var_changes = list("hunger_factor" = 0.04, "metabolism" = 0.0012)
	factors = alist(STAT_METABOLISM_MULT = 0.8) // -20% of default.
	excludes = list(/datum/trait/neutral/metabolism_up, /datum/trait/neutral/metabolism_apex, /datum/trait/neutral/singularity_metabolism)
	custom_only = FALSE

/datum/trait/neutral/metabolism_apex
	name = "Metabolism, Apex"
	desc = "Finally a proper excuse for your predatory actions. Essentially doubles the fast trait rates. Good for characters with big appetites."
	cost = 0
	can_take = ORGANICS|SYNTHETICS
	var_changes = list("hunger_factor" = 0.4, "metabolism" = 0.012)
	factors = alist(STAT_METABOLISM_MULT = 1.4) // +40% rate and 8x hunger (Double Teshari)
	excludes = list(/datum/trait/neutral/metabolism_up, /datum/trait/neutral/metabolism_down, /datum/trait/neutral/singularity_metabolism)
	custom_only = FALSE

/datum/trait/neutral/singularity_metabolism
	name = "Metabolism, Singularity"
	desc = "You are insanely hungry. You can seemingly never get enough to eat. Perhaps you had a singularity as an ancestor, or maybe one is currently living inside of your gut."
	cost = 0
	var_changes = list("hunger_factor" = 1.6, "metabolism" = 0.012)
	factors = alist(STAT_METABOLISM_MULT = 2)	//2x metabolism speed, 32x hunger speed
	custom_only = FALSE
	excludes = list(/datum/trait/neutral/metabolism_up, /datum/trait/neutral/metabolism_down, /datum/trait/neutral/metabolism_apex)

/datum/trait/neutral/coldadapt
	name = "Temp. Adapted, Cold"
	desc = "You are able to withstand much colder temperatures than other species. You are also more vulnerable to hot environments."
	cost = 0
	var_changes = list("cold_level_1" = 220,  "cold_level_2" = 160, "cold_level_3" = 80, "breath_cold_level_1" = 200, "breath_cold_level_2" = 170, "breath_cold_level_3" = 140, "cold_discomfort_level" = 253, "heat_level_1" = 330, "heat_level_2" = 380, "heat_level_3" = 700, "breath_heat_level_1" = 360, "breath_heat_level_2" = 400, "breath_heat_level_3" = 850, "heat_discomfort_level" = 295)
	can_take = ORGANICS // just in case following hot adapt
	excludes = list(/datum/trait/neutral/hotadapt, /datum/trait/neutral/notadapt)

	// Traitgenes Replaces /datum/trait/positive/superpower_cold_resist, made into a genetrait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your body is filled with warmth."
	primitive_expression_messages=list("pants, sweat dripping down their head.")

/datum/trait/neutral/hotadapt
	name = "Temp. Adapted, Heat"
	desc = "You are able to withstand much hotter temperatures than other species. You are also more vulnerable to cold environments."
	cost = 0
	var_changes = list("heat_level_1" = 400, "heat_level_2" = 440, "heat_level_3" = 1100, "breath_heat_level_1" = 420, "breath_heat_level_2" = 500, "breath_heat_level_3" = 1200, "heat_discomfort_level" = 360, "cold_level_1" = 280, "cold_level_2" = 220, "cold_level_3" = 140, "breath_cold_level_1" = 260, "breath_cold_level_2" = 240, "breath_cold_level_3" = 120, "cold_discomfort_level" = 280)
	can_take = ORGANICS // negates the need for suit coolers entirely for synths, so no
	excludes = list(/datum/trait/neutral/coldadapt, /datum/trait/neutral/notadapt)

	// Traitgenes Made into a genetrait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your body feels chilly."
	primitive_expression_messages=list("shivers.")

/datum/trait/neutral/notadapt
	name = "Temp. Unadapted" //British
	desc = "Your particular biology causes you to have trouble handling both hot and cold temperatures. You should take precautions when going out!"
	cost = 0
	var_changes = list("heat_level_1" = 330, "heat_level_2" = 380, "heat_level_3" = 700, "breath_heat_level_1" = 360, "breath_heat_level_2" = 400, "breath_heat_level_3" = 850, "heat_discomfort_level" = 295, "cold_level_1" = 280, "cold_level_2" = 220, "cold_level_3" = 140, "breath_cold_level_1" = 260, "breath_cold_level_2" = 240, "breath_cold_level_3" = 120, "cold_discomfort_level" = 280)
	can_take = ORGANICS // just in case following hot adapt
	custom_only = FALSE
	excludes = list(/datum/trait/neutral/coldadapt, /datum/trait/neutral/hotadapt)

/datum/trait/neutral/highbodytemp
	name = "Body Temp., Hot"
	desc = "Your body's temperature is hotter than the galactic average. This doesn't change what temperatures you can handle."
	cost = 0
	var_changes = list("body_temperature" = 330)
	excludes = list(/datum/trait/neutral/lowbodytemp)

/datum/trait/neutral/lowbodytemp
	name = "Body Temp., Cold"
	desc = "Your body's temperature is colder than the galactic average. This doesn't change what temperatures you can handle."
	cost = 0
	var_changes = list("body_temperature" = 290)
	excludes = list(/datum/trait/neutral/highbodytemp)

/datum/trait/neutral/autohiss_unathi
	name = "Autohiss (Unathi)"
	desc = "You roll your S's and x's"
	cost = 0
	custom_only = FALSE
	var_changes = list(
	autohiss_basic_map = list(
			"s" = list("ss", "sss", "ssss")
		),
	autohiss_extra_map = list(
			"x" = list("ks", "kss", "ksss")
		),
	autohiss_exempt = list(LANGUAGE_UNATHI))
	excludes = list(
		/datum/trait/neutral/autohiss_tajaran,
		/datum/trait/neutral/autohiss_zaddat,
		/datum/trait/neutral/autohiss_vassilian,
		/datum/trait/neutral/autohiss_yingish,
		/datum/trait/neutral/autohiss_unathi/xenochimera,
		/datum/trait/neutral/autohiss_tajaran/xenochimera,
		/datum/trait/neutral/autohiss_zaddat/xenochimera,
		/datum/trait/neutral/autohiss_vassilian/xenochimera,
		/datum/trait/neutral/autohiss_yingish/xenochimera)

/datum/trait/neutral/autohiss_tajaran
	name = "Autohiss (Tajaran)"
	desc = "You roll your R's."
	cost = 0
	custom_only = FALSE
	var_changes = list(
	autohiss_basic_map = list(
			"r" = list("rr", "rrr", "rrrr")
		),
	autohiss_exempt = list(LANGUAGE_SIIK,LANGUAGE_AKHANI,LANGUAGE_ALAI))
	excludes = list(
		/datum/trait/neutral/autohiss_unathi,
		/datum/trait/neutral/autohiss_zaddat,
		/datum/trait/neutral/autohiss_vassilian,
		/datum/trait/neutral/autohiss_yingish,
		/datum/trait/neutral/autohiss_unathi/xenochimera,
		/datum/trait/neutral/autohiss_tajaran/xenochimera,
		/datum/trait/neutral/autohiss_zaddat/xenochimera,
		/datum/trait/neutral/autohiss_vassilian/xenochimera,
		/datum/trait/neutral/autohiss_yingish/xenochimera)

/datum/trait/neutral/autohiss_zaddat
	name = "Autohiss (Zaddat)"
	desc = "You buzz your S's and F's."
	cost = 0
	custom_only = FALSE
	var_changes = list(
	autohiss_basic_map = list(
			"f" = list("v","vh"),
			"ph" = list("v", "vh")
		),
	autohiss_extra_map = list(
			"s" = list("z", "zz", "zzz"),
			"ce" = list("z", "zz"),
			"ci" = list("z", "zz"),
			"v" = list("vv", "vvv")
		),
	autohiss_exempt = list(LANGUAGE_ZADDAT,LANGUAGE_VESPINAE))
	excludes = list(
		/datum/trait/neutral/autohiss_tajaran,
		/datum/trait/neutral/autohiss_unathi,
		/datum/trait/neutral/autohiss_vassilian,
		/datum/trait/neutral/autohiss_yingish,
		/datum/trait/neutral/autohiss_unathi/xenochimera,
		/datum/trait/neutral/autohiss_tajaran/xenochimera,
		/datum/trait/neutral/autohiss_zaddat/xenochimera,
		/datum/trait/neutral/autohiss_vassilian/xenochimera,
		/datum/trait/neutral/autohiss_yingish/xenochimera)

/datum/trait/neutral/autohiss_vassilian
	name = "Autohiss (Vassilian)"
	desc = "You buzz your S's, F's, Th's, and R's."
	cost = 0
	custom_only = FALSE
	var_changes = list(
	autohiss_basic_map = list(
		"s" = list("sz", "z", "zz"),
		"f" = list("zk")
		),
	autohiss_extra_map = list(
		"th" = list("zk", "szk"),
		"r" = list("rk")
	),
	autohiss_exempt = list(LANGUAGE_VESPINAE))
	excludes = list(
		/datum/trait/neutral/autohiss_tajaran,
		/datum/trait/neutral/autohiss_unathi,
		/datum/trait/neutral/autohiss_zaddat,
		/datum/trait/neutral/autohiss_yingish,
		/datum/trait/neutral/autohiss_unathi/xenochimera,
		/datum/trait/neutral/autohiss_tajaran/xenochimera,
		/datum/trait/neutral/autohiss_zaddat/xenochimera,
		/datum/trait/neutral/autohiss_vassilian/xenochimera,
		/datum/trait/neutral/autohiss_yingish/xenochimera)

/datum/trait/neutral/autohiss_yingish
	name = "Autohiss (Yingish)"
	desc = "You pronounce th's with a lisp, a bit like zhis!"
	cost = 0
	custom_only = FALSE
	var_changes = list(
	autohiss_basic_map = list(
			"thi" = list("z"),
			"shi" = list("z"),
			"tha" = list("z"),
			"tho" = list("z")
		),
	autohiss_extra_map = list(
			"the" = list("z"),
			"so" = list("z")
		),
	autohiss_exempt = list())
	excludes = list(
		/datum/trait/neutral/autohiss_tajaran,
		/datum/trait/neutral/autohiss_unathi,
		/datum/trait/neutral/autohiss_zaddat,
		/datum/trait/neutral/autohiss_vassilian,
		/datum/trait/neutral/autohiss_unathi/xenochimera,
		/datum/trait/neutral/autohiss_tajaran/xenochimera,
		/datum/trait/neutral/autohiss_zaddat/xenochimera,
		/datum/trait/neutral/autohiss_vassilian/xenochimera,
		/datum/trait/neutral/autohiss_yingish/xenochimera)

/datum/trait/neutral/electrovore
	name = "Electrovore, Obligate"
	desc = "Makes you unable to gain nutrition from anything but electricity"
	tutorial = "HELP intent lets you consume nutrition to charge a Cell by clicking it in your hand.<br>\
	HARM intent drains battery charge and gives nutrition in exchange"

	cost = 0
	custom_only = FALSE
	excludes = list(/datum/trait/neutral/electrovore_freeform)

/datum/trait/neutral/electrovore/apply(datum/species/S, mob/living/carbon/human/human)
	..()
	add_trait(human, TRAIT_ELECTROVORE, ROUNDSTART_TRAIT)
	add_trait(human, TRAIT_ELECTROVORE_OBLIGATE, ROUNDSTART_TRAIT)

/datum/trait/neutral/electrovore_freeform
	name = "Electrovore"
	desc = "Allows you to drain power cells for nutrition."
	tutorial = "This trait allows you to consume electricity!<br>\
	Clicking a power cell in your hand on HARM intent drains its power for nutrition"

	cost = 0
	custom_only = FALSE
	excludes = list(/datum/trait/neutral/electrovore)

/datum/trait/neutral/electrovore_freeform/apply(datum/species/S, mob/living/carbon/human/human)
	..()
	add_trait(human, TRAIT_ELECTROVORE, ROUNDSTART_TRAIT)

/datum/trait/neutral/succubus_drain
	name = "Succubus Drain"
	desc = "Makes you able to gain nutrition from draining prey in your grasp."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/succubus_drain/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/carbon/human/proc/succubus_drain), src)
	grant(H, granted_verb(/mob/living/carbon/human/proc/succubus_drain_finalize), src)
	grant(H, granted_verb(/mob/living/carbon/human/proc/succubus_drain_lethal), src)

/datum/trait/neutral/feeder
	name = "Feeder"
	desc = "Allows you to feed your prey using your own body."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/feeder/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/carbon/human/proc/slime_feed), src)

/datum/trait/neutral/stuffing_feeder
	name = "Food Stuffer"
	desc = "Allows you to feed food to other people whole, rather than bite by bite."
	cost = 0
	custom_only = FALSE
	has_preferences = list("stuffing_feeder" = list(TRAIT_PREF_TYPE_BOOLEAN, "Default", TRAIT_VAREDIT_TARGET_MOB, FALSE))

/datum/trait/neutral/stuffing_feeder/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/proc/toggle_stuffing_mode), src)

/datum/trait/neutral/hard_vore
	name = "Hard Vore"
	desc = "Allows you to tear off limbs & tear out internal organs."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/hard_vore/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/proc/shred_limb), src)

/datum/trait/neutral/hardfeet
	name = "Hard Feet"	// Free protection 4 ur pawbs
	desc = "Makes your nice clawed, scaled, hooved, armored, or otherwise just awfully calloused feet immune to glass shards."
	cost = 0
	custom_only = FALSE
	var_changes = list("flags" = NO_MINOR_CUT) //Checked the flag is only used by shard stepping.

/datum/trait/neutral/synth_chemfurnace
	name = "Biofuel Processor"
	desc = "You are able to gain energy through consuming and processing normal food, at the cost of significantly slower recharging via cyborg chargers. Energy-dense foods such as protein bars and survival food will yield the best results."
	cost = 0
	custom_only = FALSE
	can_take = SYNTHETICS
	var_changes = list("organic_food_coeff" = 0.75, "synthetic_food_coeff" = 1)
	excludes = list(/datum/trait/neutral/biofuel_value_down)

/datum/trait/neutral/synth_ethanolburner
	name = "Ethanol Burner"
	desc = "You are able to gain energy through consuming and processing alcohol. The more alcoholic it is, the more energy you gain. Doesn't allow you to get drunk by itself (for that, take Ethanol Simulator)."
	cost = 0
	custom_only = FALSE
	can_take = SYNTHETICS
	var_changes = list("robo_ethanol_proc" = 1)

/datum/trait/neutral/synth_ethanol_sim
	name = "Ethanol Simulator"
	desc = "An unusual modification allows your synthetic body to simulate all but the lethal effects of ingested alcohols. You'll get dizzy, slur your speech, suffer temporary loss of vision and even pass out! But hey, at least you don't have a liver to destroy."
	cost = 0
	custom_only = FALSE
	can_take = SYNTHETICS
	var_changes = list("robo_ethanol_drunk" = 1)

/datum/trait/neutral/allergy_reaction
	name = "Allergy Reaction: Disable Toxicity"
	desc = "Take this trait to disable the toxic damage effect of being exposed to one of your allergens. Combine with the Disable Suffocation trait to have purely nonlethal reactions."
	cost = 0
	custom_only = FALSE
	var/reaction = AG_TOX_DMG

/datum/trait/neutral/allergy_reaction/apply(datum/species/S,mob/living/carbon/human/H)
	S.allergen_reaction ^= reaction
	..()

/datum/trait/neutral/allergy_reaction/oxy
	name = "Allergy Reaction: Disable Suffocation"
	desc = "Take this trait to disable the oxygen deprivation damage effect of being exposed to one of your allergens. Combine with the Disable Toxicity trait to have purely nonlethal reactions."
	cost = 0
	custom_only = FALSE
	reaction = AG_OXY_DMG

/datum/trait/neutral/allergy_reaction/brute
	name = "Allergy Reaction: Spontaneous Trauma"
	desc = "When exposed to one of your allergens, your skin develops unnatural bruises and other 'stigmata'-like injuries. Be aware that untreated wounds may become infected."
	cost = 0
	custom_only = FALSE
	reaction = AG_PHYS_DMG

/datum/trait/neutral/allergy_reaction/burn
	name = "Allergy Reaction: Blistering"
	desc = "When exposed to one of your allergens, your skin develops unnatural blisters and burns, as if exposed to fire. Be aware that untreated burns are very susceptible to infection!"
	cost = 0
	custom_only = FALSE
	reaction = AG_BURN_DMG

/datum/trait/neutral/allergy_reaction/pain
	name = "Allergy Reaction: Disable Pain"
	desc = "Take this trait to disable experiencing pain after being exposed to one of your allergens."
	cost = 0
	custom_only = FALSE
	reaction = AG_PAIN

/datum/trait/neutral/allergy_reaction/weaken
	name = "Allergy Reaction: Knockdown"
	desc = "When exposed to one of your allergens, you will experience sudden and abrupt loss of muscle control and tension, resulting in immediate collapse and immobility. Does nothing if you have no allergens."
	cost = 0
	custom_only = FALSE
	reaction = AG_WEAKEN

/datum/trait/neutral/allergy_reaction/blurry
	name = "Allergy Reaction: Disable Blurring"
	desc = "Take this trait to disable the blurred/impeded vision effect of allergens."
	cost = 0
	custom_only = FALSE
	reaction = AG_BLURRY

/datum/trait/neutral/allergy_reaction/sleepy
	name = "Allergy Reaction: Fatigue"
	desc = "When exposed to one of your allergens, you will experience fatigue and tiredness, and may potentially pass out entirely. Does nothing if you have no allergens."
	cost = 0
	custom_only = FALSE
	reaction = AG_SLEEPY

/datum/trait/neutral/allergy_reaction/confusion
	name = "Allergy Reaction: Disable Confusion"
	desc = "Take this trait to disable the confusion/disorientation effect of allergens."
	cost = 0
	custom_only = FALSE
	reaction = AG_CONFUSE

/datum/trait/neutral/allergy_reaction/gibbing
	name = "Allergy Reaction: Gibbing"
	desc = "When exposed to one of your allergens, you will explode, god help you. Does nothing if you have no allergens."
	cost = 0
	custom_only = FALSE
	reaction = AG_GIBBING
	hidden = TRUE // Disabled on virgo for obvious reasons

/datum/trait/neutral/allergy_reaction/sneeze
	name = "Allergy Reaction: Sneezing"
	desc = "When exposed to one of your allergens, you will begin sneezing harmlessly. Does nothing if you have no allergens."
	cost = 0
	custom_only = FALSE
	reaction = AG_SNEEZE

/datum/trait/neutral/allergy_reaction/cough
	name = "Allergy Reaction: Coughing"
	desc = "When exposed to one of your allergens, you will begin coughing, potentially dropping items. Does nothing if you have no allergens."
	cost = 0
	custom_only = FALSE
	reaction = AG_COUGH

/datum/trait/neutral/allergen_reduced_effect
	name = "Allergen Reaction: Reduced Intensity"
	desc = "This trait drastically reduces the effects of allergen reactions. If you don't have any allergens set, it does nothing. It does not apply to special reactions (such as unathi drowsiness from sugars)."
	cost = 0
	custom_only = FALSE
	var_changes = list("allergen_damage_severity" = 1.25, "allergen_disable_severity" = 5)
	excludes = list(/datum/trait/neutral/allergen_increased_effect)

/datum/trait/neutral/allergen_increased_effect
	name = "Allergen Reaction: Increased Intensity"
	desc = "This trait drastically increases the effects of allergen reactions, enough that even a small dose can be lethal. If you don't have any allergens set, it does nothing. It does not apply to special reactions (such as unathi drowsiness from sugars)."
	cost = 0
	custom_only = FALSE
	var_changes = list("allergen_damage_severity" = 5, "allergen_disable_severity" = 20)
	excludes = list(/datum/trait/neutral/allergen_reduced_effect)

// Spicy Food Traits, from negative to positive.
/datum/trait/neutral/spice_intolerance_extreme
	name = "Spice Intolerance, Extreme"
	desc = "Spicy (and chilly) peppers are three times as strong. (This does not affect pepperspray.)"
	cost = 0
	custom_only = FALSE
	var_changes = list("spice_mod" = 3) // 300% as effective if spice_mod is set to 1. If it's not 1 in species.dm, update this!

	// Traitgenes Made into a gene trait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your belly feels strange..."

/datum/trait/neutral/spice_intolerance_basic
	name = "Spice Intolerance, Heavy"
	desc = "Spicy (and chilly) peppers are twice as strong. (This does not affect pepperspray.)"
	cost = 0
	custom_only = FALSE
	var_changes = list("spice_mod" = 2) // 200% as effective if spice_mod is set to 1. If it's not 1 in species.dm, update this!

/datum/trait/neutral/spice_intolerance_slight
	name = "Spice Intolerance, Slight"
	desc = "You have a slight struggle with spicy foods. Spicy (and chilly) peppers are one and a half times stronger. (This does not affect pepperspray.)"
	cost = 0
	custom_only = FALSE
	var_changes = list("spice_mod" = 1.5) // 150% as effective if spice_mod is set to 1. If it's not 1 in species.dm, update this!

/datum/trait/neutral/spice_tolerance_basic
	name = "Spice Tolerance"
	desc = "Spicy (and chilly) peppers are only three-quarters as strong. (This does not affect pepperspray.)"
	cost = 0
	custom_only = FALSE
	var_changes = list("spice_mod" = 0.75) // 75% as effective if spice_mod is set to 1. If it's not 1 in species.dm, update this!

/datum/trait/neutral/spice_tolerance_advanced
	name = "Spice Tolerance, Strong"
	desc = "Spicy (and chilly) peppers are only half as strong. (This does not affect pepperspray.)"
	cost = 0
	custom_only = FALSE
	var_changes = list("spice_mod" = 0.5) // 50% as effective if spice_mod is set to 1. If it's not 1 in species.dm, update this!

/datum/trait/neutral/spice_immunity
	name = "Spice Tolerance, Extreme"
	desc = "Spicy (and chilly) peppers are basically ineffective! (This does not affect pepperspray.)"
	cost = 0
	custom_only = FALSE
	var_changes = list("spice_mod" = 0.25) // 25% as effective if spice_mod is set to 1. If it's not 1 in species.dm, update this!

	// Traitgenes Made into a gene trait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your belly feels strange..."

// Alcohol Traits Start Here, from negative to positive.
/datum/trait/neutral/alcohol_intolerance_advanced
	name = "Liver of Air"
	desc = "The only way you can hold a drink is if it's in your own two hands, and even then you'd best not inhale too deeply near it. Alcohol hits you three times as hard as they do other people."
	cost = 0
	custom_only = FALSE
	var_changes = list("chem_strength_alcohol" = 0.33)

	// Traitgenes Made into a gene trait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your belly feels strange..."

/datum/trait/neutral/alcohol_intolerance_basic
	name = "Liver of Lilies"
	desc = "You have a hard time with alcohol. Maybe you just never took to it, or maybe it doesn't agree with your system... either way, alcohol hits you twice as hard."
	cost = 0
	custom_only = FALSE
	var_changes = list("chem_strength_alcohol" = 0.5)

/datum/trait/neutral/alcohol_intolerance_slight
	name = "Liver of Tulips"
	desc = "You are what some might call 'a bit of a lightweight', but you can still keep your drinks down... most of the time. Alcohol hits you fifty percent harder."
	cost = 0
	custom_only = FALSE
	var_changes = list("chem_strength_alcohol" = 0.75)

/datum/trait/neutral/alcohol_tolerance_reset
	name = "Liver of Unremarkableness"
	desc = "This trait exists to reset alcohol (in)tolerance for non-custom species to baseline normal. It can only be taken by Skrell, Tajara, Unathi, Diona, and Prometheans, as it would have no effect on other species."
	cost = 0
	custom_only = FALSE
	var_changes = list("chem_strength_alcohol" = 1)
	allowed_species = list(SPECIES_SKRELL,SPECIES_TAJARAN,SPECIES_UNATHI,SPECIES_DIONA,SPECIES_PROMETHEAN)

/datum/trait/neutral/alcohol_tolerance_basic
	name = "Liver of Iron"
	desc = "You can hold drinks much better than those lily-livered land-lubbers! Arr! Alcohol's effects on you are reduced by about a quarter."
	cost = 0
	custom_only = FALSE
	var_changes = list("chem_strength_alcohol" = 1.25)

/datum/trait/neutral/alcohol_tolerance_advanced
	name = "Liver of Steel"
	desc = "Drinks tremble before your might! You can hold your alcohol twice as well as those blue-bellied barnacle boilers! Alcohol has just half the effect on you as it does on others."
	cost = 0
	custom_only = FALSE
	var_changes = list("chem_strength_alcohol" = 2)

/datum/trait/neutral/alcohol_immunity
	name = "Liver of Durasteel"
	desc = "You've drunk so much that most booze doesn't even faze you. It takes something like a Pan-Galactic or a pint of Deathbell for you to even get slightly buzzed."
	cost = 0
	custom_only = FALSE
	var_changes = list("chem_strength_alcohol" = 4)

	// Traitgenes Made into a gene trait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="Your belly feels strange..."

// Body shape traits
/datum/trait/neutral/taller
	name = "Tall"
	desc = "Your body is taller than average."
	sort = TRAIT_SORT_BODYTYPE
	cost = 0
	custom_only = FALSE
	var_changes = list("icon_scale_y" = 1.09)
	excludes = list(/datum/trait/neutral/tall, /datum/trait/neutral/tallest, /datum/trait/neutral/short, /datum/trait/neutral/shorter, /datum/trait/neutral/shortest)

/datum/trait/neutral/taller/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.update_transform()

/datum/trait/neutral/tall
	name = "Tall, Minor"
	desc = "Your body is a bit taller than average."
	sort = TRAIT_SORT_BODYTYPE
	cost = 0
	custom_only = FALSE
	var_changes = list("icon_scale_y" = 1.05)
	excludes = list(/datum/trait/neutral/taller, /datum/trait/neutral/tallest, /datum/trait/neutral/short, /datum/trait/neutral/shorter, /datum/trait/neutral/shortest)

/datum/trait/neutral/tall/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.update_transform()

/datum/trait/neutral/tallest
	name = "Tall, Major"
	desc = "Your body is way taller than average."
	sort = TRAIT_SORT_BODYTYPE
	cost = 0
	custom_only = FALSE
	var_changes = list("icon_scale_y" = 1.15)
	excludes = list(/datum/trait/neutral/tall, /datum/trait/neutral/taller, /datum/trait/neutral/short, /datum/trait/neutral/shorter, /datum/trait/neutral/shortest)

/datum/trait/neutral/tallest/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.update_transform()

/datum/trait/neutral/short
	name = "Short, Minor"
	desc = "Your body is a bit shorter than average."
	sort = TRAIT_SORT_BODYTYPE
	cost = 0
	custom_only = FALSE
	var_changes = list("icon_scale_y" = 0.95)
	excludes = list(/datum/trait/neutral/taller, /datum/trait/neutral/tall, /datum/trait/neutral/tallest, /datum/trait/neutral/shorter, /datum/trait/neutral/shortest)

/datum/trait/neutral/short/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.update_transform()

/datum/trait/neutral/shorter
	name = "Short"
	desc = "Your body is shorter than average."
	sort = TRAIT_SORT_BODYTYPE
	cost = 0
	custom_only = FALSE
	var_changes = list("icon_scale_y" = 0.915)
	excludes = list(/datum/trait/neutral/taller, /datum/trait/neutral/tall, /datum/trait/neutral/tallest, /datum/trait/neutral/short, /datum/trait/neutral/shortest)

/datum/trait/neutral/shorter/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.update_transform()

/datum/trait/neutral/shortest
	name = "Short, Major"
	desc = "Your body is way shorter than average."
	sort = TRAIT_SORT_BODYTYPE
	cost = 0
	custom_only = FALSE
	var_changes = list("icon_scale_y" = 0.85)
	excludes = list(/datum/trait/neutral/taller, /datum/trait/neutral/tall, /datum/trait/neutral/tallest, /datum/trait/neutral/short, /datum/trait/neutral/shorter)

/datum/trait/neutral/shortest/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.update_transform()

/datum/trait/neutral/obese
	name = "Bulky, Major"
	desc = "Your body is much wider than average."
	sort = TRAIT_SORT_BODYTYPE
	cost = 0
	custom_only = FALSE
	var_changes = list("icon_scale_x" = 1.095)
	excludes = list(/datum/trait/neutral/fat, /datum/trait/neutral/thin, /datum/trait/neutral/thinner)

/datum/trait/neutral/obese/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.update_transform()

/datum/trait/neutral/fat
	name = "Bulky"
	desc = "Your body is wider than average."
	sort = TRAIT_SORT_BODYTYPE
	cost = 0
	custom_only = FALSE
	var_changes = list("icon_scale_x" = 1.054)
	excludes = list(/datum/trait/neutral/obese, /datum/trait/neutral/thin, /datum/trait/neutral/thinner)

/datum/trait/neutral/fat/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.update_transform()

/datum/trait/neutral/thin
	name = "Thin"
	desc = "Your body is thinner than average."
	sort = TRAIT_SORT_BODYTYPE
	cost = 0
	custom_only = FALSE
	var_changes = list("icon_scale_x" = 0.945)
	excludes = list(/datum/trait/neutral/fat, /datum/trait/neutral/obese, /datum/trait/neutral/thinner)

/datum/trait/neutral/thin/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.update_transform()

/datum/trait/neutral/thinner
	name = "Thin, Major"
	desc = "Your body is much thinner than average."
	sort = TRAIT_SORT_BODYTYPE
	cost = 0
	custom_only = FALSE
	var_changes = list("icon_scale_x" = 0.905)
	excludes = list(/datum/trait/neutral/fat, /datum/trait/neutral/obese, /datum/trait/neutral/thin)

/datum/trait/neutral/thinner/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	H.update_transform()

/datum/trait/neutral/vertical_nom
	name = "Vertical Nom"
	desc = "Allows you to consume people from up above."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/vertical_nom/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/proc/vertical_nom), src)

/datum/trait/neutral/micro_size_down
	name = "Light Frame"
	desc = "You are considered smaller than you are for micro interactions."
	cost = 0
	custom_only = FALSE
	var_changes = list("micro_size_mod" = -0.15)

/datum/trait/neutral/micro_size_down_plus
	name = "Light Frame, Major"
	desc = "You are considered much smaller than you are for micro interactions."
	cost = 0
	custom_only = FALSE
	var_changes = list("micro_size_mod" = -0.30)

/datum/trait/neutral/micro_size_up
	name = "Heavy Frame"
	desc = "You are considered bigger than you are for micro interactions."
	cost = 0
	custom_only = FALSE
	var_changes = list("micro_size_mod" = 0.15)

/datum/trait/neutral/micro_size_up_plus
	name = "Heavy Frame, Major"
	desc = "You are considered much bigger than you are for micro interactions."
	cost = 0
	custom_only = FALSE
	var_changes = list("micro_size_mod" = 0.30)

/datum/trait/neutral/digestion_value_up
	name = "Highly Filling"
	desc = "You provide notably more nutrition to anyone who makes a meal of you."
	cost = 0
	custom_only = FALSE
	var_changes = list("digestion_nutrition_modifier" = 2)

/datum/trait/neutral/digestion_value_up_plus
	name = "Extremely Filling"
	desc = "You provide a lot more nutrition to anyone who makes a meal of you."
	cost = 0
	custom_only = FALSE
	var_changes = list("digestion_nutrition_modifier" = 3)

/datum/trait/neutral/digestion_value_down
	name = "Slightly Filling"
	desc = "You provide notably less nutrition to anyone who makes a meal of you."
	cost = 0
	custom_only = FALSE
	var_changes = list("digestion_nutrition_modifier" = 0.5)

/datum/trait/neutral/digestion_value_down_plus
	name = "Barely Filling"
	desc = "You provide a lot less nutrition to anyone who makes a meal of you."
	cost = 0
	custom_only = FALSE
	var_changes = list("digestion_nutrition_modifier" = 0.25)

/datum/trait/neutral/food_value_down
	name = "Insatiable"
	desc = "You need to eat a third of a plate more to be sated."
	cost = 0
	custom_only = FALSE
	can_take = ORGANICS
	var_changes = list(organic_food_coeff = 0.67, digestion_efficiency = 0.66)
	excludes = list(/datum/trait/neutral/bloodsucker)

/datum/trait/neutral/food_value_down_plus
	name = "Insatiable, Greater"
	desc = "You need to eat three times as much to feel sated."
	cost = 0
	custom_only = FALSE
	can_take = ORGANICS
	var_changes = list(organic_food_coeff = 0.33, digestion_efficiency = 0.33)
	excludes = list(/datum/trait/neutral/bloodsucker, /datum/trait/neutral/food_value_down)

/datum/trait/neutral/biofuel_value_down
	name = "Discount Biofuel processor"
	desc = "You are able to gain energy through consuming and processing normal food. Unfortunately, it is half as effective as premium models. On the plus side, you still recharge from charging stations fairly efficiently."
	cost = 0
	custom_only = FALSE
	can_take = SYNTHETICS
	var_changes = list("organic_food_coeff" = 0, "synthetic_food_coeff" = 0.3, digestion_efficiency = 0.5)
	excludes = list(/datum/trait/neutral/synth_chemfurnace)

/datum/trait/neutral/synth_cosmetic_pain
	name = "Pain simulation"
	desc = "You have added modules in your synthetic shell that simulates the sensation of pain. You are able to turn this on and off for repairs as needed or convenience at will."
	cost = 0
	custom_only = FALSE
	can_take = SYNTHETICS
	has_preferences = list("pain" = list(TRAIT_PREF_TYPE_BOOLEAN, "Enabled on spawn", TRAIT_VAREDIT_TARGET_MOB, FALSE))

/datum/trait/neutral/synth_cosmetic_pain/apply(datum/species/S,mob/living/carbon/human/H, trait_prefs = null)
	..()
	grant(H, granted_verb(/mob/living/carbon/human/proc/toggle_pain_module), src)

//Food preferences ported from RogueStar

/datum/trait/neutral/food_pref
	name = "Food Preference - Carnivore"
	desc = "You prefer to eat meat, and gain extra nutrition for doing so!"
	cost = 0
	custom_only = FALSE
	can_take = ORGANICS
	var_changes = list("food_preference_bonus" = 5)
	excludes = list(
	/datum/trait/neutral/food_pref,
	/datum/trait/neutral/food_pref/herbivore,
	/datum/trait/neutral/food_pref/beanivore,
	/datum/trait/neutral/food_pref/omnivore,
	/datum/trait/neutral/food_pref/fungivore,
	/datum/trait/neutral/food_pref/piscivore,
	/datum/trait/neutral/food_pref/granivore,
	/datum/trait/neutral/food_pref/cocoavore,
	/datum/trait/neutral/food_pref/glycovore,
	/datum/trait/neutral/food_pref/lactovore,
	/datum/trait/neutral/food_pref/coffee,
	/datum/trait/neutral/food_pref/stimulant
	)

TYPE_TABLE_DECLARE(/datum/trait/neutral/food_pref, food_pref_allergens, list(ALLERGEN_MEAT))

/datum/trait/neutral/food_pref/apply(datum/species/S, mob/living/carbon/human/H, trait_prefs)
	. = ..()
	for(var/a in TYPE_TABLE_GET(src, food_pref_allergens))
		LAZYOR(S.food_preference, a)

/datum/trait/neutral/food_pref/herbivore
	name = "Food Preference - Herbivore"
	desc = "You prefer to eat fruits and vegitables, and gain extra nutrition for doing so!"
	excludes = list(
	/datum/trait/neutral/food_pref,
	/datum/trait/neutral/food_pref/beanivore,
	/datum/trait/neutral/food_pref/omnivore,
	/datum/trait/neutral/food_pref/fungivore,
	/datum/trait/neutral/food_pref/piscivore,
	/datum/trait/neutral/food_pref/granivore,
	/datum/trait/neutral/food_pref/cocoavore,
	/datum/trait/neutral/food_pref/glycovore,
	/datum/trait/neutral/food_pref/lactovore,
	/datum/trait/neutral/food_pref/coffee,
	/datum/trait/neutral/food_pref/stimulant
	)

TYPE_TABLE(/datum/trait/neutral/food_pref/herbivore, food_pref_allergens, list(ALLERGEN_VEGETABLE,ALLERGEN_FRUIT))

/datum/trait/neutral/food_pref/beanivore
	name = "Food Preference - Legumovore"
	desc = "You prefer to eat bean related foods, such as tofu, and gain extra nutrition for doing so!"
	excludes = list(
	/datum/trait/neutral/food_pref,
	/datum/trait/neutral/food_pref/herbivore,
	/datum/trait/neutral/food_pref/omnivore,
	/datum/trait/neutral/food_pref/fungivore,
	/datum/trait/neutral/food_pref/piscivore,
	/datum/trait/neutral/food_pref/granivore,
	/datum/trait/neutral/food_pref/cocoavore,
	/datum/trait/neutral/food_pref/glycovore,
	/datum/trait/neutral/food_pref/lactovore,
	/datum/trait/neutral/food_pref/coffee,
	/datum/trait/neutral/food_pref/stimulant
	)

TYPE_TABLE(/datum/trait/neutral/food_pref/beanivore, food_pref_allergens, list(ALLERGEN_BEANS))

/datum/trait/neutral/food_pref/omnivore
	name = "Food Preference - Omnivore"
	desc = "You prefer to eat meat and vegitables, and gain extra nutrition for doing so!"
	excludes = list(
	/datum/trait/neutral/food_pref,
	/datum/trait/neutral/food_pref/herbivore,
	/datum/trait/neutral/food_pref/beanivore,
	/datum/trait/neutral/food_pref/fungivore,
	/datum/trait/neutral/food_pref/piscivore,
	/datum/trait/neutral/food_pref/granivore,
	/datum/trait/neutral/food_pref/cocoavore,
	/datum/trait/neutral/food_pref/glycovore,
	/datum/trait/neutral/food_pref/lactovore,
	/datum/trait/neutral/food_pref/coffee,
	/datum/trait/neutral/food_pref/stimulant
	)

TYPE_TABLE(/datum/trait/neutral/food_pref/omnivore, food_pref_allergens, list(ALLERGEN_VEGETABLE,ALLERGEN_MEAT))

/datum/trait/neutral/food_pref/fungivore
	name = "Food Preference - Fungivore"
	desc = "You prefer to eat mushrooms and fungus, and gain extra nutrition for doing so!"
	excludes = list(
	/datum/trait/neutral/food_pref,
	/datum/trait/neutral/food_pref/herbivore,
	/datum/trait/neutral/food_pref/beanivore,
	/datum/trait/neutral/food_pref/omnivore,
	/datum/trait/neutral/food_pref/piscivore,
	/datum/trait/neutral/food_pref/granivore,
	/datum/trait/neutral/food_pref/cocoavore,
	/datum/trait/neutral/food_pref/glycovore,
	/datum/trait/neutral/food_pref/lactovore,
	/datum/trait/neutral/food_pref/coffee,
	/datum/trait/neutral/food_pref/stimulant
	)

TYPE_TABLE(/datum/trait/neutral/food_pref/fungivore, food_pref_allergens, list(ALLERGEN_FUNGI))

/datum/trait/neutral/food_pref/piscivore
	name = "Food Preference - Piscivore"
	desc = "You prefer to eat fish, and gain extra nutrition for doing so!"
	excludes = list(
	/datum/trait/neutral/food_pref,
	/datum/trait/neutral/food_pref/herbivore,
	/datum/trait/neutral/food_pref/beanivore,
	/datum/trait/neutral/food_pref/omnivore,
	/datum/trait/neutral/food_pref/fungivore,
	/datum/trait/neutral/food_pref/granivore,
	/datum/trait/neutral/food_pref/cocoavore,
	/datum/trait/neutral/food_pref/glycovore,
	/datum/trait/neutral/food_pref/lactovore,
	/datum/trait/neutral/food_pref/coffee,
	/datum/trait/neutral/food_pref/stimulant
	)

TYPE_TABLE(/datum/trait/neutral/food_pref/piscivore, food_pref_allergens, list(ALLERGEN_FISH))

/datum/trait/neutral/food_pref/granivore
	name = "Food Preference - Granivore"
	desc = "You prefer to eat grains and seeds, and gain extra nutrition for doing so!"
	excludes = list(
	/datum/trait/neutral/food_pref,
	/datum/trait/neutral/food_pref/herbivore,
	/datum/trait/neutral/food_pref/beanivore,
	/datum/trait/neutral/food_pref/omnivore,
	/datum/trait/neutral/food_pref/fungivore,
	/datum/trait/neutral/food_pref/piscivore,
	/datum/trait/neutral/food_pref/cocoavore,
	/datum/trait/neutral/food_pref/glycovore,
	/datum/trait/neutral/food_pref/lactovore,
	/datum/trait/neutral/food_pref/coffee,
	/datum/trait/neutral/food_pref/stimulant
	)

TYPE_TABLE(/datum/trait/neutral/food_pref/granivore, food_pref_allergens, list(ALLERGEN_GRAINS,ALLERGEN_SEEDS))

/datum/trait/neutral/food_pref/cocoavore
	name = "Food Preference - Cocoavore"
	desc = "You prefer to eat chocolate, and gain extra nutrition for doing so!"
	excludes = list(
	/datum/trait/neutral/food_pref,
	/datum/trait/neutral/food_pref/herbivore,
	/datum/trait/neutral/food_pref/beanivore,
	/datum/trait/neutral/food_pref/omnivore,
	/datum/trait/neutral/food_pref/fungivore,
	/datum/trait/neutral/food_pref/piscivore,
	/datum/trait/neutral/food_pref/granivore,
	/datum/trait/neutral/food_pref/glycovore,
	/datum/trait/neutral/food_pref/lactovore,
	/datum/trait/neutral/food_pref/coffee,
	/datum/trait/neutral/food_pref/stimulant
	)

TYPE_TABLE(/datum/trait/neutral/food_pref/cocoavore, food_pref_allergens, list(ALLERGEN_CHOCOLATE))

/datum/trait/neutral/food_pref/glycovore
	name = "Food Preference - Glycovore"
	desc = "You prefer to eat sugar, and gain extra nutrition for doing so!"
	excludes = list(
	/datum/trait/neutral/food_pref,
	/datum/trait/neutral/food_pref/herbivore,
	/datum/trait/neutral/food_pref/beanivore,
	/datum/trait/neutral/food_pref/omnivore,
	/datum/trait/neutral/food_pref/fungivore,
	/datum/trait/neutral/food_pref/piscivore,
	/datum/trait/neutral/food_pref/granivore,
	/datum/trait/neutral/food_pref/cocoavore,
	/datum/trait/neutral/food_pref/lactovore,
	/datum/trait/neutral/food_pref/coffee,
	/datum/trait/neutral/food_pref/stimulant
	)

TYPE_TABLE(/datum/trait/neutral/food_pref/glycovore, food_pref_allergens, list(ALLERGEN_SUGARS))

/datum/trait/neutral/food_pref/lactovore
	name = "Food Preference - Lactovore"
	desc = "You prefer to eat and drink things with milk in them, and gain extra nutrition for doing so!"
	excludes = list(
	/datum/trait/neutral/food_pref,
	/datum/trait/neutral/food_pref/herbivore,
	/datum/trait/neutral/food_pref/beanivore,
	/datum/trait/neutral/food_pref/omnivore,
	/datum/trait/neutral/food_pref/fungivore,
	/datum/trait/neutral/food_pref/piscivore,
	/datum/trait/neutral/food_pref/granivore,
	/datum/trait/neutral/food_pref/cocoavore,
	/datum/trait/neutral/food_pref/glycovore,
	/datum/trait/neutral/food_pref/coffee,
	/datum/trait/neutral/food_pref/stimulant
	)

TYPE_TABLE(/datum/trait/neutral/food_pref/lactovore, food_pref_allergens, list(ALLERGEN_DAIRY))

/datum/trait/neutral/food_pref/coffee
	name = "Food Preference - Coffee Dependant"
	desc = "You can get by on coffee alone if you have to, and you like it that way."
	excludes = list(
	/datum/trait/neutral/food_pref,
	/datum/trait/neutral/food_pref/herbivore,
	/datum/trait/neutral/food_pref/beanivore,
	/datum/trait/neutral/food_pref/omnivore,
	/datum/trait/neutral/food_pref/fungivore,
	/datum/trait/neutral/food_pref/piscivore,
	/datum/trait/neutral/food_pref/granivore,
	/datum/trait/neutral/food_pref/cocoavore,
	/datum/trait/neutral/food_pref/glycovore,
	/datum/trait/neutral/food_pref/lactovore,
	/datum/trait/neutral/food_pref/stimulant
	)

TYPE_TABLE(/datum/trait/neutral/food_pref/coffee, food_pref_allergens, list(ALLERGEN_COFFEE))

/datum/trait/neutral/food_pref/stimulant
	name = "Food Preference - Stimulant Dependant"
	desc = "You can get by on caffine alone if you have to, and you like it that way."
	excludes = list(
	/datum/trait/neutral/food_pref,
	/datum/trait/neutral/food_pref/herbivore,
	/datum/trait/neutral/food_pref/beanivore,
	/datum/trait/neutral/food_pref/omnivore,
	/datum/trait/neutral/food_pref/fungivore,
	/datum/trait/neutral/food_pref/piscivore,
	/datum/trait/neutral/food_pref/granivore,
	/datum/trait/neutral/food_pref/cocoavore,
	/datum/trait/neutral/food_pref/glycovore,
	/datum/trait/neutral/food_pref/lactovore,
	/datum/trait/neutral/food_pref/coffee
	)

TYPE_TABLE(/datum/trait/neutral/food_pref/stimulant, food_pref_allergens, list(ALLERGEN_STIMULANT))

//////////////PHOBIAS/////////////////

/datum/trait/neutral/nyctophobia
	name = "Phobia: Nyctophobia"
	desc = "You are afraid of the dark. When in very dark conditions, you will become afraid."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/nyctophobia/apply(datum/species/S,mob/living/carbon/human/H, trait_prefs = null)
	..()
	H.set_phobias(H.phobias | NYCTOPHOBIA)

/datum/trait/neutral/arachnophobia
	name = "Phobia: Arachnophobia"
	desc = "You are afraid of spiders. When you can see a large spider, you will become afraid."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/arachnophobia/apply(datum/species/S,mob/living/carbon/human/H, trait_prefs = null)
	..()
	H.set_phobias(H.phobias | ARACHNOPHOBIA)

/datum/trait/neutral/hemophobia
	name = "Phobia: Hemophobia"
	desc = "You are afraid of blood. When you can see large amounts of blood, you will become afraid."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/hemophobia/apply(datum/species/S,mob/living/carbon/human/H, trait_prefs = null)
	..()
	H.set_phobias(H.phobias | HEMOPHOBIA)

/datum/trait/neutral/thalassophobia
	name = "Phobia: Thalassophobia"
	desc = "You are afraid of deep water. When in deep water, you will become afraid."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/thalassophobia/apply(datum/species/S,mob/living/carbon/human/H, trait_prefs = null)
	..()
	H.set_phobias(H.phobias | THALASSOPHOBIA)

/datum/trait/neutral/clasutrophobia_minor
	name = "Phobia: Claustrophobia (non-vore)"
	desc = "You are afraid of tight, enclosed spaces. When inside of another object, you will become afraid."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/clasutrophobia_minor/apply(datum/species/S,mob/living/carbon/human/H, trait_prefs = null)
	..()
	H.set_phobias(H.phobias | CLAUSTROPHOBIA_MINOR)

/datum/trait/neutral/clasutrophobia_major
	name = "Phobia: Claustrophobia (vore)"
	desc = "You are afraid of tight, enclosed spaces. When inside of another object, including vore bellies, you will become afraid."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/clasutrophobia_major/apply(datum/species/S,mob/living/carbon/human/H, trait_prefs = null)
	..()
	H.set_phobias(H.phobias | CLAUSTROPHOBIA_MAJOR)

/datum/trait/neutral/anatidaephobia
	name = "Phobia: Anatidaephobia"
	desc = "You are afraid of ducks. When you can see a duck (even rubber ones), you will become afraid."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/anatidaephobia/apply(datum/species/S,mob/living/carbon/human/H, trait_prefs = null)
	..()
	H.set_phobias(H.phobias | ANATIDAEPHOBIA)

/datum/trait/neutral/agraviaphobia
	name = "Phobia: Agraviaphobia"
	desc = "You are afraid of a lack of gravity. When you find yourself floating, you will become afraid."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/agraviaphobia/apply(datum/species/S,mob/living/carbon/human/H, trait_prefs = null)
	..()
	H.set_phobias(H.phobias | AGRAVIAPHOBIA)

/datum/trait/neutral/drippy
	name = "Drippy"
	desc = "You cannot hold your form together, or produce a constant film of sludge that drips off of your body. Hope the station has a janitor."
	cost = 0
	custom_only = FALSE // enables all races to take the trait

	// Traitgenes Made into a genetrait
	is_genetrait = TRUE
	hidden = FALSE

	activation_message="You feel softer..."
	primitive_expression_messages=list("drips.")
	added_component_path = /datum/trait_state/drippy

/datum/trait/neutral/mudking
	name = "Mudking"
	desc = "Somehow you are so filthy that tiles get dirty four times as quick from you walking on them."
	cost = 0
	var_changes = list("mudking" = TRUE)
	custom_only = FALSE

/datum/trait/neutral/patting_defence
	name = "Reflexive Biting"
	desc = "You will reflexively bite hands that attempt to pat your head or boop your nose, this can be toggled off."
	cost = 0
	custom_only = FALSE
	has_preferences = list("biting_toggle" = list(TRAIT_PREF_TYPE_BOOLEAN, "Enabled on spawn", TRAIT_NO_VAREDIT_TARGET, TRUE))

/datum/trait/neutral/patting_defence/apply(datum/species/S, mob/living/carbon/human/H, list/trait_prefs)
	..()
	if(trait_prefs && trait_prefs["biting_toggle"])
		STATE_SET(H, living_misc, touch_reaction_flags, STATE_GET(H, living_misc, touch_reaction_flags) | (SPECIES_TRAIT_PATTING_DEFENCE))
	grant(H, granted_verb(/mob/living/proc/toggle_patting_defence), src)

/datum/trait/neutral/skin_reagents
	name = "Skin Reagents"
	desc = "You secret some sort of reagent across your skin that can poison those who dare to lick you."
	cost = 0
	custom_only = FALSE
	multiple_choice = list(REAGENT_ID_ETHANOL, REAGENT_ID_CAPSAICIN, REAGENT_ID_SODIUMCHLORIDE, REAGENT_ID_STOXIN, REAGENT_ID_RAINBOWTOXIN, REAGENT_ID_PARALYSISTOXIN, REAGENT_ID_PAINENZYME)
	has_preferences = list("Reagent" = list(TRAIT_PREF_TYPE_LIST, "Skin Reagent", TRAIT_NO_VAREDIT_TARGET, REAGENT_ID_ETHANOL))

/datum/trait/neutral/skin_reagents/apply(datum/species/S, mob/living/carbon/human/H, list/trait_prefs)
	..()
	if(trait_prefs && trait_prefs["Reagent"])
		STATE_SET(H, living_misc, skin_reagent, trait_prefs["Reagent"])

/datum/trait/neutral/colour_changing_eyes
	name = "Colour changing eyes"
	desc = "You can change your eye color at will using an intuitive mental process."
	cost = 0
	custom_only = FALSE
	banned_species = list(SPECIES_SHADEKIN, SPECIES_SHADEKIN_CREW)

/datum/trait/neutral/colour_changing_eyes/apply(datum/species/S, mob/living/carbon/human/H, list/trait_prefs)
	..()
	grant(H, granted_verb(/mob/living/carbon/human/proc/shapeshifter_select_eye_colour), src)

/* // Commented out in lieu of finding a better solution.
/datum/trait/neutral/coldadapt/xenochimera
	sort = TRAIT_SORT_SPECIES
	allowed_species = list(SPECIES_XENOCHIMERA)
	name = "Xenochimera: Temp. Adapted, Cold"
	desc = "You have adapted to withstand much colder temperatures than other species, and can even be comfortable in extremely cold environments. You are also more vulnerable to hot environments, and have a lower body temperature as a consequence of these adaptations, thanks to your evolutionary efforts."
	cost = 0
	category = 0
	can_take = ORGANICS // (Not sure if this is needed for Xenochimera-specific sub-version.)
	custom_only = FALSE
	excludes = list(/datum/trait/neutral/hotadapt, /datum/trait/neutral/hotadapt/xenochimera)
/datum/trait/neutral/hotadapt/xenochimera
	sort = TRAIT_SORT_SPECIES
	allowed_species = list(SPECIES_XENOCHIMERA)
	name = "Xenochimera: Temp. Adapted, Heat"
	desc = "You have adapted to withstand much hotter temperatures than other species, and can even be comfortable in extremely hot environments. You are also more vulnerable to cold environments, and have a higher body temperature as a consequence of these adaptations, thanks to your evolutionary efforts."
	cost = 0
	category = 0
	can_take = ORGANICS // negates the need for suit coolers entirely for synths, so no. (Not sure if this is needed for Xenochimera-specific sub-version.)
	custom_only = FALSE
	excludes = list(/datum/trait/neutral/coldadapt, /datum/trait/neutral/coldadapt/xenochimera)
*/

/datum/trait/neutral/autohiss_unathi/xenochimera
	sort = TRAIT_SORT_SPECIES
	allowed_species = list(SPECIES_XENOCHIMERA)
	name = "Xenochimera: Autohiss (Unathi)"
	desc = "You roll your S's and x's"
	cost = 0
	custom_only = FALSE
	var_changes = list(
	autohiss_basic_map = list(
			"s" = list("ss", "sss", "ssss")
		),
	autohiss_extra_map = list(
			"x" = list("ks", "kss", "ksss")
		),
	autohiss_exempt = list("Sinta'unathi"))
	excludes = list(
		/datum/trait/neutral/autohiss_unathi,
		/datum/trait/neutral/autohiss_tajaran,
		/datum/trait/neutral/autohiss_zaddat,
		/datum/trait/neutral/autohiss_vassilian,
		/datum/trait/neutral/autohiss_yingish,
		/datum/trait/neutral/autohiss_tajaran/xenochimera,
		/datum/trait/neutral/autohiss_zaddat/xenochimera,
		/datum/trait/neutral/autohiss_vassilian/xenochimera,
		/datum/trait/neutral/autohiss_yingish/xenochimera)

/datum/trait/neutral/autohiss_tajaran/xenochimera
	sort = TRAIT_SORT_SPECIES
	allowed_species = list(SPECIES_XENOCHIMERA)
	name = "Xenochimera: Autohiss (Tajaran)"
	desc = "You roll your R's."
	cost = 0
	custom_only = FALSE
	var_changes = list(
	autohiss_basic_map = list(
			"r" = list("rr", "rrr", "rrrr")
		),
	autohiss_exempt = list("Siik"))
	excludes = list(
		/datum/trait/neutral/autohiss_unathi,
		/datum/trait/neutral/autohiss_tajaran,
		/datum/trait/neutral/autohiss_zaddat,
		/datum/trait/neutral/autohiss_vassilian,
		/datum/trait/neutral/autohiss_yingish,
		/datum/trait/neutral/autohiss_unathi/xenochimera,
		/datum/trait/neutral/autohiss_zaddat/xenochimera,
		/datum/trait/neutral/autohiss_vassilian/xenochimera,
		/datum/trait/neutral/autohiss_yingish/xenochimera)

/datum/trait/neutral/autohiss_zaddat/xenochimera
	sort = TRAIT_SORT_SPECIES
	allowed_species = list(SPECIES_XENOCHIMERA)
	name = "Xenochimera: Autohiss (Zaddat)"
	desc = "You buzz your S's and F's."
	cost = 0
	custom_only = FALSE
	var_changes = list(
	autohiss_basic_map = list(
			"f" = list("v","vh"),
			"ph" = list("v", "vh")
		),
	autohiss_extra_map = list(
			"s" = list("z", "zz", "zzz"),
			"ce" = list("z", "zz"),
			"ci" = list("z", "zz"),
			"v" = list("vv", "vvv")
		),
	autohiss_exempt = list(LANGUAGE_ZADDAT,LANGUAGE_VESPINAE))
	excludes = list(
		/datum/trait/neutral/autohiss_tajaran,
		/datum/trait/neutral/autohiss_unathi,
		/datum/trait/neutral/autohiss_zaddat,
		/datum/trait/neutral/autohiss_vassilian,
		/datum/trait/neutral/autohiss_yingish,
		/datum/trait/neutral/autohiss_unathi/xenochimera,
		/datum/trait/neutral/autohiss_tajaran/xenochimera,
		/datum/trait/neutral/autohiss_vassilian/xenochimera,
		/datum/trait/neutral/autohiss_yingish/xenochimera)

/datum/trait/neutral/autohiss_vassilian/xenochimera
	sort = TRAIT_SORT_SPECIES
	allowed_species = list(SPECIES_XENOCHIMERA)
	name = "Xenochimera: Autohiss (Vassilian)"
	desc = "You buzz your S's, F's, Th's, and R's."
	cost = 0
	custom_only = FALSE
	var_changes = list(
	autohiss_basic_map = list(
		"s" = list("sz", "z", "zz"),
		"f" = list("zk")
		),
	autohiss_extra_map = list(
		"th" = list("zk", "szk"),
		"r" = list("rk")
	),
	autohiss_exempt = list(LANGUAGE_VESPINAE))
	excludes = list(
		/datum/trait/neutral/autohiss_tajaran,
		/datum/trait/neutral/autohiss_unathi,
		/datum/trait/neutral/autohiss_zaddat,
		/datum/trait/neutral/autohiss_vassilian,
		/datum/trait/neutral/autohiss_yingish,
		/datum/trait/neutral/autohiss_unathi/xenochimera,
		/datum/trait/neutral/autohiss_tajaran/xenochimera,
		/datum/trait/neutral/autohiss_zaddat/xenochimera,
		/datum/trait/neutral/autohiss_yingish/xenochimera)

/datum/trait/neutral/autohiss_yingish/xenochimera
	sort = TRAIT_SORT_SPECIES
	allowed_species = list(SPECIES_XENOCHIMERA)
	name = "Xenochimera: Autohiss (Yingish)"
	desc = "You pronounce th's with a lisp, a bit like zhis!"
	cost = 0
	custom_only = FALSE
	var_changes = list(
	autohiss_basic_map = list(
			"thi" = list("z"),
			"shi" = list("z"),
			"tha" = list("z"),
			"tho" = list("z")
		),
	autohiss_extra_map = list(
			"the" = list("z"),
			"so" = list("z")
		),
	autohiss_exempt = list())
	excludes = list(
		/datum/trait/neutral/autohiss_tajaran,
		/datum/trait/neutral/autohiss_unathi,
		/datum/trait/neutral/autohiss_zaddat,
		/datum/trait/neutral/autohiss_vassilian,
		/datum/trait/neutral/autohiss_yingish,
		/datum/trait/neutral/autohiss_unathi/xenochimera,
		/datum/trait/neutral/autohiss_tajaran/xenochimera,
		/datum/trait/neutral/autohiss_zaddat/xenochimera,
		/datum/trait/neutral/autohiss_vassilian/xenochimera)

/datum/trait/neutral/waddle
	name = "Waddle / Animated Movement (Adjustable)"
	desc = "You move with a waddle or otherwise animated movement! Has adjustable settings with more adjustments able to be made in game!"
	cost = 0
	custom_only = FALSE
	is_genetrait = TRUE
	hidden = FALSE
	has_preferences = list("waddler" = list(TRAIT_PREF_TYPE_BOOLEAN, "Waddle on Spawn", TRAIT_NO_VAREDIT_TARGET, TRUE))
	added_component_path = /datum/trait_state/waddle_trait

/datum/trait/neutral/waddle/apply(datum/species/S,mob/living/carbon/human/H, list/trait_prefs)
	..()
	var/datum/trait_state/waddle_trait/G = H.get_trait_state(added_component_path)
	if(trait_prefs)
		G.waddling = trait_prefs["waddler"]

/datum/trait/neutral/nutritiongrow
	name = "Growing"
	desc = "After you consume enough nutrition, you start to slowly grow while metabolizing nutrition faster."
	cost = 0
	hidden = FALSE // Disabled on Virgo
	added_component_path = /datum/trait_state/nutrition_size_change/growing

/datum/trait/neutral/nutritionshrink
	name = "Shrinking"
	desc = "If you don't eat enough, your body starts shrinking to make up the difference!"
	cost = 0
	hidden = FALSE // Disabled on Virgo
	added_component_path = /datum/trait_state/nutrition_size_change/shrinking

/datum/trait/neutral/disease_carrier
	name = "Disease Carrier"
	desc = "Your species is a carrier of diseases! Watch out for virologists."
	excludes = list(/datum/trait/neutral/strongimmunesystem)
	cost = 0
	can_take = ORGANICS
	custom_only = FALSE

/datum/trait/neutral/disease_carrier/apply(datum/species/S, mob/living/carbon/human/H, trait_prefs)
	..()
	H.give_random_dormant_disease(200, 2, 3, 1, 9)

/datum/trait/neutral/strongimmunesystem
	name = "Strong Immune System"
	desc = "Your immune system is so strong, that not even dormant diseases can survive in you."
	cost = 0

	can_take = ORGANICS

/datum/trait/neutral/strongimmunesystem/apply(datum/species/S, mob/living/carbon/human/H, trait_prefs)
	..()
	add_trait(H, STRONG_IMMUNITY_TRAIT, ROUNDSTART_TRAIT)

/datum/trait/neutral/hide
	name = "Hide"
	desc = "You can hide beneath objects!"
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/hide/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/proc/hide), src)

/datum/trait/neutral/small_mouth_extreme
	name = "Slow Eater"
	desc = "It takes four times as many bites to finish food as it does for most people."
	cost = 0
	var_changes = list("bite_mod" = 0.25)
	custom_only = FALSE

/datum/trait/neutral/small_mouth
	name = "Slow Eater, Minor"
	desc = "It takes twice as many bites to finish food as it does for most people."
	cost = 0
	var_changes = list("bite_mod" = 0.5)
	custom_only = FALSE

/datum/trait/neutral/big_mouth
	name = "Fast Eater, Minor"
	desc = "It takes half as many bites to finish food as it does for most people."
	cost = 0
	var_changes = list("bite_mod" = 2)
	custom_only = FALSE

/datum/trait/neutral/big_mouth_extreme
	name = "Fast Eater"
	desc = "It takes a quarter as many bites to finish food as it does for most people."
	cost = 0
	var_changes = list("bite_mod" = 4)
	custom_only = FALSE

// Doing this BC I can't rename the datum without fucking over savefiles, so meh. Hyper > Extreme, right?
/datum/trait/neutral/big_mouth_hyper
	name = "Fast Eater, Major"
	desc = "You will eat anything instantly, in one bite."
	cost = 0
	var_changes = list("bite_mod" = 16) // Setting this intentionally ridiculously high, so anything will overflow and be eaten in one go.
	custom_only = FALSE

/datum/trait/neutral/slip_reflex
	name ="Slippery Reflexes"
	desc = "Your reflexes are quick enough to react to slippery surfaces. You are not immune though."
	cost = 0

/datum/trait/neutral/slip_reflex/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	add_trait(H, SLIP_REFLEX_TRAIT, ROUNDSTART_TRAIT)

/datum/trait/neutral/glowing_radiation
	name = "Radioactive Glow"
	desc = "You emit a glow when exposed to radiation! This does not prevent you from being harmed by radiation."
	cost = 0
	has_preferences = list("glow_color" = list(TRAIT_PREF_TYPE_COLOR, "Glow color", TRAIT_NO_VAREDIT_TARGET, "#c3f314"))
	added_component_path = /datum/trait_state/radiation_effects
	excludes = list(/datum/trait/positive/radioactive_heal)

/datum/trait/neutral/glowing_radiation/apply(datum/species/S,mob/living/carbon/human/H, list/trait_prefs)
	..()
	var/datum/trait_state/radiation_effects/G = H.get_trait_state(added_component_path)
	if(trait_prefs)
		G.set_radiation_color(trait_prefs["glow_color"])

/* Used twofold:
 * One, for scenes where someone is using dominate-pred and they don't want to easily be detected who is in control at what time.
 * Two, for characters that aren't exactly 'normal' in the sense of a singular mind and their body structure would accompany this. (Think Diona)
 * Additionally, changelings will appear as though they have this trait.
*/
/datum/trait/neutral/abnormal_mind
	name = "Unique Mind-structure"
	desc = "Your body's neurological structure is unusual, causing sleevemates to have difficulty in identifying any minds within your body as a proper match!"
	cost = 0

	can_take = ORGANICS

/datum/trait/neutral/abnormal_mind/apply(datum/species/S, mob/living/carbon/human/H, trait_prefs)
	..()
	add_trait(H, UNIQUE_MINDSTRUCTURE, ROUNDSTART_TRAIT)

/datum/trait/neutral/slobber
	name = "Major Slobberer"
	desc = "You produce more saliva than most people and leave people dripping when you lick them."
	tutorial = "Lick someone! Consensually please!"

	cost = 0
	custom_only = FALSE

/datum/trait/neutral/slobber/apply(datum/species/S, mob/living/carbon/human/human)
	..()
	add_trait(human, TRAIT_SLOBBER, ROUNDSTART_TRAIT)

/datum/trait/neutral/slip_prone
	name = "Slip Prone (Vore)"
	desc = "You're prone to slips, trips, and falls when next to others, resulting in occasionally falling into them! (This takes spontaneous prefs into account!)"
	cost = 0
	is_genetrait = FALSE
	hidden = FALSE
	custom_only = FALSE
	added_capability = /datum/capability/slip_prone
	excludes = list(/datum/trait/negative/unlucky/major, /datum/trait/negative/unlucky)

/datum/trait/neutral/mobegglaying
	name = "Egg Laying"
	desc = "You can lay eggs, much like an avian."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/mobegglaying/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/proc/mobegglaying), src)

/datum/trait/neutral/succubus_bite
	name = "Succubus Bite"
	desc = "Allows you to inject your prey with poison, much like a venemous snake."
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/succubus_bite/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/proc/succubus_bite), src)

/datum/trait/neutral/hotadapt
	can_take = ORGANICS | SYNTHETICS //I think synths made for high heat should exist, considering they can be made spaceproof easily anyhow
	custom_only = FALSE
	banned_species = list(SPECIES_UNATHI)

/datum/trait/neutral/coldadapt
	custom_only = FALSE
	banned_species = list(SPECIES_UNATHI)

/datum/trait/neutral/abnormal_mind
	custom_only = FALSE //I see a lot of xenochimera that have this as a trope.
	can_take = ORGANICS | SYNTHETICS //I see more synths with dual minds than organics!
