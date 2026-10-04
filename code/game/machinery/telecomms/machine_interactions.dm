//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32

/*

	All telecommunications interactions:

*/

#define STATION_Z 2
#define TELECOMM_Z 4

/obj/machinery/telecomms
	maintenance_flags = MACHINE_MAINT_STANDARD
	var/list/temp = null // output message

/obj/machinery/telecomms/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/telecomms_repair,
		/datum/interaction/machine_hand/ungated/open_ui,
	)
	..()

/// Old attackby: never called ..() for any item, so the whole thing (including the non-nanopaste no-op) stays in the effect.
/datum/interaction/machine_item/telecomms_repair
	id = "telecomms_repair"
	name = "Repair with Nanopaste"
	effect = /obj/machinery/telecomms/proc/interaction_repair

/obj/machinery/telecomms/proc/interaction_repair(mob/user, obj/item/P, datum/interaction/interaction)
	// REPAIRING: Use Nanopaste to repair 10-20 integrity points.
	if(istype(P, /obj/item/stack/nanopaste))
		var/obj/item/stack/nanopaste/T = P
		if(get_integrity() < max_integrity)
			if (T.use(1))
				repair_damage(rand(10, 20))
				to_chat(user, "You apply the Nanopaste to [src], repairing some of the damage.")
		else
			to_chat(user, "This machine is already in perfect condition.")
	return TRUE

/obj/machinery/telecomms/multitool_act(mob/user, obj/item/tool)
	attack_hand(user)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/telecomms/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()

	data["temp"] = temp
	data["on"] = on

	data["id"] = null
	data["network"] = null
	data["autolinkers"] = FALSE
	data["shadowlink"] = FALSE
	data["options"] = list()
	data["linked"] = list()
	data["filter"] = list()
	data["multitool"] = FALSE
	data["multitool_buffer"] = null

	if(on || interact_offline)
		data["id"] = id
		data["network"] = network
		data["autolinkers"] = !!LAZYLEN(autolinkers)
		data["shadowlink"] = !!hide

		data["options"] = Options_Menu()

		var/obj/item/multitool/P = get_multitool(user)
		data["multitool"] = !!P
		data["multitool_buffer"] = null
		if(P && P.buffer())
			P.update_icon()
			data["multitool_buffer"] = list("name" = "[P.buffer()]", "id" = "[P.buffer().id]")

		var/i = 0
		var/list/linked = list()
		for(var/obj/machinery/telecomms/T in links)
			i++
			linked.Add(list(list(
				"ref" = "\ref[T]",
				"name" = "[T]",
				"id" = T.id,
				"index" = i,
			)))
		data["linked"] = linked

		var/list/filter = list()
		for(var/x in freq_listening)
			filter.Add(list(list(
				"name" = "[format_frequency(x)]",
				"freq" = x,
			)))
		data["filter"] = filter

	return data

/obj/machinery/telecomms/tgui_status(mob/user)
	if(!issilicon(user))
		var/obj/item/hand_item = user.get_active_hand()
		if(!hand_item?.get_multitool())
			return STATUS_CLOSE
	. = ..()

// Off-Site Relays
//
// You are able to send/receive signals from the station's z level (changeable in the STATION_Z #define) if
// the relay is on the telecomm satellite (changable in the TELECOMM_Z #define)

/obj/machinery/telecomms/relay/proc/toggle_level()

	var/turf/position = get_turf(src)

	// Toggle on/off getting signals from the station or the current Z level
	if(src.listening_level == STATION_Z) // equals the station
		src.listening_level = position.z
		return 1
	else if(position.z == TELECOMM_Z)
		src.listening_level = STATION_Z
		return 1
	return 0

// Returns a multitool from a user depending on their mobtype.

/obj/machinery/proc/get_multitool(mob/user as mob)	//No need to have this being a telecomms specific proc.

	var/obj/item/multitool/P = null
	// Let's double check
	var/obj/item/held = user.get_active_hand()
	if(!issilicon(user))
		P = held?.get_multitool()
	else if(isAI(user))
		var/mob/living/silicon/ai/U = user
		P = U.aiMulti
	else if(isrobot(user) && in_range(user, src))
		P = held?.get_multitool()
	return P

// Additional Options for certain machines. Use this when you want to add an option to a specific machine.
// Example of how to use below.

/obj/machinery/telecomms/proc/Options_Menu()
	return list()

// The topic for Additional Options. Use this for checking href links for your specific option.
// Example of how to use below.
// RELAY

/obj/machinery/telecomms/relay/Options_Menu()
	var/list/data = ..()
	data["use_listening_level"] = TRUE
	data["use_broadcasting"] = TRUE
	data["use_receiving"] = TRUE
	data["listening_level"] = (listening_level == STATION_Z)
	data["broadcasting"] = broadcasting
	data["receiving"] = receiving
	return data

