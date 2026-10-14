/**
 * Admin verb: Convert Player Savefile
 *
 * Converts a player's save data between BYOND .sav (binary) and JSON formats.
 * Used for redundancy, import/export processing, and save file recovery.
 *
 * IMPORTANT: The target player must be logged off before conversion.
 * The verb refuses to run if the player is currently connected, and
 * instructs the admin to tell them to log off first.
 *
 * Files inside the player's vore/ subfolder are excluded from this process.
 * Those files are already JSON and are managed separately.
 */

/// Returns the base save directory for a given ckey.
/proc/get_player_save_dir(ckey)
	return "data/player_saves/[copytext(ckey, 1, 2)]/[ckey]"

ADMIN_VERB(admin_convert_savefile, R_ADMIN, "Convert Player Savefile", "Convert a player's preferences.sav to preferences.json or vice versa. Player must be logged off.", ADMIN_CATEGORY_SERVER_ADMIN)
	if(QDELETED(user.mob))
		return
	var/datum/admin_save_conversion_review/review = new
	review.client_ckey = user.ckey
	rel_set(review, nameof(review.actor), user.mob)
	review.run_step()

/datum/admin_save_conversion_review
	var/tmp/mob/actor
	var/client_ckey
	var/stage = 0
	var/target_text
	var/direction
	var/confirmation

CAPABILITIES(/datum/admin_save_conversion_review)
	ref_one(nameof(actor), /mob)

/datum/admin_save_conversion_review/proc/refusal()
	if(QDELETED(actor) || !GLOB.directory[client_ckey])
		return "The requesting administrator is no longer available."

/datum/admin_save_conversion_review/proc/run_step()
	var/datum/result/result = safe_call(PROC_REF(replay))
	if(!result.ok)
		stack_trace("om flow admin_convert_savefile continuation: [result.error]")
	if(!result.ok || result.value != TRUE)
		retire()

/datum/admin_save_conversion_review/proc/answered(datum/act/request/context)
	if(!context.answer)
		retire()
		return
	switch(stage)
		if(0)
			target_text = context.request.value
		if(1)
			direction = context.request.value
		if(2)
			confirmation = context.request.value
	stage++
	run_step()

