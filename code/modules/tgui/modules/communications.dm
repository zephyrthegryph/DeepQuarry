#define COMM_SCREEN_MAIN		1
#define COMM_SCREEN_STAT		2
#define COMM_SCREEN_MESSAGES	3

#define COMM_AUTHENTICATION_NONE	0
#define COMM_AUTHENTICATION_MIN		1
#define COMM_AUTHENTICATION_MAX		2

#define COMM_MSGLEN_MINIMUM 6
#define COMM_CCMSGLEN_MINIMUM 20
/// How long into the round before the emergency shuttle can be called.
#define SHUTTLE_CALL_GRACE (10 MINUTES)
/// How long into the round before a shift-change shuttle can be called.
#define SHIFT_CHANGE_GRACE (90 MINUTES)

/datum/tgui_module/communications
	name = "Command & Communications"

	var/current_viewing_message_id = 0
	var/current_viewing_message = null

	/// Who is logged in, and how far (REF(user) -> COMM_AUTHENTICATION_*): a login is the person's, not the console's.
	var/list/logins
	var/menu_state = COMM_SCREEN_MAIN
	var/ai_menu_state = COMM_SCREEN_MAIN
	var/aicurrmsg

	var/message_cooldown
	var/centcomm_message_cooldown
	///Cooldown on how quickly you can change the station's level.
	COOLDOWN_DECLARE(level_change_cooldown)
	var/tmp_alertlevel = 0

	var/stat_msg1
	var/stat_msg2
	var/display_type = "blank"

	var/datum/announcement/priority/crew_announcement

	var/ATC

	var/list/req_access = list() // ALLOW(instance_list): d: access list; an empty list and null differ for access checks