CAPABILITIES(/obj/machinery/telecomms/relay)
	op("receive", ui_act("receive"), then(PROC_REF(ui_act_receive)))
	op("broadcast", ui_act("broadcast"), then(PROC_REF(ui_act_broadcast)))
	op("change_listening", ui_act("change_listening"), then(PROC_REF(ui_act_change_listening)))

/obj/machinery/telecomms/relay/proc/ui_act_receive(datum/act/op/A)
	. = TRUE
	receiving = !receiving
	set_temp("-% Receiving mode changed. %-", "average")

/obj/machinery/telecomms/relay/proc/ui_act_broadcast(datum/act/op/A)
	. = TRUE
	broadcasting = !broadcasting
	set_temp("-% Broadcasting mode changed. %-", "average")

/obj/machinery/telecomms/relay/proc/ui_act_change_listening(datum/act/op/A)
	. = TRUE
	//Lock to the station OR lock to the current position!
	//You need at least two receivers and two broadcasters for this to work, this includes the machine.
	var/result = toggle_level()
	if(result)
		set_temp("-% [src]'s signal has been successfully changed.", "average")
	else
		set_temp("-% [src] could not lock it's signal onto the station. Two broadcasters or receivers required.", "average")

// BUS

/obj/machinery/telecomms/bus/Options_Menu()
	var/list/data = ..()
	data["use_change_freq"] = TRUE
	data["change_freq"] = change_frequency
	return data

CAPABILITIES(/obj/machinery/telecomms/bus)
	op("change_freq", ui_act("change_freq"), then(PROC_REF(ui_act_change_freq)))

/obj/machinery/telecomms/bus/proc/ui_act_change_freq(datum/act/op/A)
	. = TRUE
	open_request(src, /datum/prompt/number, PROC_REF(change_frequency_entered), valid = PROC_REF(access_valid), answerer = A.actor, title = "[src]", question = "Specify a new frequency for new signals to change to. Enter null to turn off frequency changing. Decimals assigned automatically.", default = network, ask_flags = ASK_CAPABLE, timeout = 0)

/// A cancel turns frequency changing off.
/obj/machinery/telecomms/bus/proc/change_frequency_entered(datum/act/request/A)
	if(!A.answer)
		if(canAccess(A.request.answerer))
			set_change_frequency(null)
		return
	set_change_frequency(A.answer.answer_value)

/obj/machinery/telecomms/bus/proc/set_change_frequency(newfreq)
	if(newfreq)
		if(findtext(num2text(newfreq), "."))
			newfreq *= 10 // shift the decimal one place
		if(newfreq < 10000)
			change_frequency = newfreq
			set_temp("-% New frequency to change to assigned: \"[newfreq] GHz\" %-", "average")
	else
		change_frequency = ZERO_FREQ
		set_temp("-% Frequency changing deactivated %-", "average")

// BROADCASTER
/obj/machinery/telecomms/broadcaster/Options_Menu()
	var/list/data = ..()
	data["use_broadcast_range"] = TRUE
	data["range"] = overmap_range
	data["minRange"] = overmap_range_min
	data["maxRange"] = overmap_range_max
	return data

/obj/machinery/telecomms/broadcaster
	interact_offline = TRUE // because you can accidentally nuke power grids with these, need to be able to fix mistake

CAPABILITIES(/obj/machinery/telecomms/broadcaster)
	op("range", ui_act("range", arg("range", num())), then(PROC_REF(ui_act_range)))

/obj/machinery/telecomms/broadcaster/proc/ui_act_range(datum/act/op/A, range)
	var/new_range = range
	overmap_range = clamp(new_range, overmap_range_min, overmap_range_max)
	update_idle_power_usage(initial(idle_power_usage)**(overmap_range+1))

// RECEIVER
/obj/machinery/telecomms/receiver/Options_Menu()
	var/list/data = ..()
	data["use_receive_range"] = TRUE
	data["range"] = overmap_range
	data["minRange"] = overmap_range_min
	data["maxRange"] = overmap_range_max
	return data

/obj/machinery/telecomms/receiver
	interact_offline = TRUE // because you can accidentally nuke power grids with these, need to be able to fix mistake

CAPABILITIES(/obj/machinery/telecomms/receiver)
	op("range", ui_act("range", arg("range", num())), then(PROC_REF(ui_act_range)))

/obj/machinery/telecomms/receiver/proc/ui_act_range(datum/act/op/A, range)
	var/new_range = range
	overmap_range = clamp(new_range, overmap_range_min, overmap_range_max)
	update_idle_power_usage(initial(idle_power_usage)**(overmap_range+1))

/// Whoever presses a button leaves their prints on the machine.
/obj/machinery/telecomms/proc/ui_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/// Re-checked on every question the window asks: the answerer can still access the machine.
/obj/machinery/telecomms/proc/access_valid(datum/request/R)
	var/mob/M = R.answerer
	return istype(M) && canAccess(M)

