//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32


/*
	Telecomms monitor tracks the overall trafficing of a telecommunications network
	and displays a heirarchy of linked machines.
*/

/obj/machinery/computer/telecomms/monitor
	name = "Telecommunications Monitor"
	desc = "Used to traverse a telecommunication network. Helpful for debugging connection issues."
	icon_screen = "comm_monitor"

	var/screen = 0				// the screen number:
	var/list/machinelist	// the machines located by the computer
	var/obj/machinery/telecomms/SelectedMachine
	circuit = /obj/item/circuitboard/comm_monitor

	var/network = "NULL"		// the network to probe

	var/list/temp = null				// temporary feedback messages

UI_DATA_REPLACE(/obj/machinery/computer/telecomms/monitor, "network", "temp:text", "merge:ui_data_obj_machinery_computer_telecomms_monitor{machinelist:list,selectedMachine:list}")

/// The computed part of /obj/machinery/computer/telecomms/monitor's window data (declared on its UI_DATA row).
/obj/machinery/computer/telecomms/monitor/proc/ui_data_obj_machinery_computer_telecomms_monitor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()


	var/list/machinelistData = list()
	for(var/obj/machinery/telecomms/T in machinelist)
		machinelistData.Add(list(list(
			"id" = T.id,
			"name" = T.name,
		)))
	data["machinelist"] = machinelistData

	data["selectedMachine"] = null
	if(SelectedMachine())
		data["selectedMachine"] = list(
			"id" = SelectedMachine().id,
			"name" = SelectedMachine().name,
		)
		var/list/links = list()
		for(var/obj/machinery/telecomms/T in SelectedMachine().links)
			if(!T.hide)
				links.Add(list(list(
					"id" = T.id,
					"name" = T.name
				)))
		data["selectedMachine"]["links"] = links
	return data

/obj/machinery/computer/telecomms/monitor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/telemonitor_open_ui,
	)
	..()

/// Old attack_hand: `if(stat & (BROKEN|NOPOWER)) return; tgui_interact(user)`, no gate (never called ..()).
/datum/interaction/machine_hand/ungated/telemonitor_open_ui
	id = "telemonitor_open_ui"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH,
		REQ_ON(PRED_TARGET, /obj/machinery/computer/telecomms/monitor/proc/telemonitor_powered, "it isn't working"))
	effect = /atom/proc/interaction_open_ui

/obj/machinery/computer/telecomms/monitor/proc/telemonitor_powered(mob/actor, atom/target, obj/item/held)
	return operable()

DECLARE_UI(/obj/machinery/computer/telecomms/monitor, "TelecommsMachineBrowser")

/obj/machinery/computer/telecomms/monitor/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/telecomms/monitor, "view", ui_act_view, UI_ARG_VALUE("id"))
UI_ACT_PROC(/obj/machinery/computer/telecomms/monitor, ui_act_view)
	for(var/obj/machinery/telecomms/T in machinelist)
		if(T.id == params["id"])
			rel_set(src, "SelectedMachine", T)
			break
	. = TRUE

UI_ACT(/obj/machinery/computer/telecomms/monitor, "mainmenu", ui_act_mainmenu)
UI_ACT_PROC(/obj/machinery/computer/telecomms/monitor, ui_act_mainmenu)
	rel_clear(src, "SelectedMachine")
	. = TRUE

UI_ACT(/obj/machinery/computer/telecomms/monitor, "release", ui_act_release)
UI_ACT_PROC(/obj/machinery/computer/telecomms/monitor, ui_act_release)
	rel_clear(src, "machinelist")
	rel_clear(src, "SelectedMachine")
	. = TRUE

UI_ACT(/obj/machinery/computer/telecomms/monitor, "scan", ui_act_scan)
UI_ACT_PROC(/obj/machinery/computer/telecomms/monitor, ui_act_scan)
	if(length(machinelist) > 0)
		set_temp("FAILED: CANNOT PROBE WHEN BUFFER FULL", "bad")
		return TRUE

	for(var/obj/machinery/telecomms/T in range(25, src))
		if(T.network == network)
			rel_add(src, "machinelist", T)

	if(!length(machinelist))
		set_temp("FAILED: UNABLE TO LOCATE NETWORK ENTITIES IN \[[network]\]", "bad")
	else
		set_temp("[length(machinelist)] ENTITIES LOCATED & BUFFERED", "good")
	. = TRUE

UI_ACT(/obj/machinery/computer/telecomms/monitor, "network", ui_act_network)
UI_ACT_PROC(/obj/machinery/computer/telecomms/monitor, ui_act_network)
	om_ask(ui.user, /datum/om/prompt/text, PROC_REF(network_entered), message = "Which network do you want to view?", title = "Comm Monitor", default = network, max_length = 15, requires = PROMPT_USABLE)
	. = TRUE

UI_ACT(/obj/machinery/computer/telecomms/monitor, "cleartemp", ui_act_cleartemp)
UI_ACT_PROC(/obj/machinery/computer/telecomms/monitor, ui_act_cleartemp)
	temp = null
	. = TRUE

/obj/machinery/computer/telecomms/monitor/proc/network_entered(datum/om/prompt/text/ask)
	var/mob/user = ask.answerer
	var/newnet = ask.text
	SStgui.update_uis(src)
	if(newnet && ((user in range(1, src)) || issilicon(user)))
		if(length(newnet) > 15)
			set_temp("FAILED: NETWORK TAG STRING TOO LENGTHY", "bad")
			return TRUE
		network = newnet
		rel_clear(src, "machinelist")
		set_temp("NEW NETWORK TAG SET IN ADDRESS \[[network]\]", "good")

	. = TRUE


/obj/machinery/computer/telecomms/monitor/emag_act(remaining_charges, mob/user)
	if(!emagged)
		play_sfx(src, SFX_EFFECTS_SPARKS4)
		set_emagged(1)
		to_chat(user, span_notice("You you disable the security protocols"))
		return 1

/obj/machinery/computer/telecomms/monitor/proc/set_temp(text, color = "average")
	temp = list("color" = color, "text" = text)

/// SelectedMachine (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/telecomms/monitor/proc/SelectedMachine() as /obj/machinery/telecomms
	return SelectedMachine
