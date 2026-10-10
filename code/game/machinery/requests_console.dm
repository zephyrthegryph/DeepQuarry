/******************** Requests Console ********************/
/** Originally written by errorage, updated by: Carn, needs more work though. I just added some security fixes */

//Request Console Screens
#define RCS_MAINMENU 0	// Main menu
#define RCS_RQASSIST 1	// Request supplies
#define RCS_RQSUPPLY 2	// Request assistance
#define RCS_SENDINFO 3	// Relay information
#define RCS_SENTPASS 4	// Message sent successfully
#define RCS_SENTFAIL 5	// Message sent unsuccessfully
#define RCS_VIEWMSGS 6	// View messages
#define RCS_MESSAUTH 7	// Authentication before sending
#define RCS_ANNOUNCE 8	// Send announcement

GLOBAL_LIST_EMPTY(req_console_assistance)
GLOBAL_LIST_EMPTY(req_console_supplies)
GLOBAL_LIST_EMPTY(req_console_information)

/obj/machinery/requests_console
	name = "requests console"
	desc = "A console intended to send requests to different departments on the station."
	anchored = TRUE
	icon = 'icons/obj/terminals_vr.dmi'
	icon_state = "req_comp_0"
	layer = ABOVE_WINDOW_LAYER
	circuit = /obj/item/circuitboard/request
	blocks_emissive = NONE
	light_power = 0.25
	light_color = "#00ff00"
	vis_flags = VIS_HIDE // They have an emissive that looks bad in openspace due to their wall-mounted nature
	flags = WALL_ITEM
	var/department = "Unknown" //The list of all departments on the station (Determined from this variable on each unit) Set this to the same thing if you want several consoles in one department
	var/list/message_log //List of all messages
	var/departmentType = 0 		//Bitflag. Zero is reply-only. Map currently uses raw numbers instead of defines.
	var/newmessagepriority = 0
		// 0 = no new message
		// 1 = normal priority
		// 2 = high priority
	var/screen = RCS_VIEWMSGS
	var/silent = 0 // set to 1 for it not to beep all the time
//	var/hackState = 0
		// 0 = not hacked
		// 1 = hacked
	var/announcementConsole = 0
		// 0 = This console cannot be used to send department announcements
		// 1 = This console can send department announcementsf
	var/open = 0 // 1 if open
	var/announceAuth = 0 //Will be set to 1 when you authenticate yourself for announcements
	var/msgVerified = "" //Will contain the name of the person who varified it
	var/msgStamped = "" //If a message is stamped, this will contain the stamp name
	var/message = "";
	var/recipient = ""; //the department which will be receiving the message
	var/priority = -1 ; //Priority of the message being sent
	light_range = 0
	var/datum/announcement/announcement

CAPABILITIES(/obj/machinery/requests_console)
	op("toggleSilent", ui_act("toggleSilent"), then(PROC_REF(ui_act_togglesilent)))
	owns_one(nameof(announcement), /datum/announcement)
	interface("RequestConsole")
	op("write", ui_act("write", arg("priority", num()), arg("write", schema_text(4096))),
		asks(/datum/prompt/text, fields = list("title" = "Awaiting Input", "question" = "Write your message:", "default" = "", "timeout" = 0), when = PROC_REF(write_target_ok)),
		then(PROC_REF(ui_act_write)))
	op("writeAnnouncement", ui_act("writeAnnouncement"),
		asks(/datum/prompt/text, fields = list("title" = "Awaiting Input", "question" = "Write your message:", "default" = "", "timeout" = 0)),
		then(PROC_REF(ui_act_writeannouncement)))
	op("sendAnnouncement", ui_act("sendAnnouncement"), then(PROC_REF(ui_act_sendannouncement)))
	op("department", ui_act("department", arg("department", schema_text(4096))), then(PROC_REF(ui_act_department)))
	op("print", ui_act("print", arg("print", num())), then(PROC_REF(ui_act_print)))
	op("setScreen", ui_act("setScreen", arg("setScreen", num())), then(PROC_REF(ui_act_setscreen)))
	extend(TAG_UI, then(PROC_REF(ui_fingerprint), early = TRUE))
	op("requests_console_id", item(/obj/item/card/id), priority(OP_PRIORITY_DEFAULT - 1), label("Swipe ID"), then(PROC_REF(interaction_id)))
	op("requests_console_stamp", item(/obj/item/stamp), priority(OP_PRIORITY_DEFAULT - 1), label("Stamp"), then(PROC_REF(interaction_stamp)))
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), label("Set department"),
		asks(/datum/prompt/text, fields = list("title" = "Multitool-Request Console Interface", "question" = "What Department ID would you like to give this request console?", "default" = nameof(department), "timeout" = 0)),
		then(PROC_REF(department_entered)))