/obj/machinery/telecomms/proc/ui_act_toggle(datum/act/op/A)
	src.toggled = !src.toggled
	set_temp("-% [src] has been [src.toggled ? "activated" : "deactivated"].", "average")
	update_power()
	. = TRUE

/obj/machinery/telecomms/proc/ui_act_id(datum/act/op/A)
	open_request(src, /datum/prompt/text, PROC_REF(id_entered), valid = PROC_REF(access_valid), answerer = A.actor, title = "[src]", question = "Specify the new ID for this machine", default = id, ask_flags = ASK_CAPABLE, timeout = 0)
	. = TRUE

/obj/machinery/telecomms/proc/ui_act_network(datum/act/op/A)
	open_request(src, /datum/prompt/text, PROC_REF(network_entered), valid = PROC_REF(access_valid), answerer = A.actor, title = "[src]", question = "Specify the new network for this machine. This will break all current links.", default = network, max_len = 15, ask_flags = ASK_CAPABLE, timeout = 0)
	. = TRUE

/obj/machinery/telecomms/proc/ui_act_freq(datum/act/op/A)
	open_request(src, /datum/prompt/number, PROC_REF(filter_frequency_entered), valid = PROC_REF(access_valid), answerer = A.actor, title = "[src]", question = "Specify a new frequency to filter (GHz). Decimals assigned automatically.", max_value = 9999, ask_flags = ASK_CAPABLE, timeout = 0)
	. = TRUE

/obj/machinery/telecomms/proc/ui_act_delete(datum/act/op/A, delete)
	var/x = delete
	set_temp("-% Removed frequency filter [x] %-", "average")
	LAZYREMOVE(freq_listening, x)
	. = TRUE

/obj/machinery/telecomms/proc/ui_act_unlink(datum/act/op/A, unlink)
	var/unlink_index = unlink
	if(unlink_index >= 1 && unlink_index <= length(links))
		var/obj/machinery/telecomms/T = LAZYACCESS(links, unlink_index)
		set_temp("-% Removed \ref[T] [T.name] from linked entities. %-", "average")

		// Remove link entries from both T and src.

		rel_remove(src, nameof(/obj/machinery/telecomms::links), T)
		. = TRUE

/obj/machinery/telecomms/proc/ui_act_link(datum/act/op/A)
	var/obj/item/multitool/P = get_multitool(A.actor)
	if(P)
		if(P.buffer() && P.buffer() != src)
			rel_add(src, nameof(/obj/machinery/telecomms::links), P.buffer())

			set_temp("-% Successfully linked with \ref[P.buffer()] [P.buffer().name] %-", "average")

		else
			set_temp("-% Unable to acquire buffer %-", "average")
		. = TRUE

/obj/machinery/telecomms/proc/ui_act_buffer(datum/act/op/A)
	var/obj/item/multitool/P = get_multitool(A.actor)
	if(P)
		rel_set(P, nameof(/obj/item/debugger::buffer), src)
		set_temp("-% Successfully stored \ref[P.buffer()] [P.buffer().name] in buffer %-", "average")
	. = TRUE

/obj/machinery/telecomms/proc/ui_act_flush(datum/act/op/A)
	var/obj/item/multitool/P = get_multitool(A.actor)
	if(P)
		set_temp("-% Buffer successfully flushed. %-", "average")
		rel_clear(P, nameof(/obj/item/debugger::buffer))
	. = TRUE

/obj/machinery/telecomms/proc/ui_act_cleartemp(datum/act/op/A)
	temp = null
	. = TRUE


/obj/machinery/telecomms/proc/id_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/newid = copytext(reject_bad_text(A.answer.answer_value),1,MAX_MESSAGE_LEN)
	if(newid)
		id = newid
		set_temp("-% New ID assigned: \"[id]\" %-", "average")
		SStgui.update_uis(src)

/obj/machinery/telecomms/proc/network_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/newnet = A.answer.answer_value
	SStgui.update_uis(src)

	if(length(newnet) > 15)
		set_temp("-% Too many characters in new network tag %-", "average")

	else
		rel_clear(src, nameof(links))

		network = newnet
		set_temp("-% New network tag assigned: \"[network]\" %-", "average")
	. = TRUE

/obj/machinery/telecomms/proc/filter_frequency_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/newfreq = A.answer.answer_value
	if(!newfreq)
		return
	SStgui.update_uis(src)
	if(findtext(num2text(newfreq), "."))
		newfreq *= 10 // shift the decimal one place
	if(!(newfreq in freq_listening) && newfreq < 10000)
		LAZYADD(freq_listening, newfreq)
		set_temp("-% New frequency filter assigned: \"[newfreq/10] GHz\" %-", "average")
	. = TRUE

/obj/machinery/telecomms/proc/canAccess(mob/user)
	if(issilicon(user) || in_range(user, src))
		return 1
	return 0

/obj/machinery/telecomms/proc/set_temp(text, color = "average")
	temp = list("color" = color, "text" = text)

#undef TELECOMM_Z
#undef STATION_Z
