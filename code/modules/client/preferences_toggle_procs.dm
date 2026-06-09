//Toggles for preferences, normal clients
/client/verb/toggle_be_special(role in GLOB.be_special_flags)
	set name = "Toggle Special Role Candidacy"
	set category = "Preferences.Character"
	set desc = "Toggles which special roles you would like to be a candidate for, during events."

	var/role_flag = GLOB.be_special_flags[role]
	if(!role_flag)	return

	// be_special migrated to /datum/preference subtype
	var/_cur = prefs.read_preference(/datum/preference/numeric/human/be_special)
	var/_new = _cur ^ role_flag
	prefs.update_preference_by_type(/datum/preference/numeric/human/be_special, _new)
	SScharacter_setup.queue_preferences_save(prefs)

	to_chat(src,"You will [(_new & role_flag) ? "now" : "no longer"] be considered for [role] events (where possible).")

	feedback_add_details("admin_verb","TBeSpecial") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
