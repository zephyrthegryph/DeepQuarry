#define MESSAGE_SERVER_SPAM_REJECT 1
#define MESSAGE_SERVER_DEFAULT_SPAM_LIMIT 10

/datum/data_pda_msg
	var/recipient = "Unspecified" //name of the person
	var/sender = "Unspecified" //name of the sender
	var/message = "Blank" //transferred message

/datum/data_pda_msg/New(param_rec = "",param_sender = "",param_message = "")

	if(param_rec)
		recipient = param_rec
	if(param_sender)
		sender = param_sender
	if(param_message)
		message = param_message

/datum/data_rc_msg
	var/rec_dpt = "Unspecified" //name of the person
	var/send_dpt = "Unspecified" //name of the sender
	var/message = "Blank" //transferred message
	var/stamp = "Unstamped"
	var/id_auth = "Unauthenticated"
	var/priority = "Normal"

/datum/data_rc_msg/New(param_rec = "",param_sender = "",param_message = "",param_stamp = "",param_id_auth = "",param_priority)
	if(param_rec)
		rec_dpt = param_rec
	if(param_sender)
		send_dpt = param_sender
	if(param_message)
		message = param_message
	if(param_stamp)
		stamp = param_stamp
	if(param_id_auth)
		id_auth = param_id_auth
	if(param_priority)
		switch(param_priority)
			if(1)
				priority = "Normal"
			if(2)
				priority = "High"
			if(3)
				priority = "Extreme"
			else
				priority = "Undetermined"

/obj/machinery/message_server
	maintenance_flags = MACHINE_MAINT_STANDARD
	icon = 'icons/obj/machines/research.dmi'
	icon_state = "server"
	name = "Messaging Server"
	desc = "Facilitates both PDA messages and request console functions."
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 100
	circuit = /obj/item/circuitboard/message_server

	var/list/datum/data_pda_msg/pda_msgs
	var/list/datum/data_rc_msg/rc_msgs
	active = 1
	var/decryptkey = "password"

	//Spam filtering stuff
	// ALLOW(instance_list): d: edited in place per instance (4 writers)
	var/list/spamfilter = list("You have won", "your prize", "male enhancement", "shitcurity", \
			"are happy to inform you", "account number", "enter your PIN")
			//Messages having theese tokens will be rejected by server. Case sensitive
	var/spamfilter_limit = MESSAGE_SERVER_DEFAULT_SPAM_LIMIT	//Maximal amount of tokens

	var/datum/looping_sound/tcomms/soundloop
	var/noisy = FALSE

