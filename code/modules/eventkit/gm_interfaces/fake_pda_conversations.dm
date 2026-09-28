/datum/eventkit/fake_pdaconvos
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
/// A fake PDA conversation on a prop PDA (target): the admin (actor) picks TGUI or dialogue mode;
/// dialogue mode picks an identity, then asks for up to 30 messages in a row, one message and
/// its direction at a time. An empty message or a cancel ends it.
/datum/om/flow/fake_pda_convo
	name = "fake pda conversation"
	requires = PROMPT_ADMIN(R_FUN)
	var/identity
	var/left = 30
	var/message

/datum/om/flow/fake_pda_convo/proc/conversations()
	var/mob/M = actor
	return M.client?.fakeConversations

/datum/om/flow/fake_pda_convo/start()
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(mode_chosen), buttons = TRUE, title = "TGUI?", message = "Use TGUI or dialogue boxes?", choices = list("TGUI", "Dialogue", "Cancel"))

/datum/om/flow/fake_pda_convo/proc/mode_chosen(datum/om/prompt/choice/ask)
	var/datum/eventkit/fake_pdaconvos/FPC = conversations()
	if(!FPC)
		return
	if(ask.choice == "Dialogue")
		om_ask(actor, /datum/om/prompt/choice, PROC_REF(identity_chosen), title = "identities", message = "Pick which identity to use(details are printed to chat)", choices = FPC.fakeRefs)

	if(ask.choice == "TGUI")
		to_chat(actor, span_notice("Sorry, the TGUI functionality is not yet implemented - use Dialogue mode!"))

/datum/om/flow/fake_pda_convo/proc/identity_chosen(datum/om/prompt/choice/ask)
	var/datum/eventkit/fake_pdaconvos/FPC = conversations()
	if(!FPC)
		return
	identity = ask.choice
	to_chat(actor, span_notice("You are using [identity]. Current name: [FPC.names[identity]]. Current assignment: [LAZYACCESS(FPC.fakeJobs, identity)]"))
	ask_message()

/datum/om/flow/fake_pda_convo/proc/ask_message()
	if(left <= 0)
		return
	om_ask(actor, /datum/om/prompt/text, PROC_REF(message_entered), message = "Input fake message. Leave empty to cancel. Can create up to 30 messages in a row", max_length = MAX_MESSAGE_LEN)

/datum/om/flow/fake_pda_convo/proc/message_entered(datum/om/prompt/text/ask)
	message = ask.text
	if(!message)
		return
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(direction_chosen), buttons = TRUE, title = "Direction", message = "Received or Sent?", choices = list("Received", "Sent"))

/datum/om/flow/fake_pda_convo/proc/direction_chosen(datum/om/prompt/choice/ask)
	var/obj/item/pda/pda = target
	var/datum/eventkit/fake_pdaconvos/FPC = conversations()
	var/datum/data/pda/app/messenger/ourPDA = pda.find_program(/datum/data/pda/app/messenger)
	if(!FPC || !ourPDA)
		return
	ourPDA.createFakeMessage(FPC.names[identity], identity, LAZYACCESS(FPC.fakeJobs, identity), ask.choice == "Sent" ? 1 : 0, message)
	left--
	ask_message()

/obj/item/pda/proc/createPropFakeConversation_admin(mob/M)
	if(!M.client || !check_rights_for(M.client, R_FUN))
		return

	var/datum/eventkit/fake_pdaconvos/FPC = M.client.fakeConversations

	if(!FPC || !istype(FPC, /datum/eventkit/fake_pdaconvos))
		to_chat(M, span_warning("First you must create a new identity with Manage PDA identities in EventKit"))
		return

	om_flow_start(/datum/om/flow/fake_pda_convo, M, src)