CAPABILITIES(/datum/tgui_module/communications)
	owns_one(nameof(crew_announcement), /datum/announcement/priority, starts = PROC_REF(make_announcement))
	interface("CommunicationsConsole")
	// The console works only near the station; after login, every button but the login one needs a login.
	extend(TAG_UI, needs(req(PROC_REF(ui_in_contact))))
	op("auth", ui_act("auth"), needs(req(PROC_REF(ui_is_human))), then(PROC_REF(ui_act_auth)))
	op("main", ui_act("main"), needs(req(PROC_REF(ui_logged_in))), then(PROC_REF(ui_act_main)))
	op("newalertlevel", ui_act("newalertlevel", arg("level", num())), needs(req(PROC_REF(ui_logged_in))), then(PROC_REF(ui_act_newalertlevel)))
	op("announce", ui_act("announce"), needs(req(PROC_REF(ui_logged_in)), req(PROC_REF(ui_captain)), req(PROC_REF(announce_ready))), asks(/datum/prompt/text, fields = list("title" = "Priority Announcement", "question" = "Please write a message to announce to the station crew.", "multiline" = TRUE, "max_len" = MAX_TGUI_INPUT)), then(PROC_REF(ui_act_announce)))
	op("callshuttle", ui_act("callshuttle"), needs(req(PROC_REF(ui_logged_in))), asks(/datum/prompt/yes_no, fields = list("title" = "Confirm", "question" = "OOC: You are required to Ahelp first before calling the shuttle. Please obtain confirmation from staff before calling the shuttle. \n\n Are you sure you want to call the shuttle?")), then(PROC_REF(ui_act_callshuttle)))
	op("cancelshuttle", ui_act("cancelshuttle"), needs(req(PROC_REF(ui_logged_in)), req(PROC_REF(ui_not_silicon))), asks(/datum/prompt/yes_no, fields = list("title" = "Confirm", "question" = "Are you sure you wish to recall the shuttle?")), then(PROC_REF(ui_act_cancelshuttle)))
	op("messagelist", ui_act("messagelist", arg("msgid", num())), needs(req(PROC_REF(ui_logged_in))), then(PROC_REF(ui_act_messagelist)))
	op("delmessage", ui_act("delmessage", arg("msgid", num())), needs(req(PROC_REF(ui_logged_in)), req(PROC_REF(message_deletable))), asks(/datum/prompt/yes_no, fields = list("title" = "Confirm", "question" = "Are you sure you wish to delete this message?")), then(PROC_REF(ui_act_delmessage)))
	extend("delmessage", then(PROC_REF(ui_select_message), early = TRUE))
	op("status", ui_act("status"), needs(req(PROC_REF(ui_logged_in))), then(PROC_REF(ui_act_status)))
	op("setstat", ui_act("setstat", arg("statdisp", enum(list("blank", "time", "shuttle", "message")))), needs(req(PROC_REF(ui_logged_in))), then(PROC_REF(ui_act_setstat)))
	op("setmsg1", ui_act("setmsg1"), needs(req(PROC_REF(ui_logged_in))), asks(/datum/prompt/text, fields = list("title" = "Enter Message Text", "question" = "Line 1", "default" = computed(PROC_REF(msg1_default)), "max_len" = 40)), then(PROC_REF(ui_act_setmsg1)))
	op("setmsg2", ui_act("setmsg2"), needs(req(PROC_REF(ui_logged_in))), asks(/datum/prompt/text, fields = list("title" = "Enter Message Text", "question" = "Line 2", "default" = computed(PROC_REF(msg2_default)), "max_len" = 40)), then(PROC_REF(ui_act_setmsg2)))
	op("MessageCentCom", ui_act("MessageCentCom"), needs(req(PROC_REF(ui_logged_in)), req(PROC_REF(ui_captain)), req(PROC_REF(centcom_ready))), asks(/datum/prompt/text, fields = list("title" = "Central Command Quantum Messaging", "question" = computed(PROC_REF(centcom_question)), "multiline" = TRUE)), then(PROC_REF(ui_act_messagecentcom)))
	op("MessageSyndicate", ui_act("MessageSyndicate"), needs(req(PROC_REF(ui_logged_in)), req(PROC_REF(ui_captain_emagged)), req(PROC_REF(centcom_ready))), asks(/datum/prompt/text, fields = list("title" = "To abort, send an empty message.", "question" = "Please choose a message to transmit to \[ABNORMAL ROUTING CORDINATES\] via quantum entanglement.  Please be aware that this process is very expensive, and abuse will lead to... termination. Transmission does not guarantee a response. There is a 30 second delay before you may send another message, be clear, full and concise.")), then(PROC_REF(ui_act_messagesyndicate)))
	op("RestoreBackup", ui_act("RestoreBackup"), needs(req(PROC_REF(ui_logged_in))), says(MSG(communications/backup_restored)), then(PROC_REF(ui_act_restorebackup)))

/// The console reaches the person: they are on a level the station's contact range covers.
/datum/tgui_module/communications/proc/ui_in_contact(datum/act/op/A)
	return (!using_map || (get_z(A.actor) in using_map.contact_levels)) ? null : MSG(communications/out_of_range)

MSG_DEF_SELF(communications/out_of_range, "Unable to establish a connection: You're too far away from the station!")
MSG_DEF_SELF(communications/access_denied, "Access denied.")
MSG_DEF_SELF(communications/no_recall, "Firewalls prevent you from recalling the shuttle.")
MSG_DEF_SELF(communications/announce_cooldown, "Please allow at least one minute to pass between announcements.")
MSG_DEF_SELF(communications/arrays_recycling, "Arrays recycling. Please stand by.")
MSG_DEF_SELF(communications/cannot_delete, "That message cannot be deleted here.")
MSG_DEF_SELF(communications/backup_restored, "Backup routing data restored!")

/// A module is a plain datum: its declared starting occupants (the announcement) are made here.
/datum/tgui_module/communications/New(host)
	. = ..()
	lifecycle_decls_init(src)