CAPABILITIES(/obj/machinery/message_server)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(active), wakes_on = list(nameof(active), STAT_OPERABLE), unpowered = TRUE)
	owns_one(nameof(soundloop), /datum/looping_sound/tcomms, starts = /datum/looping_sound/tcomms)
	owns_many(nameof(pda_msgs), /datum/data_pda_msg)
	owns_many(nameof(rc_msgs), /datum/data_rc_msg)
	op("upgrade", item(/obj/item/circuitboard/message_monitor), priority(OP_PRIORITY_DEFAULT - 1), label("Install memory upgrade"), when(req(PROC_REF(can_upgrade_holds))), then(PROC_REF(interaction_upgrade)))
	op("toggle", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Toggle PDA relay"), then(PROC_REF(interaction_toggle)))

REGISTRY_MEMBERSHIP(/obj/machinery/message_server, REGISTRY_MESSAGE_SERVERS)

/obj/machinery/message_server/Initialize(mapload)
	. = ..()
	if(prob(60)) // 60% chance to change the midloop
		if(prob(40))
			soundloop.mid_sounds = list('sound/machines/tcomms/tcomms_02.ogg' = 1)
			soundloop.mid_length = 40
		else if(prob(20))
			soundloop.mid_sounds = list('sound/machines/tcomms/tcomms_03.ogg' = 1)
			soundloop.mid_length = 10
		else
			soundloop.mid_sounds = list('sound/machines/tcomms/tcomms_04.ogg' = 1)
			soundloop.mid_length = 30
	decryptkey = GenerateKey()
	send_pda_message("System Administrator", "system", "This is an automated message. The messaging system is functioning correctly.")


/obj/machinery/message_server/examine(mob/user, distance, infix, suffix)
	. = ..()
	. += "It appears to be [active ? "online" : "offline"]."

/obj/machinery/message_server/proc/GenerateKey()
	//Feel free to move to Helpers.
	var/newKey
	newKey += pick("the", "if", "of", "as", "in", "a", "you", "from", "to", "an", "too", "little", "snow", "dead", "drunk", "rosebud", "duck", "al", "le")
	newKey += pick("diamond", "beer", "mushroom", "assistant", "clown", "captain", "twinkie", "security", "nuke", "small", "big", "escape", "yellow", "gloves", "monkey", "engine", "nuclear", "ai")
	newKey += pick("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")
	return newKey

/// Settles its hum while it is on (set_active() starts the step; it sleeps again once settled).
/obj/machinery/message_server/proc/work_step(datum/act/timer/A)
	if(active && (!operable()))
		set_active(0)
		soundloop.stop()
		noisy = FALSE
		return
	if(!noisy && active)
		soundloop.start()
		noisy = TRUE
	return PROCESS_KILL

/obj/machinery/message_server/proc/send_pda_message(recipient = "",sender = "",message = "")
	var/result
	for (var/token in spamfilter)
		if (findtextEx(message,token))
			message = span_red("[message]")	//Rejected messages will be indicated by red color.
			result = token										//Token caused rejection (if there are multiple, last will be chosen>.
	rel_add(src, nameof(pda_msgs), new/datum/data_pda_msg(recipient,sender,message))
	return result

/obj/machinery/message_server/proc/send_rc_message(recipient = "",sender = "",message = "",stamp = "", id_auth = "", priority = 1)
	rel_add(src, nameof(rc_msgs), new/datum/data_rc_msg(recipient,sender,message,stamp,id_auth,priority))
	var/authmsg = "[message]\n"
	if (id_auth)
		authmsg += "([id_auth])\n"
	if (stamp)
		authmsg += "([stamp])\n"
	for (var/obj/machinery/requests_console/Console in REGISTRY_MEMBERS(REGISTRY_ALARM_CONSOLES))
		if (ckey(Console.department) == ckey(recipient))
			if(!Console.operable())
				LAZYADD(Console.message_log, list(list("Message lost due to console failure.","Please contact [station_name()] system adminsitrator or AI for technical assistance.")))
				continue
			if(Console.newmessagepriority < priority)
				Console.newmessagepriority = priority
				Console.update_icon()
			switch(priority)
				if(2)
					if(!Console.silent)
						play_sfx(Console, SFX_MACHINES_TWOBEEP)
						Console.audible_message(text("[icon2html(Console,hearers(Console))] *The Requests Console beeps: 'PRIORITY Alert in [sender]'"),,5, runemessage = "beep! beep!")
					LAZYADD(Console.message_log, list(list("High Priority message from [sender]", "[authmsg]")))
				else
					if(!Console.silent)
						play_sfx(Console, SFX_MACHINES_TWOBEEP)
						Console.audible_message(text("[icon2html(Console,hearers(Console))] *The Requests Console beeps: 'Message from [sender]'"),,4, runemessage = "beep beep")
					LAZYADD(Console.message_log, list(list("Message from [sender]", "[authmsg]")))
			Console.set_light(2)

/obj/machinery/message_server/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_filter_notice("You toggle PDA message passing from [active ? "On" : "Off"] to [active ? "Off" : "On"]."))
	set_active(!active)
	return TRUE

/// No side effects: whether this server can currently take the upgrade board.
/obj/machinery/message_server/proc/can_upgrade(mob/actor, atom/target, obj/item/held)
	return active && operable() && (spamfilter_limit < MESSAGE_SERVER_DEFAULT_SPAM_LIMIT*2) // ALLOW(reads): the legacy check is read when the op is tried, never from a cached menu

/// Requirement (was REQ_* can_upgrade): the legacy check answers TRUE to pass.
/obj/machinery/message_server/proc/can_upgrade_holds(datum/act/op/A)
	var/answer = can_upgrade(A.actor, src, A.held)
	return (!istext(answer) && !!answer) ? null : /datum/msg/req_failed

