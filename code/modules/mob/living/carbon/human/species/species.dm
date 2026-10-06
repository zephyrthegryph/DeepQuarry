/*
	Datum-based species. Should make for much cleaner and easier to maintain race code.
*/

/datum/species

	// Descriptors and strings.
	var/name												// Species name.
	var/name_plural											// Pluralized name (since "[name]s" is not always valid)
	var/blurb = "A completely nondescript species."			// A brief lore summary for use in the chargen screen.
	var/list/catalogue_data = null							// A list of /datum/category_item/catalogue datums, for the cataloguer, or null.

	// Icon/appearance vars.
	var/icobase = 'icons/mob/human_races/r_human.dmi'		// Normal icon set.
	var/deform = 'icons/mob/human_races/r_def_human.dmi'	// Mutated icon set.

	var/speech_bubble_appearance = "normal"					// Part of icon_state to use for speech bubbles when talking.	See talk.dmi for available icons.
	var/fire_icon_state = "humanoid"						// The icon_state used inside OnFire.dmi for when on fire.
	var/suit_storage_icon = 'icons/inventory/suit_store/mob.dmi' // Icons used for worn items in suit storage slot.

	// Damage overlay and masks.
	var/damage_overlays = 'icons/mob/human_races/masks/dam_human.dmi'
	var/damage_mask = 'icons/mob/human_races/masks/dam_mask_human.dmi'
	var/blood_mask = 'icons/mob/human_races/masks/blood_human.dmi'

	var/prone_icon											// If set, draws this from icobase when mob is prone.
	var/blood_color = "#A10808"								// Red.
	var/flesh_color = "#FFC896"								// Pink.
	var/base_color											// Used by changelings. Should also be used for icon previews.

	var/tail												// Name of tail state in species effects icon file.
	var/tail_animation										// If set, the icon to obtain tail animation states from.
	var/tail_hair

	var/icon_scale_x = DEFAULT_ICON_SCALE_X										// Makes the icon wider/thinner.
	var/icon_scale_y = DEFAULT_ICON_SCALE_Y										// Makes the icon taller/shorter.

	var/race_key = 0										// Used for mob icon cache string.
	var/icon/icon_template									// Used for mob icon generation for non-32x32 species.
	var/mob_size	= MOB_MEDIUM
	var/show_ssd = "fast asleep"
	var/virus_immune
	var/short_sighted										// Permanent weldervision.
	var/blood_name = REAGENT_ID_BLOOD								// Name for the species' blood.
	var/blood_reagents = REAGENT_ID_IRON								// Reagent(s) that restore lost blood. goes by reagent IDs.
	var/blood_volume = 560									// Initial blood volume.
	var/bloodloss_rate = 1									// Multiplier for how fast a species bleeds out. Higher = Faster
	var/blood_level_safe = 0.85								//"Safe" blood level; above this, you're OK
	var/blood_level_warning = 0.75								//"Warning" blood level; above this, you're a bit woozy and will have low-level oxydamage (no more than 20, or 15 with inap)
	var/blood_level_danger = 0.6								//"Danger" blood level; above this, you'll rapidly take up to 50 oxyloss, and it will then steadily accumulate at a lower rate
	var/blood_level_fatal = 0.4								//"Fatal" blood level; below this, you take extremely high oxydamage
	var/hunger_factor = 0.05								// Multiplier for hunger.
	var/active_regen_mult = 1								// Multiplier for 'Regenerate' power speed, in human_powers.dm

	var/taste_sensitivity = TASTE_NORMAL							// How sensitive the species is to minute tastes.
	var/allergens = null									// Things that will make this species very sick
	var/medallergens = null									// Medication that will makes this species very sick
	var/allergen_reaction = AG_TOX_DMG|AG_OXY_DMG|AG_EMOTE|AG_PAIN|AG_BLURRY|AG_CONFUSE	// What type of reactions will you have? These the 'main' options and are intended to approximate anaphylactic shock at high doses.
	var/allergen_damage_severity = 2.5							// How bad are reactions to the allergen? Touch with extreme caution.
	var/allergen_disable_severity = 10							// Whilst this determines how long nonlethal effects last and how common emotes are.

	var/min_age = 18
	var/max_age = 70

	var/icodigi = 'icons/mob/human_races/r_digi.dmi'

	// Language/culture vars.
	var/default_language = LANGUAGE_GALCOM					// Default language is used when 'say' is used without modifiers.
	var/language = LANGUAGE_GALCOM							// Default racial language, if any.
	var/species_language = LANGUAGE_GALCOM		// Used on the Character Setup screen (not read; subtypes set a single language)
	var/list/secondary_langs												// The names of secondary languages that are available to this species.
	var/list/speech_sounds													// A list of sounds to potentially play when speaking.
	var/speech_chance									// The likelihood (percent) of a speech sound playing.
	var/num_alternate_languages = 0							// How many secondary languages are available to select at character creation
	var/name_language = LANGUAGE_GALCOM						// The language to use when determining names for this species, or null to use the first name/last name generator

	// The languages the species can't speak without an assisted organ.
	// This list is a guess at things that no one other than the parent species should be able to speak
	// ALLOW(instance_list): kept: shared per species type in share_type_tables(); writers assign a new list
	var/list/assisted_langs = list(LANGUAGE_EAL, LANGUAGE_SKRELLIAN, LANGUAGE_ROOTLOCAL, LANGUAGE_ROOTGLOBAL, LANGUAGE_VOX, LANGUAGE_PROMETHEAN, LANGUAGE_HIVEMIND) // Added Hivemind.

	//Soundy emotey things.
	var/scream_verb_1p = "scream"
	var/scream_verb_3p = "screams"
	var/pain_verb_1p = list("shout", "growl", "grunt", "gasp")
	var/pain_verb_3p = list("shouts", "growls", "grunts", "gasps")
	/* Our base species sounds.
	 * Note that species_sounds is meant to be used in the place of gendered sound.
	 * If your species has gendered sounds, set 'gender_specific_species_sounds' to TRUE, and define your gendered sounds below.
	*/
	var/species_sounds = "None"
	var/gender_specific_species_sounds = FALSE // This variable controls if our audible emotes pick based off of gender. Only humans have these so far.
	var/species_sounds_male = "None" // Safely ignored if the above is set FALSE
	var/species_sounds_female = "None" // Safely ignored if the above is set FALSE
	var/cough_volume = 50 // Self-explanatory, define this separately on your species if the sound files are louder.
	var/sneeze_volume = 50 // Self-explanatory, define this separately on your species if the sound files are louder.
	var/scream_volume = 60 // Self-explanatory, define this separately on your species if the sound files are louder.
	var/pain_volume = 50 // Self-explanatory, define this separately on your species if the sound files are louder.
	var/gasp_volume = 50 // Self-explanatory, define this separately on your species if the sound files are louder.
	var/death_volume = 50 // Self-explanatory, define this separately on your species if the sound files are louder.

	var/footstep = FOOTSTEP_MOB_HUMAN
	var/list/special_step_sounds = null

	// Combat/health/chem/etc. vars.
	/// Body plan a species' members get (set_species swaps the body when it differs).
	var/body_plan = /datum/body/humanoid
	var/total_health = 100								// How much damage the mob can take before entering crit.
	// ALLOW(instance_list): kept: shared per species type in share_type_tables(); give_numbing_bite() assigns a new list
	var/list/unarmed_types = list(							// Possible unarmed attacks that the mob will use in combat,
		/datum/unarmed_attack,
		/datum/unarmed_attack/bite
		)
	var/list/unarmed_attacks = null							// For empty hand harm-intent attack
	/// Multiplier on radiation's EFFECTS (mutation, sickness, radiation burns); the
	/// dose absorbed is not scaled. Injury multipliers are body factors in
	/// `factor_baseline` (BF_INCOMING_*).
	var/radiation_mod = 1
	var/flash_mod =     1								// Stun from blindness modifier (flashes and flashbangs)
	var/flash_burn =    0								// how much damage to take from being flashed if light hypersensitive
	var/sound_mod =     1								// Multiplier to the effective *range* of flashbangs. a flashbang's bang hits an entire screen radius, with some falloff.
	var/throwforce_absorb_threshold = 0					// Ignore damage of thrown items below this value

	var/chem_strength_heal =    1						// Multiplier to most beneficial chem strength
	var/chem_strength_pain =    1						// Multiplier to painkiller strength (could be used in a negative trait to simulate long-term addiction reducing effects, etc.)
	var/chem_strength_tox =	    1						// Multiplier to the strength of toxic or deabilitating chemicals (inc. chloral/sopo/mindbreaker/ambrosia/etc. thresholds)
	var/chem_strength_alcohol = 1						// Multiplier to alcohol effect thresholds; higher means more is needed to reach a given effect tier

	var/chemOD_threshold =		1						// Multiplier to overdose threshold; lower = easier overdosing
	var/chemOD_mod =		1						// Damage modifier for overdose; higher = more damage from ODs
	var/stun_mod =			1						// Multiplier to stun effects; 0.5 = half, - = no effect (immune), 2 = double, etc.
	var/weaken_mod =		1						// Multiplier to weakness effects; 0.5 = half, - = no effect (immune), 2 = double, etc.
													// Stuns + Weakens will be rounded to the nearest whole #. If you set 0.5 mod, on a base stun of 3, the return will be 1.5, which rounds to 1. Be careful.
	var/spice_mod =			1						// Multiplier to spice/capsaicin/frostoil effects; 0.5 = half, 0 = no effect (immunity), 2 = double, etc.
	var/trauma_mod = 		1						// Affects traumatic shock (how fast pain crit happens). 0 = no effect (immunity to pain crit), 2 = double etc.Overriden by "can_feel_pain" var
	// set below is EMP interactivity for nonsynth carbons
	var/emp_sensitivity =		0			// bitflag. valid flags are: EMP_PAIN, EMP_BLIND, EMP_DEAFEN, EMP_CONFUSE, EMP_STUN, and EMP_(BRUTE/BURN/TOX/OXY)_DMG
	var/emp_dmg_mod =		1			// Multiplier to all EMP damage sustained by the mob, if it's EMP-sensitive
	var/emp_stun_mod = 		1			// Multiplier to all EMP disorient/etc. sustained by the mob, if it's EMP-sensitive
	var/vision_flags = SEE_SELF							// Same flags as glasses.
	var/has_vibration_sense = FALSE 	// Motion tracker subsystem

	// Death vars.
	var/meat_type = /obj/item/reagent_containers/food/snacks/meat/human
	var/remains_type = /obj/effect/decal/remains/xeno
	var/gibbed_anim = "gibbed-h"
	var/dusted_anim = "dust-h"
	var/death_sound
	var/death_message = "seizes up and falls limp, their eyes dead and lifeless..."
	var/knockout_message = "has been knocked unconscious!"
	var/cloning_modifier = /datum/body_effect/cloning_sickness

	// Environment tolerance/life processes vars.
	var/reagent_tag											//Used for metabolizing reagents.
	var/breath_type = GAS_O2								// Non-oxygen gas breathed, if any.
	var/poison_type = GAS_PHORON								// Poisonous air.
	var/exhale_type = GAS_CO2								// Exhaled gas type.
	var/water_breather = FALSE
	var/suit_inhale_sound = SFX_EFFECTS_MOB_EFFECTS_SUIT_BREATHE_IN
	var/suit_exhale_sound = SFX_EFFECTS_MOB_EFFECTS_SUIT_BREATHE_OUT
	var/bad_swimmer = FALSE

	var/body_temperature = BODYTEMP_NORMAL							// Species will try to stabilize at this temperature. (also affects temperature processing)

	// Cold
	var/cold_level_1 = 260									// Cold damage level 1 below this point.
	var/cold_level_2 = 200									// Cold damage level 2 below this point.
	var/cold_level_3 = 120									// Cold damage level 3 below this point.

	var/breath_cold_level_1 = 240							// Cold gas damage level 1 below this point.
	var/breath_cold_level_2 = 180							// Cold gas damage level 2 below this point.
	var/breath_cold_level_3 = 100							// Cold gas damage level 3 below this point.

	var/cold_discomfort_level = 285							// Aesthetic messages about feeling chilly.
	var/list/cold_discomfort_strings = list( // ALLOW(instance_list): kept: shared per species type in share_type_tables(); writers assign a new list
		"You feel chilly.",
		"You shiver suddenly.",
		"Your chilly flesh stands out in goosebumps."
		)

	// Hot
	var/heat_level_1 = 360									// Heat damage level 1 above this point.
	var/heat_level_2 = 400									// Heat damage level 2 above this point.
	var/heat_level_3 = 1000									// Heat damage level 3 above this point.

	var/breath_heat_level_1 = 380							// Heat gas damage level 1 below this point.
	var/breath_heat_level_2 = 450							// Heat gas damage level 2 below this point.
	var/breath_heat_level_3 = 1250							// Heat gas damage level 3 below this point.

	var/heat_discomfort_level = 315							// Aesthetic messages about feeling warm.
	var/list/heat_discomfort_strings = list( // ALLOW(instance_list): kept: shared per species type in share_type_tables(); writers assign a new list
		"You feel sweat drip down your neck.",
		"You feel uncomfortably warm.",
		"Your skin prickles in the heat."
		)

	var/water_resistance = 0.1								// How wet the species gets from being splashed.
	var/water_damage_mod = 0								// How much water damage is multiplied by when splashing this species.

	var/passive_temp_gain = 0								// Species will gain this much temperature every second
	var/hazard_high_pressure = HAZARD_HIGH_PRESSURE			// Dangerously high pressure.
	var/warning_high_pressure = WARNING_HIGH_PRESSURE		// High pressure warning.
	var/warning_low_pressure = WARNING_LOW_PRESSURE			// Low pressure warning.
	var/hazard_low_pressure = HAZARD_LOW_PRESSURE			// Dangerously low pressure.
	var/safe_pressure = ONE_ATMOSPHERE
	var/minimum_breath_pressure = 16						// Minimum required pressure for breath, in kPa


	/// Body factors every member of the species has (BF_* -> value), e.g.
	/// slowdown and metabolism. See code/modules/body/factors.dm.
	var/alist/factor_baseline
	/// Factor tables granted by traits and perks applied to this species
	/// instance. Lazy list of alists.
	var/list/granted_factors

	// HUD data vars.
	var/datum/hud_data/hud
	var/hud_type
	var/health_hud_intensity = 1							// This modifies how intensely the health hud is colored.

	// Body/form vars.
	var/list/inherent_verbs									// Species-specific verbs.
	var/has_fine_manipulation = 1							// Can use small items.
	var/siemens_coefficient = 1								// The lower, the thicker the skin and better the insulation.
	var/darksight = 2										// Native darksight distance.
	var/flags = NONE											// Various specific features.
	var/appearance_flags = 0								// Appearance/display related features.
	var/spawn_flags = 0										// Flags that specify who can spawn as this species

	var/obj/effect/decal/cleanable/blood/tracks/move_trail = /obj/effect/decal/cleanable/blood/tracks/footprints // What marks are left when walking
	var/list/skin_overlays
	var/has_floating_eyes = 0								// Whether the eyes can be shown above other icons
	var/has_glowing_eyes = 0								// Whether the eyes are shown above all lighting
	var/water_movement = 0									// How much faster or slower the species is in water
	var/snow_movement = 0									// How much faster or slower the species is on snow
	var/dirtslip = FALSE									// If we slip over dirt or not.
	var/can_space_freemove = FALSE							// Can we freely move in space?
	var/can_zero_g_move	= FALSE								// What about just in zero-g non-space?

	var/swim_mult = 1										//multiplier to our z-movement rate for swimming
	var/climb_mult = 1										//multiplier to our z-movement rate for lattices/catwalks

	var/item_slowdown_mod = 1								// How affected by item slowdown the species is.
	var/primitive_form										// Lesser form, if any (ie. monkey for humans)
	var/greater_form										// Greater form, if any, ie. human for monkeys.
	var/holder_type = /obj/item/holder/micro 				//This allows you to pick up crew
	var/gluttonous											// Can eat some mobs. 1 for mice, 2 for monkeys, 3 for people.
	var/soft_landing = FALSE								// Can fall down and land safely on small falls.

	var/crit_mod = 1										// Used for when we go unconscious. Used downstream.
	var/list/env_traits /// Lazy: traits with environment effects (trait/apply adds them).
	var/pixel_offset_x = 0									// Used for offsetting 64x64 and up icons.
	var/pixel_offset_y = 0									// Used for offsetting 64x64 and up icons.
	var/rad_levels = NORMAL_RADIATION_RESISTANCE			//For handle_radiation
	var/rad_removal_mod = 1

	var/ambulant_blood = FALSE								// Force changeling blood effects

	var/rarity_value = 1									// Relative rarity/collector value for this species.
	var/economic_modifier = 2								// How much money this species makes

	var/vanity_base_fit 									//when shapeshifting using vanity_copy_to, this allows you to have add something so they can go back to their original species fit

	var/mudking = FALSE										// If we dirty up tiles quicker

	var/vore_belly_default_variant = "H"

	var/list/default_emotes

	// Determines the organs that the species spawns with and
	// ALLOW(instance_list): kept: shared per species type in share_type_tables(); writers assign a new list
	var/list/has_organ = list(								// which required-organ checks are conducted.
		O_HEART =		/obj/item/organ/internal/heart,
		O_LUNGS =		/obj/item/organ/internal/lungs,
		O_VOICE = 		/obj/item/organ/internal/voicebox,
		O_LIVER =		/obj/item/organ/internal/liver,
		O_KIDNEYS =		/obj/item/organ/internal/kidneys,
		O_BRAIN =		/obj/item/organ/internal/brain,
		O_APPENDIX =	/obj/item/organ/internal/appendix,
		O_SPLEEN =		/obj/item/organ/internal/spleen,
		O_EYES =		/obj/item/organ/internal/eyes,
		O_STOMACH =		/obj/item/organ/internal/stomach,
		O_INTESTINE =	/obj/item/organ/internal/intestine
		)
	var/vision_organ										// If set, this organ is required for vision. Defaults to "eyes" if the species has them.
	var/dispersed_eyes            // If set, the species will be affected by flashbangs regardless if they have eyes or not, as they see in large areas.

	var/list/has_limbs = list( // ALLOW(instance_list): d: nested per-limb data ("descriptor", "has_children") is written per mob copy during organ creation (body/medical code)
		BP_TORSO =	list("path" = /obj/item/organ/external/chest),
		BP_GROIN =	list("path" = /obj/item/organ/external/groin),
		BP_HEAD =	 list("path" = /obj/item/organ/external/head),
		BP_L_ARM =	list("path" = /obj/item/organ/external/arm),
		BP_R_ARM =	list("path" = /obj/item/organ/external/arm/right),
		BP_L_LEG =	list("path" = /obj/item/organ/external/leg),
		BP_R_LEG =	list("path" = /obj/item/organ/external/leg/right),
		BP_L_HAND = list("path" = /obj/item/organ/external/hand),
		BP_R_HAND = list("path" = /obj/item/organ/external/hand/right),
		BP_L_FOOT = list("path" = /obj/item/organ/external/foot),
		BP_R_FOOT = list("path" = /obj/item/organ/external/foot/right)
		)

	var/list/genders = list(MALE, FEMALE) // ALLOW(instance_list): kept: shared per species type in share_type_tables(); writers assign a new list
	var/ambiguous_genders = FALSE // If true, people examining a member of this species whom are not also the same species will see them as gender neutral.	Because aliens.

	// Bump vars
	var/bump_flag = HUMAN			// What are we considered to be when bumped?
	var/push_flags = ~HEAVY			// What can we push?
	var/swap_flags = ~HEAVY			// What can we swap place with?

	var/pass_flags = 0

	//This is used in character setup preview generation (prefences_setup.dm) and human mob
	//rendering (update_icons.dm)
	var/color_mult = 0

	//This is for overriding tail rendering with a specific icon in icobase, for static
	//tails only, since tails would wag when dead if you used this
	var/icobase_tail = 0

	var/wing_hair
	var/wing
	var/wing_animation
	var/icobase_wing
	var/wikilink = null //link to wiki page for species
	var/icon_height = 32
	var/agility = 20 //prob() to do agile things
	var/gun_accuracy_mod = 0	// More is better
	var/gun_accuracy_dispersion_mod = 0	// More is worse

	var/sort_hint = SPECIES_SORT_NORMAL
	//This is so that if a race is using the chimera revive they can't use it more than once.
	//Shouldn't really be seen in play too often, but it's case an admin event happens and they give a non chimera the chimera revive. Only one person can use the chimera revive at a time per race.

	var/organic_food_coeff = 1
	var/synthetic_food_coeff = 0
	var/robo_ethanol_proc = 0 //can we get fuel from booze, as a synth?
	var/robo_ethanol_drunk = 0 //can we get *drunk* from booze, as a synth?
	var/digestion_efficiency = 1 //VORE specific digestion var
	var/metabolism = 0.0015
	var/lightweight = FALSE //Oof! Nonhelpful bump stumbles.
	var/trashcan = FALSE //It's always sunny in the wrestling ring.
	var/eat_minerals = FALSE //HEAVY METAL DIET
	var/base_species = null // Unused outside of a few species
	var/selects_bodytype = SELECTS_BODYTYPE_FALSE // Allows the species to choose from body types like custom species can, affecting suit fitting and etcetera as you would expect.

	var/bloodsucker = FALSE // Allows safely getting nutrition from blood.
	// P2-S5: species FACTS, read instead of comparing species names.
	/// A gelatinous slime body: slime batons and extracts act on it like on a slime.
	var/is_slime_bodied = FALSE
	/// Radiation and mutation can grow malignant organs in this body.
	var/can_host_malignant = TRUE
	/// Which nutrition alert icons the HUD shows (HUNGER_ALERT_*). Synthetic bodies always show synth ones.
	var/hunger_alert_style = HUNGER_ALERT_ORGANIC
	/// Small enough to scoop up whenever its pickup preference allows, carried as a plush, and to slip through plastic flaps.
	var/micro_carry = FALSE
	/// Induced moods (berserk rage, tranquility, unholy hunger) don't take hold of this mind.
	var/mood_immune = FALSE
	var/bloodsucker_controlmode = "always loud" //Allows selecting between bloodsucker control modes. Always Loud corresponds to original implementation.

	var/list/traits = list() // ALLOW(instance_list): d: per-mob trait selection; produceCopy() assigns it and genes Add/Remove in place
	//Vars that need to be copied when producing a copy of species.
	var/static/list/copy_vars = list("base_species", "icobase", "deform", "tail", "tail_animation", "icobase_tail", "color_mult", "primitive_form", "appearance_flags", "flesh_color", "base_color", "blood_mask", "damage_mask", "damage_overlays", "move_trail", "has_floating_eyes")
	var/trait_points = 0

	var/ideal_air_type = null	// Set to something else if you breathe something else from default composition. Used for inbelly air.

	var/micro_size_mod = 0		// How different is our size for interactions that involve us being small?
	var/macro_size_mod = 0		// How different is our size for interactions that involve us being big?
	var/digestion_nutrition_modifier = 1
	var/center_offset = 0.5
	var/can_climb = FALSE
	var/climbing_delay = 1.5	// We climb with a quarter delay

	var/list/food_preference //RS edit. Lazy.
	var/food_preference_bonus = 0

	var/list/species_component // Per-mob state this species adds: /datum/trait_state, /datum/forms, /datum/shadekin or /datum/xenochimera paths.
	var/component_requires_late_recalc = FALSE // If TRUE, the component will do special recalculation stuff at the end of update_icons_body()

	// For Lleill and Hanner
	var/lleill_energy = 200
	var/lleill_energy_max = 200

	var/bite_mod = 1
	var/grab_resist_divisor_victims = 1
	var/grab_resist_divisor_self = 1
	var/grab_power_victims = 0
	var/grab_power_self = 0
	var/waking_speed = 1 //NYI - Used Downstream
	var/lightweight_light = 0
	var/unarmed_bonus = 0 //do you have stronger unarmed attacks?
	var/shredding = FALSE //do you shred when attacking? Affects escaping restraints, and punching normally unpunchable things

	var/default_custom_base = SPECIES_HUMAN

