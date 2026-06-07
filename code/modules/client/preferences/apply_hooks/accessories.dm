// DQAdd — Resolve ear/tail/wing style names to species-filtered sprite_accessory objects
// and apply them to the character. The raw style name (e.g. "Fox tail") is a /datum/preference
// pref; the actual character.tail_style is the resolved /datum/sprite_accessory instance.
//
// This is cross-pref because the resolution depends on species (different species expose
// different style lists). It also writes to a character field that the per-pref apply could
// not, since the per-pref apply only sees a string and has no preferences context for
// get_available_styles().

/datum/preference_apply_hook/accessories
	priority = APPLY_HOOK_PRIORITY_ACCESSORIES

/datum/preference_apply_hook/accessories/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	if(!ishuman(target))
		return

	var/list/ear_styles = preferences.get_available_styles(GLOB.ear_styles_list)
	target.ear_style = ear_styles[preferences.read_preference(/datum/preference/text/human/ear_style)]
	target.ear_secondary_style = ear_styles[preferences.read_preference(/datum/preference/text/human/ear_secondary_style)]

	var/list/tail_styles = preferences.get_available_styles(GLOB.tail_styles_list)
	target.tail_style = tail_styles[preferences.read_preference(/datum/preference/text/human/tail_style)]

	var/list/wing_styles = preferences.get_available_styles(GLOB.wing_styles_list)
	target.wing_style = wing_styles[preferences.read_preference(/datum/preference/text/human/wing_style)]
