//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/obj/machinery/computer/telecomms
	icon_keyboard = "tech_key"

/obj/machinery/computer/telecomms/server
	name = "Telecommunications Server Monitor"
	desc = "View communication logs here. Translation not guaranteed."
	icon_screen = "comm_logs"

	var/list/servers	// the servers located by the computer
	var/obj/machinery/telecomms/server/SelectedServer
	circuit = /obj/item/circuitboard/comm_server

	var/network = "NULL"		// the network to probe
	var/list/temp = null				// temporary feedback messages

	var/universal_translate = 0 // set to 1 if it can translate nonhuman speech

	req_access = list(ACCESS_TCOMSAT)

UI_DATA_REPLACE(/obj/machinery/computer/telecomms/server, "universal_translate:num", "network", "temp:text", "merge:ui_data_obj_machinery_computer_telecomms_server{servers:list,selectedServer:list}")

/// The computed part of /obj/machinery/computer/telecomms/server's window data (declared on its UI_DATA row).
/obj/machinery/computer/telecomms/server/proc/ui_data_obj_machinery_computer_telecomms_server(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()


	var/list/serverData = list()
	for(var/obj/machinery/telecomms/T in servers)
		serverData.Add(list(list(
			"id" = T.id,
			"name" = T.name,
		)))
	data["servers"] = serverData

	data["selectedServer"] = null
	if(SelectedServer())
		data["selectedServer"] = list(
			"id" = SelectedServer().id,
			"totalTraffic" = SelectedServer().totaltraffic,
		)

		var/list/logs = list()
		var/i = 0
		for(var/c in SelectedServer().log_entries)
			i++
			var/datum/comm_log_entry/C = c

			// This is necessary to prevent leaking information to the clientside
			var/static/list/acceptable_params = list("uspeech", "intelligible", "message", "name", "race", "job", "timecode")
			var/list/parameters = list()
			for(var/log_param in acceptable_params)
				parameters["[log_param]"] = C.parameters["[log_param]"]

			logs.Add(list(list(
				"name" = C.name,
				"input_type" = C.input_type,
				"id" = i,
				"parameters" = parameters,
			)))

		data["selectedServer"]["logs"] = logs

	return data

/obj/machinery/computer/telecomms/server/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/telecomms_server_open_ui,
	)
	..()

/// Old attack_hand: never called ..().
/datum/interaction/machine_hand/ungated/telecomms_server_open_ui
	id = "telecomms_server_open_ui"
	name = "Use"
	effect = /obj/machinery/computer/telecomms/server/proc/interaction_open_ui_impl

/obj/machinery/computer/telecomms/server/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	if(!operable())
		return TRUE
	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/machinery/computer/telecomms/server, "TelecommsLogBrowser")

/obj/machinery/computer/telecomms/server/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/telecomms/server, "view", ui_act_view, UI_ARG_TEXT("id"))
UI_ACT_PROC(/obj/machinery/computer/telecomms/server, ui_act_view)
	for(var/obj/machinery/telecomms/T in servers)
		if(T.id == params["id"])
			rel_set(src, "SelectedServer", T)
			break
	. = TRUE

UI_ACT(/obj/machinery/computer/telecomms/server, "mainmenu", ui_act_mainmenu)
UI_ACT_PROC(/obj/machinery/computer/telecomms/server, ui_act_mainmenu)
	rel_clear(src, "SelectedServer")
	. = TRUE

UI_ACT(/obj/machinery/computer/telecomms/server, "release", ui_act_release)
UI_ACT_PROC(/obj/machinery/computer/telecomms/server, ui_act_release)
	rel_clear(src, "servers")
	rel_clear(src, "SelectedServer")
	. = TRUE

UI_ACT(/obj/machinery/computer/telecomms/server, "scan", ui_act_scan)
UI_ACT_PROC(/obj/machinery/computer/telecomms/server, ui_act_scan)
	if(length(servers) > 0)
		set_temp("FAILED: CANNOT PROBE WHEN BUFFER FULL", "bad")
		return TRUE

	for(var/obj/machinery/telecomms/server/T in range(25, src))
		if(T.network == network)
			rel_add(src, "servers", T)

	if(!length(servers))
		set_temp("FAILED: UNABLE TO LOCATE SERVERS IN \[[network]\]", "bad")
	else
		set_temp("[length(servers)] SERVERS PROBED & BUFFERED", "good")
	. = TRUE

UI_ACT(/obj/machinery/computer/telecomms/server, "delete", ui_act_delete, UI_ARG_NUM("id"))
UI_ACT_PROC(/obj/machinery/computer/telecomms/server, ui_act_delete)
	if(!allowed(ui.user) && !emagged)
		to_chat(ui.user, span_warning("ACCESS DENIED."))
		return

	if(SelectedServer())
		var/idx = params["id"]
		if(!idx || idx < 1 || idx > length(SelectedServer().log_entries))
			return
		var/datum/comm_log_entry/D = LAZYACCESS(SelectedServer().log_entries, idx)
		set_temp("DELETED ENTRY: [D.name]", "bad")
		own_remove(SelectedServer(), "log_entries", D)
	else
		set_temp("FAILED: NO SELECTED MACHINE", "bad")
	. = TRUE

UI_ACT(/obj/machinery/computer/telecomms/server, "network", ui_act_network)
UI_ACT_PROC(/obj/machinery/computer/telecomms/server, ui_act_network)
	om_ask(ui.user, /datum/om/prompt/text, PROC_REF(network_entered), message = "Which network do you want to view?", title = "Comm Monitor", default = network, max_length = 15, requires = PROMPT_USABLE)
	. = TRUE

UI_ACT(/obj/machinery/computer/telecomms/server, "cleartemp", ui_act_cleartemp)
UI_ACT_PROC(/obj/machinery/computer/telecomms/server, ui_act_cleartemp)
	temp = null
	. = TRUE

/obj/machinery/computer/telecomms/server/proc/network_entered(datum/om/prompt/text/ask)
	var/mob/user = ask.answerer
	var/newnet = ask.text
	SStgui.update_uis(src)
	if(newnet && ((user in range(1, src)) || issilicon(user)))
		if(length(newnet) > 15)
			set_temp("FAILED: NETWORK TAG STRING TOO LENGTHY", "bad")
			return TRUE
		network = newnet
		rel_clear(src, "servers")
		set_temp("NEW NETWORK TAG SET IN ADDRESS \[[network]\]", "good")

	. = TRUE

DECLARE_EMAG(/obj/machinery/computer/telecomms/server, PROC_REF(on_emag), null, null)
/obj/machinery/computer/telecomms/server/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	play_sfx(src, SFX_EFFECTS_SPARKS4)
	set_emagged(1)
	to_chat(user, span_notice("You you disable the security protocols"))
	return 1

/obj/machinery/computer/telecomms/server/proc/set_temp(text, color = "average")
	temp = list("color" = color, "text" = text)

/// SelectedServer (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/telecomms/server/proc/SelectedServer() as /obj/machinery/telecomms/server
	return SelectedServer
