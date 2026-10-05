/datum/eventkit/fake_pdaconvos
	// ALLOW(instance_list): d: event kit state, one instance
	var/list/names = list()		//Assoc list of refs in fakeRefs = name
	var/list/fakeRefs //Used to find elements in other lists and tracking conversations. MUST BE UNIQUE.
	var/list/fakeJobs //Assoc list of name in names = job

ADMIN_VERB(fake_pdaconvos, R_FUN, "Manage PDA identities", "Creates fake identities for use in setting up PDA props", ADMIN_CATEGORY_FUN_EVENT_KIT)
	return fake_pdaconvos_stage(user, list())

/datum/admin_verb/fake_pdaconvos/proc/fake_pdaconvos_stage(client/user, list/pda_answers)
	if(!("choice" in pda_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/choice/fake_pda_identity, PROC_REF(fake_pdaconvos_answered), answerer = user.mob, pda_answers = pda_answers, pda_key = "choice", question = "What do you wish to do?", title = "Options", choices = list("Add new identity", "Edit existing identity", "Delete existing identity", "Delete holder", "Cancel"))
		return
	var/choice = pda_answers["choice"]
	if(isnull(choice))
		return

	if(choice == "Delete holder")
		QDEL_NULL(user.fakeConversations) // ALLOW(ownership): /client is not a datum; its session disposes this directly held conversation model on disconnect
		return
	if(choice == "Cancel")
		return

	if(!user.fakeConversations || !istype(user.fakeConversations, /datum/eventkit/fake_pdaconvos))
		user.fakeConversations = new /datum/eventkit/fake_pdaconvos // ALLOW(ownership): /client is not a datum; its session disposes this directly held conversation model on disconnect

	var/datum/eventkit/fake_pdaconvos/FPC = user.fakeConversations

	// Everything is asked before anything changes: each answer re-runs this verb.
	if(choice == "Add new identity")
		if(!("ref" in pda_answers))
			if(!user || !user.mob || QDELETED(user.mob))
				return
			open_request(src, /datum/prompt/text/fake_pda_identity, PROC_REF(fake_pdaconvos_answered), answerer = user.mob, pda_answers = pda_answers, pda_key = "ref", question = "Input unique reference. Duplicates are FORBIDDEN!. Players can't see this.Used to uniquely identify conversations in PDAs")
			return
		var/newRef = pda_answers["ref"]
		if(!newRef) return
		if(!("name" in pda_answers))
			if(!user || !user.mob || QDELETED(user.mob))
				return
			open_request(src, /datum/prompt/text/fake_pda_identity, PROC_REF(fake_pdaconvos_answered), answerer = user.mob, pda_answers = pda_answers, pda_key = "name", question = "Input fake name", title = newRef)
			return
		var/new_name = pda_answers["name"]
		if(isnull(new_name)) return
		if(!("job" in pda_answers))
			if(!user || !user.mob || QDELETED(user.mob))
				return
			open_request(src, /datum/prompt/text/fake_pda_identity, PROC_REF(fake_pdaconvos_answered), answerer = user.mob, pda_answers = pda_answers, pda_key = "job", question = "Input fake assignment.", title = newRef)
			return
		var/new_job = pda_answers["job"]
		if(isnull(new_job)) return
		LAZYADD(FPC.fakeRefs, newRef)
		FPC.names[newRef] = new_name
		LAZYSET(FPC.fakeJobs, newRef, new_job)
		to_chat(user, span_notice("You have created [newRef]. Current name: [FPC.names[newRef]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, newRef)]"))
		return

	if(choice == "Edit existing identity")
		if(!("ref" in pda_answers))
			if(!user || !user.mob || QDELETED(user.mob))
				return
			open_request(src, /datum/prompt/choice/fake_pda_identity, PROC_REF(fake_pdaconvos_answered), answerer = user.mob, pda_answers = pda_answers, pda_key = "ref", question = "Pick which identity to edit (details are printed to chat)", title = "identities", choices = FPC.fakeRefs)
			return
		var/ref = pda_answers["ref"]
		if(isnull(ref)) return
		if(!("edit" in pda_answers))
			if(!user || !user.mob || QDELETED(user.mob))
				return
			open_request(src, /datum/prompt/choice/fake_pda_identity, PROC_REF(fake_pdaconvos_answered), answerer = user.mob, pda_answers = pda_answers, pda_key = "edit", buttons = TRUE, question = "You are editing [ref]. Current name: [FPC.names[ref]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, ref)]\nWhat do you wish to edit?", title = "Details", choices = list("Name", "Job", "Cancel"))
			return
		var/editChoice = pda_answers["edit"]
		if(isnull(editChoice)) return
		if(editChoice == "Name")
			if(!("name" in pda_answers))
				if(!user || !user.mob || QDELETED(user.mob))
					return
				open_request(src, /datum/prompt/text/fake_pda_identity, PROC_REF(fake_pdaconvos_answered), answerer = user.mob, pda_answers = pda_answers, pda_key = "name", question = "Input fake name", title = FPC.names[ref])
				return
			var/new_name = pda_answers["name"]
			if(isnull(new_name)) return
			FPC.names[ref] = new_name
			to_chat(user, span_notice("Current data for [ref] are : Current name: [FPC.names[ref]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, ref)]"))
		if(editChoice == "Job")
			if(!("job" in pda_answers))
				if(!user || !user.mob || QDELETED(user.mob))
					return
				open_request(src, /datum/prompt/text/fake_pda_identity, PROC_REF(fake_pdaconvos_answered), answerer = user.mob, pda_answers = pda_answers, pda_key = "job", question = "Input fake name", title = LAZYACCESS(FPC.fakeJobs, ref))
				return
			var/new_job = pda_answers["job"]
			if(isnull(new_job)) return
			LAZYSET(FPC.fakeJobs, ref, new_job)
			to_chat(user, span_notice("Current data for [ref] are : Current name: [FPC.names[ref]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, ref)]"))
		return
	if(choice == "Delete existing identity")
		if(!("ref" in pda_answers))
			if(!user || !user.mob || QDELETED(user.mob))
				return
			open_request(src, /datum/prompt/choice/fake_pda_identity, PROC_REF(fake_pdaconvos_answered), answerer = user.mob, pda_answers = pda_answers, pda_key = "ref", question = "Pick which identity to delete (details are printed to chat)", title = "identities", choices = FPC.fakeRefs)
			return
		var/ref = pda_answers["ref"]
		if(isnull(ref)) return
		if(!("sure" in pda_answers))
			if(!user || !user.mob || QDELETED(user.mob))
				return
			open_request(src, /datum/prompt/choice/fake_pda_identity, PROC_REF(fake_pdaconvos_answered), answerer = user.mob, pda_answers = pda_answers, pda_key = "sure", buttons = TRUE, question = "You are deleting [ref]. Current name: [FPC.names[ref]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, ref)]", title = "are you sure?", choices = list("Yes", "No"))
			return
		var/confirmed = pda_answers["sure"]
		if(confirmed == "Yes")
			LAZYREMOVE(FPC.fakeRefs, ref)
			LAZYREMOVE(FPC.fakeJobs, ref)
			FPC.names -= ref
		return


/*
Invoked by vv topic "fakepdapropconvo" in code\modules\admin\view_variables\topic.dm found in PDA vv dropdown.
*/
/// A prop PDA conversation: select a mode and identity, then up to 30 messages.
/datum/prompt/choice/prop_pda_conversation
	timeout = 0
	rights = R_FUN
	var/identity
	var/messages_left = 30
	var/conversation_message
	recheck_on_open = TRUE

/datum/prompt/text/prop_pda_conversation
	timeout = 0
	rights = R_FUN
	var/identity
	var/messages_left = 30
	recheck_on_open = TRUE

/obj/item/pda/proc/prop_conversation_mode_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/datum/eventkit/fake_pdaconvos/FPC = user.client?.fakeConversations
	if(!FPC)
		return
	if(A.request.answer_value == "Dialogue")
		open_request(src, /datum/prompt/choice/prop_pda_conversation, PROC_REF(prop_conversation_identity_chosen), answerer = user, title = "identities", question = "Pick which identity to use(details are printed to chat)", choices = FPC.fakeRefs)
	if(A.request.answer_value == "TGUI")
		to_chat(user, span_notice("Sorry, the TGUI functionality is not yet implemented - use Dialogue mode!"))

/obj/item/pda/proc/prop_conversation_identity_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/datum/eventkit/fake_pdaconvos/FPC = user.client?.fakeConversations
	if(!FPC)
		return
	var/identity = A.request.answer_value
	to_chat(user, span_notice("You are using [identity]. Current name: [FPC.names[identity]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, identity)]"))
	prop_conversation_ask_message(user, identity, 30)

/obj/item/pda/proc/prop_conversation_ask_message(mob/user, identity, messages_left)
	if(messages_left <= 0)
		return
	open_request(src, /datum/prompt/text/prop_pda_conversation, PROC_REF(prop_conversation_message_entered), answerer = user, question = "Input fake message. Leave empty to cancel. Can create up to 30 messages in a row", max_len = MAX_MESSAGE_LEN, identity = identity, messages_left = messages_left)

/obj/item/pda/proc/prop_conversation_message_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/text/prop_pda_conversation/ask = A.request
	var/conversation_message = ask.answer_value
	if(!conversation_message)
		return
	open_request(src, /datum/prompt/choice/prop_pda_conversation, PROC_REF(prop_conversation_direction_chosen), answerer = ask.answerer, buttons = TRUE, title = "Direction", question = "Received or Sent?", choices = list("Received", "Sent"), identity = ask.identity, messages_left = ask.messages_left, conversation_message = conversation_message)

/obj/item/pda/proc/prop_conversation_direction_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/prop_pda_conversation/ask = A.request
	var/mob/user = ask.answerer
	var/datum/eventkit/fake_pdaconvos/FPC = user.client?.fakeConversations
	var/datum/data/pda/app/messenger/ourPDA = find_program(/datum/data/pda/app/messenger)
	if(!FPC || !ourPDA)
		return
	ourPDA.createFakeMessage(FPC.names[ask.identity], ask.identity, LAZYACCESS(FPC.fakeJobs, ask.identity), ask.answer_value == "Sent" ? 1 : 0, ask.conversation_message)
	prop_conversation_ask_message(user, ask.identity, ask.messages_left - 1)

/obj/item/pda/proc/createPropFakeConversation_admin(mob/M)
	if(!M.client || !check_rights_for(M.client, R_FUN))
		return

	var/datum/eventkit/fake_pdaconvos/FPC = M.client.fakeConversations

	if(!FPC || !istype(FPC, /datum/eventkit/fake_pdaconvos))
		to_chat(M, span_warning("First you must create a new identity with Manage PDA identities in EventKit"))
		return

	open_request(src, /datum/prompt/choice/prop_pda_conversation, PROC_REF(prop_conversation_mode_chosen), answerer = M, buttons = TRUE, title = "TGUI?", question = "Use TGUI or dialogue boxes?", choices = list("TGUI", "Dialogue", "Cancel"))

/datum/prompt/choice/fake_pda_identity
	timeout = 0
	rights = R_FUN
	recheck_on_open = TRUE
	var/list/pda_answers
	var/pda_key

/datum/prompt/choice/fake_pda_identity/recheck_extra()
	return admin_can(answerer?.client, 0) ? null : "no admin rights"

/datum/prompt/text/fake_pda_identity
	timeout = 0
	rights = R_FUN
	recheck_on_open = TRUE
	var/list/pda_answers
	var/pda_key

/datum/prompt/text/fake_pda_identity/recheck_extra()
	return admin_can(answerer?.client, 0) ? null : "no admin rights"

/datum/prompt/text/fake_pda_identity/normalize(given)
	return istext(given) ? given : null

/proc/fake_pda_identity_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/admin_verb/fake_pdaconvos/proc/fake_pdaconvos_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/list/pda_answers
	var/pda_key
	if(istype(A.answer, /datum/prompt/choice/fake_pda_identity))
		var/datum/prompt/choice/fake_pda_identity/ask_choice = A.answer
		pda_answers = ask_choice.pda_answers.Copy()
		pda_key = ask_choice.pda_key
	else
		var/datum/prompt/text/fake_pda_identity/ask_text = A.answer
		pda_answers = ask_text.pda_answers.Copy()
		pda_key = ask_text.pda_key
	var/client/user = A.request.answerer?.client
	if(!user)
		return
	if(fake_pda_identity_advanced_call(A.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(!admin_can(user, permissions))
		admin_log_denial(user, "verb:[src.type]", permissions)
		to_chat(user, span_adminnotice("You lack the permissions to do this."))
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	pda_answers[pda_key] = A.answer.answer_value
	return fake_pdaconvos_stage(user, pda_answers)
