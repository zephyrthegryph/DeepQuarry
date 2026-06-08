// savefile is single-version on this fork. No legacy migrations carried over.
#define SAVEFILE_VERSION_MAX	1

/datum/preferences/proc/save_data_needs_update(list/save_data)
	// empty list = new char; anything else with the current version = fine; anything else = stale, wipe it.
	if(!save_data)
		return -1
	if(save_data["version"] == SAVEFILE_VERSION_MAX)
		return -1
	return -2

/datum/preferences/proc/update_preferences(current_version, datum/json_savefile/S)
	return // no migrations on this fork.

/datum/preferences/proc/update_character(current_version, list/save_data)
	return // no migrations on this fork.

/datum/preferences/proc/load_path(ckey, filename = "preferences.json")
	if(!ckey || !load_and_save)
		return
	path = "data/player_saves/[copytext(ckey,1,2)]/[ckey]/[filename]"

/datum/preferences/proc/load_savefile()
	if(load_and_save && !path)
		CRASH("Attempted to load savefile without first loading a path!")
	savefile = new /datum/json_savefile(load_and_save ? path : null)

// General preferences, have to be preloaded
/datum/preferences/proc/load_early_prefs()
	lastchangelog	= savefile.get_entry("lastchangelog", lastchangelog)
	default_slot	= savefile.get_entry("default_slot", default_slot)
	lastnews		= savefile.get_entry("lastnews", lastnews)
	lastlorenews	= savefile.get_entry("lastlorenews", lastlorenews)

/datum/preferences/proc/sanitize_early_prefs()
	lastchangelog	= sanitize_text(lastchangelog, initial(lastchangelog))
	default_slot 	= sanitize_integer(default_slot, 1, CONFIG_GET(number/character_slots), initial(default_slot))
	lastnews		= sanitize_text(lastnews, initial(lastnews))
	lastlorenews	= sanitize_text(lastlorenews, initial(lastlorenews))

/datum/preferences/proc/save_early_prefs()
	savefile.set_entry("lastchangelog",	lastchangelog)
	savefile.set_entry("default_slot",	default_slot)
	savefile.set_entry("lastnews",		lastnews)
	savefile.set_entry("lastlorenews",	lastlorenews)

/datum/preferences/proc/load_preferences(skip_client)
	if(!savefile)
		stack_trace("Attempted to load the preferences of [client] without a savefile; did you forget to call load_savefile?")
		load_savefile()
		if(!savefile)
			stack_trace("Failed to load the savefile for [client] after manually calling load_savefile; something is very wrong.")
			return FALSE

	var/needs_update = save_data_needs_update(savefile.get_entry())
	if(load_and_save && (needs_update <= -2)) //fatal, can't load any data
		var/bacpath = "[path].updatebac" //todo: if the savefile version is higher then the server, check the backup, and give the player a prompt to load the backup
		if(fexists(bacpath))
			fdel(bacpath) //only keep 1 version of backup
		fcopy(savefile.path, bacpath) //byond helpfully lets you use a savefile for the first arg.
		// surface the wipe so the player knows their old savefile was incompatible
		// with the fork's clean-room pref schema. Backup is preserved at <path>.updatebac
		// for manual recovery / admin help.
		if(client)
			to_chat(client, span_warning("Your savefile is from an incompatible upstream version and could not be loaded. A backup was saved to your data directory; please re-create your characters. If you believe this is an error, contact server staff."))
		return FALSE

	if(!skip_client)
		apply_all_client_preferences()

	load_early_prefs()
	sanitize_early_prefs()

	//try to fix any outdated data if necessary
	if(needs_update >= 0)
		var/bacpath = "[path].updatebac" //todo: if the savefile version is higher then the server, check the backup, and give the player a prompt to load the backup
		if(fexists(bacpath))
			fdel(bacpath) //only keep 1 version of backup
		fcopy(savefile.path, bacpath) //byond helpfully lets you use a savefile for the first arg.
		update_preferences(needs_update, savefile) //needs_update = savefile_version if we need an update (positive integer)

		// Bay player_setup.load_preferences chain deleted; PREFERENCE_PLAYER prefs
		// load via the per-pref read() path triggered by read_preference() in apply_all_client_preferences().

		//save the updated version
		var/old_default_slot = default_slot
		// var/old_max_save_slots = max_save_slots

		for(var/slot in savefile.get_entry()) //but first, update all current character slots.
			if (copytext(slot, 1, 10) != "character")
				continue
			var/slotnum = text2num(copytext(slot, 10))
			if (!slotnum)
				continue
			// max_save_slots = max(max_save_slots, slotnum) //so we can still update byond member slots after they lose memeber status
			default_slot = slotnum
			if(load_character())
				save_character()
		default_slot = old_default_slot
		// max_save_slots = old_max_save_slots
		save_preferences()
	// Bay player_setup.load_preferences chain deleted; see comment above.

	return TRUE

/datum/preferences/proc/save_preferences()
	if(!savefile)
		CRASH("Attempted to save the preferences of [client] without a savefile. This should have been handled by load_preferences()")
	savefile.set_entry("version", SAVEFILE_VERSION_MAX) //updates (or failing that the sanity checks) will ensure data is not invalid at load. Assume up-to-date

	// Bay player_setup.save_preferences chain deleted; per-pref write() handles persistence.

	for(var/preference_type in GLOB.preference_entries)
		var/datum/preference/preference = GLOB.preference_entries[preference_type]
		if(preference.savefile_identifier != PREFERENCE_PLAYER)
			continue

		if(!(preference.type in recently_updated_keys))
			continue

		recently_updated_keys -= preference.type

		if(preference_type in value_cache)
			write_preference(preference, preference.pref_serialize(value_cache[preference_type]))

	save_early_prefs()
	savefile.save()

	return TRUE