/// Rebuilds unarmed_attacks from unarmed_types. Call it on a mob's private copy
/// (proto_private(H, "species")), never on the registered species.
/datum/species/proc/update_attack_types()
	own_clear(src, nameof(unarmed_attacks), OWN_DELETE)
	for(var/u_type in unarmed_types)
		rel_add(src, nameof(unarmed_attacks), new u_type())

/datum/species/New()
	share_type_tables()
	if(hud_type)
		rel_set(src, nameof(hud), new hud_type())
	else
		rel_set(src, nameof(hud), new /datum/hud_data())

	//If the species has eyes, they are the default vision organ
	if(!vision_organ && has_organ[O_EYES])
		vision_organ = O_EYES

	own_take_all(src, nameof(unarmed_attacks))
	for(var/u_type in unarmed_types)
		rel_add(src, nameof(unarmed_attacks), new u_type())

	update_sort_hint()

/// Names of list vars that subtypes override but nothing edits in place. Every
/// instance of a species type shares the first instance's lists (one per human
/// plus one in GLOB.all_species), so writers must assign a new list, never edit.
TYPE_TABLE_DECLARE(/datum/species, shared_table_vars, list("assisted_langs", "unarmed_types", "cold_discomfort_strings", "heat_discomfort_strings", "has_organ", "genders", "secondary_langs", "inherent_verbs", "default_emotes", "speech_sounds", "species_component"))

