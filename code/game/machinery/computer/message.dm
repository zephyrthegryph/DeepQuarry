// Allows you to monitor messages that passes the server.

/obj/machinery/computer/message_monitor
	name = "messaging monitor console"
	desc = "Used to access and maintain data on messaging servers. Allows you to view PDA and request console messages."
	icon_screen = "comm_logs"
	light_color = "#00b000"
	var/hack_icon = "error"
	circuit = /obj/item/circuitboard/message_monitor
	//Server linked to.
	var/obj/machinery/message_server/linkedServer
	//Messages - Saves me time if I want to change something.
	var/noserver = list("text" = "ALERT: No server detected.", "style" = "alert")
	var/incorrectkey = list("text" = "ALERT: Incorrect decryption key!", "style" = "warning")
	var/defaultmsg = list("text" = "Welcome. Please select an option.", "style" = "notice")
	var/rebootmsg = list("text" = "%$&(£: Critical %$$@ Error // !RestArting! <lOadiNg backUp iNput ouTput> - ?pLeaSe wAit!", "style" = "warning")
	//Computer properties
	var/hacking = 0		// Is it being hacked into by the AI/Cyborg
	var/emag = 0		// When it is emagged.
	var/auth = 0 // Are they authenticated?
	var/optioncount = 8
	// Custom temp Properties
	var/customsender = "System Administrator"
	var/obj/item/pda/customrecepient
	var/customjob		= "Admin"
	var/custommessage 	= "This is a test, please ignore."
	var/list/temp = null

MSG_DEF_SELF(message_monitor/too_hot, "It is too hot to mess with!")

/// needs: an emagged monitor that still works is too hot to unscrew (so it cannot be reset by putting it back together).
/obj/machinery/computer/message_monitor/proc/cool_enough(datum/act/op/A)
	return !emag || !operable()

/obj/machinery/computer/message_monitor/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	// Will create sparks and print out the console's password. You will then have to wait a while for the console to be back online.
	// It'll take more time if there's more characters in the password..
	if(!emag && operable())
		if(!isnull(linkedServer()))
			set_emag(TRUE)
			fx_sparks(src, 5, FALSE)
			var/obj/item/paper/monitorkey/MK = new/obj/item/paper/monitorkey
			MK.forceMove(loc)
			// Will help make emagging the console not so easy to get away with.
			MK.set_info(MK.info + ("<br><br>" + span_red("£%@%(*$%&(£&?*(%&£/{}")))
			after(src, 100*length(linkedServer().decryptkey), PROC_REF(UnmagConsole))
			temp = rebootmsg
			changed(src)
			return OP_OK
		else
			to_chat(user, span_notice("A no server error appears on the screen."))
	return OP_DECLINE

/// An emagged or hacked monitor shows the hack screen.
/obj/machinery/computer/message_monitor/screen_state()
	return (emag || hacking) ? hack_icon : icon_screen

/// Links the first message server when the map has one and none is set.
/obj/machinery/computer/message_monitor/proc/link_default_server(datum/act/timer/A)
	//Is the server isn't linked to a server, and there's a server available, default it to the first one in the list.
	if(!linkedServer())
		if(REGISTRY_MEMBERS(REGISTRY_MESSAGE_SERVERS) && REGISTRY_COUNT(REGISTRY_MESSAGE_SERVERS) > 0)
			rel_set(src, nameof(linkedServer), REGISTRY_MEMBERS(REGISTRY_MESSAGE_SERVERS)[1])

TRACKED(/obj/machinery/computer/message_monitor, emag)

