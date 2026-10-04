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

/obj/machinery/computer/telecomms/monitor/ui_data(datum/act/eval/A)
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
	data["network"] = network
	data["temp"] = temp
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

CAPABILITIES(/obj/machinery/computer/telecomms/monitor)
	interface("TelecommsMachineBrowser")
	op("view", ui_act("view", arg("id")), then(PROC_REF(ui_act_view)))
	op("mainmenu", ui_act("mainmenu"), then(PROC_REF(ui_act_mainmenu)))
	op("release", ui_act("release"), then(PROC_REF(ui_act_release)))
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("network", ui_act("network"), then(PROC_REF(ui_act_network)))
	op("cleartemp", ui_act("cleartemp"), then(PROC_REF(ui_act_cleartemp)))
	extend(TAG_UI, then(PROC_REF(ui_fingerprint), early = TRUE))
	emag(then(PROC_REF(on_emag)))

/obj/machinery/computer/telecomms/monitor/proc/ui_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/obj/machinery/computer/telecomms/monitor/proc/ui_act_view(datum/act/op/A, raw_id)
	for(var/obj/machinery/telecomms/T in machinelist)
		if(T.id == raw_id)
			rel_set(src, nameof(/obj/machinery/computer/telecomms/monitor::SelectedMachine), T)
			break
	. = TRUE

/obj/machinery/computer/telecomms/monitor/proc/ui_act_mainmenu(datum/act/op/A)
	add_fingerprint(A.actor)
	rel_clear(src, nameof(/obj/machinery/computer/telecomms/monitor::SelectedMachine))
	return OP_OK

/obj/machinery/computer/telecomms/monitor/proc/ui_act_release(datum/act/op/A)
	add_fingerprint(A.actor)
	rel_clear(src, nameof(/obj/machinery/computer/telecomms/monitor::machinelist))
	rel_clear(src, nameof(/obj/machinery/computer/telecomms/monitor::SelectedMachine))
	return OP_OK

/obj/machinery/computer/telecomms/monitor/proc/ui_act_scan(datum/act/op/A)
	if(length(machinelist) > 0)
		set_temp("FAILED: CANNOT PROBE WHEN BUFFER FULL", "bad")
		return TRUE

	for(var/obj/machinery/telecomms/T in range(25, src))
		if(T.network == network)
			rel_add(src, nameof(/obj/machinery/computer/telecomms/monitor::machinelist), T)

	if(!length(machinelist))
		set_temp("FAILED: UNABLE TO LOCATE NETWORK ENTITIES IN \[[network]\]", "bad")
	else
		set_temp("[length(machinelist)] ENTITIES LOCATED & BUFFERED", "good")
	. = TRUE

/obj/machinery/computer/telecomms/monitor/proc/ui_act_network(datum/act/op/A)
	open_request(src, /datum/prompt/text, PROC_REF(network_entered), answerer = A.actor, title = "Comm Monitor", question = "Which network do you want to view?", default = network, max_len = 15, ask_flags = ASK_CAPABLE, timeout = 0)
	. = TRUE

/obj/machinery/computer/telecomms/monitor/proc/ui_act_cleartemp(datum/act/op/A)
	add_fingerprint(A.actor)
	temp = null
	return OP_OK

/obj/machinery/computer/telecomms/monitor/proc/network_entered(datum/act/request/A)
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
		rel_clear(src, nameof(machinelist))
		set_temp("NEW NETWORK TAG SET IN ADDRESS \[[network]\]", "good")

	. = TRUE


/obj/machinery/computer/telecomms/monitor/proc/on_emag(datum/act/op/A)
	play_sfx(src, SFX_EFFECTS_SPARKS4)
	set_emagged(1)
	to_chat(A.actor, span_notice("You you disable the security protocols"))
	return OP_OK

/obj/machinery/computer/telecomms/monitor/proc/set_temp(text, color = "average")
	temp = list("color" = color, "text" = text)

/// SelectedMachine (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/telecomms/monitor/proc/SelectedMachine() as /obj/machinery/telecomms
	return SelectedMachine
