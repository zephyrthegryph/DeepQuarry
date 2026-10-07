/datum/data/pda/app/messenger
	name = "Messenger"
	icon = "comments-o"
	notify_icon = "comments"
	title = "SpaceMessenger V4.1.0"
	template = "pda_messenger"

	var/toff = 0 //If 1, messenger disabled
	var/list/tnote  //Current Texts
	COOLDOWN_DECLARE(text_cooldown) //No text spamming

	var/m_hidden = 0 // Is the PDA hidden from the PDA list?
	var/active_conversation = null // New variable that allows us to only view a single conversation.
	var/list/conversations    // For keeping up with who we have PDA messsages from.
	var/list/fakepdas //So that fake PDAs show up in conversations for props. Namedlist of "fakeName" = fakeRef

/datum/data/pda/app/messenger/start()
	. = ..()
	unnotify()

/datum/data/pda/app/messenger/update_ui(mob/user, list/data)
	data["silent"] = notify_silent						// does the pda make noise when it receives a message?
	data["toff"] = toff									// is the messenger function turned off?
	data["active_conversation"] = active_conversation	// Which conversation are we following right now?
	data["enable_message_embeds"] = user?.client?.prefs?.read_preference(/datum/preference/toggle/messenger_embeds)

	has_back = active_conversation
	if(active_conversation)
		data["messages"] = (tnote || list())
		for(var/c in tnote)
			if(c["target"] == active_conversation)
				data["convo_name"] = sanitize(c["owner"])
				data["convo_job"] = sanitize(c["job"])
				break
	else
		var/list/convopdas = list()
		var/list/pdas = list()
		for(var/obj/item/pda/P as anything in REGISTRY_MEMBERS(REGISTRY_PDAS))
			var/datum/data/pda/app/messenger/PM = P.find_program(/datum/data/pda/app/messenger)

			if(!PM || !P.owner || PM.toff || P == pda() || PM.m_hidden)
				continue
			if(LAZYFIND(conversations, "\ref[P]"))
				convopdas.Add(list(list("Name" = "[P]", "Reference" = "\ref[P]", "Detonate" = "[P.detonate]", "inconvo" = "1")))
			else
				pdas.Add(list(list("Name" = "[P]", "Reference" = "\ref[P]", "Detonate" = "[P.detonate]", "inconvo" = "0")))
		for(var/fakeRef in fakepdas)
			convopdas.Add(list(list("Name" = "[LAZYACCESS(fakepdas, fakeRef)]", "Reference" = "[fakeRef]", "Detonate" = "0", "inconvo" = "1")))

		data["convopdas"] = convopdas
		data["pdas"] = pdas

		var/list/plugins = list()
		if(pda().cartridge)
			for(var/datum/data/pda/messenger_plugin/P as anything in pda().cartridge.messenger_plugins)
				plugins += list(list(name = P.name, icon = P.icon, ref = "\ref[P]"))
		data["plugins"] = plugins

		if(pda().cartridge)
			data["charges"] = pda().cartridge.charges ? pda().cartridge.charges : 0

/datum/data/pda/app/messenger/proc/ui_gate(datum/act/op/A)
	unnotify()
	return TRUE

CAPABILITIES(/datum/data/pda/app/messenger)
	op("Toggle Messenger", ui_act(), then(PROC_REF(ui_act_toggle_messenger)))
	op("Toggle Ringer", ui_act(), then(PROC_REF(ui_act_toggle_ringer)))
	op("Back", ui_act(), then(PROC_REF(ui_act_back)))
	op("Clear", ui_act("Clear", arg("option", schema_text(4096))), then(PROC_REF(ui_act_clear)))
	op("Message", ui_act("Message", arg("target", schema_ref(/obj/item/pda))), then(PROC_REF(ui_act_message)))
	op("Select Conversation", ui_act("Select Conversation", arg("target")), then(PROC_REF(ui_act_select_conversation)))
	op("Messenger Plugin", ui_act("Messenger Plugin", arg("plugin", schema_ref(/datum/data/pda/messenger_plugin)), arg("target", schema_ref(/obj/item/pda))), then(PROC_REF(ui_act_messenger_plugin)))
	op("choice_Message", topic("choice=Message", arg("target", schema_ref(/obj/item/pda), optional = TRUE)), then(PROC_REF(topic_message)))

/datum/data/pda/app/messenger/proc/ui_act_toggle_messenger(datum/act/op/A)
	unnotify()
	toff = !toff
	return OP_OK

/datum/data/pda/app/messenger/proc/ui_act_toggle_ringer(datum/act/op/A)
	unnotify()
	notify_silent = !notify_silent
	return OP_OK