/datum/species/proc/share_type_tables()
	var/static/list/tables_by_type = list()
	var/list/shared = tables_by_type[type]
	if(shared)
		for(var/name in shared)
			vars[name] = shared[name] // ALLOW(api): species copy and shared-list interning
		return
	resolve_limb_table()
	shared = list()
	for(var/name in TYPE_TABLE_GET(src, shared_table_vars))
		shared[name] = vars[name]
	tables_by_type[type] = shared

/// Fills the per-limb data create_organs() used to write into the table on every spawn: a default
/// "descriptor" and the "has_children" count. Done once, before the table is interned and frozen,
/// so spawning a mob never writes into a shared (registered) species table.
/datum/species/proc/resolve_limb_table()
	var/list/limbs = list()
	for(var/limb_type in has_limbs)
		var/list/organ_data = has_limbs[limb_type]
		limbs[limb_type] = organ_data.Copy()
	for(var/limb_type in limbs)
		limbs[limb_type]["has_children"] = 0
	for(var/limb_type in limbs)
		var/list/organ_data = limbs[limb_type]
		var/obj/item/organ/external/limb_path = organ_data["path"]
		if(!ispath(limb_path))
			continue
		if(!organ_data["descriptor"])
			organ_data["descriptor"] = initial(limb_path.name)
		var/parent_tag = initial(limb_path.parent_organ)
		if(parent_tag && limbs[parent_tag])
			limbs[parent_tag]["has_children"] = limbs[parent_tag]["has_children"] + 1
	has_limbs = limbs

