// Bay-prefs Basic tab deleted. The only surviving non-Bay piece is the
// set_biological_gender helper on /datum/preferences, which is still called from name
// random-character flows and several pref editors.

/datum/preferences/proc/set_biological_gender(gender)
	update_preference_by_type(/datum/preference/choiced/gender/biological, gender)
	update_preference_by_type(/datum/preference/choiced/gender/identifying, gender)
