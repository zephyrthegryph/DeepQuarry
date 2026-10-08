// Proc: receive_exonet_message()
// Parameters: 4 (origin atom - the source of the message's holder, origin_address - where the message came from, message - the message received,
//				  text - message text to send if message is of type "text")
// Description: Handles voice requests and invite messages originating from both real communicators and ghosts.  Also includes a ping response and IM function.
/obj/item/communicator/receive_exonet_message(atom/origin_atom, origin_address, message, text)
	if(message == "voice")
		if(isobserver(origin_atom) || istype(origin_atom, /obj/item/communicator))
			if(origin_atom in voice_invites)
				var/user = null
				if(ismob(origin_atom.loc))
					user = origin_atom.loc
				open_connection(user, origin_atom)
				return
			else if(origin_atom in voice_requests)
				return //Spam prevention
			else
				request(origin_atom)
	if(message == "ping")
		if(network_visibility)
			var/random = rand(200,350)
			random = random / 10
			exonet.send_message(origin_address, "64 bytes received from [exonet.address] ecmp_seq=1 ttl=51 time=[random] ms")
	if(message == "text")
		request_im(origin_atom, origin_address, text)
		return

// Proc: receive_exonet_message()
// Parameters: 3 (origin atom - the source of the message's holder, origin_address - where the message came from, message - the message received)
// Description: Handles voice requests and invite messages originating from both real communicators and ghosts.  Also includes a ping response.
/mob/observer/dead/receive_exonet_message(origin_atom, origin_address, message, text)
	if(message == "voice")
		if(istype(origin_atom, /obj/item/communicator))
			var/obj/item/communicator/comm = origin_atom
			if(src in comm.voice_invites)
				comm.open_connection(src)
				return
			to_chat(src, span_notice("[icon2html(origin_atom,src.client)] Receiving communicator request from [origin_atom].  To answer, use the " + span_bold("Call Communicator") + "\
			verb, and select that name to answer the call."))
			src << 'sound/machines/defib_SafetyOn.ogg'
			rel_add(comm, nameof(comm.voice_invites), src)
	if(message == "ping")
		if(client && client.prefs.read_preference(/datum/preference/toggle/human/communicator_visibility)) // migrated pref
			var/random = rand(450,700)
			random = random / 10
			exonet.send_message(origin_address, "64 bytes received from [exonet.address] ecmp_seq=1 ttl=51 time=[random] ms")
	if(message == "text")
		to_chat(src, span_notice("[icon2html(origin_atom,src.client)] Received text message from [origin_atom]: " + span_bold("\"[text]\"")))
		src << 'sound/machines/defib_safetyOff.ogg'
		exonet_messages.Add(span_bold("From [origin_atom]:") + "<br>[text]")
		return

// Proc: request_im()
// Parameters: 3 (candidate - the communicator wanting to message the device, origin_address - the address of the sender, text - the message)
// Description: Response to a communicator trying to message the device.
//				Adds them to the list of people that have messaged this device and adds the message to the message list.
/obj/item/communicator/proc/request_im(atom/candidate, origin_address, text)
	var/who = null
	if(isobserver(candidate))
		var/mob/observer/dead/ghost = candidate
		who = ghost.name
		LAZYADD(im_list, list(list("address" = origin_address, "to_address" = exonet.address, "im" = text)))
	else if(istype(candidate, /obj/item/communicator))
		var/obj/item/communicator/comm = candidate
		who = comm.owner
		rel_add(comm, nameof(comm.im_contacts), src)
		LAZYADD(im_list, list(list("address" = origin_address, "to_address" = exonet.address, "im" = text)))
	else if(istype(candidate, /obj/item/integrated_circuit))
		var/obj/item/integrated_circuit/CIRC = candidate
		who = CIRC
		LAZYADD(im_list, list(list("address" = origin_address, "to_address" = exonet.address, "im" = text)))
	else return

	rel_add(src, nameof(im_contacts), candidate)

	if(!who)
		return

	if(ringer)
		var/S
		if(ttone in GLOB.device_ringtones)
			S = GLOB.device_ringtones[ttone]
		else
			S = SFX_MACHINES_TWOBEEP

		playsound(src, S, 50, 1)
		for (var/mob/O in hearers(2, loc))
			O.show_message(text("[icon2html(src,O.client)] *[ttone]*"))

	alert_called = 1
	changed(src)

	//Search for holder of the device.
	var/mob/living/L = null
	if(loc && isliving(loc))
		L = loc

	if(L)
		to_chat(L, span_notice("[icon2html(src,L.client)] Message from [who]: <b>\"[text]\"</b> (<a href='byond://?src=\ref[src];action=Reply;target=\ref[candidate]'>Reply</a>)"))

// This is the only Topic the communicators really uses
/datum/prompt/text/communicator_reply
	title = "Reply"
	question = "Enter your message below."
	timeout = 0
	usable_state = "default"
	var/obj/item/communicator/comm
	var/comm_expected = FALSE

CAPABILITIES(/datum/prompt/text/communicator_reply)
	ref_one(nameof(comm), /obj/item/communicator)

/datum/prompt/text/communicator_reply/prepare(datum/act/A)
	. = ..()
	var/obj/item/communicator/captured = comm
	comm_expected = !isnull(captured)
	rel_clear(src, nameof(comm))
	if(captured && !QDELETED(captured))
		rel_set(src, nameof(comm), captured)

/datum/prompt/text/communicator_reply/recheck_extra()
	. = ..()
	if(.)
		return
	if(comm_expected && QDELETED(comm))
		return "gone"