/datum/data/pda/app/messenger/proc/ui_act_clear(datum/act/op/A, option)
	if(!ui_gate(A))
		return FALSE
	. = TRUE
	if(option == "All")
		LAZYCLEARLIST(tnote)
		LAZYCLEARLIST(conversations)
	if(option == "Convo")
		var/new_tnote[0]
		for(var/i in tnote)
			if(i["target"] != active_conversation)
				new_tnote[++new_tnote.len] = i
		tnote = new_tnote
		LAZYREMOVE(conversations, active_conversation)

	active_conversation = null

/datum/data/pda/app/messenger/proc/ui_act_message(datum/act/op/A, target)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(isnull(target))
		return FALSE
	. = TRUE
	var/obj/item/pda/P = target
	create_message(user, P)
	if(target in conversations)            // Need to make sure the message went through, if not welp.
		active_conversation = target

/datum/data/pda/app/messenger/proc/ui_act_select_conversation(datum/act/op/A, target)
	if(!ui_gate(A))
		return FALSE
	. = TRUE
	var/P = target
	for(var/n in conversations)
		if(P == n)
			active_conversation = P

/datum/data/pda/app/messenger/proc/ui_act_messenger_plugin(datum/act/op/A, plugin_arg, target)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	. = TRUE
	if(!target || !plugin_arg)
		return

	var/obj/item/pda/P = target
	if(!P)
		to_chat(user, "PDA not found.")

	var/datum/data/pda/messenger_plugin/plugin = plugin_arg
	if(plugin && (plugin in pda().cartridge.messenger_plugins))
		rel_set(plugin, nameof(/datum/data/pda/messenger_plugin::messenger), src)
		plugin.user_act(user, P)

/datum/data/pda/app/messenger/proc/ui_act_back(datum/act/op/A)
	unnotify()
	active_conversation = null
	return OP_OK

// Specifically here for the chat message.

/datum/data/pda/app/messenger/topic_allowed(mob/user, list/href_list)
	return pda()?.can_use(user)

/datum/data/pda/app/messenger/proc/topic_message(datum/act/op/A, href_target)
	var/mob/user = A.actor
	unnotify()
	var/obj/item/pda/P = href_target
	create_message(user, P)
	var/target_ref = "\ref[P]"
	if(target_ref in conversations)            // Need to make sure the message went through, if not welp.
		active_conversation = target_ref
	return TRUE


/datum/data/pda/app/messenger/proc/create_message(mob/living/U, obj/item/pda/P)
	open_request(src, /datum/prompt/text/pda_message, PROC_REF(message_entered), answerer = U, subject = P, target_expected = !isnull(P), title = name)

/datum/prompt/text/pda_message
	question = "Please enter message"
	timeout = 0
	recheck_on_open = TRUE
	var/target_expected = FALSE

/datum/prompt/text/pda_message/recheck_extra()
	var/datum/data/pda/app/messenger/program = owner
	if(!istype(program) || QDELETED(program) || !answerer || QDELETED(answerer))
		return "gone"
	if(target_expected && (!subject || QDELETED(subject)))
		return "gone"
	// These are answer-time guards: the old entry opened before checking them.
	if(isnull(value))
		return
	if(!value || !readd_quotes(value) || !istype(subject, /obj/item/pda))
		return "not sent"
	var/obj/item/pda/sender = program.pda()
	if(!sender || QDELETED(sender))
		return "no sender"
	if(!in_range(sender, answerer) && sender.loc != answerer)
		return "not sent"
	var/obj/item/pda/target = subject
	var/datum/data/pda/app/messenger/recipient = target.find_program(/datum/data/pda/app/messenger)
	if(!recipient || recipient.toff || program.toff)
		return "not sent"
	if(!COOLDOWN_FINISHED(program, text_cooldown))
		return "not sent"
	if(!sender.can_use(answerer))
		return "not sent"

/datum/data/pda/app/messenger/proc/message_entered(datum/act/request/A)
	if(isnull(A.request.value) || A.request.last_error == "gone")
		return
	SStgui.update_uis(src)
	if(A.answer)
		var/obj/item/pda/P = A.request.subject
		var/datum/data/pda/app/messenger/PM = P.find_program(/datum/data/pda/app/messenger)
		send_message_answered(A.request.answerer, P, PM, readd_quotes(A.answer.value))

