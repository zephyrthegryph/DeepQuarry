GLOBAL_VAR_INIT(client_record_update_lock, FALSE)

// Manually updating records from medical console to a player's save.
/proc/get_current_mob_from_record(datum/data/record/active)
	var/datum/transcore_db/db = GLOB.transcore_service.db_by_mind_name(active.fields["name"])
	if(db)
		var/datum/transhuman/mind_record/record = db.backed_up[active.fields["name"]]
		if(record.mind_ref)
			var/datum/mind/D = record.mind_ref
			if(D.current)
				var/client/C = D.current.client
				if(C && C.ckey != record.ckey)
					return null
			return D.current
	return null


/proc/client_update_record(obj/machinery/computer/COM, user)
	if(!COM || QDELETED(COM))
		return "Invalid console"

	if(jobban_isbanned(user, JOB_RECORDS) )
		COM.visible_message(span_notice("\The [COM] buzzes!"))
		play_sfx(COM, SFX_MACHINES_DENIEDBEEP)
		return "Update syncronization denied (OOC: You are banned from editing records)"

	var/record_string = ""
	var/datum/data/record/active
	var/console_path = null
	if(istype(COM,/obj/machinery/computer/med_data))
		var/obj/machinery/computer/med_data/MCOM = COM
		active = MCOM.active2()
		record_string = "medical"
		console_path = /obj/machinery/computer/med_data
	if(istype(COM,/obj/machinery/computer/skills))
		var/obj/machinery/computer/skills/ECOM = COM
		active = ECOM.active1()
		record_string = "employment"
		console_path = /obj/machinery/computer/skills
	if(istype(COM,/obj/machinery/computer/secure_data))
		var/obj/machinery/computer/secure_data/SCOM = COM
		active = SCOM.active2()
		record_string = "security"
		console_path = /obj/machinery/computer/secure_data

	if(GLOB.client_record_update_lock)
		to_chat(user,"Update already in progress! Please wait a moment...")
		if(COM && !QDELETED(COM))
			COM.visible_message(span_notice("\The [COM] buzzes!"))
			play_sfx(COM, SFX_MACHINES_DENIEDBEEP)
		return "Update already in progress! Please wait a moment..."
	GLOB.client_record_update_lock = TRUE
	om_after(null, 60 SECONDS, /proc/client_record_update_unlock) // the global owner: a global lock

	if(!active || !console_path)
		if(COM && !QDELETED(COM))
			COM.visible_message(span_notice("\The [COM] buzzes!"))
			play_sfx(COM, SFX_MACHINES_DENIEDBEEP)
		return "Update syncronization failed (OOC: Record or console destroyed)"

	to_chat(user,"Update sent! Please wait for a response...")
	message_admins("[user] pushed [record_string] record update to [active.fields["name"]].")

	var/mob/M = get_current_mob_from_record(active)
	if(!M)
		if(COM && !QDELETED(COM))
			COM.visible_message(span_notice("\The [COM] buzzes!"))
			play_sfx(COM, SFX_MACHINES_DENIEDBEEP)
		return "Update syncronization failed (OOC: Player mob does not exist, has no mind record, or is possesssed)"

	var/client/C = M.client
	if(!C)
		if(COM && !QDELETED(COM))
			COM.visible_message(span_notice("\The [COM] buzzes!"))
			play_sfx(COM, SFX_MACHINES_DENIEDBEEP)
		return "Update syncronization failed (OOC: Record's owner is offline)"

	var/datum/preferences/P = C.prefs
	if(P.default_slot != M.mind.loaded_from_slot)
		if(COM && !QDELETED(COM))
			COM.visible_message(span_notice("\The [COM] buzzes!"))
			play_sfx(COM, SFX_MACHINES_DENIEDBEEP)
			to_chat(M, span_warning("[user] attempted to update your [record_string] record, but your current character slot does not match your played slot. Please ensure your currently played character is selected in your Character Setup."))
		return "Update syncronization failed (OOC: Player's current character slot does not match their played slot. They have been informed.)"

	// The owner reviews the change; the flow applies it.
	om_flow_start(/datum/om/flow/client_record_update, M, null, console = REF(COM), console_path = console_path, record = active, record_name = active.fields["name"], record_string = record_string, pusher = "[user]")
	return "Update sent. Waiting for the record's owner to review it."

