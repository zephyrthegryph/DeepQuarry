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

/obj/machinery/computer/telecomms/server/ui_data(datum/act/eval/A)
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

	data["universal_translate"] = universal_translate
	data["network"] = network
	data["temp"] = temp
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

CAPABILITIES(/obj/machinery/computer/telecomms/server)
	interface("TelecommsLogBrowser")
	op("view", ui_act("view", arg("id", schema_text(4096))), then(PROC_REF(ui_act_view)))
	op("mainmenu", ui_act("mainmenu"), then(PROC_REF(ui_act_mainmenu)))
	op("release", ui_act("release"), then(PROC_REF(ui_act_release)))
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("delete", ui_act("delete", arg("id", num())), then(PROC_REF(ui_act_delete)))
	op("network", ui_act("network"), then(PROC_REF(ui_act_network)))
	op("cleartemp", ui_act("cleartemp"), then(PROC_REF(ui_act_cleartemp)))
	extend(TAG_UI, then(PROC_REF(ui_fingerprint), early = TRUE))
	emag(then(PROC_REF(on_emag)))

/obj/machinery/computer/telecomms/server/proc/ui_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/obj/machinery/computer/telecomms/server/proc/ui_act_view(datum/act/op/A, raw_id)
	for(var/obj/machinery/telecomms/T in servers)
		if(T.id == raw_id)
			rel_set(src, nameof(/obj/machinery/computer/telecomms/server::SelectedServer), T)
			break
	. = TRUE

/obj/machinery/computer/telecomms/server/proc/ui_act_mainmenu(datum/act/op/A)
	add_fingerprint(A.actor)
	rel_clear(src, nameof(/obj/machinery/computer/telecomms/server::SelectedServer))
	return OP_OK

/obj/machinery/computer/telecomms/server/proc/ui_act_release(datum/act/op/A)
	add_fingerprint(A.actor)
	rel_clear(src, nameof(/obj/machinery/computer/telecomms/server::servers))
	rel_clear(src, nameof(/obj/machinery/computer/telecomms/server::SelectedServer))
	return OP_OK

/obj/machinery/computer/telecomms/server/proc/ui_act_scan(datum/act/op/A)
	if(length(servers) > 0)
		set_temp("FAILED: CANNOT PROBE WHEN BUFFER FULL", "bad")
		return TRUE

	for(var/obj/machinery/telecomms/server/T in range(25, src))
		if(T.network == network)
			rel_add(src, nameof(/obj/machinery/computer/telecomms/server::servers), T)

	if(!length(servers))
		set_temp("FAILED: UNABLE TO LOCATE SERVERS IN \[[network]\]", "bad")
	else
		set_temp("[length(servers)] SERVERS PROBED & BUFFERED", "good")
	. = TRUE

/obj/machinery/computer/telecomms/server/proc/ui_act_delete(datum/act/op/A, id)
	var/mob/user = A.actor
	if(!allowed(user) && !emagged)
		to_chat(user, span_warning("ACCESS DENIED."))
		return

	if(SelectedServer())
		var/idx = id
		if(!idx || idx < 1 || idx > length(SelectedServer().log_entries))
			return
		var/datum/comm_log_entry/D = LAZYACCESS(SelectedServer().log_entries, idx)
		set_temp("DELETED ENTRY: [D.name]", "bad")
		own_remove(SelectedServer(), nameof(/obj/machinery/telecomms/server::log_entries), D)
	else
		set_temp("FAILED: NO SELECTED MACHINE", "bad")
	. = TRUE

/obj/machinery/computer/telecomms/server/proc/ui_act_network(datum/act/op/A)
	open_request(src, /datum/prompt/text, PROC_REF(network_entered), answerer = A.actor, title = "Comm Monitor", question = "Which network do you want to view?", default = network, max_len = 15, ask_flags = ASK_CAPABLE, timeout = 0)
	. = TRUE

/obj/machinery/computer/telecomms/server/proc/ui_act_cleartemp(datum/act/op/A)
	add_fingerprint(A.actor)
	temp = null
	return OP_OK

/obj/machinery/computer/telecomms/server/proc/network_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/newnet = A.answer.answer_value
	SStgui.update_uis(src)
	if(newnet && ((user in range(1, src)) || issilicon(user)))
		if(length(newnet) > 15)
			set_temp("FAILED: NETWORK TAG STRING TOO LENGTHY", "bad")
			return TRUE
		network = newnet
		rel_clear(src, nameof(servers))
		set_temp("NEW NETWORK TAG SET IN ADDRESS \[[network]\]", "good")

	. = TRUE

/obj/machinery/computer/telecomms/server/proc/on_emag(datum/act/op/A)
	play_sfx(src, SFX_EFFECTS_SPARKS4)
	set_emagged(1)
	to_chat(A.actor, span_notice("You you disable the security protocols"))
	return OP_OK

/obj/machinery/computer/telecomms/server/proc/set_temp(text, color = "average")
	temp = list("color" = color, "text" = text)

/// SelectedServer (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/telecomms/server/proc/SelectedServer() as /obj/machinery/telecomms/server
	return SelectedServer