/datum/species/proc/get_footsep_sounds()
	return footstep

/datum/species/proc/update_sort_hint()
	if(spawn_flags & SPECIES_IS_RESTRICTED)
		sort_hint = SPECIES_SORT_RESTRICTED
	else if(spawn_flags & SPECIES_IS_WHITELISTED)
		sort_hint = SPECIES_SORT_WHITELISTED

/datum/species/proc/sanitize_name(name, robot = 0)
	return sanitizeName(name, MAX_NAME_LEN, robot)

/datum/species/proc/equip_survival_gear(mob/living/carbon/human/H,extendedtank = 0,comprehensive = 0)
	var/boxtype = /obj/item/storage/box/survival //Default survival box

	var/synth = HAS_SYNTHETIC_BIOLOGY(H)

	//Empty box for synths
	if(synth)
		boxtype = /obj/item/storage/box/survival/synth

	//Special box with extra equipment
	else if(comprehensive)
		boxtype = /obj/item/storage/box/survival/comp

	//Create the box
	var/obj/item/storage/box/box = new boxtype(H)

	//If not synth, they get an air tank (if they breathe)
	if(!synth && breath_type)
		//Create a tank (if such a thing exists for this species)
		var/tanktext = "/obj/item/tank/emergency/" + "[breath_type]"
		var/obj/item/tank/emergency/tankpath //Will force someone to come look here if they ever alter this path.
		if(extendedtank)
			tankpath = text2path(tanktext + "/engi")
			if(!tankpath) //Is it just that there's no /engi?
				tankpath = text2path(tanktext + "/double")

		if(!tankpath)
			tankpath = text2path(tanktext)

		if(tankpath)
			new tankpath(box)

	//If they are synth, they get a smol battery
	else if(synth)
		new /obj/item/fbp_backup_cell(box)

	box.calibrate_size()

	if(H.backbag == 1)
		H.equip_to_slot_or_del(box, SLOT_ID_HAND_R)
	else
		H.equip_to_slot_or_del(box, SLOT_ID_IN_BACKPACK)

