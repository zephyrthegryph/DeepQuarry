//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/obj/machinery/computer/telecomms/server
	name = "Telecommunications Server Monitor"
	desc = "View communication logs here. Translation not guaranteed."
	icon_screen = "comm_logs"

	var/list/servers	// the servers located by the computer
	var/obj/machinery/telecomms/server/SelectedServer
	circuit = /obj/item/circuitboard/comm_server

	var/universal_translate = 0 // set to 1 if it can translate nonhuman speech

	req_access = list(ACCESS_TCOMSAT)

MSG_DEF_SELF(tcomms_console/denied, "ACCESS DENIED.")
MSG_DEF_SELF(tcomms_console/no_entry, "There is no such log entry on the server shown.")

// The server log browser: probes the servers of its network (tcomms_probe_console(), telemonitor.dm), shows one with its logs, and deletes a
// log entry for someone with its access (or anyone, once emagged).
CAPABILITIES(/obj/machinery/computer/telecomms/server)
	interface("TelecommsLogBrowser")
	tcomms_probe_console()
	op("delete", ui_act("delete", arg("id", num())), needs(req(PROC_REF(may_delete)), req(PROC_REF(entry_exists))), then(PROC_REF(ui_act_delete)))

/obj/machinery/computer/telecomms/server/probed()
	return servers

/obj/machinery/computer/telecomms/server/probe_type()
	return /obj/machinery/telecomms/server

/obj/machinery/computer/telecomms/server/probe_add(obj/machinery/telecomms/T)
	rel_add(src, nameof(servers), T)

/obj/machinery/computer/telecomms/server/probe_clear()
	rel_clear(src, nameof(servers))

/obj/machinery/computer/telecomms/server/show(obj/machinery/telecomms/T)
	rel_set(src, nameof(SelectedServer), T)

/obj/machinery/computer/telecomms/server/show_none()
	rel_clear(src, nameof(SelectedServer))

/// needs: the actor has the browser's access, or it was emagged.
/obj/machinery/computer/telecomms/server/proc/may_delete(datum/act/op/A)
	return (emag_emagged(src) || allowed(A.actor)) ? null : MSG(tcomms_console/denied)

/// needs: the server shown has a log entry at that place.
/obj/machinery/computer/telecomms/server/proc/entry_exists(datum/act/op/A)
	var/idx = A.args["id"]
	var/obj/machinery/telecomms/server/S = SelectedServer()
	return (S && isnum(idx) && idx >= 1 && idx <= LAZYLEN(S.log_entries)) ? null : MSG(tcomms_console/no_entry)

/// The log entry goes (the server's log count is its length, so the place is free again).
/obj/machinery/computer/telecomms/server/proc/ui_act_delete(datum/act/op/A, id)
	var/obj/machinery/telecomms/server/S = SelectedServer()
	var/datum/comm_log_entry/D = LAZYACCESS(S.log_entries, id)
	report("DELETED ENTRY: [D.name]", "bad")
	own_remove(S, nameof(/obj/machinery/telecomms/server::log_entries), D)
	return OP_OK

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
				parameters["[log_param]"] = LAZYACCESS(C.parameters, "[log_param]")

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


/// SelectedServer (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/telecomms/server/proc/SelectedServer() as /obj/machinery/telecomms/server
	return SelectedServer // ALLOW(reads): the server shown is asked when it is needed, never cached