/// The priority announcement the console makes (a newscast as well).
/datum/tgui_module/communications/proc/make_announcement(datum/act/A)
	var/datum/announcement/priority/P = new
	P.newscast = TRUE
	return P

/// The routing circuits are scrambled: the console's host was emagged (a modular program cannot be).
/datum/tgui_module/communications/proc/routing_scrambled()
	var/obj/machinery/computer/communications/C = host()
	return istype(C) && !!emag_emagged(C)

/// Logs `user` in at `level` (COMM_AUTHENTICATION_NONE logs them out).
/datum/tgui_module/communications/proc/set_login(mob/user, level)
	if(level)
		LAZYSET(logins, REF(user), level)
	else
		LAZYREMOVE(logins, REF(user))

/// needs: the message named is one this console may delete (a modular program's own copy; the station's list is kept).
/datum/tgui_module/communications/proc/message_deletable(datum/act/op/A)
	var/datum/comm_message_listener/l = obtain_message_listener()
	return (l != GLOB.global_message_listener && !!message_by_id(A.args["msgid"])) ? null : MSG(communications/cannot_delete)

/// The message of that id in this console's list, or null.
/datum/tgui_module/communications/proc/message_by_id(msgid)
	var/datum/comm_message_listener/l = obtain_message_listener()
	for(var/list/m in l.messages)
		if(m["id"] == msgid)
			return m

/datum/tgui_module/communications/proc/msg1_default(datum/act/op/A)
	return stat_msg1

/datum/tgui_module/communications/proc/msg2_default(datum/act/op/A)
	return stat_msg2

/datum/tgui_module/communications/proc/ui_is_human(datum/act/op/A)
	return (ishuman(A.actor)) ? null : MSG(communications/access_denied)

/datum/tgui_module/communications/proc/ui_logged_in(datum/act/op/A)
	return (is_authenticated(A.actor, FALSE)) ? null : MSG(communications/access_denied)

/datum/tgui_module/communications/proc/ui_captain(datum/act/op/A)
	return (is_authenticated(A.actor, FALSE) == COMM_AUTHENTICATION_MAX) ? null : /datum/msg/req_silent

/datum/tgui_module/communications/proc/ui_captain_emagged(datum/act/op/A)
	return routing_scrambled() ? ui_captain(A) : /datum/msg/req_silent

/datum/tgui_module/communications/proc/ui_not_silicon(datum/act/op/A)
	return (!(isAI(A.actor) || isrobot(A.actor))) ? null : MSG(communications/no_recall)

/datum/tgui_module/communications/proc/announce_ready(datum/act/op/A)
	return (COOLDOWN_FINISHED(src, message_cooldown)) ? null : MSG(communications/announce_cooldown)

/datum/tgui_module/communications/proc/centcom_ready(datum/act/op/A)
	return (COOLDOWN_FINISHED(src, centcomm_message_cooldown)) ? null : MSG(communications/arrays_recycling)

/datum/tgui_module/communications/proc/centcom_question(datum/act/op/A)
	return "Please choose a message to transmit to [using_map.boss_short] via quantum entanglement. Please be aware that this process is very expensive, and abuse will lead to... termination.  Transmission does not guarantee a response. There is a 30 second delay before you may send another message, be clear, full and concise."

/datum/tgui_module/communications/ui_prepare(mob/user, datum/tgui/ui)
	if(using_map && !(get_z(user) in using_map.contact_levels))
		to_chat(user, span_danger("Unable to establish a connection: You're too far away from the station!"))
		return FALSE
	return ..()

/// How far `user` is logged in: an admin ghost as the captain; anyone else as far as their own login went.
/datum/tgui_module/communications/proc/is_authenticated(mob/user, message = TRUE)
	if(is_admin_ghost(user))
		return COMM_AUTHENTICATION_MAX
	var/level = LAZYACCESS(logins, REF(user)) || COMM_AUTHENTICATION_NONE
	if(!level && message)
		to_chat(user, span_warning("Access denied."))
	return level

