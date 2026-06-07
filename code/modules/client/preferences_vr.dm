// DQEdit — show_in_directory, directory_*, sensorpref, capture_crystal,
// auto_backup_implant, borg_petting migrated to /datum/preference subtypes
// (see code/modules/client/preferences/types/character/directory.dm).

/client/verb/toggle_capture_crystal()
	set name = "Toggle Catchable"
	set category = "Preferences.Character"
	set desc = "Toggles being catchable with capture crystals."

	var/mob/living/L = mob

	var/cur = prefs.read_preference(/datum/preference/toggle/human/capture_crystal)
	prefs.update_preference_by_type(/datum/preference/toggle/human/capture_crystal, !cur)
	if(cur)
		to_chat(src, "You are no longer catchable.")
	else
		to_chat(src, "You are now catchable.")
	if(L && istype(L))
		L.capture_crystal = !cur
	SScharacter_setup.queue_preferences_save(prefs)

	feedback_add_details("admin_verb","TCaptureCrystal") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
