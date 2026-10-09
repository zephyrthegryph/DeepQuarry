// The telecommunications machines' window and what a multitool does to them (doc/rewrite/final_api.html, sections 9, 13).
//
// The window opens with a multitool (in hand, or a silicon's own over its link): the multitool is what reads and writes a machine's network
// settings, so every button needs one (req_tcomms_multitool()). A machine reports what a button did on a status line (report()). Its buffer
// buttons store the machine in the multitool and link another machine to the stored one (a link is symmetric: links(), telecomunications.dm);
// the id, the network and a frequency filter are typed answers (asks()). Nanopaste repairs a damaged machine. Machine types add their own
// settings: the relay's receive/broadcast switches and its station lock, the bus's frequency changer, and the range of a ranged machine
// (the receiver and the broadcaster).


MSG_DEF_SELF(tcomms/needs_multitool, "You need a multitool to work its network settings.")
MSG_DEF_SELF(tcomms/no_buffer, "The multitool holds no telecommunications machine to link to.")
MSG_DEF_SELF(tcomms/whole, "This machine is already in perfect condition.")
MSG_DEF(tcomms/repaired, "You apply the Nanopaste to %T%, repairing some of the damage.", "")
MSG_DEF_SELF(tcomms/no_such_link, "There is no such link.")
MSG_DEF_SELF(tcomms/cannot_lock, "It can only change its signal lock on the telecommunications satellite or the station.")

/obj/machinery/telecomms
	maintenance_flags = MACHINE_MAINT_STANDARD
	var/list/temp = null // the status line: list("color", "text")

TRACKED(/obj/machinery/telecomms, temp)

/// req_tcomms_multitool(): the actor has a multitool for the machine (in hand; an AI's own; a cyborg's at the machine).
/proc/req_tcomms_multitool()
	return req_bool(TYPE_PROC_REF(/obj/machinery, actor_has_multitool), because = MSG(tcomms/needs_multitool))

/obj/machinery/proc/actor_has_multitool(datum/act/op/A)
	return !!get_multitool(A.actor)

/obj/machinery/telecomms/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()

	data["temp"] = temp
	data["on"] = running

	data["id"] = null
	data["network"] = null
	data["autolinkers"] = FALSE
	data["shadowlink"] = FALSE
	data["options"] = list()
	data["linked"] = list()
	data["filter"] = list()
	data["multitool"] = FALSE
	data["multitool_buffer"] = null

	if(running || interact_offline)
		data["id"] = id
		data["network"] = network
		data["autolinkers"] = !!LAZYLEN(autolinkers)
		data["shadowlink"] = !!hide

		data["options"] = Options_Menu()

		var/obj/item/multitool/P = get_multitool(user)
		data["multitool"] = !!P
		data["multitool_buffer"] = null
		if(P && P.buffer())
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

// Returns a multitool from a user depending on their mobtype.
/obj/machinery/proc/get_multitool(mob/user as mob)	//No need to have this being a telecomms specific proc.
	var/obj/item/multitool/P = null
	var/obj/item/held = user.get_active_hand()
	if(!issilicon(user))
		P = held?.get_multitool()
	else if(isAI(user))
		var/mob/living/silicon/ai/U = user
		P = U.aiMulti
	else if(isrobot(user) && get_dist(user, src) <= 1)
		P = held?.get_multitool()
	return P

/// The type's own settings in the window (each machine type adds its own; a ranged machine shows its range).
/obj/machinery/telecomms/proc/Options_Menu()
	var/list/data = list()
	if(ranged)
		data[ranged] = TRUE
		data["range"] = overmap_range
		data["minRange"] = overmap_range_min
		data["maxRange"] = overmap_range_max
	return data

/// The status line the window shows: what the last button did.
/obj/machinery/telecomms/proc/report(text, color = "average")
	set_temp(list("color" = color, "text" = text))

/// Whoever presses a button leaves their prints on the machine.
/obj/machinery/telecomms/proc/ui_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/obj/machinery/telecomms/proc/toggle_reported(datum/act/op/A)
	report("-% [src] has been [toggled ? "activated" : "deactivated"].")
	return OP_OK