/// A record pushed from a records console: the owner (actor) chooses to review it, edits the
/// notes, and confirming saves their current slot. A no, a cancel or bad text refuses it.
/datum/om/flow/client_record_update
	name = "client record update"
	/// REF() of the console, looked up again for its beeps.
	var/console
	var/console_path
	var/datum/data/record/record
	var/record_name
	var/record_string
	/// Who pushed it (text).
	var/pusher
	var/reviewed = FALSE

/datum/om/flow/client_record_update/start()
	om_ask(actor, /datum/om/prompt/confirm, PROC_REF(review), title = "Record Updated", message = "Your [record_string] record has been updated from the a records console by [pusher]. Please review the changes made to your [record_string] record. Accepting these changes will SAVE your CURRENT character slot! If your new [record_string] record has errors, it is recomended to have it corrected IC instead of editing it yourself.", yes_text = "Review Changes", no_text = "DENY")

/datum/om/flow/client_record_update/proc/review()
	reviewed = TRUE
	om_ask(actor, /datum/om/prompt/text, PROC_REF(notes_entered), title = "Character Preference", message = "Please review [pusher]'s changes to your [record_string] record before confirming. Confirming will SAVE your CURRENT character slot! If your new [record_string] record major errors, it is recomended to have it corrected IC instead of editing it yourself.", default = html_decode(record.fields["notes"]), max_length = MAX_RECORD_LENGTH, multiline = TRUE)

/datum/om/flow/client_record_update/proc/console_says(message, sound)
	var/obj/machinery/computer/COM = locate(console)
	if(istype(COM) && !QDELETED(COM))
		COM.visible_message(span_notice("\The [COM] [message]!"))
		play_sfx(COM, sound, volume = 50, vary = sound == SFX_MACHINES_DING)

/datum/om/flow/client_record_update/proc/refused()
	message_admins("[record_name] refused [record_string] record update from [pusher][reviewed ? " with review" : " without review"].")
	console_says("buzzes", SFX_MACHINES_DENIEDBEEP)

/datum/om/flow/client_record_update/ended(reason)
	refused()

/datum/om/flow/client_record_update/proc/notes_entered(datum/om/prompt/text/ask)
	var/mob/M = actor
	var/new_data = strip_html_simple(ask.text, MAX_RECORD_LENGTH)
	if(!new_data)
		refused()
		return
	var/datum/preferences/prefs = M?.client?.prefs
	if(!prefs || prefs.default_slot != M.mind?.loaded_from_slot)
		message_admins("[record_name]'s [record_string] record could not be updated, player disconnected or changed slot.")
		console_says("buzzes", SFX_MACHINES_DENIEDBEEP)
		return

	// Update records in the consoles, remember this can happen a while after a record is closed on the console... Use cached data.
	switch(console_path)
		if(/obj/machinery/computer/med_data)
			prefs.write_preference_by_type(/datum/preference/text/human/med_record, new_data)
		if(/obj/machinery/computer/skills)
			prefs.write_preference_by_type(/datum/preference/text/human/gen_record, new_data)
		if(/obj/machinery/computer/secure_data)
			prefs.write_preference_by_type(/datum/preference/text/human/sec_record, new_data)
	record.fields["notes"] = new_data

	// Update player record
	prefs.save_preferences()
	prefs.save_character()
	to_chat(M,span_notice("Your [record_string] record for [record.fields["name"]] has been updated."))
	message_admins("[record.fields["name"]] accepted the [record_string] record update from [pusher].")
	console_says("dings", SFX_MACHINES_DING)

/proc/client_record_update_unlock()
	GLOB.client_record_update_lock = FALSE
