/mob/living/carbon/human
	// Every human has a body plan with limbs and organs; species setup refills these.
	organs = list()
	organs_by_name = list()

	// Hair, eye, skin and synth colours, styles, skin tone, digitigrade and lips: the looks profile record
	// (/datum/record/appearance, profile_records.dm).

	var/damage_multiplier = 1 //multiplies melee combat damage


	var/datum/robolimb/synthetic		//If they are a synthetic (aka synthetic torso). Also holds the datum for the type of robolimb.

	var/list/all_underwear	// Lazy.
	var/list/all_underwear_metadata = list() // ALLOW(instance_list): d: per-mob all_underwear_metadata, filled at runtime; mobs are few
	var/list/hide_underwear = list() // ALLOW(instance_list): d: per-mob hide_underwear, filled at runtime; mobs are few

	// Age, background, records, flavour text and kit choices: the bio profile record on /mob
	// (/datum/record/identity, code/modules/mob/profile_records.dm).





	var/hand_blood_color

	var/robobody_count = 0 // Counts torso, groin, and head, if they're robotic


	var/identifying_gender // In case the human identifies as another gender than it's biological

	var/step_count = 0 // Track how many footsteps have been taken to know when to play footstep sounds


// Used by mobs in virtual reality to point back to the "real" mob the client belongs to.
	var/mob/living/carbon/human/vr_holder = null
	// Used by "real" mobs after they leave a VR session
	var/mob/living/carbon/human/vr_link = null


	butchery_loot = list(/obj/item/stack/animalhide/human = 1)

	// Horray Furries!
	var/datum/sprite_accessory/ears/ear_style = null
	var/r_ears = 30
	var/g_ears = 30
	var/b_ears = 30
	var/r_ears2 = 30
	var/g_ears2 = 30
	var/b_ears2 = 30
	var/r_ears3 = 30 //Trust me, we could always use more colour. No japes.
	var/g_ears3 = 30
	var/b_ears3 = 30
	var/a_ears = 255 //applied to the ears
	var/a_ears2 = 255 //applied to the horns

	/// secondary ears sprite accessory reference
	var/datum/sprite_accessory/ears/ear_secondary_style
	/// secondary ears color channels; can be null, or a list of #aabbcc hexcolors
	var/list/ear_secondary_colors

	var/datum/sprite_accessory/tail/tail_style = null
	var/r_tail = 30
	var/g_tail = 30
	var/b_tail = 30
	var/r_tail2 = 30
	var/g_tail2 = 30
	var/b_tail2 = 30
	var/r_tail3 = 30
	var/g_tail3 = 30
	var/b_tail3 = 30
	var/a_tail = 255 //applied to the entire tail

	var/wagging = 0 //UGH.

	var/datum/sprite_accessory/wing/wing_style = null
	var/r_wing = 30
	var/g_wing = 30
	var/b_wing = 30
	var/r_wing2 = 30
	var/g_wing2 = 30
	var/b_wing2 = 30
	var/r_wing3 = 30
	var/g_wing3 = 30
	var/b_wing3 = 30

	var/a_wing = 255 //applied to both portions.

	var/flapping = 0

	// Custom Species Name
	var/custom_species

	var/block_hud

	var/phobias		//For holding a list of phobias

	var/redgate_restricted = FALSE
	var/hide_headset = FALSE
	var/hide_glasses = FALSE


/mob/living/carbon/human
	var/vantag_pref = VANTAG_NONE //What's my status?
	var/ability_flags = 0	//Shadekin abilities/potentially other species-based?
	var/sensorpref = 5		//Suit sensor loadout pref
	var/wings_hidden = FALSE
	var/tail_hidden = FALSE
	var/markings_len = 0 //mostly an arbitrary number
	var/low_sorting_priority = FALSE

	var/list/body_writing // assoc list by BP_ key


/mob/living/carbon/human
	var/gender_change_cooldown = 0 // A cooldown for gender and gender indentify changing procs to make it easy to avoid spam of gender change
	var/speech_sound_enabled = TRUE
	var/nutrition_hidden = FALSE

/mob/living/carbon/human/ai_controlled
	low_priority = TRUE

// Tracked inputs of the Life presentation reactions (HUD, sight, canmove; living_systems.dm): their setters publish.
TRACKED(/mob/living/carbon/human, block_hud)
TRACKED(/mob/living/carbon/human, vantag_pref)
/// Limbs and organs attach and detach through the body (body/parts/attach.dm invalidates it): MOB_KEY_HEALTH.
PUBLISHED_BY(/mob/living/carbon/human, organs, MOB_KEY_HEALTH)

/// The phobias step reads them.
TRACKED(/mob/living/carbon/human, phobias)
