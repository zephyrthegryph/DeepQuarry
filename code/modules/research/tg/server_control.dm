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

/obj/machinery/computer/rdservercontrol/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/rdservercontrol_connect_techweb,
		/datum/interaction/machine_hand/ungated/open_ui,
	)
	..()

/// The old attackby: never called ..(), connected a techweb via a multitool buffer.
/datum/interaction/machine_item/rdservercontrol_connect_techweb
	id = "rdservercontrol_connect_techweb"
	name = "Connect techweb"
	held_type = /obj/item
	effect = /obj/machinery/computer/rdservercontrol/proc/interaction_connect_techweb

/obj/machinery/computer/rdservercontrol/proc/interaction_connect_techweb(mob/user, obj/item/I, datum/interaction/interaction)
	var/obj/item/multitool/tool = I.get_multitool()
	if(tool)
		if(!QDELETED(tool.buffer()) && istype(tool.buffer(), /datum/techweb))
			stored_research_static = tool.buffer()
			balloon_alert(user, "techweb connected")
	return TRUE

DECLARE_EMAG(/obj/machinery/computer/rdservercontrol, PROC_REF(on_emag), null, null)
/obj/machinery/computer/rdservercontrol/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	set_emagged(TRUE)
	play_sfx(src, SFX_SPARKS, 1.5)
	balloon_alert(user, "console emagged")
	return TRUE

DECLARE_UI(/obj/machinery/computer/rdservercontrol, "ServerControl")

UI_DATA_REPLACE(/obj/machinery/computer/rdservercontrol, "merge:ui_data_obj_machinery_computer_rdservercontrol{server_connected:bool,logs:list,servers:list,consoles:list}")

/// The computed part of /obj/machinery/computer/rdservercontrol's window data (declared on its UI_DATA row).
/obj/machinery/computer/rdservercontrol/proc/ui_data_obj_machinery_computer_rdservercontrol(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/obj/machinery/computer/rdservercontrol/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!allowed(user) && !emagged)
		balloon_alert(user, "access denied!")
		play_sfx(src, SFX_MACHINES_CLICK, 0.4)
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/computer/rdservercontrol, "lockdown_server", ui_act_lockdown_server, UI_ARG_REF("selected_server", "proc:ui_source_stored_research_techweb_servers", /obj/machinery/rnd/server))
UI_ACT_PROC(/obj/machinery/computer/rdservercontrol, ui_act_lockdown_server)
	var/obj/machinery/rnd/server/server_selected = params["selected_server"]
	if(!server_selected)
		return FALSE
	server_selected.toggle_disable(user)
	return TRUE

UI_ACT(/obj/machinery/computer/rdservercontrol, "lock_console", ui_act_lock_console, UI_ARG_REF("selected_console", "proc:ui_source_stored_research_consoles_accessing", /obj/machinery/computer/rdconsole_tg))
UI_ACT_PROC(/obj/machinery/computer/rdservercontrol, ui_act_lock_console)
	var/obj/machinery/computer/rdconsole_tg/console_selected = params["selected_console"]
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