/datum/data/pda/app/messenger/proc/send_message_answered(mob/living/U, obj/item/pda/P, datum/data/pda/app/messenger/PM, t)
	COOLDOWN_START(src, text_cooldown, 0.5 SECONDS)
	// check if telecomms I/O route 1459 is stable
	//var/telecomms_intact = telecomms_process(P.owner, owner, t)
	var/obj/machinery/message_server/useMS = null
	for(var/obj/machinery/message_server/MS as anything in REGISTRY_MEMBERS(REGISTRY_MESSAGE_SERVERS))
	//PDAs are now dependent on the Message Server.
		if(MS.active)
			useMS = MS
			break

	var/datum/signal/signal = pda().telecomms_process()

	var/useTC = 0
	if(signal)
		if(signal.data["done"])
			useTC = 1
			var/turf/pos = get_turf(P)
			// TODO: Make the radio system cooperate with the space manager
			if(pos.z in signal.data["level"])
				useTC = 2
				//Let's make this barely readable
				if(signal.data["compression"] > 0)
					t = Gibberish(t, signal.data["compression"] + 50)

	if(useMS && useTC) // only send the message if it's stable
		if(useTC != 2) // Does our recipient have a broadcaster on their level?
			to_chat(U, "ERROR: Cannot reach recipient.")
			return
		useMS.send_pda_message("[P.owner]","[pda().owner]","[t]")
		pda().investigate_log(span_game(span_say("PDA Message - " + span_name("[U.key] - [pda().owner]") + " -> " + span_name("[P.owner]") + ": " + span_message("[t]"))), "pda")

		receive_message(list("sent" = 1, "owner" = "[P.owner]", "job" = "[P.ownjob]", "message" = "[t]", "target" = "\ref[P]"), "\ref[P]")
		PM.receive_message(list("sent" = 0, "owner" = "[pda().owner]", "job" = "[pda().ownjob]", "message" = "[t]", "target" = "\ref[pda()]"), "\ref[pda()]")

		SStgui.update_user_uis(U, P) // Update the sending user's PDA UI so that they can see the new message
		U.log_message("(PDA: [src.name] | [U.real_name]) sent \"[t]\" to [P.name]", LOG_PDA, color="#00ff00")
		to_chat(U, "[icon2html(pda(),U.client)] <b>Sent message to [P.owner] ([P.ownjob]), </b>\"[t]\"")
	else
		to_chat(U, span_notice("ERROR: Messaging server is not responding.\n\n\
			However, your message has been saved: ") + t)

/datum/data/pda/app/messenger/proc/can_receive()
	return pda().owner && !toff && !hidden

/datum/data/pda/app/messenger/proc/receive_message(list/data, ref)
	LAZYADD(tnote, list(data))
	if(!LAZYFIND(conversations, ref))
		LAZYADD(conversations, ref)
	if(!data["sent"])
		var/owner = data["owner"]
		var/job = data["job"]
		var/message = data["message"]
		notify(span_bold("Message from [owner] ([job]), ") + "\"[message]\" (<a href='byond://?src=\ref[src];choice=Message;target=[ref]'>Reply</a>)")

/datum/data/pda/app/messenger/multicast
/datum/data/pda/app/messenger/multicast/receive_message(list/data, ref)
	. = ..()

	var/obj/item/pda/multicaster/M = pda()
	if(!istype(M))
		return

	var/list/modified_message = data.Copy()
	modified_message["owner"] = modified_message["owner"] + " \[Relayed]"
	modified_message["target"] = "\ref[M]"

	var/list/targets = list()
	for(var/obj/item/pda/pda in REGISTRY_MEMBERS(REGISTRY_PDAS))
		if(pda.cartridge && pda.owner && is_type_in_list(pda.cartridge, M.cartridges_to_send_to))
			targets |= pda
	if(targets.len)
		for(var/obj/item/pda/target in targets)
			var/datum/data/pda/app/messenger/P = target.find_program(/datum/data/pda/app/messenger)
			if(P)
				P.receive_message(modified_message, "\ref[M]")

/*
Generalized proc to handle GM fake prop messages, or future fake prop messages from mapping landmarks.
We need a separate proc for this due to the "target" component and creation of a fake conversation entry.
Invoked by /obj/item/pda/proc/createPropFakeConversation_admin(var/mob/M)
*/
/datum/data/pda/app/messenger/proc/createFakeMessage(fakeName, fakeRef, fakeJob, sent, message)
	receive_message(list("sent" = sent, "owner" = "[fakeName]", "job" = "[fakeJob]", "message" = "[message]", "target" = "[fakeRef]"), fakeRef)
	if(!LAZYACCESS(fakepdas, fakeRef))
		LAZYSET(fakepdas, fakeRef, fakeName)