/datum/tgui_module/communications/proc/change_security_level(mob/user, new_level)
	if(!COOLDOWN_FINISHED(src, level_change_cooldown))
		to_chat(user, span_warning("Please wait [round((COOLDOWN_TIMELEFT(src, level_change_cooldown) * 0.1), 1)] second(s) before changing the station's alert level again."))
		tmp_alertlevel = 0
		return
	tmp_alertlevel = new_level
	var/old_level = GLOB.security_level
	if(!tmp_alertlevel) tmp_alertlevel = SEC_LEVEL_GREEN
	if(tmp_alertlevel < SEC_LEVEL_GREEN) tmp_alertlevel = SEC_LEVEL_GREEN
	if(tmp_alertlevel > SEC_LEVEL_BLUE) tmp_alertlevel = SEC_LEVEL_BLUE //Cannot engage delta with this
	set_security_level(tmp_alertlevel)
	if(GLOB.security_level != old_level)
		//Only notify the admins if an actual change happened
		log_game("[key_name(user)] has changed the security level to [get_security_level()].")
		message_admins("[key_name_admin(user)] has changed the security level to [get_security_level()].")
		switch(GLOB.security_level)
			if(SEC_LEVEL_GREEN)
				feedback_inc("alert_comms_green",1)
			if(SEC_LEVEL_YELLOW)
				feedback_inc("alert_comms_yellow",1)
			if(SEC_LEVEL_VIOLET)
				feedback_inc("alert_comms_violet",1)
			if(SEC_LEVEL_ORANGE)
				feedback_inc("alert_comms_orange",1)
			if(SEC_LEVEL_BLUE)
				feedback_inc("alert_comms_blue",1)
		COOLDOWN_START(src, level_change_cooldown, 2 MINUTES) // 2 minute cd on station alert changing.
	tmp_alertlevel = 0

/datum/tgui_module/communications/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	data["emagged"] = routing_scrambled()
	data["message_current_id"] = current_viewing_message_id
	data["message_current"] = current_viewing_message
	data["is_ai"]         = isAI(user) || isrobot(user)
	data["menu_state"]    = data["is_ai"] ? ai_menu_state : menu_state
	data["authenticated"] = is_authenticated(user, 0)
	data["authmax"] = data["authenticated"] == COMM_AUTHENTICATION_MAX ? TRUE : FALSE
	data["boss_short"] = using_map.boss_short

	data["stat_display"] =  list(
		"type"   = display_type,
		// "icon"   = display_icon,
		"line_1" = (stat_msg1 ? stat_msg1 : "-----"),
		"line_2" = (stat_msg2 ? stat_msg2 : "-----"),

		"presets" = list(
			list("name" = "blank",    "label" = "Clear",        "desc" = "Blank slate."),
			list("name" = "time",     "label" = "Station Time", "desc" = "The current time according to the station's clock."),
			list("name" = "shuttle",  "label" = "Shuttle ETA",     "desc" = "Display how much time is left."), // we have a shuttle not a tram silly virgo// Shuttle ETA -> Tram ETA because we use trams
			list("name" = "message",  "label" = "Message",      "desc" = "A custom message.")
		),
	)

	data["security_level"] = GLOB.security_level
	switch(GLOB.security_level)
		if(SEC_LEVEL_BLUE)
			data["security_level_color"] = "blue";
		if(SEC_LEVEL_ORANGE)
			data["security_level_color"] = "orange";
		if(SEC_LEVEL_VIOLET)
			data["security_level_color"] = "violet";
		if(SEC_LEVEL_YELLOW)
			data["security_level_color"] = "yellow";
		if(SEC_LEVEL_GREEN)
			data["security_level_color"] = "green";
		if(SEC_LEVEL_RED)
			data["security_level_color"] = "red";
		else
			data["security_level_color"] = "purple";
	data["str_security_level"] = capitalize(get_security_level())
	data["levels"] = list(
		list("id" = SEC_LEVEL_GREEN,  "name" = "Green",  "icon" = "dove"),
		list("id" = SEC_LEVEL_YELLOW, "name" = "Yellow", "icon" = "exclamation-triangle"),
		list("id" = SEC_LEVEL_BLUE,   "name" = "Blue",   "icon" = "eye"),
		list("id" = SEC_LEVEL_ORANGE, "name" = "Orange", "icon" = "wrench"),
		list("id" = SEC_LEVEL_VIOLET, "name" = "Violet", "icon" = "biohazard"),
	)

	var/datum/comm_message_listener/l = obtain_message_listener()
	data["messages"] = l.messages
	data["message_deletion_allowed"] = l != GLOB.global_message_listener

	// data["lastCallLoc"]     = SSshuttle.emergencyLastCallLoc ? strip_improper(SSshuttle.emergencyLastCallLoc.name) : null
	data["msg_cooldown"] = round(COOLDOWN_TIMELEFT(src, message_cooldown) / (1 SECOND))
	data["cc_cooldown"] = round(COOLDOWN_TIMELEFT(src, centcomm_message_cooldown) / (1 SECOND))

	data["esc_callable"] = SSemergency_shuttle.location() && !SSemergency_shuttle.online() ? TRUE : FALSE
	data["esc_recallable"] = SSemergency_shuttle.location() && SSemergency_shuttle.online() ? TRUE : FALSE
	data["esc_status"] = FALSE
	if(SSemergency_shuttle.has_eta())
		var/timeleft = SSemergency_shuttle.estimate_arrival_time()
		data["esc_status"] = SSemergency_shuttle.online() ? "ETA:" : "RECALLING:"
		data["esc_status"] += " [timeleft / 60 % 60]:[add_zero(num2text(timeleft % 60), 2)]"
	return data