/// Builds `H`'s part tree from this species' tables, replacing whatever tree
/// it had. The old tree is deleted through its root (the slot policies delete
/// it children first; the detach hook clears every cache). The new one is
/// built parent first: each part is born inside `H` and takes its place in
/// its parent's slot (code/modules/body/parts/), so no list is written here.
/datum/species/proc/create_organs(mob/living/carbon/human/H) //Handles creation of mob organs.

	H.mob_size = mob_size
	var/obj/item/organ/old_root = H.slot_item(SLOT_ID_PART_ROOT)
	if(old_root)
		replaced_by(old_root, H)
	// Parts left over outside the tree (loose after a refused placement).
	for(var/obj/item/organ/stray as anything in H.organs?.Copy())
		replaced_by(stray, H)
	for(var/obj/item/organ/stray as anything in H.internal_organ_list())
		replaced_by(stray, H)

	// Parent first, whatever order the table lists them in.
	var/list/pending = has_limbs.Copy()
	while(length(pending))
		var/placed = 0
		for(var/limb_type in pending.Copy())
			var/list/organ_data = has_limbs[limb_type]
			var/obj/item/organ/external/limb_path = organ_data["path"]
			var/parent_tag = initial(limb_path.parent_organ)
			if(parent_tag && !H.organs_by_name[parent_tag] && (parent_tag in pending))
				continue
			pending -= limb_type
			placed++
			var/obj/item/organ/O = new limb_path(H)
			// "has_children" is precomputed (resolve_limb_table); a private copy may keep the built
			// limb's own name, a registered species' table stays untouched.
			if(!is_registered(src))
				organ_data["descriptor"] = O.name
		if(!placed)
			log_runtime("PARTS: [name] has_limbs has a parent cycle or a missing parent: [jointext(pending, ", ")]")
			break

	for(var/organ_tag in has_organ)
		var/organ_type = has_organ[organ_tag]
		var/obj/item/organ/O = new organ_type(H, 1)
		if(organ_tag != O.organ_tag)
			WARNING("[O.type] has a default organ tag \"[O.organ_tag]\" that differs from the species' organ tag \"[organ_tag]\". Updating organ_tag to match.")
			O.set_organ_tag(organ_tag)

	// set butcherable meats from species
	for(var/obj/item/organ/O in H.organs)
		O.set_initial_meat()
	for(var/obj/item/organ/O in H.internal_organ_list())
		O.set_initial_meat()

