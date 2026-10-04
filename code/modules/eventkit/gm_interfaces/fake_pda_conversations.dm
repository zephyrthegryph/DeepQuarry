/datum/eventkit/fake_pdaconvos
	// ALLOW(instance_list): d: event kit state, one instance
	var/list/names = list()		//Assoc list of refs in fakeRefs = name
	var/list/fakeRefs //Used to find elements in other lists and tracking conversations. MUST BE UNIQUE.
	var/list/fakeJobs //Assoc list of name in names = job

ADMIN_VERB(fake_pdaconvos, R_FUN, "Manage PDA identities", "Creates fake identities for use in setting up PDA props", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/choice = verb_ask(user, "choice", args, /datum/om/prompt/choice, message = "What do you wish to do?", title = "Options", choices = list("Add new identity", "Edit existing identity", "Delete existing identity", "Delete holder", "Cancel"))
	if(isnull(choice))
		return

	if(choice == "Delete holder")
		QDEL_NULL(user.fakeConversations)
		return
	if(choice == "Cancel")
		return

	if(!user.fakeConversations || !istype(user.fakeConversations, /datum/eventkit/fake_pdaconvos))
		user.fakeConversations = new /datum/eventkit/fake_pdaconvos

	var/datum/eventkit/fake_pdaconvos/FPC = user.fakeConversations

	// Everything is asked before anything changes: each answer re-runs this verb.
	if(choice == "Add new identity")
		var/newRef = verb_ask(user, "ref", args, /datum/om/prompt/text, message = "Input unique reference. Duplicates are FORBIDDEN!. Players can't see this.Used to uniquely identify conversations in PDAs")
		if(!newRef) return
		var/new_name = verb_ask(user, "name", args, /datum/om/prompt/text, message = "Input fake name", title = newRef)
		if(isnull(new_name)) return
		var/new_job = verb_ask(user, "job", args, /datum/om/prompt/text, message = "Input fake assignment.", title = newRef)
		if(isnull(new_job)) return
		LAZYADD(FPC.fakeRefs, newRef)
		FPC.names[newRef] = new_name
		LAZYSET(FPC.fakeJobs, newRef, new_job)
		to_chat(user, span_notice("You have created [newRef]. Current name: [FPC.names[newRef]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, newRef)]"))
		return

	if(choice == "Edit existing identity")
		var/ref = verb_ask(user, "ref", args, /datum/om/prompt/choice, message = "Pick which identity to edit (details are printed to chat)", title = "identities", choices = FPC.fakeRefs)
		if(isnull(ref)) return
		var/editChoice = verb_ask(user, "edit", args, /datum/om/prompt/choice/alert, message = "You are editing [ref]. Current name: [FPC.names[ref]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, ref)]\nWhat do you wish to edit?", title = "Details", choices = list("Name", "Job", "Cancel"))
		if(isnull(editChoice)) return
		if(editChoice == "Name")
			var/new_name = verb_ask(user, "name", args, /datum/om/prompt/text, message = "Input fake name", title = FPC.names[ref])
			if(isnull(new_name)) return
			FPC.names[ref] = new_name
			to_chat(user, span_notice("Current data for [ref] are : Current name: [FPC.names[ref]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, ref)]"))
		if(editChoice == "Job")
			var/new_job = verb_ask(user, "job", args, /datum/om/prompt/text, message = "Input fake name", title = LAZYACCESS(FPC.fakeJobs, ref))
			if(isnull(new_job)) return
			LAZYSET(FPC.fakeJobs, ref, new_job)
			to_chat(user, span_notice("Current data for [ref] are : Current name: [FPC.names[ref]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, ref)]"))
		return
	if(choice == "Delete existing identity")
		var/ref = verb_ask(user, "ref", args, /datum/om/prompt/choice, message = "Pick which identity to delete (details are printed to chat)", title = "identities", choices = FPC.fakeRefs)
		if(isnull(ref)) return
		if(verb_ask(user, "sure", args, /datum/om/prompt/choice/alert, message = "You are deleting [ref]. Current name: [FPC.names[ref]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, ref)]", title = "are you sure?", choices = list("Yes", "No")) == "Yes")
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