/// Whoever presses a button leaves their prints on the console.
/obj/machinery/requests_console/proc/ui_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

REGISTRY_MEMBERSHIP(/obj/machinery/requests_console, REGISTRY_ALARM_CONSOLES)

/obj/machinery/requests_console/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(announcement), new /datum/announcement)
	announcement.title = "[department] announcement"
	announcement.newscast = 1

	name = "[department] requests console"
	if(departmentType & RC_ASSIST)
		GLOB.req_console_assistance |= department
	if(departmentType & RC_SUPPLY)
		GLOB.req_console_supplies |= department
	if(departmentType & RC_INFO)
		GLOB.req_console_information |= department

	update_icon()

// the last console of a department takes it off the request lists.
/obj/machinery/requests_console/lifecycle_dematerialize()
	var/lastDeptRC = 1
	for (var/obj/machinery/requests_console/Console in REGISTRY_MEMBERS(REGISTRY_ALARM_CONSOLES))
		if(Console != src && Console.department == department)
			lastDeptRC = 0
			break
	if(lastDeptRC)
		if(departmentType & RC_ASSIST)
			GLOB.req_console_assistance -= department
		if(departmentType & RC_SUPPLY)
			GLOB.req_console_supplies -= department
		if(departmentType & RC_INFO)
			GLOB.req_console_information -= department
	..()