/obj/machinery/telecomms/proc/id_entered(datum/act/op/A)
	var/datum/prompt/P = A.answer
	var/newid = copytext(reject_bad_text(P?.value), 1, MAX_MESSAGE_LEN)
	if(newid)
		id = newid
		report("-% New ID assigned: \"[id]\" %-")
	return OP_OK

/// A new network breaks every link.
/obj/machinery/telecomms/proc/network_entered(datum/act/op/A)
	var/datum/prompt/P = A.answer
	var/newnet = P?.value
	if(!newnet)
		return OP_OK
	rel_clear(src, nameof(links))
	network = newnet
	report("-% New network tag assigned: \"[network]\" %-")
	return OP_OK

/// A frequency typed in GHz with its decimal ("145.9") is kept in tenths (1459).
/proc/tcomms_tenths(freq)
	if(findtext(num2text(freq), "."))
		freq *= 10
	return freq

/obj/machinery/telecomms/proc/filter_frequency_entered(datum/act/op/A)
	var/datum/prompt/P = A.answer
	var/newfreq = P?.value
	if(!newfreq)
		return OP_OK
	newfreq = tcomms_tenths(newfreq)
	if(!(newfreq in freq_listening) && newfreq < TCOMMS_FREQ_LIMIT)
		LAZYADD(freq_listening, newfreq)
		report("-% New frequency filter assigned: \"[newfreq / 10] GHz\" %-")
	return OP_OK

/obj/machinery/telecomms/proc/ui_act_delete(datum/act/op/A, delete)
	LAZYREMOVE(freq_listening, delete)
	report("-% Removed frequency filter [delete] %-")
	return OP_OK

/// needs: the link the button names is one of the machine's.
/obj/machinery/telecomms/proc/link_index_valid(datum/act/op/A)
	var/index = A.args["unlink"]
	return isnum(index) && index >= 1 && index <= LAZYLEN(links)

/obj/machinery/telecomms/proc/ui_act_unlink(datum/act/op/A, unlink)
	var/obj/machinery/telecomms/T = LAZYACCESS(links, unlink)
	report("-% Removed \ref[T] [T.name] from linked entities. %-")
	rel_remove(src, nameof(links), T)
	return OP_OK

/// needs: the actor's multitool holds another telecommunications machine to link to.
/obj/machinery/telecomms/proc/buffer_linkable(datum/act/op/A)
	var/obj/item/multitool/P = get_multitool(A.actor)
	var/obj/machinery/telecomms/T = P?.buffer()
	return istype(T) && T != src

/obj/machinery/telecomms/proc/ui_act_link(datum/act/op/A)
	var/obj/item/multitool/P = get_multitool(A.actor)
	rel_add(src, nameof(links), P.buffer())
	report("-% Successfully linked with \ref[P.buffer()] [P.buffer().name] %-")
	return OP_OK

/obj/machinery/telecomms/proc/ui_act_buffer(datum/act/op/A)
	var/obj/item/multitool/P = get_multitool(A.actor)
	rel_set(P, nameof(/obj/item/multitool::buffer), src)
	report("-% Successfully stored \ref[src] [name] in buffer %-")
	return OP_OK

/obj/machinery/telecomms/proc/ui_act_flush(datum/act/op/A)
	var/obj/item/multitool/P = get_multitool(A.actor)
	rel_clear(P, nameof(/obj/item/multitool::buffer))
	report("-% Buffer successfully flushed. %-")
	return OP_OK

/obj/machinery/telecomms/proc/ui_act_cleartemp(datum/act/op/A)
	set_temp(null)
	return OP_OK

/// A ranged machine's range, within what it can do; a longer range draws more power.
/obj/machinery/telecomms/proc/ui_act_range(datum/act/op/A, range)
	overmap_range = clamp(range, overmap_range_min, overmap_range_max)
	update_idle_power_usage(initial(idle_power_usage) ** (overmap_range + 1))
	return OP_OK

/// needs: the machine is damaged.
/obj/machinery/telecomms/proc/damaged(datum/act/op/A)
	return get_integrity() < max_integrity // ALLOW(reads): the machine's integrity is asked when the paste is applied, never cached

