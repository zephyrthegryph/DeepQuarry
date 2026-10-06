/client/var/datum/tgui_shock/tgui_shocker

/client/verb/configure_shocker()
	set name = "Configure MultiShock Integration"
	set category = VERB_CAT_OOC_GAME_SETTINGS

	if(tgui_shocker)
		tgui_shocker.tgui_interact(mob)

/mob/proc/attempt_multishock(flag)
	client?.attempt_multishock(flag)

/client/proc/attempt_multishock(flag)
	tgui_shocker?.shock(flag)

// NOTE: This datum controls TWO UIs, `window` is hidden and provides all of the WebSocket shit, `tgui_interact` is a
// normal configuration UI!
/datum/tgui_shock
	/// The user who opened the window
	var/tmp/client/client
	/// The modal window
	var/datum/tgui_window/window

	var/port = 8765
	var/enabled_flags = 0
	var/intensity = 15
	var/duration = 1

	var/connected = FALSE
	var/selected_device = -1
	var/list/available_devices

CAPABILITIES(/datum/tgui_shock)
	owns_one(nameof(window), /datum/tgui_window)
	interface("ShockConfigurator", title = "Shock Configurator", state = nameof(GLOB.tgui_always_state))
	op("connect", ui_act("connect"), then(PROC_REF(ui_act_connect)))
	op("request_devices", ui_act("request_devices"), then(PROC_REF(ui_act_request_devices)))
	op("estop", ui_act("estop"), then(PROC_REF(ui_act_estop)))
	op("setSelectedDevice", ui_act("setSelectedDevice", arg("device", num())), then(PROC_REF(ui_act_setselecteddevice)))
	op("test", ui_act("test"), then(PROC_REF(ui_act_test)))
	op("set_flag", ui_act("set_flag", arg("flag", num())), then(PROC_REF(ui_act_set_flag)))
	op("port", ui_act("port", arg("port", num())), then(PROC_REF(ui_act_port)))
	op("intensity", ui_act("intensity", arg("intensity", num())), then(PROC_REF(ui_act_intensity)))
	op("duration", ui_act("duration", arg("duration", num())), then(PROC_REF(ui_act_duration)))

//////////////////////////////////////////
// SHOCK.JS UI                          //
//////////////////////////////////////////
/datum/tgui_shock/New(client/client, id)
	rel_set(src, nameof(client), client)
	rel_set(src, nameof(window), new /datum/tgui_window(client, id))
	window.subscribe(src, PROC_REF(on_message))
	window.is_browser = TRUE

/datum/tgui_shock/proc/initialize()
	set waitfor = FALSE // ALLOW(scheduler): tgui window init can wait on asset generation
	window.initialize(
		inline_js = file2text('html/shock.js')
	)

/datum/tgui_shock/proc/connect()
	window.send_message("connect", list(
		"port" = port,
	))

/datum/tgui_shock/proc/request_devices()
	if(!connected)
		return
	window.send_message("enumerateShockers")

/datum/tgui_shock/proc/shock(flag)
	if(!connected || !selected_device)
		return

	if(flag != SHOCKFLAG_TEST)
		if(!(enabled_flags & flag))
			return

	window.send_message("shock", list(
		"intensity" = intensity,
		"duration" = duration,
		"shocker_ids" = list(
			selected_device
		),
		"warning" = FALSE,
	))

/datum/tgui_shock/proc/estop()
	window.send_message("estop")

/datum/tgui_shock/proc/on_message(type, payload, href_list)
	if(type == "connected")
		connected = TRUE
	else if(type == "disconnected")
		connected = FALSE
	else if(type == "error")
		connected = FALSE
		log_runtime("WebSocket Error [json_encode(payload)]")
	else if(type == "incomingMessage")
		if(payload["lastCall"] == "get_devices")
			available_devices = json_decode(payload["data"])

//////////////////////////////////////////
// TGUI                                 //
//////////////////////////////////////////

/datum/tgui_shock/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["port"] = port
	data["connected"] = connected
	data["intensity"] = intensity
	data["duration"] = duration
	data["selectedDevice"] = selected_device
	data["availableDevices"] = available_devices
	data["enabledFlags"] = enabled_flags
	return data

/datum/tgui_shock/proc/ui_act_connect(datum/act/op/A)
	if(connected)
		estop()
	else
		// TODO: preferences
		connect()
	. = TRUE

/datum/tgui_shock/proc/ui_act_request_devices(datum/act/op/A)
	request_devices()
	. = TRUE

/datum/tgui_shock/proc/ui_act_estop(datum/act/op/A)
	estop()
	. = TRUE

/datum/tgui_shock/proc/ui_act_setselecteddevice(datum/act/op/A, device)
	selected_device = device
	. = TRUE

/datum/tgui_shock/proc/ui_act_test(datum/act/op/A)
	shock(SHOCKFLAG_TEST)
	. = TRUE

/datum/tgui_shock/proc/ui_act_set_flag(datum/act/op/A, flag)
	enabled_flags ^= flag
	. = TRUE

/datum/tgui_shock/proc/ui_act_port(datum/act/op/A, port_arg)
	port = port_arg
	. = TRUE

/datum/tgui_shock/proc/ui_act_intensity(datum/act/op/A, intensity_arg)
	intensity = intensity_arg
	. = TRUE

/datum/tgui_shock/proc/ui_act_duration(datum/act/op/A, duration_arg)
	duration = duration_arg
	. = TRUE



/// The client this refers to (a relation view: null once that is deleted).
/datum/tgui_shock/proc/client() as /client
	return client
