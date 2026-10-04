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

/datum/data/pda/app/messenger/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	unnotify()
	return TRUE

CAPABILITIES(/datum/data/pda/app/messenger)
	op("Toggle Messenger", ui_act(), then(PROC_REF(ui_act_toggle_messenger)))
	op("Toggle Ringer", ui_act(), then(PROC_REF(ui_act_toggle_ringer)))
	op("Back", ui_act(), then(PROC_REF(ui_act_back)))

/datum/data/pda/app/messenger/proc/ui_act_toggle_messenger(datum/act/op/A)
	unnotify()
	toff = !toff
	return OP_OK

/datum/data/pda/app/messenger/proc/ui_act_toggle_ringer(datum/act/op/A)
	unnotify()
	notify_silent = !notify_silent
	return OP_OK

UI_ACT(/datum/data/pda/app/messenger, "Clear", ui_act_clear, UI_ARG_TEXT("option"))
UI_ACT_PROC(/datum/data/pda/app/messenger, ui_act_clear)
	. = TRUE
	if(params["option"] == "All")
		LAZYCLEARLIST(tnote)
		LAZYCLEARLIST(conversations)
	if(params["option"] == "Convo")
		var/new_tnote[0]
		for(var/i in tnote)
			if(i["target"] != active_conversation)
				new_tnote[++new_tnote.len] = i
		tnote = new_tnote
		LAZYREMOVE(conversations, active_conversation)

	active_conversation = null

UI_ACT(/datum/data/pda/app/messenger, "Message", ui_act_message, UI_ARG_REF("target", null, /obj/item/pda))
UI_ACT_PROC(/datum/data/pda/app/messenger, ui_act_message)
	. = TRUE
	var/obj/item/pda/P = params["target"]
	create_message(ui.user, P)
	if(params["target"] in conversations)            // Need to make sure the message went through, if not welp.
		active_conversation = params["target"]

UI_ACT(/datum/data/pda/app/messenger, "Select Conversation", ui_act_select_conversation, UI_ARG_VALUE("target"))
UI_ACT_PROC(/datum/data/pda/app/messenger, ui_act_select_conversation)
	. = TRUE
	var/P = params["target"]
	for(var/n in conversations)
		if(P == n)
			active_conversation = P

UI_ACT(/datum/data/pda/app/messenger, "Messenger Plugin", ui_act_messenger_plugin, UI_ARG_REF("plugin", null, /datum/data/pda/messenger_plugin), UI_ARG_REF("target", null, /obj/item/pda))
UI_ACT_PROC(/datum/data/pda/app/messenger, ui_act_messenger_plugin)
	. = TRUE
	if(!params["target"] || !params["plugin"])
		return

	var/obj/item/pda/P = params["target"]
	if(!P)
		to_chat(ui.user, "PDA not found.")

	var/datum/data/pda/messenger_plugin/plugin = params["plugin"]
	if(plugin && (plugin in pda().cartridge.messenger_plugins))
		rel_set(plugin, nameof(/datum/data/pda/messenger_plugin::messenger), src)
		plugin.user_act(ui.user, P)

/datum/data/pda/app/messenger/proc/ui_act_back(datum/act/op/A)
	unnotify()
	active_conversation = null
	return OP_OK

// Specifically here for the chat message.
TOPIC_ACTION(/datum/data/pda/app/messenger, "choice=Message", PROC_REF(topic_message), TOPIC_REF("target", /obj/item/pda))

/datum/data/pda/app/messenger/topic_allowed(mob/user, list/href_list)
	return pda()?.can_use(user)

/datum/data/pda/app/messenger/proc/topic_message(mob/user, list/args)
	unnotify()
	var/obj/item/pda/P = args["target"]
	create_message(user, P)
	var/target_ref = "\ref[P]"
	if(target_ref in conversations)            // Need to make sure the message went through, if not welp.
		active_conversation = target_ref
	return TRUE


/datum/data/pda/app/messenger/proc/create_message(mob/living/U, obj/item/pda/P)
	var/t = rerun_ask(U, "k127", PROC_REF(create_message), args, /datum/om/prompt/text, message = "Please enter message", title = name)
	if(isnull(t))
		return
	if(!t)
		return
	t = readd_quotes(t)
	if(!t || !istype(P))
		return
	if(!in_range(pda(), U) && pda().loc != U)
		return

	var/datum/data/pda/app/messenger/PM = P.find_program(/datum/data/pda/app/messenger)

	if(!PM || PM.toff || toff)
		return

	if(!COOLDOWN_FINISHED(src, text_cooldown))
		return

	if(!pda().can_use(U))
		return

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