/datum/species/proc/hug(mob/living/carbon/human/H, mob/living/target)

	var/t_him = "them"
	if(ishuman(target))
		var/mob/living/carbon/human/T = target
		if(!T.species.ambiguous_genders || (T.species.ambiguous_genders && H.species == T.species))
			switch(T.identifying_gender)
				if(MALE)
					t_him = "him"
				if(FEMALE)
					t_him = "her"
		else
			t_him = "them"
	else
		switch(target.gender)
			if(MALE)
				t_him = "him"
			if(FEMALE)
				t_him = "her"

	if(target.touch_reaction_flags & SPECIES_TRAIT_PERSONAL_BUBBLE)
		act_message(H, target, MSG_SELF(span_notice("%T% moves to avoid being touched by you!")), \
			MSG_OTHERS(span_notice("%T% moves to avoid being touched by %U%!")))
		return

	var/covered_mouth = FALSE
	if((target.touch_reaction_flags & SPECIES_TRAIT_PATTING_DEFENCE) && ishuman(target)) // No need to test this for now if they don't have the trait
		var/mob/living/carbon/human/M = target
		if(M.get_equipped_item(SLOT_ID_HEAD))
			if((M.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE) || (M.get_equipped_item(SLOT_ID_HEAD).flags_inv & HIDEFACE)) // Need to check both because a lot of items set one or the other, rather than both as you'd expect
				covered_mouth = TRUE
		if(M.get_equipped_item(SLOT_ID_MASK))
			if((M.get_equipped_item(SLOT_ID_MASK).body_parts_covered & FACE) || (M.get_equipped_item(SLOT_ID_MASK).flags_inv & HIDEFACE))
				covered_mouth = TRUE
	if(target.is_muzzled())
		covered_mouth = TRUE

	if(H.zone_sel.selecting == BP_HEAD)
		if((target.touch_reaction_flags & SPECIES_TRAIT_PATTING_DEFENCE) && !covered_mouth)
			act_message(H, target, MSG_SELF(span_warning("%T% reflexively bites your hand!")), \
				MSG_OTHERS(span_warning("%T% reflexively bites the hand of %U% to prevent head patting!")))
			H.injure(INJURY_PIERCE, 1, H.hand ? BP_L_HAND : BP_R_HAND, target) // Bitten
		else
			act_message(H, target, MSG_SELF(span_notice("You pat %T% on the head.")), MSG_OTHERS(span_notice("%U% pats %T% on the head.")))
	else if(H.zone_sel.selecting == BP_R_HAND || H.zone_sel.selecting == BP_L_HAND)
		act_message(H, target, MSG_SELF(span_notice("You shake %T%'s hand.")), MSG_OTHERS(span_notice("%U% shakes %T%'s hand.")))
	else if(H.zone_sel.selecting == "mouth")
		if((target.touch_reaction_flags & SPECIES_TRAIT_PATTING_DEFENCE) && !covered_mouth)
			act_message(H, target, MSG_SELF(span_warning("%T% reflexively bites your hand!")), \
				MSG_OTHERS(span_warning("%T% reflexively bites the hand of %U% to prevent nose booping!")))
			H.injure(INJURY_PIERCE, 1, H.hand ? BP_L_HAND : BP_R_HAND, target) // Bitten
		else
			act_message(H, target, MSG_SELF(span_notice("You boop %T% on the nose.")), MSG_OTHERS(span_notice("%U% boops %T%'s nose.")))
	else if(H.zone_sel.selecting == BP_GROIN)
		H.vore_bellyrub(target)
	else
		act_message(H, target, MSG_SELF(span_notice("You hug %T% to make [t_him] feel better!")), \
			MSG_OTHERS(span_notice("%U% hugs %T% to make [t_him] feel better!")))

/datum/species/proc/remove_inherent_verbs(mob/living/carbon/human/H)
	if(inherent_verbs)
		for(var/verb_path in inherent_verbs)
			revoke(H, granted_verb(verb_path), src)
	return

/datum/species/proc/add_inherent_verbs(mob/living/carbon/human/H)
	if(inherent_verbs)
		for(var/verb_path in inherent_verbs)
			grant(H, granted_verb(verb_path), src)
	return

/datum/species/proc/handle_post_spawn(mob/living/carbon/human/H) //Handles anything not already covered by basic species assignment.
	add_inherent_verbs(H)
	H.mob_bump_flag = bump_flag
	H.mob_swap_flags = swap_flags
	H.mob_push_flags = push_flags
	H.pass_flags = pass_flags

/datum/species/proc/handle_death(mob/living/carbon/human/H) //Handles any species-specific death events (such as dionaea nymph spawns).
	return

// Strategy called by the human environment system for species and traits with special
// environmental effects.
/datum/species/proc/environment_effects(mob/living/carbon/human/H)
	for(var/datum/trait/env_trait in env_traits)
		env_trait.environment_effects(H)
	return

// Used to update alien icons for aliens.
/datum/species/proc/handle_login_special(mob/living/carbon/human/H)
	return

// As above.
/datum/species/proc/handle_logout_special(mob/living/carbon/human/H)
	return

// Builds the HUD using species-specific icons and usable slots.
/datum/species/proc/build_hud(mob/living/carbon/human/H)
	return

//Used by xenos understanding larvae and dionaea understanding nymphs.
/datum/species/proc/can_understand(mob/other)
	return

// Called when using the shredding behavior, returning unarmed damage value
//CheckHighDamage returns the damage value of the attack if it meets at least the noted value
/datum/species/proc/can_shred(mob/living/carbon/human/H, ignore_intent, checkhighdamage = 0)

	if(!ignore_intent && !H.combat_mode) // the shredder's posture (state): combat mode on means claws out
		return 0

	if(H.get_feralness())
		return TRUE

	var/damage = 0
	var/shreds = (shredding * 5)

	for(var/datum/unarmed_attack/attack in unarmed_attacks)
		if(!attack.is_usable(H))
			continue
		damage = max(damage, attack.get_unarmed_damage(H) + 5)
		if(attack.shredding)
			shreds = 5
	if((checkhighdamage && damage >= checkhighdamage) || shreds)
		shreds += damage
	return shreds

// Strategy called by the human NPC system each cycle the mob has no client.
/// Does npc_behaviour() have anything to do for `H` right now? The life stage idles while it
/// doesn't (MED-6). Override alongside npc_behaviour().
/datum/species/proc/npc_behaviour_active(mob/living/carbon/human/H)
	return H.stat == CONSCIOUS && H.ai_brain && H.resting

/datum/species/proc/npc_behaviour(mob/living/carbon/human/H)
	if(H.stat == CONSCIOUS && H.ai_brain)
		if(H.resting)
			H.set_resting(FALSE)
			H.update_canmove()
	return

// Called when lying down on a water tile.
/datum/species/proc/can_breathe_water()
	return water_breather

// Called when standing on a water tile.
/datum/species/proc/is_bad_swimmer()
	return bad_swimmer

// Impliments different trails for species depending on if they're wearing shoes.
/datum/species/proc/get_move_trail(mob/living/carbon/human/H)
	if( H.get_equipped_item(SLOT_ID_SHOES) || ( H.get_equipped_item(SLOT_ID_SUIT) && (H.get_equipped_item(SLOT_ID_SUIT).body_parts_covered & FEET) ) )
		return /obj/effect/decal/cleanable/blood/tracks/footprints
	else
		return move_trail

/datum/species/proc/update_skin(mob/living/carbon/human/H)
	return

/datum/species/proc/get_eyes(mob/living/carbon/human/H)
	return

/datum/species/proc/can_overcome_gravity(mob/living/carbon/human/H)
	return FALSE

// Used for any extra behaviour when falling and to see if a species will fall at all.
/datum/species/proc/can_fall(mob/living/carbon/human/H)
	return TRUE

// Used to find a special target for falling on, such as pouncing on someone from above.
/datum/species/proc/find_fall_target_special(source, landing)
	return FALSE

// Used to override normal fall behaviour. Use only when the species does fall down a level.
/datum/species/proc/fall_impact_special(mob/living/carbon/human/H, atom/A)
	return FALSE

