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

/obj/machinery/computer/telecomms/monitor/tgui_data(mob/user)
	var/list/data = list()

	data["network"] = network
	data["temp"] = temp

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

/obj/machinery/computer/telecomms/monitor/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "TelecommsMachineBrowser", name)
		ui.open()

/obj/machinery/computer/telecomms/monitor/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	add_fingerprint(ui.user)

	switch(action)
		if("view")
			for(var/obj/machinery/telecomms/T in machinelist)
				if(T.id == params["id"])
					rel_set(src, "SelectedMachine", T)
					break
			. = TRUE

		if("mainmenu")
			rel_clear(src, "SelectedMachine")
			. = TRUE

		if("release")
			rel_clear(src, "machinelist")
			rel_clear(src, "SelectedMachine")
			. = TRUE

		if("scan")
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

		if("network")
			om_ask(ui.user, /datum/om/prompt/text, PROC_REF(network_entered), message = "Which network do you want to view?", title = "Comm Monitor", default = network, max_length = 15, requires = PROMPT_USABLE)
			. = TRUE

		if("cleartemp")
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


DECLARE_EMAG(/obj/machinery/computer/telecomms/monitor, PROC_REF(on_emag), null, null)
/obj/machinery/computer/telecomms/monitor/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	play_sfx(src, SFX_EFFECTS_SPARKS4)
	set_emagged(1)
	to_chat(user, span_notice("You you disable the security protocols"))
	return 1

/obj/machinery/computer/telecomms/monitor/proc/set_temp(text, color = "average")
	temp = list("color" = color, "text" = text)

/// SelectedMachine (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/telecomms/monitor/proc/SelectedMachine() as /obj/machinery/telecomms
	return SelectedMachine
