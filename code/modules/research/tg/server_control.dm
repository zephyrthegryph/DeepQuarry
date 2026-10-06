/obj/machinery/computer/rdservercontrol
	name = "R&D Server Controller"
	desc = "Manages access to research databases and consoles."
	icon_screen = "rdcomp"
	icon_keyboard = "rd_key"
	circuit = /obj/item/circuitboard/rdservercontrol
	req_access = list(ACCESS_RD)

	///Connected techweb node the server is connected to.
	var/tmp/datum/techweb/stored_research_static
	var/badmin = FALSE // old compatibility

/obj/machinery/computer/rdservercontrol/Initialize(mapload)
	. = ..()
	if(!stored_research())
		var/datum/techweb/connected_web
		CONNECT_TO_RND_SERVER_ROUNDSTART(connected_web, src)
		stored_research_static = connected_web

/obj/machinery/computer/rdservercontrol/proc/interaction_connect_techweb(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	var/obj/item/multitool/tool = I.get_multitool()
	if(tool)
		if(!QDELETED(tool.buffer()) && istype(tool.buffer(), /datum/techweb))
			stored_research_static = tool.buffer()
			balloon_alert(user, "techweb connected")
	return OP_OK

DECLARE_EMAG(/obj/machinery/computer/rdservercontrol, PROC_REF(on_emag), null, null)
/obj/machinery/computer/rdservercontrol/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	set_emagged(TRUE)
	play_sfx(src, SFX_SPARKS, 1.5)
	balloon_alert(user, "console emagged")
	return TRUE

CAPABILITIES(/obj/machinery/computer/rdservercontrol)
	interface("ServerControl")
	without("ui_open")
	op("lockdown_server", ui_act("lockdown_server", arg("selected_server", schema_ref(/obj/machinery/rnd/server))), then(PROC_REF(ui_act_lockdown_server)))
	op("lock_console", ui_act("lock_console", arg("selected_console", schema_ref(/obj/machinery/computer/rdconsole_tg))), then(PROC_REF(ui_act_lock_console)))
	op("connect_techweb", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Connect techweb"), then(PROC_REF(interaction_connect_techweb)))

/// /obj/machinery/computer/rdservercontrol's window data.
/obj/machinery/computer/rdservercontrol/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["server_connected"] = !!stored_research()

	if(stored_research())
		if(length(stored_research().research_logs)) data["logs"] += stored_research().research_logs

		for(var/obj/machinery/rnd/server/server as anything in stored_research().techweb_servers)
			data["servers"] += list(list(
				"server_name" = server,
				"server_details" = server.get_status_text(),
				"server_disabled" = server.research_disabled || !server.working,
				"server_ref" = REF(server),
			))

		for(var/obj/machinery/computer/rdconsole_tg/console as anything in stored_research().consoles_accessing)
			data["consoles"] += list(list(
				"console_name" = console,
				"console_location" = get_area(console),
				"console_locked" = console.locked,
				"console_ref" = REF(console),
			))

	return data

/obj/machinery/computer/rdservercontrol/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!allowed(user) && !emagged)
		balloon_alert(user, "access denied!")
		play_sfx(src, SFX_MACHINES_CLICK, 0.4)
		return FALSE
	return TRUE

/obj/machinery/computer/rdservercontrol/proc/ui_act_lockdown_server(datum/act/op/A, selected_server)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(selected_server) && !(selected_server in ui_source_stored_research_techweb_servers()))
		return FALSE
	var/obj/machinery/rnd/server/server_selected = selected_server
	if(!server_selected)
		return FALSE
	server_selected.toggle_disable(user)
	return TRUE

/obj/machinery/computer/rdservercontrol/proc/ui_act_lock_console(datum/act/op/A, selected_console)
	if(!ui_gate(A))
		return FALSE
	if(!isnull(selected_console) && !(selected_console in ui_source_stored_research_consoles_accessing()))
		return FALSE
	var/obj/machinery/computer/rdconsole_tg/console_selected = selected_console
	if(!console_selected)
		return FALSE
	console_selected.set_locked(!console_selected.locked)
	return TRUE

/// The list the UI_ARG_REF rows resolve refs in.
/obj/machinery/computer/rdservercontrol/proc/ui_source_stored_research_consoles_accessing()
	return stored_research().consoles_accessing

/// The list the UI_ARG_REF rows resolve refs in.
/obj/machinery/computer/rdservercontrol/proc/ui_source_stored_research_techweb_servers()
	return stored_research().techweb_servers

/// A shared definition/flyweight (never cleared).
/obj/machinery/computer/rdservercontrol/proc/stored_research() as /datum/techweb
	return stored_research_static
