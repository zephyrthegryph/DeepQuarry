// DQ-migrated: equipment scalar prefs.
//
// DQEdit — headset/backbag/pdachoice prefs deleted. Headsets and backpacks are now
// regular loadout gear datums (see code/datums/gear/loadout_standard_kit.dm),
// and the PDA chassis pick was purely cosmetic — players get the default chassis.
// Mob vars H.headset / H.backbag / H.pdachoice still exist with their hardcoded defaults
// in human_defines.dm; the job-outfit pre_equip and antag spawners that read them
// continue to work unchanged (just always pick the canonical first variant now).

// DQEdit — no_jacket pref deleted. Players who want to spawn without a uniform jacket
// pick a different uniform via the regular loadout system. Existing code that read the
// pref (job.dm equip_rank, outfit.dm equip_base) now equips the default unconditionally.


/datum/preference/text/human/ringtone
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "ttone"     // matches legacy disk key
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = 20

/datum/preference/text/human/ringtone/create_default_value()
	return "beep"

/datum/preference/text/human/ringtone/get_pref_choices(datum/preferences/preferences)
	return GLOB.device_ringtones ? assoc_to_keys(GLOB.device_ringtones) : null

/datum/preference/text/human/ringtone/apply_to_human(mob/living/carbon/human/target, value)
	return // read directly from prefs when PDA is built


/datum/preference/toggle/human/communicator_visibility
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "communicator_visibility"
	default_value = FALSE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/communicator_visibility/apply_to_human(mob/living/carbon/human/target, value)
	return