// Allow species to display interesting information in the human stat panels
/datum/species/proc/get_status_tab_items(mob/living/carbon/human/H)
	return ""

/datum/species/proc/handle_water_damage(mob/living/carbon/human/H, amount = 0)
	amount *= 1 - H.get_water_protection()
	amount *= water_damage_mod
	if(amount > 0)
		H.injure(INJURY_TOXIN, amount)

/datum/species/proc/handle_falling(mob/living/carbon/human/H, atom/hit_atom, damage_min, damage_max, silent, planetary)
	var/turf/landing = get_turf(hit_atom)
	if(!istype(landing))
		return FALSE
	if(planetary || !istype(H))
		return FALSE
	//commented out, as this turf doesn't exist upstream
	/*if(istype(landing, /turf/simulated/floor/boxing))
		if(!silent)
			to_chat(H, span_notice("\The [landing] cushions your fall."))
			landing.visible_message(span_infoplain(span_bold("\The [H]") + " 's fall is cushioned by \The [landing]."))
			play_sfx(H, SFX_RUSTLE, extrarange = 0)
		if(!soft_landing)
			H.status_at_least(STAT_WEAKENED, 10)
		return TRUE*/
	//end edit
	if(istype(landing, /turf/simulated/floor/water))
		var/turf/simulated/floor/water/W = landing
		if(W.depth)
			if(!silent)
				to_chat(H, span_notice("You splash down into \the [landing]."))
				landing.visible_message(span_infoplain(span_bold("\The [H]") + " splashes down into \The [landing]."))
				play_sfx(H, SFX_EFFECTS_SLOSH)
			return TRUE

	if(soft_landing)

		if(!silent)
			to_chat(H, span_notice("You manage to lower impact of the fall and land safely."))
			landing.visible_message(span_infoplain(span_bold("\The [H]") + " lowers down from above, landing safely."))
			play_sfx(H, SFX_RUSTLE, extrarange = 0)
		return TRUE

	if(has_trait(src, TRAIT_HEAVY_LANDING))

		if(!silent)
			to_chat(H, span_danger("You land with a heavy crash!"))
			landing.visible_message(span_danger(span_bold("\The [H]") + " crashes down from above!"))
			play_sfx(H, SFX_EFFECTS_METEORIMPACT, volume = 75, extrarange = 3)
			for(var/i = 1 to 10)
				H.injure(INJURY_BLUNT, rand((0), (10)), null, landing)
			H.status_at_least(STAT_WEAKENED, 20)
			if(istype(landing, /turf/simulated/floor) && prob(50))
				var/turf/simulated/floor/our_crash = landing
				our_crash.break_tile()
		return TRUE

	return FALSE

/datum/species/proc/post_spawn_special(mob/living/carbon/human/H)
	return

/datum/species/proc/update_misc_tabs(mob/living/carbon/human/H)
	return

/datum/species/proc/handle_base_eyes(mob/living/carbon/human/H, custom_base)
	if(selects_bodytype && custom_base) // only bother if our src species datum allows bases and one is assigned
		var/datum/species/S = GLOB.all_species[custom_base]

		//extract default eye data from species datum
		var/baseHeadPath = S.has_limbs[BP_HEAD]["path"] //has_limbs is a list of lists

		if(!baseHeadPath)
			return // exit if we couldn't find a head path from the base.

		var/obj/item/organ/external/head/baseHead = new baseHeadPath()
		if(!baseHead)
			return // exit if we didn't create the base properly

		var/obj/item/organ/external/head/targetHead = H.get_organ(BP_HEAD)
		if(!targetHead)
			return // don't bother if target mob has no head for whatever reason

		targetHead.eye_icon = baseHead.eye_icon
		targetHead.eye_icon_location = baseHead.eye_icon_location

		if(!QDELETED(baseHead) && baseHead)
			spent(baseHead, H)
	return

/// Call it on a mob's private copy (proto_private(H, "species")), never on the registered species.
/datum/species/proc/give_numbing_bite() //Holy SHIT this is hacky, but it works. Updating a mob's attacks mid game is insane.
	own_clear(src, nameof(unarmed_attacks), OWN_DELETE)
	unarmed_types = unarmed_types + /datum/unarmed_attack/bite/sharp/numbing // copy: the table is shared per type
	for(var/u_type in unarmed_types)
		rel_add(src, nameof(unarmed_attacks), new u_type())

/// Gives `H` this species' per-mob state: /datum/trait_state paths, a /datum/forms type,
/// /datum/shadekin and /datum/xenochimera.
/datum/species/proc/apply_components(mob/living/carbon/human/H)
	if(LAZYLEN(species_component))
		for(var/component in species_component)
			species_state_add(H, component)

/// Remove this species' components that `next` doesn't also use (species change).
/datum/species/proc/remove_components(mob/living/carbon/human/H, datum/species/next)
	for(var/component in species_component)
		if(next && (component in next.species_component))
			continue
		if(!species_state_has(H, component))
			continue
		log_game("SPECIES: removing [component] from [key_name(H)] on species change [name] -> [next?.name].")
		species_state_remove(H, component)

/// Adds one species_component entry to `H`.
/proc/species_state_add(mob/living/carbon/human/H, path)
	if(ispath(path, /datum/trait_state))
		return H.add_trait_state(path)
	if(ispath(path, /datum/forms))
		return H.add_forms(path)
	if(ispath(path, /datum/shadekin))
		return H.add_shadekin(path)
	if(ispath(path, /datum/xenochimera))
		return H.add_xenochimera()
	log_game("SPECIES: unknown species state [path] for [key_name(H)]; ignored.")
	return null

/// TRUE when `H` holds the state for one species_component entry.
/proc/species_state_has(mob/living/carbon/human/H, path)
	if(ispath(path, /datum/trait_state))
		return !!H.get_trait_state(path)
	if(ispath(path, /datum/forms))
		return istype(H.character_forms, path)
	if(ispath(path, /datum/shadekin))
		return istype(H.shadekin, path)
	if(ispath(path, /datum/xenochimera))
		return !!H.xenochimera
	return FALSE

/// Removes the state for one species_component entry from `H`.
/proc/species_state_remove(mob/living/carbon/human/H, path)
	if(ispath(path, /datum/trait_state))
		return H.remove_trait_state(path)
	if(ispath(path, /datum/forms))
		return H.remove_forms(path)
	if(ispath(path, /datum/shadekin))
		if(istype(H.shadekin, path))
			H.remove_shadekin()
			return TRUE
		return FALSE
	if(ispath(path, /datum/xenochimera))
		if(H.xenochimera)
			H.remove_xenochimera()
			return TRUE
	return FALSE

