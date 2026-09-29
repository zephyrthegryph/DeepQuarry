/client/var/datum/tgui_shock/tgui_shocker

/client/verb/configure_shocker()
	set name = "Configure MultiShock Integration"
	set category = "OOC.Game Settings"

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
	var/tmp/client_handle
	/// The modal window
	var/datum/tgui_window/window

	var/port = 8765
	var/enabled_flags = 0
	var/intensity = 15
	var/duration = 1

	var/connected = FALSE
	var/selected_device = -1
	var/list/available_devices

//////////////////////////////////////////
// SHOCK.JS UI                          //
//////////////////////////////////////////
/datum/tgui_shock/New(client/client, id)
	src.client_handle = om_handle(client)
	window = new(client, id)
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
DECLARE_UI_STATE(/datum/tgui_shock, GLOB.tgui_always_state)

DECLARE_UI(/datum/tgui_shock, "ShockConfigurator", UI_TITLE("Shock Configurator"))

UI_DATA(/datum/tgui_shock, "port:num", "connected:num", "intensity:num", "duration:num", "selectedDevice=selected_device:num", "availableDevices=available_devices:list", "enabledFlags=enabled_flags:num")

UI_ACT(/datum/tgui_shock, "connect", ui_act_connect)
UI_ACT_PROC(/datum/tgui_shock, ui_act_connect)
	if(connected)
		estop()
	else
		// TODO: preferences
		connect()
	. = TRUE

UI_ACT(/datum/tgui_shock, "request_devices", ui_act_request_devices)
UI_ACT_PROC(/datum/tgui_shock, ui_act_request_devices)
	request_devices()
	. = TRUE

UI_ACT(/datum/tgui_shock, "estop", ui_act_estop)
UI_ACT_PROC(/datum/tgui_shock, ui_act_estop)
	estop()
	. = TRUE

UI_ACT(/datum/tgui_shock, "setSelectedDevice", ui_act_setselecteddevice, UI_ARG_NUM("device"))
UI_ACT_PROC(/datum/tgui_shock, ui_act_setselecteddevice)
	selected_device = params["device"]
	. = TRUE

UI_ACT(/datum/tgui_shock, "test", ui_act_test)
UI_ACT_PROC(/datum/tgui_shock, ui_act_test)
	shock(SHOCKFLAG_TEST)
	. = TRUE

UI_ACT(/datum/tgui_shock, "set_flag", ui_act_set_flag, UI_ARG_NUM("flag"))
UI_ACT_PROC(/datum/tgui_shock, ui_act_set_flag)
	enabled_flags ^= params["flag"]
	. = TRUE

UI_ACT(/datum/tgui_shock, "port", ui_act_port, UI_ARG_NUM("port"))
UI_ACT_PROC(/datum/tgui_shock, ui_act_port)
	port = params["port"]
	. = TRUE

UI_ACT(/datum/tgui_shock, "intensity", ui_act_intensity, UI_ARG_NUM("intensity"))
UI_ACT_PROC(/datum/tgui_shock, ui_act_intensity)
	intensity = params["intensity"]
	. = TRUE

UI_ACT(/datum/tgui_shock, "duration", ui_act_duration, UI_ARG_NUM("duration"))
UI_ACT_PROC(/datum/tgui_shock, ui_act_duration)
	duration = params["duration"]
	. = TRUE

DECLARE_REF(/client, "tgui_shocker", OWNED, null)

DECLARE_REF(/datum/tgui_shock, "window", OWNED, null)

/// LC-refs: the client this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/tgui_shock/proc/client() as /client
	return om_resolve(client_handle)