/datum/tgui_module/communications/proc/setCurrentMessage(mob/user, value)
	current_viewing_message_id = value

	var/datum/comm_message_listener/l = obtain_message_listener()
	for(var/list/m in l.messages)
		if(m["id"] == current_viewing_message_id)
			current_viewing_message = m

/datum/tgui_module/communications/proc/setMenuState(mob/user, value)
	if(isAI(user) || isrobot(user))
		ai_menu_state = value
	else
		menu_state = value

/datum/tgui_module/communications/proc/obtain_message_listener()
	if(istype(host(), /datum/computer_file/program/comm))
		var/datum/computer_file/program/comm/P = host()
		return P.message_core
	return GLOB.global_message_listener

/proc/post_status(atom/source, command, data1, data2, mob/user = null)
	var/datum/radio_frequency/frequency = SSradio.return_frequency(DISPLAY_FREQ)

	if(!frequency)
		return

	var/datum/signal/status_signal = new
	rel_set(status_signal, nameof(status_signal.source), source)
	status_signal.transmission_method = TRANSMISSION_RADIO
	status_signal.data["command"] = command

	switch(command)
		if("message")
			status_signal.data["msg1"] = data1
			status_signal.data["msg2"] = data2
			log_admin("STATUS: [user] set status screen message: [data1] [data2]")
		if("alert")
			status_signal.data["picture_state"] = data1

	frequency.post_signal(null, status_signal)

/// The login button: logs in (a head of staff, or the captain with an ID) or, when logged in, out.
/datum/tgui_module/communications/proc/ui_act_auth(datum/act/op/A)
	var/mob/user = A.actor
	// Logout function.
	if(LAZYACCESS(logins, REF(user)))
		set_login(user, COMM_AUTHENTICATION_NONE)
		setMenuState(user, COMM_SCREEN_MAIN)
		return TRUE
	// Login function.
	var/level = COMM_AUTHENTICATION_NONE
	if(check_access(user, ACCESS_HEADS))
		level = COMM_AUTHENTICATION_MIN
	if(check_access(user, ACCESS_CAPTAIN))
		level = COMM_AUTHENTICATION_MAX
	set_login(user, level)
	if(level == COMM_AUTHENTICATION_NONE)
		to_chat(user, span_warning("You need to wear your ID."))
	return TRUE

