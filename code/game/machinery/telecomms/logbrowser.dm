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

/obj/machinery/computer/telecomms/server/tgui_data(mob/user)
	var/list/data = list()

	data["universal_translate"] = universal_translate
	data["network"] = network
	data["temp"] = temp

	var/list/serverData = list()
	for(var/obj/machinery/telecomms/T in servers)
		serverData.Add(list(list(
			"id" = T.id,
			"name" = T.name,
		)))
	data["servers"] = serverData

	data["selectedServer"] = null
	if(SelectedServer)
		data["selectedServer"] = list(
			"id" = SelectedServer.id,
			"totalTraffic" = SelectedServer.totaltraffic,
		)

		var/list/logs = list()
		var/i = 0
		for(var/c in SelectedServer.log_entries)
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
	if(stat & (BROKEN|NOPOWER))
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/computer/telecomms/server/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "TelecommsLogBrowser", name)
		ui.open()

/obj/machinery/computer/telecomms/server/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	add_fingerprint(ui.user)

	switch(action)
		if("view")
			for(var/obj/machinery/telecomms/T in servers)
				if(T.id == params["id"])
					SelectedServer = T
					break
			. = TRUE

		if("mainmenu")
			SelectedServer = null
			. = TRUE

		if("release")
			servers = list()
			SelectedServer = null
			. = TRUE

		if("scan")
			if(length(servers) > 0)
				set_temp("FAILED: CANNOT PROBE WHEN BUFFER FULL", "bad")
				return TRUE

			for(var/obj/machinery/telecomms/server/T in range(25, src))
				if(T.network == network)
					LAZYADD(servers, T)

			if(!length(servers))
				set_temp("FAILED: UNABLE TO LOCATE SERVERS IN \[[network]\]", "bad")
			else
				set_temp("[length(servers)] SERVERS PROBED & BUFFERED", "good")
			. = TRUE

		if("delete")
			if(!allowed(ui.user) && !emagged)
				to_chat(ui.user, span_warning("ACCESS DENIED."))
				return

			if(SelectedServer)
				var/idx = text2num(params["id"])
				if(!idx || idx < 1 || idx > length(SelectedServer.log_entries))
					return
				var/datum/comm_log_entry/D = LAZYACCESS(SelectedServer.log_entries, idx)
				set_temp("DELETED ENTRY: [D.name]", "bad")
				LAZYREMOVE(SelectedServer.log_entries, D)
				qdel(D)
			else
				set_temp("FAILED: NO SELECTED MACHINE", "bad")
			. = TRUE

		if("network")
			var/newnet = tgui_input_text(ui.user, "Which network do you want to view?", "Comm Monitor", network, 15)

			if(newnet && ((ui.user in range(1, src)) || issilicon(ui.user)))
				if(length(newnet) > 15)
					set_temp("FAILED: NETWORK TAG STRING TOO LENGTHY", "bad")
					return TRUE
				network = newnet
				servers = list()
				set_temp("NEW NETWORK TAG SET IN ADDRESS \[[network]\]", "good")

			. = TRUE

		if("cleartemp")
			temp = null
			. = TRUE

/obj/machinery/computer/telecomms/server/emag_act(remaining_charges, mob/user)
	if(!emagged)
		playsound(src, 'sound/effects/sparks4.ogg', 75, 1)
		emagged = 1
		to_chat(user, span_notice("You you disable the security protocols"))
		return 1

/obj/machinery/computer/telecomms/server/proc/set_temp(text, color = "average")
	temp = list("color" = color, "text" = text)
