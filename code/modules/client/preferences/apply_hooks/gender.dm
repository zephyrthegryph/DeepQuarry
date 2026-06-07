// DQAdd — Apply biological/identifying gender from prefs. Biological gender goes through
// character.set_gender() so dependent body state (icons, identity) updates correctly;
// identifying is a direct field. This is two prefs that should always write together to
// preserve invariants, so it lives in a hook rather than two competing per-pref applies.

/datum/preference_apply_hook/gender
	priority = APPLY_HOOK_PRIORITY_DEFAULT

/datum/preference_apply_hook/gender/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	if(!ishuman(target))
		return
	target.set_gender(preferences.read_preference(/datum/preference/choiced/gender/biological))
	target.identifying_gender = preferences.read_preference(/datum/preference/choiced/gender/identifying)