/datum/tgui_module/communications/proc/ui_act_main(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	setMenuState(user, COMM_SCREEN_MAIN)

/datum/tgui_module/communications/proc/ui_act_newalertlevel(datum/act/op/A, level)
	var/mob/user = A.actor
	. = TRUE
	if(isAI(user) || isrobot(user))
		to_chat(user, span_warning("Firewalls prevent you from changing the alert level."))
		return
	else if(isobserver(user))
		var/mob/observer/dead/D = user
		if(D.can_admin_interact())
			change_security_level(user, level)
			return TRUE
	else if(!ishuman(user))
		to_chat(user, span_warning("Security measures prevent you from changing the alert level."))
		return

	if(is_authenticated(user))
		change_security_level(user, level)
	else
		to_chat(user, span_warning("You are not authorized to do this."))
	setMenuState(user, COMM_SCREEN_MAIN)

/datum/tgui_module/communications/proc/ui_act_announce(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/P = A.answer
	var/input = P?.value
	if(!input)
		return TRUE
	if(length(input) < COMM_MSGLEN_MINIMUM)
		to_chat(user, span_warning("Message '[input]' is too short. [COMM_MSGLEN_MINIMUM] character minimum."))
		return TRUE
	var/obj/item/card/id/id = user.GetIdCard()
	crew_announcement.announcer = istype(id) ? GetNameAndAssignmentFromId(id) : null
	crew_announcement.Announce(input)
	COOLDOWN_START(src, message_cooldown, 60 SECONDS)
	return TRUE

/datum/tgui_module/communications/proc/ui_act_callshuttle(datum/act/op/A)
	var/mob/user = A.actor
	call_shuttle_proc(user)
	if(SSemergency_shuttle.online())
		post_status(src, "shuttle", user = user)
	setMenuState(user, COMM_SCREEN_MAIN)
	return TRUE

/datum/tgui_module/communications/proc/ui_act_cancelshuttle(datum/act/op/A)
	var/mob/user = A.actor
	cancel_call_proc(user)
	setMenuState(user, COMM_SCREEN_MAIN)
	return TRUE

/datum/tgui_module/communications/proc/ui_act_messagelist(datum/act/op/A, msgid)
	var/mob/user = A.actor
	. = TRUE
	current_viewing_message = null
	current_viewing_message_id = null
	if(msgid)
		setCurrentMessage(user, msgid)
	setMenuState(user, COMM_SCREEN_MESSAGES)

/// The delete button names the message before it asks, so the window shows which one is in question.
/datum/tgui_module/communications/proc/ui_select_message(datum/act/op/A)
	var/msgid = A.args["msgid"]
	if(msgid)
		setCurrentMessage(A.actor, msgid)
	return OP_OK

/// The message the button named (by its id, as pressed: another selection while the question was open does not change which) is deleted.
/datum/tgui_module/communications/proc/ui_act_delmessage(datum/act/op/A, msgid)
	var/datum/comm_message_listener/l = obtain_message_listener()
	var/list/m = message_by_id(msgid)
	if(m)
		l.Remove(m)
	if(current_viewing_message_id == msgid)
		current_viewing_message = null
	setMenuState(A.actor, COMM_SCREEN_MESSAGES)
	return TRUE

/datum/tgui_module/communications/proc/ui_act_status(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	setMenuState(user, COMM_SCREEN_STAT)

// Status display stuff

/// The status displays show one of the presets: blank, the time, the shuttle's ETA, or the console's two lines.
/datum/tgui_module/communications/proc/ui_act_setstat(datum/act/op/A, statdisp)
	display_type = statdisp
	if(statdisp == "message")
		post_status(src, "message", stat_msg1, stat_msg2, user = A.actor)
	else
		post_status(src, statdisp, user = A.actor)
	return TRUE

/datum/tgui_module/communications/proc/ui_act_setmsg1(datum/act/op/A)
	var/datum/prompt/P = A.answer
	stat_msg1 = reject_bad_text(P?.value, 40)
	setMenuState(A.actor, COMM_SCREEN_STAT)
	return TRUE

/datum/tgui_module/communications/proc/ui_act_setmsg2(datum/act/op/A)
	var/datum/prompt/P = A.answer
	stat_msg2 = reject_bad_text(P?.value, 40)
	setMenuState(A.actor, COMM_SCREEN_STAT)
	return TRUE


// OMG CENTCOMM LETTERHEAD

/datum/tgui_module/communications/proc/ui_act_messagecentcom(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/P = A.answer
	var/input = P?.value
	if(input)
		if(length(input) < COMM_CCMSGLEN_MINIMUM)
			to_chat(user, span_warning("Message '[input]' is too short. [COMM_CCMSGLEN_MINIMUM] character minimum."))
		else
			CentCom_announce(input, user)
			to_chat(user, span_blue("Message transmitted."))
			log_game("[key_name(user)] has made an IA [using_map.boss_short] announcement: [input]")
			COOLDOWN_START(src, centcomm_message_cooldown, 30 SECONDS) // 30 seconds
	setMenuState(user, COMM_SCREEN_MAIN)
	return TRUE


// OMG SYNDICATE ...LETTERHEAD

/datum/tgui_module/communications/proc/ui_act_messagesyndicate(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/P = A.answer
	var/input = P?.value
	if(input)
		if(length(input) < COMM_CCMSGLEN_MINIMUM)
			to_chat(user, span_warning("Message '[input]' is too short. [COMM_CCMSGLEN_MINIMUM] character minimum."))
		else
			Syndicate_announce(input, user)
			to_chat(user, span_blue("Message transmitted."))
			log_game("[key_name(user)] has made an illegal announcement: [input]")
			COOLDOWN_START(src, centcomm_message_cooldown, 30 SECONDS) // 30 seconds
	return TRUE

/// The backup routing is restored: the console's scrambled circuits work again (and it can be emagged again).
/datum/tgui_module/communications/proc/ui_act_restorebackup(datum/act/op/A)
	var/obj/machinery/computer/communications/C = host()
	if(istype(C))
		key_set(C, EMAG_EMAGGED, FALSE)
	setMenuState(A.actor, COMM_SCREEN_MAIN)
	return TRUE

/datum/tgui_module/communications/ntos
	ntos = TRUE

/* Etc global procs */
/proc/enable_prison_shuttle(mob/user)
	for(var/obj/machinery/computer/prison_shuttle/PS in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		PS.allowedtocall = !(PS.allowedtocall)

/proc/call_shuttle_proc(mob/user)
	if ((!( SSticker ) || !SSemergency_shuttle.location()))
		return

	if(!GLOB.universe.OnShuttleCall(user))
		to_chat(user, span_notice("Cannot establish a bluespace connection."))
		return

	if(GLOB.deathsquad.deployed)
		to_chat(user, "[using_map.boss_short] will not allow the shuttle to be called. Consider all contracts terminated.")
		return

	if(emergency_shuttle_deny_shuttle())
		to_chat(user, "The emergency shuttle may not be sent at this time. Please try again later.")
		return

	var/into_round = ELAPSED(SSticker, round_start_time, CLOCK_WORLD)
	if(into_round < SHUTTLE_CALL_GRACE) // a grace period to let the round get going
		to_chat(user, "The emergency shuttle is refueling. Please wait another [round((SHUTTLE_CALL_GRACE - into_round) / (1 MINUTE))] minute\s before trying again.")
		return

	if(SSemergency_shuttle.going_to_centcom())
		to_chat(user, "The emergency shuttle may not be called while returning to [using_map.boss_short].")
		return

	if(SSemergency_shuttle.online())
		to_chat(user, "The emergency shuttle is already on its way.")
		return

	if(ticker_mode().name == "blob")
		to_chat(user, "Under directive 7-10, [station_name()] is quarantined until further notice.")
		return

	SSemergency_shuttle.call_evac()
	log_game("[key_name(user)] has called the shuttle.")
	message_admins("[key_name_admin(user)] has called the shuttle.", 1)
	admin_chat_message(message = "Emergency evac beginning! Called by [key_name(user)]!", color = "#CC2222")

	return

/proc/init_shift_change(mob/user, force = 0)
	if ((!( SSticker ) || !SSemergency_shuttle.location()))
		return

	if(SSemergency_shuttle.going_to_centcom())
		to_chat(user, "The shuttle may not be called while returning to [using_map.boss_short].")
		return

	if(SSemergency_shuttle.online())
		to_chat(user, "The shuttle is already on its way.")
		return

	// if force is 0, some things may stop the shuttle call
	if(!force)
		if(emergency_shuttle_deny_shuttle())
			to_chat(user, "[using_map.boss_short] does not currently have a shuttle available in your sector. Please try again later.")
			return

		if(GLOB.deathsquad.deployed == 1)
			to_chat(user, "[using_map.boss_short] will not allow the shuttle to be called. Consider all contracts terminated.")
			return

		var/into_round = ELAPSED(SSticker, round_start_time, CLOCK_WORLD)
		if(into_round < SHIFT_CHANGE_GRACE) // a grace period to let the round get going
			to_chat(user, "The shuttle is refueling. Please wait another [round((SHIFT_CHANGE_GRACE - into_round) / (1 MINUTE))] minutes before trying again.")
			return

		if(ticker_mode().auto_recall_shuttle)
			//New version pretends to call the shuttle but cause the shuttle to return after a random duration.
			SSemergency_shuttle.auto_recall = TRUE

		if(ticker_mode().name == "blob" || ticker_mode().name == "epidemic")
			to_chat(user, "Under directive 7-10, [station_name()] is quarantined until further notice.")
			return

	SSemergency_shuttle.call_transfer()

	//delay events in case of an autotransfer
	if (isnull(user))
		SSevents.delay_events(EVENT_LEVEL_MODERATE, 15 MINUTES)
		SSevents.delay_events(EVENT_LEVEL_MAJOR, 15 MINUTES)

	log_game("[user? key_name(user) : "Autotransfer"] has called the shuttle.")
	message_admins("[user? key_name_admin(user) : "Autotransfer"] has called the shuttle.", 1)
	admin_chat_message(message = "Autotransfer shuttle dispatched, shift ending soon.", color = "#2277BB")

	return

/proc/cancel_call_proc(mob/user)
	if (!( SSticker ) || !SSemergency_shuttle.can_recall())
		return
	if((ticker_mode().name == "blob")||(ticker_mode().name == "Meteor"))
		return

	if(!SSemergency_shuttle.going_to_centcom()) //check that shuttle isn't already heading to CentCom
		SSemergency_shuttle.recall()
		log_game("[key_name(user)] has recalled the shuttle.")
		message_admins("[key_name_admin(user)] has recalled the shuttle.", 1)
	return

/proc/is_relay_online()
	for(var/obj/machinery/telecomms/relay/M in world)
		if(!M.has_condition())
			return 1
	return 0

#undef COMM_SCREEN_MAIN
#undef COMM_SCREEN_STAT
#undef COMM_SCREEN_MESSAGES

#undef COMM_AUTHENTICATION_NONE
#undef COMM_AUTHENTICATION_MIN
#undef COMM_AUTHENTICATION_MAX

#undef COMM_MSGLEN_MINIMUM
#undef COMM_CCMSGLEN_MINIMUM
#undef SHUTTLE_CALL_GRACE
#undef SHIFT_CHANGE_GRACE
