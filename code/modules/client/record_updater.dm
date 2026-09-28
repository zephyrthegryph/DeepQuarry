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
		playsound(COM, 'sound/machines/deniedbeep.ogg', 50, 0)
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
			playsound(COM, 'sound/machines/deniedbeep.ogg', 50, 0)
		return "Update already in progress! Please wait a moment..."
	GLOB.client_record_update_lock = TRUE
	om_after(null, 60 SECONDS, /proc/client_record_update_unlock) // the global owner: a global lock

	if(!active || !console_path)
		if(COM && !QDELETED(COM))
			COM.visible_message(span_notice("\The [COM] buzzes!"))
			playsound(COM, 'sound/machines/deniedbeep.ogg', 50, 0)
		return "Update syncronization failed (OOC: Record or console destroyed)"

	to_chat(user,"Update sent! Please wait for a response...")
	message_admins("[user] pushed [record_string] record update to [active.fields["name"]].")

	var/mob/M = get_current_mob_from_record(active)
	if(!M)
		if(COM && !QDELETED(COM))
			COM.visible_message(span_notice("\The [COM] buzzes!"))
			playsound(COM, 'sound/machines/deniedbeep.ogg', 50, 0)
		return "Update syncronization failed (OOC: Player mob does not exist, has no mind record, or is possesssed)"

	var/client/C = M.client
	if(!C)
		if(COM && !QDELETED(COM))
			COM.visible_message(span_notice("\The [COM] buzzes!"))
			playsound(COM, 'sound/machines/deniedbeep.ogg', 50, 0)
		return "Update syncronization failed (OOC: Record's owner is offline)"

	var/datum/preferences/P = C.prefs
	if(P.default_slot != M.mind.loaded_from_slot)
		if(COM && !QDELETED(COM))
			COM.visible_message(span_notice("\The [COM] buzzes!"))
			playsound(COM, 'sound/machines/deniedbeep.ogg', 50, 0)
			to_chat(M, span_warning("[user] attempted to update your [record_string] record, but your current character slot does not match your played slot. Please ensure your currently played character is selected in your Character Setup."))
		return "Update syncronization failed (OOC: Player's current character slot does not match their played slot. They have been informed.)"

	// The owner reviews the change; client_record_update_answered() applies it.
	om_prompt_sequence(null, M, list(
		list("key" = "review", "message" = "Your [record_string] record has been updated from the a records console by [user]. Please review the changes made to your [record_string] record. Accepting these changes will SAVE your CURRENT character slot! If your new [record_string] record has errors, it is recomended to have it corrected IC instead of editing it yourself.", "title" = "Record Updated", "choices" = list("Review Changes","DENY"), "confirm" = "Review Changes", "on_stop" = GLOBAL_PROC_REF(client_record_update_refused)),
		list("key" = "notes", "kind" = "text", "message" = "Please review [user]'s changes to your [record_string] record before confirming. Confirming will SAVE your CURRENT character slot! If your new [record_string] record major errors, it is recomended to have it corrected IC instead of editing it yourself.", "title" = "Character Preference", "default" = html_decode(active.fields["notes"]), "max_length" = MAX_RECORD_LENGTH, "multiline" = TRUE, "on_stop" = GLOBAL_PROC_REF(client_record_update_refused)),
	), GLOBAL_PROC_REF(client_record_update_answered), list("data" = list("console" = REF(COM), "console_path" = console_path, "record" = active, "record_name" = active.fields["name"], "record_string" = record_string, "user" = "[user]")))
	return "Update sent. Waiting for the record's owner to review it."

/proc/client_record_update_console_says(datum/om/prompt/P, message, sound)
	var/obj/machinery/computer/COM = locate(P.get("console"))
	if(istype(COM) && !QDELETED(COM))
		COM.visible_message(span_notice("\The [COM] [message]!"))
		playsound(COM, sound, 50, sound == 'sound/machines/ding.ogg')

/proc/client_record_update_refused(datum/E, mob/M, datum/om/prompt/P)
	message_admins("[P.get("record_name")] refused [P.get("record_string")] record update from [P.get("user")][isnull(P.get("review")) ? " without review" : " with review"].")
	client_record_update_console_says(P, "buzzes", 'sound/machines/deniedbeep.ogg')

/proc/client_record_update_answered(datum/E, mob/M, datum/om/prompt/P)
	var/record_string = P.get("record_string")
	var/datum/data/record/active = P.get("record")
	var/new_data = strip_html_simple(P.get("notes"), MAX_RECORD_LENGTH)
	if(!new_data)
		client_record_update_refused(E, M, P)
		return
	var/datum/preferences/prefs = M?.client?.prefs
	if(!prefs || prefs.default_slot != M.mind?.loaded_from_slot)
		message_admins("[P.get("record_name")]'s [record_string] record could not be updated, player disconnected or changed slot.")
		client_record_update_console_says(P, "buzzes", 'sound/machines/deniedbeep.ogg')
		return

	// Update records in the consoles, remember this can happen a while after a record is closed on the console... Use cached data.
	switch(P.get("console_path"))
		if(/obj/machinery/computer/med_data)
			prefs.write_preference_by_type(/datum/preference/text/human/med_record, new_data)
		if(/obj/machinery/computer/skills)
			prefs.write_preference_by_type(/datum/preference/text/human/gen_record, new_data)
		if(/obj/machinery/computer/secure_data)
			prefs.write_preference_by_type(/datum/preference/text/human/sec_record, new_data)
	active.fields["notes"] = new_data

	// Update player record
	prefs.save_preferences()
	prefs.save_character()
	to_chat(M,span_notice("Your [record_string] record for [active.fields["name"]] has been updated."))
	message_admins("[active.fields["name"]] accepted the [record_string] record update from [P.get("user")].")
	client_record_update_console_says(P, "dings", 'sound/machines/ding.ogg')

/proc/client_record_update_unlock()
	GLOB.client_record_update_lock = FALSE