/datum/species/proc/produceCopy(list/traits, mob/living/carbon/human/H, custom_base, reset_dna = TRUE) // Traitgenes reset_dna flag required, or genes get reset on resleeve
	ASSERT(src)
	ASSERT(istype(H))
	var/datum/species/new_copy = new src.type()
	new_copy.race_key = race_key
	if (selects_bodytype && custom_base)
		new_copy.base_species = custom_base
		if(selects_bodytype == SELECTS_BODYTYPE_CUSTOM || selects_bodytype == SELECTS_BODYTYPE_ZORREN) //If race selects a bodytype, retrieve the custom_base species and copy needed variables.
			var/datum/species/S = GLOB.all_species[custom_base]
			S.copy_variables(new_copy, copy_vars)

		if(selects_bodytype == SELECTS_BODYTYPE_SHAPESHIFTER)
			H.shapeshifter_change_shape(custom_base, FALSE)

	// The copy's own table first: its has_limbs may be a table interned per type (the registered
	// species' own list), which must never be written.
	new_copy.has_limbs = new_copy.has_limbs?.Copy() || list()
	for(var/organ in has_limbs) //Copy important organ data generated by species.
		var/list/organ_data = has_limbs[organ]
		new_copy.has_limbs[organ] = organ_data.Copy()

	new_copy.traits = traits
	//If you had traits, apply them
	if(new_copy.traits)
		for(var/trait in new_copy.traits)
			var/datum/trait/T = GLOB.all_traits[trait]
			T.apply(new_copy, H, new_copy.traits[trait])

	//Set up a mob. The mob's species is PROTO: the copy becomes its private copy, and the private
	// copy it replaces (often src itself, still read below) is deleted.
	proto_set(H, nameof(H.species), new_copy)
	H.invalidate_factors()
	H.icon_state = new_copy.get_bodytype()

	if(new_copy.holder_type)
		H.holder_type = new_copy.holder_type

	if(H.dna && reset_dna)
		H.dna.ready_dna(H)
	handle_base_eyes(H, custom_base)

	if(H.species.has_vibration_sense)
		H.motiontracker_subscribe()

	return new_copy

//We REALLY don't need to go through every variable. Doing so makes this lag like hell on 515
/// The private copy proto_private() makes of a mob's species (copy-on-write, carbon_defines.dm):
/// a fresh instance with this one's saved vars copied over, lists copied so the copy never
/// shares a mutable list with the registered prototype. tmp/const/global vars (the ownership
/// stamps and reverse indexes among them) are left at the new instance's values.
/// TRUE when `L` holds (as a member or an assoc value) something this species owns.
/datum/species/proc/species_list_holds_owned(list/L)
	for(var/key in L)
		if(isdatum(key) && owner_of(key) == src)
			return TRUE
		if(!isnum(key))
			var/datum/value = L[key]
			if(isdatum(value) && owner_of(value) == src)
				return TRUE
	return FALSE

/datum/species/proto_copy()
	var/datum/species/copy = new type()
	for(var/var_name in vars)
		if(var_name == "vars" || !issaved(vars[var_name]))
			continue
		var/value = vars[var_name]
		if(copy.vars[var_name] == value)
			continue
		// What we own (hud, unarmed_attacks) the copy built for itself in New(); sharing ours
		// would have its teardown or rebuild delete our children.
		if(isdatum(value) && owner_of(value) == src)
			continue
		if(islist(value))
			var/list/L = value
			if(species_list_holds_owned(L))
				continue
			value = L.Copy()
		copy.vars[var_name] = value // ALLOW(api): a species copy writes every species var by name, which is what copying one means
	return copy

/datum/species/proc/copy_variables(datum/species/S, list/whitelist)
	//List of variables to ignore, trying to copy type will runtime.
	//Makes thorough copy of species datum.
	for(var/i in whitelist)
		if(S.vars[i] != vars[i] && !islist(vars[i])) //If vars are same, no point in copying.
			S.vars[i] = vars[i] // ALLOW(api): species copy and shared-list interning

/datum/species/get_bodytype()
	return base_species

/datum/species/proc/update_vore_belly_def_variant()
	// Determine the actual vore_belly_default_variant, if the base species in the VORE tab is set
	switch (base_species)
		if("Teshari")
			vore_belly_default_variant = "T"
		if("Unathi")
			vore_belly_default_variant = "L"

/// Returns a list of names for all allergy types, null if no allergies are present
/proc/assembly_allergy_list(allergens, med_allergens)
	if(allergens > 0 || med_allergens > 0)
		var/list/allergies = list()
		// foods
		if(allergens & ALLERGEN_MEAT)
			allergies.Add("Meat protein")
		if(allergens & ALLERGEN_FISH)
			allergies.Add("Fish protein")
		if(allergens & ALLERGEN_FRUIT)
			allergies.Add("Fruit")
		if(allergens & ALLERGEN_VEGETABLE)
			allergies.Add("Vegetable")
		if(allergens & ALLERGEN_GRAINS)
			allergies.Add("Grain")
		if(allergens & ALLERGEN_BEANS)
			allergies.Add("Bean")
		if(allergens & ALLERGEN_SEEDS)
			allergies.Add("Nut")
		if(allergens & ALLERGEN_DAIRY)
			allergies.Add("Dairy")
		if(allergens & ALLERGEN_FUNGI)
			allergies.Add("Fungi")
		if(allergens & ALLERGEN_COFFEE)
			allergies.Add("Caffeine")
		if(allergens & ALLERGEN_SUGARS)
			allergies.Add("Sugar")
		if(allergens & ALLERGEN_EGGS)
			allergies.Add("Egg")
		if(allergens & ALLERGEN_STIMULANT)
			allergies.Add("Stimulant")
		if(allergens & ALLERGEN_CHOCOLATE)
			allergies.Add("Chocolate")
		if(allergens & ALLERGEN_POLLEN)
			allergies.Add("Pollen")
		if(allergens & ALLERGEN_SALT)
			allergies.Add("Salt")
		// meds
		if(med_allergens & MEDALLERGEN_TRICORD)
			allergies.Add(REAGENT_TRICORDRAZINE)
		if(med_allergens & MEDALLERGEN_BICARD)
			allergies.Add(REAGENT_BICARIDINE)
		if(med_allergens & MEDALLERGEN_DYLO)
			allergies.Add(REAGENT_ANTITOXIN)
		if(med_allergens & MEDALLERGEN_SPACACIL)
			allergies.Add(REAGENT_SPACEACILLIN)
		if(med_allergens & MEDALLERGEN_PERIDAX)
			allergies.Add(REAGENT_PERIDAXON)
		if(med_allergens & MEDALLERGEN_KELOTANE)
			allergies.Add(REAGENT_KELOTANE)
		return allergies
	return null

// An icon file and a trail type path.
