/obj/machinery/computer/rdservercontrol
	name = "R&D Server Controller"
	desc = "Manages access to research databases and consoles."
	icon_screen = "rdcomp"
	icon_keyboard = "rd_key"
	circuit = /obj/item/circuitboard/rdservercontrol
	req_access = list(ACCESS_RD)

	///Connected techweb node the server is connected to.
	var/datum/techweb/stored_research
	var/badmin = FALSE // old compatibility

/obj/machinery/computer/rdservercontrol/Initialize(mapload)
	. = ..()
	if(!stored_research)
		CONNECT_TO_RND_SERVER_ROUNDSTART(stored_research, src)

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
		if(!QDELETED(tool.buffer) && istype(tool.buffer, /datum/techweb))
			stored_research = tool.buffer
			balloon_alert(user, "techweb connected")
	return TRUE

/obj/machinery/computer/rdservercontrol/emag_act(remaining_charges, mob/user, emag_source)
	if(emagged)
		return FALSE
	emagged = TRUE
	playsound(src, "sparks", 75, TRUE)
	balloon_alert(user, "console emagged")
	return TRUE

/obj/machinery/computer/rdservercontrol/tgui_interact(mob/user, datum/tgui/ui)
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ServerControl", name)
		ui.open()

/obj/machinery/computer/rdservercontrol/tgui_data(mob/user)
	var/list/data = list()

	data["server_connected"] = !!stored_research

	if(stored_research)
		data["logs"] += stored_research.research_logs

		for(var/obj/machinery/rnd/server/server as anything in stored_research.techweb_servers)
			data["servers"] += list(list(
				"server_name" = server,
				"server_details" = server.get_status_text(),
				"server_disabled" = server.research_disabled || !server.working,
				"server_ref" = REF(server),
			))

		for(var/obj/machinery/computer/rdconsole_tg/console as anything in stored_research.consoles_accessing)
			data["consoles"] += list(list(
				"console_name" = console,
				"console_location" = get_area(console),
				"console_locked" = console.locked,
				"console_ref" = REF(console),
			))

	return data

/obj/machinery/computer/rdservercontrol/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return TRUE
	if(!allowed(usr) && !emagged)
		balloon_alert(usr, "access denied!")
		playsound(src, 'sound/machines/click.ogg', 20, TRUE)
		return TRUE

	switch(action)
		if("lockdown_server")
			var/obj/machinery/rnd/server/server_selected = locate(params["selected_server"]) in stored_research.techweb_servers
			if(!server_selected)
				return FALSE
			server_selected.toggle_disable(usr)
			return TRUE
		if("lock_console")
			var/obj/machinery/computer/rdconsole_tg/console_selected = locate(params["selected_console"]) in stored_research.consoles_accessing
			if(!console_selected)
				return FALSE
			console_selected.locked = !console_selected.locked
			return TRUE
