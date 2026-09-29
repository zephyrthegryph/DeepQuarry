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

UI_DATA_REPLACE(/obj/machinery/telecomms, "temp:text", "merge:ui_data_obj_machinery_telecomms{on:num,id:unknown,network:unknown,autolinkers:bool,shadowlink:bool,options:unknown,linked:list,filter:list,multitool:bool,multitool_buffer:listmap}")

/// The computed part of /obj/machinery/telecomms's window data (declared on its UI_DATA row).
/obj/machinery/telecomms/proc/ui_data_obj_machinery_telecomms(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

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

DECLARE_UI(/obj/machinery/telecomms, "TelecommsMultitoolMenu")

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

UI_ACT(/obj/machinery/telecomms/relay, "receive", ui_act_receive)
UI_ACT_PROC(/obj/machinery/telecomms/relay, ui_act_receive)
	. = TRUE
	receiving = !receiving
	set_temp("-% Receiving mode changed. %-", "average")

UI_ACT(/obj/machinery/telecomms/relay, "broadcast", ui_act_broadcast)
UI_ACT_PROC(/obj/machinery/telecomms/relay, ui_act_broadcast)
	. = TRUE
	broadcasting = !broadcasting
	set_temp("-% Broadcasting mode changed. %-", "average")

UI_ACT(/obj/machinery/telecomms/relay, "change_listening", ui_act_change_listening)
UI_ACT_PROC(/obj/machinery/telecomms/relay, ui_act_change_listening)
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

UI_ACT(/obj/machinery/telecomms/bus, "change_freq", ui_act_change_freq)
UI_ACT_PROC(/obj/machinery/telecomms/bus, ui_act_change_freq)
	. = TRUE
	om_ask(ui.user, /datum/om/prompt/number/telecomms_change_frequency, PROC_REF(change_frequency_entered), title = "[src]", default = network)

/// A cancel turns frequency changing off.
/datum/om/prompt/number/telecomms_change_frequency
	message = "Specify a new frequency for new signals to change to. Enter null to turn off frequency changing. Decimals assigned automatically."
	round_entry = FALSE
	requires = PROMPT_USABLE

/datum/om/prompt/number/telecomms_change_frequency/valid()
	var/obj/machinery/telecomms/machine = subject
	return machine.canAccess(answerer) ? null : "no access"

/datum/om/prompt/number/telecomms_change_frequency/cancelled()
	var/obj/machinery/telecomms/bus/machine = subject
	if(machine?.canAccess(answerer))
		machine.set_change_frequency(null)

/obj/machinery/telecomms/bus/proc/change_frequency_entered(datum/om/prompt/number/telecomms_change_frequency/ask)
	set_change_frequency(ask.number)

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

UI_ACT(/obj/machinery/telecomms/broadcaster, "range", ui_act_range, UI_ARG_NUM("range"))
UI_ACT_PROC(/obj/machinery/telecomms/broadcaster, ui_act_range)
	var/new_range = params["range"]
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

UI_ACT(/obj/machinery/telecomms/receiver, "range", ui_act_range, UI_ARG_NUM("range"))
UI_ACT_PROC(/obj/machinery/telecomms/receiver, ui_act_range)
	var/new_range = params["range"]
	overmap_range = clamp(new_range, overmap_range_min, overmap_range_max)
	update_idle_power_usage(initial(idle_power_usage)**(overmap_range+1))

/obj/machinery/telecomms/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(user)
	return TRUE

UI_ACT(/obj/machinery/telecomms, "toggle", ui_act_toggle)
UI_ACT_PROC(/obj/machinery/telecomms, ui_act_toggle)
	src.toggled = !src.toggled
	set_temp("-% [src] has been [src.toggled ? "activated" : "deactivated"].", "average")
	update_power()
	. = TRUE

UI_ACT(/obj/machinery/telecomms, "id", ui_act_id)
UI_ACT_PROC(/obj/machinery/telecomms, ui_act_id)
	om_ask(ui.user, /datum/om/prompt/text/telecomms_setting, PROC_REF(id_entered), title = "[src]", message = "Specify the new ID for this machine", default = id)
	. = TRUE

UI_ACT(/obj/machinery/telecomms, "network", ui_act_network)
UI_ACT_PROC(/obj/machinery/telecomms, ui_act_network)
	om_ask(ui.user, /datum/om/prompt/text/telecomms_setting, PROC_REF(network_entered), title = "[src]", message = "Specify the new network for this machine. This will break all current links.", default = network, max_length = 15)
	. = TRUE

UI_ACT(/obj/machinery/telecomms, "freq", ui_act_freq)
UI_ACT_PROC(/obj/machinery/telecomms, ui_act_freq)
	om_ask(ui.user, /datum/om/prompt/number/telecomms_setting, PROC_REF(filter_frequency_entered), title = "[src]", message = "Specify a new frequency to filter (GHz). Decimals assigned automatically.", max = 9999)
	. = TRUE

UI_ACT(/obj/machinery/telecomms, "delete", ui_act_delete, UI_ARG_NUM("delete"))
UI_ACT_PROC(/obj/machinery/telecomms, ui_act_delete)
	var/x = params["delete"]
	set_temp("-% Removed frequency filter [x] %-", "average")
	LAZYREMOVE(freq_listening, x)
	. = TRUE

UI_ACT(/obj/machinery/telecomms, "unlink", ui_act_unlink, UI_ARG_NUM("unlink"))
UI_ACT_PROC(/obj/machinery/telecomms, ui_act_unlink)
	var/unlink_index = params["unlink"]
	if(unlink_index >= 1 && unlink_index <= length(links))
		var/obj/machinery/telecomms/T = LAZYACCESS(links, unlink_index)
		set_temp("-% Removed \ref[T] [T.name] from linked entities. %-", "average")

		// Remove link entries from both T and src.

		if(src in T.links)
			LAZYREMOVE(T.links, src)
		LAZYREMOVE(links, T)
		. = TRUE

UI_ACT(/obj/machinery/telecomms, "link", ui_act_link)
UI_ACT_PROC(/obj/machinery/telecomms, ui_act_link)
	var/obj/item/multitool/P = get_multitool(ui.user)
	if(P)
		if(P.buffer() && P.buffer() != src)
			if(!(src in P.buffer().links))
				LAZYADD(P.buffer().links, src)

			if(!(P.buffer() in src.links))
				LAZYADD(src.links, P.buffer())

			set_temp("-% Successfully linked with \ref[P.buffer()] [P.buffer().name] %-", "average")

		else
			set_temp("-% Unable to acquire buffer %-", "average")
		. = TRUE

UI_ACT(/obj/machinery/telecomms, "buffer", ui_act_buffer)
UI_ACT_PROC(/obj/machinery/telecomms, ui_act_buffer)
	var/obj/item/multitool/P = get_multitool(ui.user)
	if(P)
		P.buffer_handle = om_handle(src)
		set_temp("-% Successfully stored \ref[P.buffer()] [P.buffer().name] in buffer %-", "average")
	. = TRUE

UI_ACT(/obj/machinery/telecomms, "flush", ui_act_flush)
UI_ACT_PROC(/obj/machinery/telecomms, ui_act_flush)
	var/obj/item/multitool/P = get_multitool(ui.user)
	if(P)
		set_temp("-% Buffer successfully flushed. %-", "average")
		P.buffer_handle = null
	. = TRUE

UI_ACT(/obj/machinery/telecomms, "cleartemp", ui_act_cleartemp)
UI_ACT_PROC(/obj/machinery/telecomms, ui_act_cleartemp)
	temp = null
	. = TRUE


/// A telecomms machine setting; re-checked on the answer: the answerer can still access the machine.
/datum/om/prompt/text/telecomms_setting
	requires = PROMPT_USABLE

/datum/om/prompt/text/telecomms_setting/valid()
	var/obj/machinery/telecomms/machine = subject
	return machine.canAccess(answerer) ? null : "no access"

/datum/om/prompt/number/telecomms_setting
	requires = PROMPT_USABLE

/datum/om/prompt/number/telecomms_setting/valid()
	var/obj/machinery/telecomms/machine = subject
	return machine.canAccess(answerer) ? null : "no access"

/obj/machinery/telecomms/proc/id_entered(datum/om/prompt/text/telecomms_setting/ask)
	var/newid = copytext(reject_bad_text(ask.text),1,MAX_MESSAGE_LEN)
	if(newid)
		id = newid
		set_temp("-% New ID assigned: \"[id]\" %-", "average")
		SStgui.update_uis(src)

/obj/machinery/telecomms/proc/network_entered(datum/om/prompt/text/telecomms_setting/ask)
	var/newnet = ask.text
	SStgui.update_uis(src)

	if(length(newnet) > 15)
		set_temp("-% Too many characters in new network tag %-", "average")

	else
		for(var/obj/machinery/telecomms/T in links)
			LAZYREMOVE(T.links, src)

		network = newnet
		links = list()
		set_temp("-% New network tag assigned: \"[network]\" %-", "average")
	. = TRUE

/obj/machinery/telecomms/proc/filter_frequency_entered(datum/om/prompt/number/telecomms_setting/ask)
	var/newfreq = ask.number
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
