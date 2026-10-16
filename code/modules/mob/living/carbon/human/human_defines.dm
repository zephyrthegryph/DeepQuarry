/mob/living/carbon/human
	// Every human has a body plan with limbs and organs; species setup refills these.
	organs = list()
	organs_by_name = list()

	// Hair, eye, skin and synth colours, styles, skin tone, digitigrade and lips: the looks profile record
	// (/datum/record/appearance, profile_records.dm).



	var/datum/robolimb/synthetic		//If they are a synthetic (aka synthetic torso). Also holds the datum for the type of robolimb.

	var/list/all_underwear	// Lazy.
	var/list/all_underwear_metadata = list() // ALLOW(instance_list): d: per-mob all_underwear_metadata, filled at runtime; mobs are few
	var/list/hide_underwear = list() // ALLOW(instance_list): d: per-mob hide_underwear, filled at runtime; mobs are few

	// Age, background, records, flavour text and kit choices: the bio profile record on /mob
	// (/datum/record/identity, code/modules/mob/profile_records.dm).





	var/hand_blood_color



	var/identifying_gender // In case the human identifies as another gender than it's biological



	// Used by mobs in virtual reality to point back to the "real" mob the client belongs to.
	// Used by "real" mobs after they leave a VR session


	butchery_loot = list(/obj/item/stack/animalhide/human = 1)

	// Horray Furries!
	var/datum/sprite_accessory/ears/ear_style = null

	/// secondary ears sprite accessory reference
	var/datum/sprite_accessory/ears/ear_secondary_style
	/// secondary ears color channels; can be null, or a list of #aabbcc hexcolors
	var/list/ear_secondary_colors

	var/datum/sprite_accessory/tail/tail_style = null

	var/wagging = 0 //UGH.

	var/datum/sprite_accessory/wing/wing_style = null


	var/flapping = 0

	// Custom Species Name

	var/block_hud

	var/phobias		//For holding a list of phobias

	var/hide_headset = FALSE
	var/hide_glasses = FALSE


/mob/living/carbon/human
	var/vantag_pref = VANTAG_NONE //What's my status?
	var/wings_hidden = FALSE
	var/tail_hidden = FALSE



/mob/living/carbon/human


/mob/living/carbon/human/ai_controlled
	low_priority = TRUE

// Tracked inputs of the Life presentation reactions (HUD, sight, canmove; living_systems.dm): their setters publish.
/// Limbs and organs attach and detach through the body (body/parts/attach.dm invalidates it): MOB_KEY_HEALTH.
PUBLISHED_BY(/mob/living/carbon/human, organs, MOB_KEY_HEALTH)

/// The phobias step reads them.

sparse(/mob/living/carbon/human, gender_change_cooldown, type = num)

/mob/living/carbon/human/var/redgate_restricted = FALSE
sparse(/mob/living/carbon/human, ability_flags, type = num)

/// The real body controlling this VR avatar, or null.
/mob/living/carbon/human/proc/get_vr_holder()
	RETURN_TYPE(/mob/living/carbon/human)
	return link_get(src, LK_VR_HOLDER)

/// The VR avatar remembered by this real body, or null.
/mob/living/carbon/human/proc/get_vr_avatar()
	RETURN_TYPE(/mob/living/carbon/human)
	return link_get(src, LK_VR_AVATAR)