// Reply links arrive in chat for whoever carries the communicator (in hand, a pocket, or a NIF).
/obj/item/communicator/topic_usable(datum/act/op/A)
	return A.actor && get(src, /mob) == A.actor

/obj/item/communicator/proc/reply_subject(datum/act/op/A)
	return src

/obj/item/communicator/proc/topic_reply(datum/act/op/A, href_target)
	var/mob/user = A.actor
	var/obj/item/communicator/comm = href_target
	var/message = A.step_value("message")
	if(!comm?.exonet || !message)
		return
	exonet.send_message(comm.exonet.address, "text", message)
	LAZYADD(im_list, list(list("address" = exonet.address, "to_address" = comm.exonet.address, "im" = message)))
	user.log_talk("(COMM: [src]) sent \"[message]\" to [exonet.get_atom_from_address(comm.exonet.address)]", LOG_PDA)
	to_chat(user, span_notice("[icon2html(src,user.client)] Sent message to [istype(comm, /obj/item/communicator) ? comm.owner : comm.name], <b>\"[message]\"</b> (<a href='byond://?src=\ref[src];action=Reply;target=\ref[exonet.get_atom_from_address(comm.exonet.address)]'>Reply</a>)"))

// Verb: text_communicator()
// Parameters: None
// Description: Allows a ghost to send a text message to a communicator.
/mob/observer/dead/verb/text_communicator()
	set category = VERB_CAT_GHOST_MESSAGE
	set name = "Text Communicator"
	set desc = "If there is a communicator available, send a text message to it."

	if(SSticker.current_state < GAME_STATE_PLAYING)
		to_chat(src, span_danger("The game hasn't started yet!"))
		return

	if (!src.stat)
		return

	if (usr != src)
		return //something is terribly wrong

	for(var/mob/living/L in REGISTRY_MEMBERS(REGISTRY_MOBS)) //Simple check so you don't have dead people calling.
		if(src.client.prefs.read_preference(/datum/preference/name/real_name) == L.real_name)
			to_chat(src, span_danger("Your identity is already present in the game world.  Please load in a different character first."))
			return

	var/obj/machinery/exonet_node/E = get_exonet_node()
	if(!E || !E.on || !E.allow_external_communicators)
		to_chat(src, span_danger("The Exonet node at telecommunications is down at the moment, or is actively blocking you, \
		so your call can't go through."))
		return

	var/list/choices = list()
	for(var/obj/item/communicator/comm in REGISTRY_MEMBERS(REGISTRY_COMMUNICATORS))
		if(!comm.network_visibility || !comm.exonet || !comm.exonet.address)
			continue
		choices.Add(comm)

	if(!choices.len)
		to_chat(src, span_danger("There are no available communicators, sorry."))
		return

	open_request(src, /datum/prompt/choice, PROC_REF(ghost_text_recipient_chosen), answerer = src, title = "Recipient Choice", question = "Send a text message to whom?", choices = choices, timeout = 0)

/datum/prompt/text/ghost_text
	question = "What do you want the message to say?"
	timeout = 0
	encode = FALSE
	multiline = TRUE
	var/obj/item/communicator/recipient
	var/recipient_expected = FALSE

CAPABILITIES(/datum/prompt/text/ghost_text)
	ref_one(nameof(recipient), /obj/item/communicator)

/datum/prompt/text/ghost_text/prepare(datum/act/A)
	. = ..()
	var/obj/item/communicator/captured = recipient
	recipient_expected = !isnull(captured)
	rel_clear(src, nameof(recipient))
	if(captured && !QDELETED(captured))
		rel_set(src, nameof(recipient), captured)

/datum/prompt/text/ghost_text/recheck_extra()
	. = ..()
	if(.)
		return
	if(recipient_expected && QDELETED(recipient))
		return "gone"

/mob/observer/dead/proc/ghost_text_recipient_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/obj/item/communicator/recipient = A.answer.value
	if(!istype(recipient) || QDELETED(recipient))
		return
	open_request(src, /datum/prompt/text/ghost_text, PROC_REF(ghost_text_written), answerer = src, recipient = recipient)

/mob/observer/dead/proc/ghost_text_written(datum/act/request/A)
	if(!A.answer)
		return
	return ghost_text_apply(A)

/mob/observer/dead/proc/ghost_text_apply(datum/act/request/A)
	var/datum/prompt/text/ghost_text/ask = A.answer
	var/obj/item/communicator/chosen_communicator = ask.recipient
	var/mob/observer/dead/O = src
	var/text_message = sanitize(ask.value, MAX_MESSAGE_LEN, FALSE, FALSE, TRUE)
	if(text_message && O.exonet && chosen_communicator.exonet)
		O.exonet.send_message(chosen_communicator.exonet.address, "text", text_message)

		to_chat(src, span_notice("You have sent '[text_message]' to [chosen_communicator]."))
		exonet_messages.Add(span_bold("To [chosen_communicator]:") + "<br>[text_message]")
		log_talk("(DCOMM: [src]) sent \"[text_message]\" to [chosen_communicator]", LOG_PDA)
		for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
			if(M.stat == DEAD && M.client?.prefs?.read_preference(/datum/preference/toggle/ghost_ears))
				if(isnewplayer(M) || M.forbid_seeing_deadchat)
					continue
				if(M == src)
					continue
				M.show_message("Comm IM - [src] -> [chosen_communicator]: [text_message]")


// Show Text Messages verb body relocated to code/modules/communicator/exonet_log_panel.dm (structured TGUI).
