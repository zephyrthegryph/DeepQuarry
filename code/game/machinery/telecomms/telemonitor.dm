// The telecommunications consoles that probe a network (doc/rewrite/final_api.html, sections 9, 11, 13): the network monitor (machines and their
// links) and the server log browser (the servers and their logs). Both probe the machines of their network tag within range into a buffer,
// show one of them, release the buffer, take a new network tag (which empties the buffer) and report on a status line; an emag disables the
// browser's access check. What they share is tcomms_probe_console(), a plain proc of entries each console's block includes.


MSG_DEF(tcomms_console/emagged, "You disable the security protocols.", "")
MSG_DEF_SELF(tcomms_console/buffer_full, "The buffer is full: release it before probing again.")

/obj/machinery/computer/telecomms
	icon_keyboard = "tech_key"
	var/network = "NULL"	// the network to probe
	var/temp = null			// the status line: list("color", "text") (the traffic console keeps its own text)

TRACKED(/obj/machinery/computer/telecomms, temp)

/// The entries of a console that probes its network: the buttons, the network question, the status line and the emag.
/proc/tcomms_probe_console()
	return list(
		op("scan", ui_act("scan"), needs(req(TYPE_PROC_REF(/obj/machinery/computer/telecomms, buffer_empty))), then(TYPE_PROC_REF(/obj/machinery/computer/telecomms, probe_scan))),
		op("view", ui_act("view", arg("id", schema_text(4096))), then(TYPE_PROC_REF(/obj/machinery/computer/telecomms, ui_act_view))),
		op("mainmenu", ui_act("mainmenu"), then(TYPE_PROC_REF(/obj/machinery/computer/telecomms, ui_act_mainmenu))),
		op("release", ui_act("release"), then(TYPE_PROC_REF(/obj/machinery/computer/telecomms, ui_act_release))),
		op("network", ui_act("network"), asks(/datum/prompt/text, fields = list("title" = "Comm Monitor", "question" = "Which network do you want to view?", "default" = "network", "max_len" = TCOMMS_NETWORK_MAX_LEN)), then(TYPE_PROC_REF(/obj/machinery/computer/telecomms, probe_network_entered))),
		op("cleartemp", ui_act("cleartemp"), then(TYPE_PROC_REF(/obj/machinery/computer/telecomms, ui_act_cleartemp))),
		extend(TAG_UI, then(TYPE_PROC_REF(/obj/machinery/computer/telecomms, ui_fingerprint), early = TRUE)),
		emag(say = MSG(tcomms_console/emagged)))

// ---- what each console probes (its buffer and the machine it shows) ----

/// The machines in the buffer.
/obj/machinery/computer/telecomms/proc/probed()
	return null

/// The type of machine this console probes for.
/obj/machinery/computer/telecomms/proc/probe_type()
	return /obj/machinery/telecomms

/obj/machinery/computer/telecomms/proc/probe_add(obj/machinery/telecomms/T)
	return

/obj/machinery/computer/telecomms/proc/probe_clear()
	return

/obj/machinery/computer/telecomms/proc/show(obj/machinery/telecomms/T)
	return

/obj/machinery/computer/telecomms/proc/show_none()
	return

// ---- the shared buttons ----

/// The status line: what the last button did.
/obj/machinery/computer/telecomms/proc/report(text, color = "average")
	set_temp(list("color" = color, "text" = text))

/obj/machinery/computer/telecomms/proc/ui_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/// needs: the buffer is empty (a full one is released first).
/obj/machinery/computer/telecomms/proc/buffer_empty(datum/act/op/A)
	return (!length(probed())) ? null : MSG(tcomms_console/buffer_full)

/// The machines of the console's network within range go into the buffer.
/obj/machinery/computer/telecomms/proc/probe_scan(datum/act/op/A)
	var/wanted = probe_type()
	for(var/obj/machinery/telecomms/T in range(TCOMMS_PROBE_RANGE, src))
		if(istype(T, wanted) && T.network == network)
			probe_add(T)
	if(!length(probed()))
		report("FAILED: UNABLE TO LOCATE NETWORK ENTITIES IN \[[network]\]", "bad")
	else
		report("[length(probed())] ENTITIES LOCATED & BUFFERED", "good")
	return OP_OK

/// The machine of that id in the buffer is shown.
/obj/machinery/computer/telecomms/proc/ui_act_view(datum/act/op/A, raw_id)
	for(var/obj/machinery/telecomms/T in probed())
		if(T.id == raw_id)
			show(T)
			break
	return OP_OK

/obj/machinery/computer/telecomms/proc/ui_act_mainmenu(datum/act/op/A)
	show_none()
	return OP_OK

/obj/machinery/computer/telecomms/proc/ui_act_release(datum/act/op/A)
	probe_clear()
	show_none()
	return OP_OK

/// A new network tag empties the buffer.
/obj/machinery/computer/telecomms/proc/probe_network_entered(datum/act/op/A)
	var/datum/prompt/P = A.answer
	var/newnet = P?.value
	if(!newnet)
		return OP_OK
	network = newnet
	probe_clear()
	show_none()
	report("NEW NETWORK TAG SET IN ADDRESS \[[network]\]", "good")
	return OP_OK

/obj/machinery/computer/telecomms/proc/ui_act_cleartemp(datum/act/op/A)
	set_temp(null)
	return OP_OK

// ---- the network monitor ----

/obj/machinery/computer/telecomms/monitor
	name = "Telecommunications Monitor"
	desc = "Used to traverse a telecommunication network. Helpful for debugging connection issues."
	icon_screen = "comm_monitor"

	var/screen = 0				// the screen number:
	var/list/machinelist	// the machines located by the computer
	var/obj/machinery/telecomms/SelectedMachine
	circuit = /obj/item/circuitboard/comm_monitor

CAPABILITIES(/obj/machinery/computer/telecomms/monitor)
	interface("TelecommsMachineBrowser")
	tcomms_probe_console()

/obj/machinery/computer/telecomms/monitor/probed()
	return machinelist

/obj/machinery/computer/telecomms/monitor/probe_add(obj/machinery/telecomms/T)
	rel_add(src, nameof(machinelist), T)

/obj/machinery/computer/telecomms/monitor/probe_clear()
	rel_clear(src, nameof(machinelist))

/obj/machinery/computer/telecomms/monitor/show(obj/machinery/telecomms/T)
	rel_set(src, nameof(SelectedMachine), T)

/obj/machinery/computer/telecomms/monitor/show_none()
	rel_clear(src, nameof(SelectedMachine))

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

/// SelectedMachine (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/telecomms/monitor/proc/SelectedMachine() as /obj/machinery/telecomms
	return SelectedMachine