CAPABILITIES(/obj/machinery/computer/message_monitor)
	ref_one(nameof(linkedServer), /obj/machinery/message_server)
	extend("disconnect", needs(req(PROC_REF(cool_enough), because = MSG(message_monitor/too_hot))))
	after_init(0, then(PROC_REF(link_default_server)))
	interface("MessageMonitor")
	op("cleartemp", ui_act("cleartemp"), then(PROC_REF(ui_act_cleartemp)))
	op("auth", ui_act("auth", arg("key", schema_text(4096))), then(PROC_REF(ui_act_auth)))
	op("deauth", ui_act("deauth"), then(PROC_REF(ui_act_deauth)))
	op("find", ui_act("find"), needs(req_adjacent(), req_capable()), asks(/datum/prompt/choice, fields = list("title" = "Select a server.", "question" = "Please select a server.", "choices" = computed(PROC_REF(server_prompt_choices)), "timeout" = 0), when = PROC_REF(multiple_servers)), then(PROC_REF(ui_act_find)))
	op("hack", ui_act("hack"), then(PROC_REF(ui_act_hack)))
	op("active", ui_act("active"), then(PROC_REF(ui_act_active)))
	op("del_pda", ui_act("del_pda"), then(PROC_REF(ui_act_del_pda)))
	op("del_rc", ui_act("del_rc"), then(PROC_REF(ui_act_del_rc)))
	op("pass", ui_act("pass"), needs(req_adjacent(), req_capable()), asks(/datum/prompt/text, fields = list("question" = "Please enter the current decryption key.", "timeout" = 0), step = "current_key", when = PROC_REF(key_action_ready)), asks(/datum/prompt/text, fields = list("question" = "Please enter the new key (3 - 16 characters max):", "max_len" = 16, "timeout" = 0), step = "new_key", when = PROC_REF(current_key_matches)), then(PROC_REF(ui_act_pass)))
	op("delete", ui_act("delete", arg("id"), arg("type", schema_text(4096))), then(PROC_REF(ui_act_delete)))
	op("set_sender", ui_act("set_sender", arg("val", schema_text(4096))), then(PROC_REF(ui_act_set_sender)))
	op("set_sender_job", ui_act("set_sender_job", arg("val", schema_text(4096))), then(PROC_REF(ui_act_set_sender_job)))
	op("set_recipient", ui_act("set_recipient", arg("val")), then(PROC_REF(ui_act_set_recipient)))
	op("set_message", ui_act("set_message", arg("val", schema_text(4096))), then(PROC_REF(ui_act_set_message)))
	op("send_message", ui_act("send_message"), then(PROC_REF(ui_act_send_message)))
	op("addtoken", ui_act("addtoken"), needs(req_adjacent(), req_capable()), asks(/datum/prompt/text, fields = list("title" = "Token creation", "question" = "Enter text you want to be filtered out", "timeout" = 0), when = PROC_REF(key_action_ready)), then(PROC_REF(ui_act_addtoken)))
	op("deltoken", ui_act("deltoken", arg("deltoken", num())), then(PROC_REF(ui_act_deltoken)))
	op("open_ui_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_open_ui_impl)))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)

/obj/machinery/computer/message_monitor/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	data["customsender"] = customsender
	data["customjob"] = customjob
	data["custommessage"] = custommessage
	data["temp"] = temp

	data["customrecepient"] = "[customrecepient()]"

	data["hacking"] = !!hacking
	data["emag"] = !!emag
	data["auth"] = !!auth
	data["linkedServer"] = list()
	if(linkedServer() && auth)
		data["linkedServer"]["active"] = linkedServer().active
		data["linkedServer"]["broke"] = (linkedServer().power_lost() || linkedServer().broken_now())

		var/list/pda_msgs = list()
		for(var/datum/data_pda_msg/pda in linkedServer().pda_msgs)
			pda_msgs.Add(list(list(
				"ref" = "\ref[pda]",
				"sender" = pda.sender,
				"recipient" = pda.recipient,
				"message" = pda.message,
			)))
		data["linkedServer"]["pda_msgs"] = pda_msgs

		var/list/rc_msgs = list()
		for(var/datum/data_rc_msg/rc in linkedServer().rc_msgs)
			rc_msgs.Add(list(list(
				"ref" = "\ref[rc]",
				"sender" = rc.send_dpt,
				"recipient" = rc.rec_dpt,
				"message" = rc.message,
				"stamp" = rc.stamp,
				"id_auth" = rc.id_auth,
				"priority" = rc.priority,
			)))
		data["linkedServer"]["rc_msgs"] = rc_msgs

		var/spamIndex = 0
		var/list/spamfilter = list()
		for(var/token in linkedServer().spamfilter)
			spamIndex++
			spamfilter.Add(list(list(
				"index" = spamIndex,
				"token" = token,
			)))
		data["linkedServer"]["spamFilter"] = spamfilter

		//Get out list of viable PDAs
		var/list/obj/item/pda/sendPDAs = list()
		for(var/obj/item/pda/P in REGISTRY_MEMBERS(REGISTRY_PDAS))
			if(!P.owner || P.hidden)
				continue
			var/datum/data/pda/app/messenger/M = P.find_program(/datum/data/pda/app/messenger)
			if(!M || M.toff)
				continue
			sendPDAs["[P.name]"] = "\ref[P]"
		data["possibleRecipients"] = sendPDAs
	var/mob/living/original = user.mind.original_character
	data["isMalfAI"] = ((isAI(user) || isrobot(user)) && (user.mind.special_role && (original && original == user)))

	return data

/obj/machinery/computer/message_monitor/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return TRUE
	if(!istype(user))
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/computer/message_monitor/proc/BruteForce(mob/user as mob)
	if(isnull(linkedServer()))
		to_chat(user, span_warning("Could not complete brute-force: Linked Server Disconnected!"))
	else
		var/currentKey = linkedServer().decryptkey
		to_chat(user, span_warning("Brute-force completed! The key is '[currentKey]'."))
	hacking = 0
	changed(src)

/obj/machinery/computer/message_monitor/proc/UnmagConsole()
	set_emag(FALSE)
	changed(src)

/obj/machinery/computer/message_monitor/proc/ResetMessage()
	customsender 	= "System Administrator"
	rel_clear(src, nameof(customrecepient))
	custommessage 	= "This is a test, please ignore."
	customjob 		= "Admin"

/obj/machinery/computer/message_monitor/proc/ui_act_cleartemp(datum/act/op/A)
	temp = null
	. = TRUE
//Authenticate

/obj/machinery/computer/message_monitor/proc/ui_act_auth(datum/act/op/A, key)
	var/dkey = key
	if(dkey && dkey != "")
		if(linkedServer() && linkedServer().decryptkey == dkey)
			auth = TRUE
		else
			temp = incorrectkey
	. = TRUE

/obj/machinery/computer/message_monitor/proc/ui_act_deauth(datum/act/op/A)
	auth = FALSE
	. = TRUE
//Find a server

/obj/machinery/computer/message_monitor/proc/ui_act_find(datum/act/op/A)
	if(A.answer)
		server_selected(A)
		return OP_OK
	if(REGISTRY_MEMBERS(REGISTRY_MESSAGE_SERVERS) && REGISTRY_COUNT(REGISTRY_MESSAGE_SERVERS) > 1)
		server_selected(A)
	else if(REGISTRY_MEMBERS(REGISTRY_MESSAGE_SERVERS) && REGISTRY_COUNT(REGISTRY_MESSAGE_SERVERS) > 0)
		rel_set(src, nameof(/obj/machinery/computer/message_monitor::linkedServer), REGISTRY_MEMBERS(REGISTRY_MESSAGE_SERVERS)[1])
		set_temp("NOTICE: Only Single Server Detected - Server selected.", "average")
	else
		temp = noserver
//Hack the Console to get the password

/obj/machinery/computer/message_monitor/proc/ui_act_hack(datum/act/op/A)
	var/mob/living/original = A.actor.mind.original_character
	if((isAI(A.actor) || isrobot(A.actor)) && (A.actor.mind.special_role && (original && original == A.actor)))
		hacking = 1
		//Time it takes to bruteforce is dependant on the password length.
		after(src, 100*length(linkedServer().decryptkey), PROC_REF(brute_force_done), with = list(A.actor))

//Turn the server on/off.

/obj/machinery/computer/message_monitor/proc/ui_act_active(datum/act/op/A)
	if(!auth)
		return
	if(!linkedServer() || (linkedServer().power_lost() || linkedServer().broken_now()))
		temp = noserver
		return TRUE
	linkedServer().set_active(!linkedServer().active)
	. = TRUE
//Clears the logs - KEY REQUIRED

/obj/machinery/computer/message_monitor/proc/ui_act_del_pda(datum/act/op/A)
	if(!auth)
		return
	if(!linkedServer() || (linkedServer().power_lost() || linkedServer().broken_now()))
		temp = noserver
		return TRUE
	own_clear(linkedServer(), nameof(/obj/machinery/message_server::pda_msgs), OWN_DELETE)
	set_temp("NOTICE: Logs cleared.", "average")
	. = TRUE
//Clears the request console logs - KEY REQUIRED

/obj/machinery/computer/message_monitor/proc/ui_act_del_rc(datum/act/op/A)
	if(!auth)
		return
	if(!linkedServer() || (linkedServer().power_lost() || linkedServer().broken_now()))
		temp = noserver
		return TRUE
	own_clear(linkedServer(), nameof(/obj/machinery/message_server::rc_msgs), OWN_DELETE)
	set_temp("NOTICE: Logs cleared.", "average")
	. = TRUE
//Change the password - KEY REQUIRED

/obj/machinery/computer/message_monitor/proc/ui_act_pass(datum/act/op/A)
	if(A.answer)
		current_key_entered(A)
		return OP_OK
	if(!auth)
		return
	if(!linkedServer() || (linkedServer().power_lost() || linkedServer().broken_now()))
		temp = noserver
		return TRUE
	current_key_entered(A)
	. = TRUE
//Delete the log.

/obj/machinery/computer/message_monitor/proc/ui_act_delete(datum/act/op/A, id, kind)
	if(!auth)
		return
	if(!linkedServer() || (linkedServer().power_lost() || linkedServer().broken_now()))
		temp = noserver
		return TRUE
	if(kind == "pda")
		var/datum/log_entry = ui_ref(id, linkedServer().pda_msgs, null)
		if(log_entry)
			own_remove(linkedServer(), nameof(/obj/machinery/message_server::pda_msgs), log_entry)
	else
		var/datum/log_entry = ui_ref(id, linkedServer().rc_msgs, null)
		if(log_entry)
			own_remove(linkedServer(), nameof(/obj/machinery/message_server::rc_msgs), log_entry)
	set_temp("NOTICE: Log Deleted!", "average")
	. = TRUE
//Fake messaging selection - KEY REQUIRED

/obj/machinery/computer/message_monitor/proc/ui_act_set_sender(datum/act/op/A, val)
	if(!auth)
		return
	if(!linkedServer() || (linkedServer().power_lost() || linkedServer().broken_now()))
		temp = noserver
		return TRUE
	customsender = sanitize(val)
	. = TRUE

/obj/machinery/computer/message_monitor/proc/ui_act_set_sender_job(datum/act/op/A, val)
	if(!auth)
		return
	if(!linkedServer() || (linkedServer().power_lost() || linkedServer().broken_now()))
		temp = noserver
		return TRUE
	customjob = sanitize(val)
	. = TRUE

/obj/machinery/computer/message_monitor/proc/ui_act_set_recipient(datum/act/op/A, val)
	if(!auth)
		return
	if(!linkedServer() || (linkedServer().power_lost() || linkedServer().broken_now()))
		temp = noserver
		return TRUE
	var/obj/item/pda/P = ui_ref(val, null, /obj/item/pda)
	if(!istype(P) || !P.owner || P.hidden)
		return FALSE

	var/datum/data/pda/app/messenger/M = P.find_program(/datum/data/pda/app/messenger)
	if(!M || M.toff)
		return FALSE
	rel_set(src, nameof(/obj/machinery/computer/message_monitor::customrecepient), P)
	. = TRUE

/obj/machinery/computer/message_monitor/proc/ui_act_set_message(datum/act/op/A, val)
	if(!auth)
		return
	if(!linkedServer() || (linkedServer().power_lost() || linkedServer().broken_now()))
		temp = noserver
		return TRUE
	custommessage = sanitize(val)
	. = TRUE

/obj/machinery/computer/message_monitor/proc/ui_act_send_message(datum/act/op/A)
	if(!auth)
		return
	if(!linkedServer() || (linkedServer().power_lost() || linkedServer().broken_now()))
		temp = noserver
		return TRUE
	if(isnull(customsender) || customsender == "")
		customsender = "UNKNOWN"

	if(isnull(customrecepient()))
		set_temp("NOTICE: No recepient selected!", "average")
		return TRUE

	if(isnull(custommessage) || custommessage == "")
		set_temp("NOTICE: No message entered!", "average")
		return TRUE

	var/obj/item/pda/PDARec = null
	for(var/obj/item/pda/P in REGISTRY_MEMBERS(REGISTRY_PDAS))
		if(!P.owner || P.hidden)
			continue
		var/datum/data/pda/app/messenger/M = P.find_program(/datum/data/pda/app/messenger)
		if(!M || M.toff)
			continue
		if(P.owner == customsender)
			PDARec = P
	//Sender isn't faking as someone who exists
	if(isnull(PDARec))
		linkedServer().send_pda_message("[customrecepient().owner]", "[customsender]","[custommessage]")
		var/datum/data/pda/app/messenger/M = customrecepient().find_program(/datum/data/pda/app/messenger)
		if(M)
			M.receive_message(list("sent" = 0, "owner" = customsender, "job" = customjob, "message" = custommessage), null)
	//Sender is faking as someone who exists
	else
		linkedServer().send_pda_message("[customrecepient().owner]", "[PDARec.owner]","[custommessage]")

		var/datum/data/pda/app/messenger/M = customrecepient().find_program(/datum/data/pda/app/messenger)
		if(M)
			M.receive_message(list("sent" = 0, "owner" = "[PDARec.owner]", "job" = "[customjob]", "message" = "[custommessage]", "target" = "\ref[PDARec]"), "\ref[PDARec]")
	//Finally..
	ResetMessage()
	. = TRUE

/obj/machinery/computer/message_monitor/proc/ui_act_addtoken(datum/act/op/A)
	if(A.answer)
		token_entered(A)
		return OP_OK
	if(!auth)
		return
	if(!linkedServer() || (linkedServer().power_lost() || linkedServer().broken_now()))
		temp = noserver
		return TRUE
	token_entered(A)
	. = TRUE

/obj/machinery/computer/message_monitor/proc/ui_act_deltoken(datum/act/op/A, deltoken)
	if(!auth)
		return
	if(!linkedServer() || (linkedServer().power_lost() || linkedServer().broken_now()))
		temp = noserver
		return TRUE
	var/tokennum = deltoken
	linkedServer().spamfilter.Cut(tokennum, tokennum + 1)
	. = TRUE

/// The message servers by the name the question lists them under (a repeated name gets its number).
/obj/machinery/computer/message_monitor/proc/server_choices()
	var/list/choices = list()
	for(var/obj/machinery/message_server/server in REGISTRY_MEMBERS(REGISTRY_MESSAGE_SERVERS))
		var/label = "[server.name]"
		if(label in choices)
			label = "[label] #[length(choices) + 1]"
		choices[label] = server
	return choices

/obj/machinery/computer/message_monitor/proc/server_selected(datum/act/op/A)
	if(!A.answer)
		return
	var/obj/machinery/message_server/server = server_choices()[A.answer.value]
	if(!server)
		return
	rel_set(src, nameof(linkedServer), server)
	set_temp("NOTICE: Server selected.", "alert")

/obj/machinery/computer/message_monitor/proc/current_key_entered(datum/act/op/A)
	if(!A.answer)
		return
	var/dkey = trim(A.step_value("current_key"))
	if(!dkey || !linkedServer())
		return
	if(linkedServer().decryptkey != dkey)
		temp = incorrectkey
		return
	if(!isnull(A.step_value("new_key")))
		new_key_entered(A)

/obj/machinery/computer/message_monitor/proc/new_key_entered(datum/act/op/A)
	if(!A.answer)
		return
	var/newkey = trim(A.step_value("new_key"))
	if(!linkedServer())
		return
	if(length(newkey) <= 3)
		set_temp("NOTICE: Decryption key too short!", "average")
	else if(length(newkey) > 16)
		set_temp("NOTICE: Decryption key too long!", "average")
	else if(newkey && newkey != "")
		linkedServer().decryptkey = newkey
	set_temp("NOTICE: Decryption key set.", "average")

/obj/machinery/computer/message_monitor/proc/token_entered(datum/act/op/A)
	if(A.answer && linkedServer())
		linkedServer().spamfilter += A.answer.value

/obj/machinery/computer/message_monitor/proc/set_temp(text = "", style = "info", update_now = FALSE)
	temp = list(text = text, style = style)
	if(update_now)
		SStgui.update_uis(src)

/obj/item/paper/monitorkey
	name = "Monitor Decryption Key"

CAPABILITIES(/obj/item/paper/monitorkey)
	after_init(0, then(PROC_REF(write_daily_key)))

/// Writes the message servers' key, once they all exist.
/obj/item/paper/monitorkey/proc/write_daily_key(datum/act/timer/A)
	for(var/obj/machinery/message_server/server in REGISTRY_MEMBERS(REGISTRY_MESSAGE_SERVERS))
		if(!isnull(server.decryptkey))
			set_info("<center><h2>Daily Key Reset</h2></center><br>The new message monitor key is '[server.decryptkey]'.<br>Please keep this a secret and away from the clown.<br>If necessary, change the password to a more secure one.")
			info_links = info
			icon_state = "paper_words"
			break

/obj/machinery/computer/message_monitor/proc/brute_force_done(mob/user)
	if(linkedServer() && user)
		BruteForce(user)

/// linkedServer (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/message_monitor/proc/linkedServer() as /obj/machinery/message_server
	return linkedServer

/// The custom recipient PDA (a relation view).
/obj/machinery/computer/message_monitor/proc/customrecepient() as /obj/item/pda
	return customrecepient

/obj/machinery/computer/message_monitor/proc/multiple_servers(datum/act/op/A)
	return read_once(REGISTRY_COUNT(REGISTRY_MESSAGE_SERVERS)) > 1

/obj/machinery/computer/message_monitor/proc/server_prompt_choices(datum/act/op/A)
	return read_once(server_choices())

/obj/machinery/computer/message_monitor/proc/key_action_ready(datum/act/op/A)
	var/obj/machinery/message_server/server = linkedServer()
	return read_once(auth) && server && !server.power_lost() && !server.broken_now()

/obj/machinery/computer/message_monitor/proc/current_key_matches(datum/act/op/A)
	var/key = trim(A.step_value("current_key"))
	var/obj/machinery/message_server/server = linkedServer()
	return key && server && read_once(server.decryptkey) == key