/// Nanopaste repairs 10 to 20 integrity.
/obj/machinery/telecomms/proc/nanopaste_repair(datum/act/op/A)
	repair_damage(rand(10, 20))
	return OP_OK

// ---- the relay ----

CAPABILITIES(/obj/machinery/telecomms/relay)
	op("receive", ui_act(), toggles(nameof(receiving)), then(PROC_REF(receiving_reported)))
	op("broadcast", ui_act(), toggles(nameof(broadcasting)), then(PROC_REF(broadcasting_reported)))
	op("change_listening", ui_act("change_listening"), needs(req_bool(PROC_REF(can_change_level), because = MSG(tcomms/cannot_lock))), then(PROC_REF(ui_act_change_listening)))

/obj/machinery/telecomms/relay/Options_Menu()
	var/list/data = ..()
	data["use_listening_level"] = TRUE
	data["use_broadcasting"] = TRUE
	data["use_receiving"] = TRUE
	data["listening_level"] = (listening_level == TCOMMS_STATION_Z)
	data["broadcasting"] = broadcasting
	data["receiving"] = receiving
	return data

/obj/machinery/telecomms/relay/proc/receiving_reported(datum/act/op/A)
	report("-% Receiving mode changed. %-")
	return OP_OK

/obj/machinery/telecomms/relay/proc/broadcasting_reported(datum/act/op/A)
	report("-% Broadcasting mode changed. %-")
	return OP_OK

/// needs: the relay listens to the station now (it can go back to its own level), or stands on the satellite (it can lock onto the station).
/obj/machinery/telecomms/relay/proc/can_change_level(datum/act/op/A)
	return listening_level == TCOMMS_STATION_Z || z == TCOMMS_SATELLITE_Z // ALLOW(reads): the relay's level is asked when the button is pressed

/// Locks the relay's signal onto the station, or back onto its own level.
/obj/machinery/telecomms/relay/proc/ui_act_change_listening(datum/act/op/A)
	listening_level = (listening_level == TCOMMS_STATION_Z) ? z : TCOMMS_STATION_Z
	report("-% [src]'s signal has been successfully changed.")
	return OP_OK

// ---- the bus ----

CAPABILITIES(/obj/machinery/telecomms/bus)
	op("change_freq", ui_act("change_freq"), asks(/datum/prompt/number, fields = list("question" = "Specify a new frequency for new signals to change to. Enter 0 to turn off frequency changing. Decimals assigned automatically.", "default" = computed(PROC_REF(change_freq_default)))), then(PROC_REF(change_frequency_entered)))

/obj/machinery/telecomms/bus/Options_Menu()
	var/list/data = ..()
	data["use_change_freq"] = TRUE
	data["change_freq"] = change_frequency
	return data

/// The question's default: the frequency it changes to now, in GHz.
/obj/machinery/telecomms/bus/proc/change_freq_default(datum/act/op/A)
	return change_frequency ? change_frequency / 10 : 0

/// The answer is the frequency signals change to; 0 turns frequency changing off.
/obj/machinery/telecomms/bus/proc/change_frequency_entered(datum/act/op/A)
	var/datum/prompt/P = A.answer
	set_change_frequency(P?.value)
	return OP_OK

/obj/machinery/telecomms/bus/proc/set_change_frequency(newfreq)
	if(!newfreq)
		change_frequency = ZERO_FREQ
		report("-% Frequency changing deactivated %-")
		return
	newfreq = tcomms_tenths(newfreq)
	if(newfreq < TCOMMS_FREQ_LIMIT)
		change_frequency = newfreq
		report("-% New frequency to change to assigned: \"[newfreq] GHz\" %-")

// ---- ranged machines: the receiver and the broadcaster ----

/obj/machinery/telecomms/broadcaster
	interact_offline = TRUE // because you can accidentally nuke power grids with these, need to be able to fix mistake
	ranged = "use_broadcast_range"

/obj/machinery/telecomms/receiver
	interact_offline = TRUE // because you can accidentally nuke power grids with these, need to be able to fix mistake
	ranged = "use_receive_range"