/obj/machinery/message_server/proc/interaction_upgrade(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(!consume(O, user))
		return TRUE
	spamfilter_limit += round(MESSAGE_SERVER_DEFAULT_SPAM_LIMIT / 2)
	to_chat(user, span_filter_notice("You install additional memory and processors into message server. Its filtering capabilities been enhanced."))
	return TRUE

/// Appearance reader: the icon_state suffix for power/active state.
/obj/machinery/message_server/proc/appearance_server_state()
	if(!operable())
		return "nopower"
	if(!active)
		return "off"
	return "on"

/// The look (the draw sweep: from its template).
/obj/machinery/message_server/draw(datum/look/look)
	..()
	look.state("server-[appearance_server_state()]")

/datum/feedback_variable
	var/variable
	var/value
	var/details

/datum/feedback_variable/vv_edit_var(var_name, var_value)
	if(var_name == NAMEOF(src, variable) || var_name == NAMEOF(src, value) || var_name == NAMEOF(src, details))
		return FALSE
	return ..()

/datum/feedback_variable/New(param_variable,param_value = 0)
	variable = param_variable
	value = param_value

/datum/feedback_variable/proc/inc(num = 1)
	if(isnum(value))
		value += num
	else
		value = text2num(value)
		if(isnum(value))
			value += num
		else
			value = num

/datum/feedback_variable/proc/dec(num = 1)
	if(isnum(value))
		value -= num
	else
		value = text2num(value)
		if(isnum(value))
			value -= num
		else
			value = -num

/datum/feedback_variable/proc/set_value(num)
	if(isnum(num))
		value = num

/datum/feedback_variable/proc/get_value()
	return value

/datum/feedback_variable/proc/get_variable()
	return variable

/datum/feedback_variable/proc/set_details(text)
	if(istext(text))
		details = text

/datum/feedback_variable/proc/add_details(text)
	if(istext(text))
		if(!details)
			details = text
		else
			details += " [text]"

/datum/feedback_variable/proc/get_details()
	return details

/datum/feedback_variable/proc/get_parsed()
	return list(variable,value,details)

GLOBAL_DATUM(blackbox, /obj/machinery/blackbox_recorder)

/obj/machinery/blackbox_recorder
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "blackbox"
	name = "Blackbox Recorder"
	desc = "Records all radio communications, as well as various other information in case of the worst."
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 100
	// ALLOW(instance_list): d: blackbox singleton log
	var/list/messages = list()		//Stores messages of non-standard frequencies
	var/list/messages_admin

	var/list/msg_common
	var/list/msg_science
	var/list/msg_command
	var/list/msg_medical
	var/list/msg_engineering
	var/list/msg_security
	var/list/msg_deathsquad
	var/list/msg_syndicate
	var/list/msg_raider
	var/list/msg_cargo
	var/list/msg_service
	var/list/msg_explorer

	var/list/datum/feedback_variable/feedback = new() // ALLOW(instance_list): d: blackbox singleton; feedback datums fill it every round

	//Only one can exist in the world!

CAPABILITIES(/obj/machinery/blackbox_recorder)
	owns_many(nameof(feedback), /datum/feedback_variable)
/obj/machinery/blackbox_recorder/Initialize(mapload)
	. = ..()
	if(istype(GLOB.blackbox, /obj/machinery/blackbox_recorder))
		return INITIALIZE_HINT_QDEL
	GLOB.blackbox = src

// The blackbox respawns with its logs. Phase 1, before phase 4 deletes the feedback
// it owns (an owned list): the replacement takes the list over.
/obj/machinery/blackbox_recorder/lifecycle_unbind()
	var/turf/T = locate(1,1,2)
	if(T)
		GLOB.blackbox = null
		var/obj/machinery/blackbox_recorder/BR = new/obj/machinery/blackbox_recorder(T)
		BR.msg_common = msg_common
		BR.msg_science = msg_science
		BR.msg_command = msg_command
		BR.msg_medical = msg_medical
		BR.msg_engineering = msg_engineering
		BR.msg_security = msg_security
		BR.msg_deathsquad = msg_deathsquad
		BR.msg_syndicate = msg_syndicate
		BR.msg_cargo = msg_cargo
		BR.msg_service = msg_service
		// The feedback datums move over one by one (the replacement takes the list over).
		own_clear(BR, nameof(BR.feedback), OWN_DELETE)
		for(var/datum/entry as anything in rel_take_all(src, nameof(feedback)))
			rel_add(BR, nameof(BR.feedback), entry)
		BR.messages = messages
		BR.messages_admin = messages_admin
	return ..()

/obj/machinery/blackbox_recorder/proc/find_feedback_datum(variable)
	for(var/datum/feedback_variable/FV in feedback)
		if(FV.get_variable() == variable)
			return FV
	var/datum/feedback_variable/FV = new(variable)
	rel_add(src, nameof(feedback), FV)
	return FV

/obj/machinery/blackbox_recorder/proc/get_round_feedback()
	return feedback

/obj/machinery/blackbox_recorder/proc/round_end_data_gathering()

	var/pda_msg_amt = 0
	var/rc_msg_amt = 0

	for(var/obj/machinery/message_server/MS in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(length(MS.pda_msgs) > pda_msg_amt)
			pda_msg_amt = length(MS.pda_msgs)
		if(length(MS.rc_msgs) > rc_msg_amt)
			rc_msg_amt = length(MS.rc_msgs)

	feedback_set_details("radio_usage","")

	feedback_add_details("radio_usage","COM-[length(msg_common)]")
	feedback_add_details("radio_usage","SCI-[length(msg_science)]")
	feedback_add_details("radio_usage","HEA-[length(msg_command)]")
	feedback_add_details("radio_usage","MED-[length(msg_medical)]")
	feedback_add_details("radio_usage","ENG-[length(msg_engineering)]")
	feedback_add_details("radio_usage","SEC-[length(msg_security)]")
	feedback_add_details("radio_usage","DTH-[length(msg_deathsquad)]")
	feedback_add_details("radio_usage","SYN-[length(msg_syndicate)]")
	feedback_add_details("radio_usage","CAR-[length(msg_cargo)]")
	feedback_add_details("radio_usage","SRV-[length(msg_service)]")
	feedback_add_details("radio_usage","OTH-[messages.len]")
	feedback_add_details("radio_usage","PDA-[pda_msg_amt]")
	feedback_add_details("radio_usage","RC-[rc_msg_amt]")

	feedback_set_details("round_end","[time2text(world.realtime)]") //This one MUST be the last one that gets set.

/obj/machinery/blackbox_recorder/vv_edit_var(var_name, var_value)
	var/static/list/blocked_vars		//hacky as fuck kill me
	if(!blocked_vars)
		var/obj/machinery/M = new
		var/list/parent_vars = M.vars.Copy()
		blocked_vars = vars.Copy() - parent_vars
	if(var_name in blocked_vars)
		return FALSE
	return ..()

//This proc is only to be called at round end.
/obj/machinery/blackbox_recorder/proc/save_all_data_to_sql()
	if(!feedback) return

	round_end_data_gathering() //round_end time logging and some other data processing
	if(!SSdbcore.IsConnected()) return
	// The feedback is captured now (text and numbers); the rows are written on the I/O lane
	// once the next round id is known.
	var/list/rows = list()
	for(var/datum/feedback_variable/FV in feedback)
		rows += list(list(FV.get_variable(), FV.get_value(), FV.get_details()))
	io_job(null, /datum/io_backend/sql, "SELECT MAX(round_id) AS round_id FROM erro_feedback", null, /proc/blackbox_write_feedback_rows, rows)

/// io_job() callback: writes the blackbox's captured feedback rows under the next round id.
/proc/blackbox_write_feedback_rows(list/result, error, list/rows)
	if(error)
		log_sql("Blackbox feedback: round id lookup failed: [error]")
		return
	var/round_id
	for(var/list/row in result["rows"])
		round_id = row[1]
	if(!isnum(round_id))
		round_id = text2num(round_id)
	round_id++
	for(var/list/row in rows)
		sql_write("INSERT INTO erro_feedback VALUES (null, Now(), :round_id, :fv_variable, :fv_value, :fv_details)", list("round_id" = round_id, "fv_variable" = row[1], "fv_value" = row[2], "fv_details" = row[3]))

// Sanitize inputs to avoid SQL injection attacks. This is not secure. Basic filters like this are pretty easy to bypass. Use the format for arguments used in the above.
/proc/sql_sanitize_text(text)
	text = replacetext(text, "'", "''")
	text = replacetext(text, ";", "")
	text = replacetext(text, "&", "")
	return text

/proc/feedback_set(variable,value)
	if(!GLOB.blackbox) return

	variable = sql_sanitize_text(variable)

	var/datum/feedback_variable/FV = GLOB.blackbox.find_feedback_datum(variable)

	if(!FV) return

	FV.set_value(value)

/proc/feedback_inc(variable,value)
	if(!GLOB.blackbox) return

	variable = sql_sanitize_text(variable)

	var/datum/feedback_variable/FV = GLOB.blackbox.find_feedback_datum(variable)

	if(!FV) return

	FV.inc(value)

/proc/feedback_dec(variable,value)
	if(!GLOB.blackbox) return

	variable = sql_sanitize_text(variable)

	var/datum/feedback_variable/FV = GLOB.blackbox.find_feedback_datum(variable)

	if(!FV) return

	FV.dec(value)

/proc/feedback_set_details(variable,details)
	if(!GLOB.blackbox) return

	variable = sql_sanitize_text(variable)
	details = sql_sanitize_text(details)

	var/datum/feedback_variable/FV = GLOB.blackbox.find_feedback_datum(variable)

	if(!FV) return

	FV.set_details(details)

/proc/feedback_add_details(variable,details)
	if(!GLOB.blackbox) return

	variable = sql_sanitize_text(variable)
	details = sql_sanitize_text(details)

	var/datum/feedback_variable/FV = GLOB.blackbox.find_feedback_datum(variable)

	if(!FV) return

	FV.add_details(details)

#undef MESSAGE_SERVER_SPAM_REJECT
#undef MESSAGE_SERVER_DEFAULT_SPAM_LIMIT