DECLARE_APPEARANCE_PROC(/obj/machinery/requests_console, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/requests_console/appearance_overlays()
	. = list()

	if(power_lost())
		set_light(0)
		set_light_on(FALSE)
		icon_state = "req_comp_off"
	else
		icon_state = "req_comp_[newmessagepriority]"
		. += mutable_appearance(icon, "req_comp_ov[newmessagepriority]")
		. += emissive_appearance(icon, "req_comp_ov[newmessagepriority]")
		set_light(2)
		set_light_on(TRUE)

/obj/machinery/requests_console/ui_title(mob/user)
	return "[department] Request Console"

/obj/machinery/requests_console/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["message_log"] = (message_log || list())

	data["assist_dept"] = GLOB.req_console_assistance
	data["supply_dept"] = GLOB.req_console_supplies
	data["info_dept"]   = GLOB.req_console_information

	data["department"] = department
	data["screen"] = screen
	data["newmessagepriority"] = newmessagepriority
	data["silent"] = silent
	data["announcementConsole"] = announcementConsole
	data["message"] = message
	data["recipient"] = recipient
	data["priority"] = priority
	data["msgStamped"] = msgStamped
	data["msgVerified"] = msgVerified
	data["announceAuth"] = announceAuth
	return data

/// The write button's question opens only for a department name that reads as text.
/obj/machinery/requests_console/proc/write_target_ok(datum/act/op/A)
	return !!reject_bad_text(A.args?["write"])

/// The write button: the message to that department, at the window's priority (an empty one starts over).
/obj/machinery/requests_console/proc/ui_act_write(datum/act/op/A, raw_priority, raw_write)
	if(!reject_bad_text(raw_write))
		return FALSE
	recipient = raw_write //write contains the string of the receiving department's name
	var/new_message = A.answer?.value
	SStgui.update_uis(src)
	if(new_message)
		message = new_message
		screen = RCS_MESSAUTH
		switch(raw_priority)
			if(1)
				priority = 1
			if(2)
				priority = 2
			else
				priority = 0
	else
		reset_message(1)
	. = TRUE

/// The announcement button: the announcement's text (an empty one starts over).
/obj/machinery/requests_console/proc/ui_act_writeannouncement(datum/act/op/A)
	var/new_message = A.answer?.value
	SStgui.update_uis(src)
	if(new_message)
		message = new_message
	else
		reset_message(1)
	. = TRUE

/obj/machinery/requests_console/proc/ui_act_sendannouncement(datum/act/op/A)
	if(!announcementConsole)
		return FALSE
	announcement.Announce(message, msg_sanitized = 1)
	reset_message(1)
	. = TRUE

/obj/machinery/requests_console/proc/ui_act_department(datum/act/op/A, raw_department)
	if(!message)
		return FALSE
	var/log_msg = message
	var/pass = 0
	screen = RCS_SENTFAIL
	for(var/obj/machinery/message_server/MS in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(!MS.active)
			continue
		MS.send_rc_message(ckey(raw_department), department, log_msg, msgStamped, msgVerified, priority)
		pass = 1
	if(pass)
		screen = RCS_SENTPASS
		LAZYADD(message_log, list(list("Message sent to [recipient]", "[message]")))
	else
		audible_message(text("[icon2html(src,viewers(src))] *The Requests Console beeps: 'NOTICE: No server detected!'"),,4)
	. = TRUE

//Handle printing

/obj/machinery/requests_console/proc/ui_act_print(datum/act/op/A, print)
	var/print_index = print
	if(!print_index || print_index < 1 || print_index > length(message_log))
		return
	var/msg = LAZYACCESS(message_log, print_index)
	if(msg)
		msg = span_bold("[msg[1]]:") + "<br>[msg[2]]"
		msg = replacetext(msg, "<BR>", "\n")
		msg = strip_html_properly(msg)
		var/obj/item/paper/R = new(src.loc)
		R.name = "[department] Message"
		R.set_info("<H3>[department] Requests Console</H3><div>[msg]</div>")
		. = TRUE

//Handle screen switching

/obj/machinery/requests_console/proc/ui_act_setscreen(datum/act/op/A, setScreen)
	var/tempScreen = setScreen
	if(tempScreen == RCS_ANNOUNCE && !announcementConsole)
		return
	if(tempScreen == RCS_VIEWMSGS)
		for (var/obj/machinery/requests_console/Console in REGISTRY_MEMBERS(REGISTRY_ALARM_CONSOLES))
			if(Console.department == department)
				Console.newmessagepriority = 0
				Console.update_icon()
	if(tempScreen == RCS_MAINMENU)
		reset_message()
	screen = tempScreen
	. = TRUE

//Handle silencing the console

/obj/machinery/requests_console/proc/ui_act_togglesilent(datum/act/op/A)
	add_fingerprint(A.actor)
	silent = !silent
	return OP_OK

			//err... hacking code, which has no reason for existing... but anyway... it was once supposed to unlock priority 3 messaging on that console (EXTREME priority...), but the code for that was removed.

/obj/machinery/requests_console/proc/interaction_id(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(!operable())
		return OP_OK
	if(screen == RCS_MESSAUTH)
		var/obj/item/card/id/T = held
		msgVerified = span_green(span_bold("Verified by [T.registered_name] ([T.assignment])"))
		SStgui.update_uis(src)
	if(screen == RCS_ANNOUNCE)
		var/obj/item/card/id/ID = held
		if(ACCESS_RC_ANNOUNCE in ID.GetAccess())
			announceAuth = 1
			announcement.announcer = ID.assignment ? "[ID.assignment] [ID.registered_name]" : ID.registered_name
		else
			reset_message()
			to_chat(user, span_warning("You are not authorized to send announcements."))
		SStgui.update_uis(src)
	return OP_OK

/obj/machinery/requests_console/proc/interaction_stamp(datum/act/op/A)
	var/obj/item/held = A.held
	if(!operable())
		return OP_OK
	if(screen == RCS_MESSAUTH)
		var/obj/item/stamp/T = held
		msgStamped = span_blue(span_bold("Stamped with the [T.name]"))
		SStgui.update_uis(src)
	return OP_OK

/// The multitool's answer: the console's department, and the lists it joins.
/obj/machinery/requests_console/proc/department_entered(datum/act/op/A)
	var/input = A.answer?.value
	if(!input)
		to_chat(A.actor, "No input found. Please hang up and try your call again.")
		return OP_OK
	department = input
	announcement.title = "[department] announcement"
	announcement.newscast = TRUE
	name = "[department] Requests Console"
	if(departmentType & RC_ASSIST)
		GLOB.req_console_assistance |= department
	if(departmentType & RC_SUPPLY)
		GLOB.req_console_supplies |= department
	if(departmentType & RC_INFO)
		GLOB.req_console_information |= department
	return OP_OK

/obj/machinery/requests_console/proc/reset_message(mainmenu = 0)
	message = ""
	recipient = ""
	priority = 0
	msgVerified = ""
	msgStamped = ""
	announceAuth = 0
	announcement.announcer = ""
	if(mainmenu)
		screen = RCS_MAINMENU

#undef RCS_MAINMENU
#undef RCS_RQASSIST
#undef RCS_RQSUPPLY
#undef RCS_SENDINFO
#undef RCS_SENTPASS
#undef RCS_SENTFAIL
#undef RCS_VIEWMSGS
#undef RCS_MESSAUTH
#undef RCS_ANNOUNCE

// Request Console Presets!  Make mapping 400% easier!
// By using these presets we can rename the departments easily.

//Request Console Department Types
// # define RC_ASSIST 1		//Request Assistance
// # define RC_SUPPLY 2		//Request Supplies
// # define RC_INFO   4		//Relay Info

/obj/machinery/requests_console/preset
	name = ""
	department = ""
	departmentType = ""
	announcementConsole = TRUE

// Departments
/obj/machinery/requests_console/preset/cargo
	name = "Cargo RC"
	department = "Cargo Bay"
	departmentType = RC_SUPPLY

/obj/machinery/requests_console/preset/security
	name = "Security RC"
	department = "Security"
	departmentType = RC_ASSIST

/obj/machinery/requests_console/preset/engineering
	name = "Engineering RC"
	department = "Engineering"
	departmentType = RC_ASSIST|RC_SUPPLY

/obj/machinery/requests_console/preset/atmos
	name = "Atmospherics RC"
	department = "Atmospherics"
	departmentType = RC_ASSIST|RC_SUPPLY

/obj/machinery/requests_console/preset/medical
	name = "Medical RC"
	department = "Medical Department"
	departmentType = RC_ASSIST|RC_SUPPLY

/obj/machinery/requests_console/preset/research
	name = "Research RC"
	department = "Research Department"
	departmentType = RC_ASSIST|RC_SUPPLY

/obj/machinery/requests_console/preset/janitor
	name = JOB_JANITOR + " RC"
	department = JOB_JANITOR + "ial"
	departmentType = RC_ASSIST

/obj/machinery/requests_console/preset/bridge
	name = "Bridge RC"
	department = "Bridge"
	departmentType = RC_ASSIST|RC_INFO
	announcementConsole = 1

// Heads

/obj/machinery/requests_console/preset/ce
	name = JOB_CHIEF_ENGINEER + " RC"
	department = JOB_CHIEF_ENGINEER + "'s Desk"
	departmentType = RC_ASSIST|RC_INFO
	announcementConsole = 1

/obj/machinery/requests_console/preset/cmo
	name = JOB_CHIEF_MEDICAL_OFFICER + " RC"
	department = JOB_CHIEF_MEDICAL_OFFICER + "'s Desk"
	departmentType = RC_ASSIST|RC_INFO
	announcementConsole = 1

/obj/machinery/requests_console/preset/hos
	name = JOB_HEAD_OF_SECURITY + " RC"
	department = JOB_HEAD_OF_SECURITY  + "'s Desk"
	departmentType = RC_ASSIST|RC_INFO
	announcementConsole = 1

/obj/machinery/requests_console/preset/rd
	name = JOB_RESEARCH_DIRECTOR + " RC"
	department = JOB_RESEARCH_DIRECTOR +"'s Desk"
	departmentType = RC_ASSIST|RC_INFO
	announcementConsole = 1

/obj/machinery/requests_console/preset/captain
	name = "Captain RC"
	department = "Captain's Desk"
	departmentType = RC_ASSIST|RC_INFO
	announcementConsole = 1

/obj/machinery/requests_console/preset/ai
	name = JOB_AI + " RC"
	department = JOB_AI
	departmentType = RC_ASSIST|RC_INFO

/obj/machinery/requests_console/preset/hop //yw edit
	name = "Head of personnel RC"
	department = "Head of Personnel's Desk"
	departmentType = RC_ASSIST|RC_INFO
	announcementConsole = 1
