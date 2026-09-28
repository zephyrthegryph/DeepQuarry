/datum/eventkit/fake_pdaconvos
	// ALLOW(instance_list): d: event kit state, one instance
	var/list/names = list()		//Assoc list of refs in fakeRefs = name
	var/list/fakeRefs //Used to find elements in other lists and tracking conversations. MUST BE UNIQUE.
	var/list/fakeJobs //Assoc list of name in names = job

ADMIN_VERB(fake_pdaconvos, R_FUN, "Manage PDA identities", "Creates fake identities for use in setting up PDA props", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/choice = verb_prompt(user, "choice", list("kind" = "list", "message" = "What do you wish to do?", "title" = "Options", "choices" = list("Add new identity", "Edit existing identity", "Delete existing identity", "Delete holder", "Cancel")), args)
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
		var/newRef = verb_prompt(user, "ref", list("kind" = "text", "message" = "Input unique reference. Duplicates are FORBIDDEN!. Players can't see this.Used to uniquely identify conversations in PDAs", "max_length" = MAX_MESSAGE_LEN), args)
		if(!newRef) return
		var/new_name = verb_prompt(user, "name", list("kind" = "text", "message" = "Input fake name", "title" = newRef, "max_length" = MAX_MESSAGE_LEN), args)
		if(isnull(new_name)) return
		var/new_job = verb_prompt(user, "job", list("kind" = "text", "message" = "Input fake assignment.", "title" = newRef, "max_length" = MAX_MESSAGE_LEN), args)
		if(isnull(new_job)) return
		LAZYADD(FPC.fakeRefs, newRef)
		FPC.names[newRef] = new_name
		LAZYSET(FPC.fakeJobs, newRef, new_job)
		to_chat(user, span_notice("You have created [newRef]. Current name: [FPC.names[newRef]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, newRef)]"))
		return

	if(choice == "Edit existing identity")
		var/ref = verb_prompt(user, "ref", list("kind" = "list", "message" = "Pick which identity to edit (details are printed to chat)", "title" = "identities", "choices" = FPC.fakeRefs), args)
		if(isnull(ref)) return
		var/editChoice = verb_prompt(user, "edit", list("message" = "You are editing [ref]. Current name: [FPC.names[ref]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, ref)]\nWhat do you wish to edit?", "title" = "Details", "choices" = list("Name", "Job", "Cancel")), args)
		if(isnull(editChoice)) return
		if(editChoice == "Name")
			var/new_name = verb_prompt(user, "name", list("kind" = "text", "message" = "Input fake name", "title" = FPC.names[ref], "max_length" = MAX_MESSAGE_LEN), args)
			if(isnull(new_name)) return
			FPC.names[ref] = new_name
			to_chat(user, span_notice("Current data for [ref] are : Current name: [FPC.names[ref]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, ref)]"))
		if(editChoice == "Job")
			var/new_job = verb_prompt(user, "job", list("kind" = "text", "message" = "Input fake name", "title" = LAZYACCESS(FPC.fakeJobs, ref), "max_length" = MAX_MESSAGE_LEN), args)
			if(isnull(new_job)) return
			LAZYSET(FPC.fakeJobs, ref, new_job)
			to_chat(user, span_notice("Current data for [ref] are : Current name: [FPC.names[ref]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, ref)]"))
		return
	if(choice == "Delete existing identity")
		var/ref = verb_prompt(user, "ref", list("kind" = "list", "message" = "Pick which identity to delete (details are printed to chat)", "title" = "identities", "choices" = FPC.fakeRefs), args)
		if(isnull(ref)) return
		if(verb_prompt(user, "sure", list("message" = "You are deleting [ref]. Current name: [FPC.names[ref]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, ref)]", "title" = "are you sure?", "choices" = list("Yes", "No")), args) == "Yes")
			LAZYREMOVE(FPC.fakeRefs, ref)
			LAZYREMOVE(FPC.fakeJobs, ref)
			FPC.names -= ref
		return


/*
Invoked by vv topic "fakepdapropconvo" in code\modules\admin\view_variables\topic.dm found in PDA vv dropdown.
*/
/// The dialogue mode asks for up to 30 messages in a row, one message and its direction at a time.
/obj/item/pda/proc/fake_convo_identity_chosen(mob/M, identity, datum/om/prompt/ask)
	var/datum/eventkit/fake_pdaconvos/FPC = M.client?.fakeConversations
	if(!FPC)
		return
	to_chat(M, span_notice("You are using [identity]. Current name: [FPC.names[identity]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, identity)]"))
	fake_convo_ask_message(M, identity, 30)

/obj/item/pda/proc/fake_convo_ask_message(mob/M, identity, left)
	if(left <= 0)
		return
	om_prompt_sequence(src, M, list(
		list("key" = "message", "kind" = "text", "message" = "Input fake message. Leave empty to cancel. Can create up to 30 messages in a row", "max_length" = MAX_MESSAGE_LEN),
		list("key" = "direction", "message" = "Received or Sent?", "title" = "Direction", "choices" = list("Received", "Sent")),
	), PROC_REF(fake_convo_message_entered), list("requires" = PROMPT_ADMIN(R_FUN), "data" = list("identity" = identity, "left" = left)))

/obj/item/pda/proc/fake_convo_message_entered(mob/M, datum/om/prompt/ask)
	var/datum/eventkit/fake_pdaconvos/FPC = M.client?.fakeConversations
	var/message = ask.get("message")
	var/identity = ask.get("identity")
	var/datum/data/pda/app/messenger/ourPDA = find_program(/datum/data/pda/app/messenger)
	if(!FPC || !message || !ourPDA)
		return
	ourPDA.createFakeMessage(FPC.names[identity], identity, LAZYACCESS(FPC.fakeJobs, identity), ask.get("direction") == "Sent" ? 1 : 0, message)
	fake_convo_ask_message(M, identity, ask.get("left") - 1)

/obj/item/pda/proc/createPropFakeConversation_admin(mob/M)
	if(!M.client || !check_rights_for(M.client, R_FUN))
		return

	var/datum/eventkit/fake_pdaconvos/FPC = M.client.fakeConversations

	if(!FPC || !istype(FPC, /datum/eventkit/fake_pdaconvos))
		to_chat(M, span_warning("First you must create a new identity with Manage PDA identities in EventKit"))
		return

	om_prompt(src, M, list("message" = "Use TGUI or dialogue boxes?", "title" = "TGUI?", "choices" = list("TGUI", "Dialogue", "Cancel"), "requires" = PROMPT_ADMIN(R_FUN)), PROC_REF(fake_convo_mode_chosen))

/obj/item/pda/proc/fake_convo_mode_chosen(mob/M, choice, datum/om/prompt/ask)
	var/datum/eventkit/fake_pdaconvos/FPC = M.client?.fakeConversations
	if(!FPC)
		return
	if(choice == "Dialogue")
		om_prompt(src, M, list("kind" = "list", "message" = "Pick which identity to use(details are printed to chat)", "title" = "identities", "choices" = FPC.fakeRefs, "requires" = PROMPT_ADMIN(R_FUN)), PROC_REF(fake_convo_identity_chosen))

	if(choice == "TGUI")
		to_chat(M, span_notice("Sorry, the TGUI functionality is not yet implemented - use Dialogue mode!"))