/datum/admin_save_conversion_review/proc/replay()
	var/client/user = GLOB.directory[client_ckey]
	if(!user || QDELETED(user.mob))
		return
	rel_set(src, nameof(actor), user.mob)
	// Pick your target.
	if(stage == 0)
		open_request(src, /datum/prompt/text/admin_convert_ckey, PROC_REF(answered), answerer = actor)
		return TRUE
	var/target_ckey = target_text
	if(isnull(target_ckey))
		return
	if(!target_ckey)
		return
	target_ckey = lowertext(target_ckey)

	// Refuse outright if the player is currently connected.
	// Modifying save files while the client is online risks data loss or corruption
	// because the server may overwrite the converted file on the next auto-save.
	for(var/client/C as anything in GLOB.clients)
		if(C.ckey == target_ckey)
			to_chat(user, span_danger("[target_ckey] is currently logged in. Tell them to log off before you try again."))
			message_admins("[key_name_admin(user)] attempted to convert [target_ckey]'s save file, but that player is online.")
			return

	// Also block if they connected at any point this round, even if currently offline.
	if(persistent_client_for(target_ckey))
		to_chat(user, span_danger("[target_ckey] has connected this round. Their save may have been written by the server since then. Wait until next round to convert."))
		message_admins("[key_name_admin(user)] attempted to convert [target_ckey]'s save file, but that player connected this round.")
		return

	// Make sure save files actually exist for this ckey.
	var/save_dir = get_player_save_dir(target_ckey)
	var/has_sav  = fexists("[save_dir]/preferences.sav")
	var/has_json = fexists("[save_dir]/preferences.json")

	if(!has_sav && !has_json)
		to_chat(user, span_danger("No save files found for '[target_ckey]'. Check that the ckey is correct."))
		return

	// Let the admin pick the conversion direction.
	var/list/options = list()
	if(has_sav)
		options += "preferences.sav -> preferences.json"
	if(has_json)
		options += "preferences.json -> preferences.sav"

	if(stage == 1)
		open_request(src, /datum/prompt/choice/admin_convert_direction, PROC_REF(answered), answerer = actor, choices = options, question = "Select the conversion to perform for '[target_ckey]'.")
		return TRUE
	var/direction = src.direction
	if(isnull(direction))
		return
	if(!direction)
		return

	// Warn the admin in case the player has logged in since we checked.
	if(stage == 2)
		open_request(src, /datum/prompt/choice/admin_convert_confirmation, PROC_REF(answered), answerer = actor, question = "WARNING: '[target_ckey]' should be logged off before this runs. Proceeding while they are online can corrupt their save.\n\nAre you sure [target_ckey] is logged off?")
		return TRUE
	var/confirm = confirmation
	if(confirm != "Yes, they are logged off")
		return

	// Re-verify the player is still offline immediately before touching any files.
	for(var/client/C as anything in GLOB.clients)
		if(C.ckey == target_ckey)
			to_chat(user, span_danger("[target_ckey] is now online. Conversion aborted. Tell them to log off and try again."))
			message_admins("[key_name_admin(user)] attempted to convert [target_ckey]'s save file, but that player came online during the confirmation. Blocked.")
			return

	if(direction == "preferences.sav -> preferences.json")
		var/sav_path  = "[save_dir]/preferences.sav"
		var/json_path = "[save_dir]/preferences.json"

		// Back up the existing JSON file before overwriting it.
		if(fexists(json_path))
			var/bak = "[json_path].convbak"
			if(fexists(bak))
				fdel(bak)
			fcopy(json_path, bak)

		var/datum/json_savefile/result = new(json_path)
		result.import_byond_savefile(new /savefile(sav_path))
		result.save()

		log_and_message_admins("converted [target_ckey]'s preferences.sav to preferences.json", user)
		to_chat(user, span_filter_adminlog("Done. [target_ckey]'s preferences.sav has been converted to preferences.json."))

	else if(direction == "preferences.json -> preferences.sav")
		var/json_path = "[save_dir]/preferences.json"
		var/sav_path  = "[save_dir]/preferences.sav"

		// Back up the existing .sav file before overwriting it.
		if(fexists(sav_path))
			var/bak = "[sav_path].convbak"
			if(fexists(bak))
				fdel(bak)
			fcopy(sav_path, bak)
			// Delete the original so new() creates a blank savefile.
			// Without this, old entries not present in the JSON would persist in the file.
			fdel(sav_path)

		var/datum/json_savefile/source = new(json_path)
		var/savefile/result = new(sav_path)
		source.export_to_byond_savefile(result)

		log_and_message_admins("converted [target_ckey]'s preferences.json to preferences.sav", user)
		to_chat(user, span_filter_adminlog("Done. [target_ckey]'s preferences.json has been converted to preferences.sav."))

/datum/admin_save_conversion_review/proc/retire()
	spent(src)

/datum/prompt/text/admin_convert_ckey
	rights = R_ADMIN
	timeout = 0
	title = "Convert Player Savefile"
	question = "Enter the ckey of the player whose save file you want to convert."
	recheck_on_open = TRUE

/datum/prompt/text/admin_convert_ckey/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_save_conversion_review/review = owner
	return review.refusal()

/datum/prompt/choice/admin_convert_direction
	rights = R_ADMIN
	timeout = 0
	title = "Convert Player Savefile"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_convert_direction/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_save_conversion_review/review = owner
	return review.refusal()

/datum/prompt/choice/admin_convert_confirmation
	rights = R_ADMIN
	timeout = 0
	title = "Convert Player Savefile"
	choices = list("Cancel", "Yes, they are logged off")
	buttons = TRUE
	recheck_on_open = TRUE

/datum/prompt/choice/admin_convert_confirmation/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_save_conversion_review/review = owner
	return review.refusal()