/datum/preferences/proc/reset_slot()
	var/bacpath = "[path].resetbac"
	if(fexists(bacpath))
		fdel(bacpath) //only keep 1 version of backup
	fcopy(savefile.path, bacpath) //byond helpfully lets you use a savefile for the first arg.

	savefile.remove_entry("character[default_slot]")
	default_slot = 1

	clear_character_previews()

	// Load slot 1 character
	load_character()
	// And save them immediately, in case we load an empty slot
	save_character()
	save_preferences()
	return TRUE

/datum/preferences/proc/load_character(slot)
	SHOULD_NOT_SLEEP(TRUE)
	if(!slot)
		slot = default_slot

	slot = sanitize_integer(slot, 1, CONFIG_GET(number/character_slots), initial(default_slot))
	if(slot != default_slot)
		default_slot = slot
		savefile.set_entry("default_slot", slot)

	var/list/save_data = savefile.get_entry("character[slot]") // This is allowed to be null and will give a -1 in needs_update

	var/needs_update = save_data_needs_update(save_data)
	if(needs_update == -2) //fatal, can't load any data
		return FALSE

	// Read everything into cache (pre-migrations, as migrations should have access to deserialized data)
	// Uses priority order as some values may rely on others for creating default values
	for(var/datum/preference/preference as anything in get_preferences_in_priority_order())
		if(preference.savefile_identifier != PREFERENCE_CHARACTER)
			continue

		value_cache -= preference.type
		read_preference(preference.type)

	// Bay player_setup.load_character chain deleted; pre-cache loop above already
	// loaded every PREFERENCE_CHARACTER pref from save_data via read_preference().

	//try to fix any outdated data if necessary
	//preference updating will handle saving the updated data for us.
	if(needs_update >= 0 || needs_update == -3)
		update_character(needs_update, save_data) //needs_update == savefile_version if we need an update (positive integer

	clear_character_previews()
	return TRUE

/datum/preferences/proc/save_character(override)
	SHOULD_NOT_SLEEP(TRUE)
	if(!savefile)
		return FALSE

	var/tree_key = "character[default_slot]"
	var/first_save = FALSE
	if(!(tree_key in savefile.get_entry()))
		savefile.set_entry(tree_key, list())
		first_save = TRUE
	var/save_data = savefile.get_entry(tree_key)

	for(var/datum/preference/preference as anything in get_preferences_in_priority_order())
		if(preference.savefile_identifier != PREFERENCE_CHARACTER && !first_save && !override)
			continue

		if(!(preference.type in recently_updated_keys) && !first_save && !override)
			continue

		recently_updated_keys -= preference.type

		if(preference.type in value_cache)
			write_preference(preference, preference.pref_serialize(value_cache[preference.type]))

	save_data["version"] = SAVEFILE_VERSION_MAX //load_character will sanitize any bad data, so assume up-to-date.
	// Bay player_setup.save_character chain deleted; per-pref write() handles persistence.

	return TRUE

/datum/preferences/proc/overwrite_character(slot)
	if(!savefile)
		return FALSE
	if(!slot)
		slot = default_slot

	// This basically just changes default_slot without loading the correct data, so the next save call will overwrite
	// the slot
	slot = sanitize_integer(slot, 1, CONFIG_GET(number/character_slots), initial(default_slot))
	if(slot != default_slot)
		default_slot = slot
		// Don't copy NIF to the new slot; clear migrated /datum/preference values.
		update_preference_by_type(/datum/preference/nif_path, null)
		update_preference_by_type(/datum/preference/numeric/nif_durability, null)
		update_preference_by_type(/datum/preference/nif_savedata, list())
		savefile.set_entry("default_slot", slot)

	// Clear stale data before overwriting.
	savefile.remove_entry("character[slot]")

	return TRUE

/datum/preferences/proc/sanitize_preferences()
	// walk the /datum/preference registry and run each entry's sanitize() against
	// its currently-cached value. Per-pref sanitizers live in _pref_sanitizers.dm.
	// Cross-pref invariants are enforced by /datum/preference_constraint subtypes after
	// each update; this proc just makes sure the load-time values are clean.
	//
	// Sanitizers commonly mutate list values in place and return the same reference, so
	// `sanitized != current` would be a same-ref comparison → always FALSE → the cleanup
	// would silently drop. For list values we unconditionally write; the cost is one
	// batched flush on load (dwarfed by the load itself), and the correctness gain is
	// that stale data actually leaves the savefile.
	begin_update_batch()
	for(var/pref_type in GLOB.preference_entries)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		if(pref.savefile_identifier != PREFERENCE_CHARACTER)
			continue
		var/current = read_preference(pref_type)
		var/sanitized = pref.sanitize(current, src)
		if(islist(sanitized) || sanitized != current)
			update_preference_by_type(pref_type, sanitized)
	end_update_batch()
	return TRUE

#undef SAVEFILE_VERSION_MAX
