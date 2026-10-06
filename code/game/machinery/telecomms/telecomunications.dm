// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32

/*
	Hello, friends, this is Doohl from sexylands. You may be wondering what this
	monstrous code file is. Sit down, boys and girls, while I tell you the tale.

	The machines defined in this file were designed to be compatible with any radio
	signals, provided they use subspace transmission. Currently they are only used for
	headsets, but they can eventually be outfitted for real COMPUTER networks. This
	is just a skeleton, ladies and gentlemen.

	Look at radio.dm for the prequel to this code.
*/

/obj/machinery/telecomms
	icon = 'icons/obj/stationobjs.dmi'
	unacidable = TRUE
	var/list/links // list of machines this machine is linked to
	var/traffic = 0 // value increases as traffic increases
	var/netspeed = 5 // how much traffic to lose per tick (50 gigabytes/second * netspeed)
	var/list/autolinkers // list of text/number values to link with
	var/id = "NULL" // identification string
	var/network = "NULL" // the network of the machinery

	var/list/freq_listening // list of frequencies to tune into: if none, will listen to all

	var/machinetype = 0 // just a hacky way of preventing alike machines from pairing
	var/toggled = TRUE 	// switched on (it runs while switched on and working: STAT running)
	max_integrity = 100
	var/produces_heat = 1	//whether the machine will produce heat when on.
	heat_output = 1 // scaled by current_heat_output()
	/// Dissipates its idle heat a few kelvin above the room.
	heat_dissipation = 200
	var/delay = 10 // how many machine frames between its thermal steps, less one
	var/long_range_link = 0	// Can you link it across Z levels or on the otherside of the map? (Relay & Hub)
	var/hide = 0				// Is it a hidden machine?
	var/listening_level = 0	// 0 = auto set in New() - this is the z level that the machine is listening to.

	var/datum/looping_sound/tcomms/soundloop

	/// The range of a ranged machine (the receiver, the broadcaster): the name of its window option, or FALSE.
	var/ranged = FALSE
	var/overmap_range = 0
	var/overmap_range_min = 0
	var/overmap_range_max = 5

TRACKED(/obj/machinery/telecomms, toggled)
/// Whether the node passes signals: switched on and working.
STAT(/obj/machinery/telecomms, running, ALL)


// A telecommunications node (doc/rewrite/final_api.html, sections 5, 6, 16.13). It runs while switched on and working (STAT running); running,
// it hums, heats its room with its traffic and lets its traffic decay a little every thermal step; stopped, it is silent, cold and drawn off.
// Links are symmetric membership: linking A to B lists each in the other's links, and a dying machine leaves every partner's list (the
// framework clears both sides). A pulse knocks it out for a while (emp_disable()).
CAPABILITIES(/obj/machinery/telecomms)
	after_init(0, then(PROC_REF(autolink)))
	links(/obj/machinery/telecomms::links, /obj/machinery/telecomms::links, a_many = TRUE, b_many = TRUE)
	owns_one(nameof(soundloop), /datum/looping_sound/tcomms, starts = PROC_REF(make_soundloop))
	contributes(STAT_RUNNING, nameof(toggled))
	contributes(STAT_OPERABLE, TYPE_PROC_REF(/obj/machinery, stat_bits_allow), reads = list("stat"))
	contributes(STAT_RUNNING, STAT_OPERABLE)
	on_change(STAT_RUNNING, ANY, then(PROC_REF(running_changed)))
	emp_disable(PROC_REF(emp_outage))
	every(PROC_REF(thermal_interval), then(PROC_REF(thermal_step)), when = STAT_RUNNING)
	on_change(STAT_OPERABLE, ANY, then(PROC_REF(emp_state_changed)))
	section(window, "The multitool window and what a multitool and nanopaste do (machine_interactions.dm)")
	interface("TelecommsMultitoolMenu", input = tool(TOOL_MULTITOOL))
	extend(TAG_UI, needs(req_tcomms_multitool()))
	extend("ui_open", needs(req_tcomms_multitool()))
	extend(TAG_UI, then(PROC_REF(ui_fingerprint), early = TRUE))
	op("toggle", ui_act("toggle"), toggles(nameof(toggled)), then(PROC_REF(toggle_reported)))
	op("id", ui_act("id"), asks(/datum/prompt/text, fields = list("question" = "Specify the new ID for this machine", "default" = nameof(id))), then(PROC_REF(id_entered)))
	op("network", ui_act("network"), asks(/datum/prompt/text, fields = list("question" = "Specify the new network for this machine. This will break all current links.", "default" = nameof(network), "max_len" = TCOMMS_NETWORK_MAX_LEN)), then(PROC_REF(network_entered)))
	op("freq", ui_act("freq"), asks(/datum/prompt/number, fields = list("question" = "Specify a new frequency to filter (GHz). Decimals assigned automatically.", "max_value" = 9999)), then(PROC_REF(filter_frequency_entered)))
	op("delete", ui_act("delete", arg("delete", num())), then(PROC_REF(ui_act_delete)))
	op("unlink", ui_act("unlink", arg("unlink", num())), needs(req(PROC_REF(link_index_valid), because = MSG(tcomms/no_such_link))), then(PROC_REF(ui_act_unlink)))
	op("link", ui_act("link"), needs(req(PROC_REF(buffer_linkable), because = MSG(tcomms/no_buffer))), then(PROC_REF(ui_act_link)))
	op("buffer", ui_act("buffer"), then(PROC_REF(ui_act_buffer)))
	op("flush", ui_act("flush"), then(PROC_REF(ui_act_flush)))
	op("cleartemp", ui_act("cleartemp"), then(PROC_REF(ui_act_cleartemp)))
	op("range", ui_act("range", arg("range", num())), when(nameof(ranged)), then(PROC_REF(ui_act_range)))
	op("repair", stack(/obj/item/stack/nanopaste, 1), needs(req(PROC_REF(damaged), because = MSG(tcomms/whole))), says(MSG(tcomms/repaired)), then(PROC_REF(nanopaste_repair)))

/obj/machinery/telecomms/proc/relay_information(datum/signal/signal, filter, copysig, amount = 20)
	// relay signal to all linked machinery that are of type [filter]. If signal has been sent [amount] times, stop sending

	if(!running)
		return
	var/send_count = 0

	signal.data["slow"] += rand(0, round(100 - (100 * get_integrity() / max_integrity)))

	/*
	// Edit by Atlantis: Commented out as emergency fix due to causing extreme delays in communications.
	// Apply some lag based on traffic rates
	var/netlag = round(traffic / 50)
	if(netlag > signal.data["slow"])
		signal.data["slow"] = netlag
	*/
// Loop through all linked machines and send the signal or copy.
	for(var/obj/machinery/telecomms/machine in links)
		if(filter && !istype(machine, filter))
			continue
		if(!machine.running)
			continue
		if(amount && send_count >= amount)
			break
		if(machine.loc.z != listening_level)
			if(long_range_link == 0 && machine.long_range_link == 0)
				continue
		// If we're sending a copy, be sure to create the copy for EACH machine and paste the data
		var/datum/signal/copy
		if(copysig)
			copy = new
			copy.transmission_method = TRANSMISSION_SUBSPACE
			copy.frequency = signal.frequency
			copy.data = signal.data.Copy()

			// Keep the "original" signal constant
			if(!signal.data["original"])
				copy.data["original"] = signal // ALLOW(ownership): signal payload data, transient message dict
			else
				copy.data["original"] = signal.data["original"]

		send_count++
		if(machine.is_freq_listening(signal))
			machine.traffic++

		if(copysig && copy)
			machine.receive_information(copy, src)
		else
			machine.receive_information(signal, src)

	if(send_count > 0 && is_freq_listening(signal))
		traffic++

	return send_count

/obj/machinery/telecomms/proc/relay_direct_information(datum/signal/signal, obj/machinery/telecomms/machine)
	// send signal directly to a machine
	machine.receive_information(signal, src)

/obj/machinery/telecomms/proc/receive_information(datum/signal/signal, obj/machinery/telecomms/machine_from)
	// receive information from linked machinery
	return

/obj/machinery/telecomms/proc/receive_information_delayed(datum/signal/signal, obj/machinery/telecomms/machine_from)
	// The second half of receive_information(), called after the slowness delay from its first half.
	PROTECTED_PROC(TRUE)
	return

/obj/machinery/telecomms/proc/is_freq_listening(datum/signal/signal)
	// return 1 if found, 0 if not found
	if(!signal)
		return 0
	if((signal.frequency in freq_listening) || (!length(freq_listening)))
		return 1
	else
		return 0

REGISTRY_MEMBERSHIP(/obj/machinery/telecomms, REGISTRY_TELECOMMS)

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with
/obj/machinery/telecomms/Initialize(mapload)
	. = ..()
	default_apply_parts()

/// Sets its listening level and links the machines it names, once they all exist.
/obj/machinery/telecomms/proc/autolink(datum/act/timer/A)
	//Set the listening_level if there's none.
	if(!listening_level)
		//Defaults to our Z level!
		var/turf/position = get_turf(src)
		listening_level = position.z

	if(length(autolinkers))
		// Links nearby machines
		if(!long_range_link)
			for(var/obj/machinery/telecomms/T in orange(TCOMMS_AUTOLINK_RANGE, src))
				add_link(T)
		else
			for(var/obj/machinery/telecomms/T in REGISTRY_MEMBERS(REGISTRY_TELECOMMS))
				add_link(T)
	if(running)
		soundloop?.start()

/// Its hum: one machine in four-ish hums another of three midloops.
/obj/machinery/telecomms/proc/make_soundloop(datum/act/A)
	var/datum/looping_sound/tcomms/S = new(list(src), FALSE)
	if(prob(60))
		if(prob(40))
			S.mid_sounds = list('sound/machines/tcomms/tcomms_02.ogg' = 1)
			S.mid_length = 40
		else if(prob(20))
			S.mid_sounds = list('sound/machines/tcomms/tcomms_03.ogg' = 1)
			S.mid_length = 10
		else
			S.mid_sounds = list('sound/machines/tcomms/tcomms_04.ogg' = 1)
			S.mid_length = 30
	return S


// Used in auto linking
/obj/machinery/telecomms/proc/add_link(obj/machinery/telecomms/T)
	var/pos_z = get_z(src)
	var/tpos_z = get_z(T)
	if((pos_z == tpos_z) || (src.long_range_link && T.long_range_link))
		for(var/x in autolinkers)
			if(LAZYFIND(T.autolinkers, x))
				if(src != T)
					rel_add(src, nameof(links), T)

/// Drawn running, or off.
/obj/machinery/telecomms/draw(datum/look/look)
	..()
	look.state(running ? initial(icon_state) : "[initial(icon_state)]_off")

/// Started or stopped: the hum, the heat it gives off and its look follow.
/obj/machinery/telecomms/proc/running_changed(datum/act/A)
	if(running)
		soundloop?.start()
	else
		soundloop?.stop()
	update_heat_output()

/// How long between thermal steps: `delay` + 1 machine frames.
/obj/machinery/telecomms/proc/thermal_interval(datum/act/A)
	return (initial(delay) + 1) * MACHINE_SERVICE_INTERVAL

/// One thermal step of a running node: its traffic decays by its net speed, and its heat follows.
/obj/machinery/telecomms/proc/thermal_step(datum/act/timer/A)
	if(traffic > 0)
		traffic = max(traffic - netspeed, 0)
	update_heat_output()

/// emp_disable()'s outage: 300 s over the severity, and weaker pulses only sometimes knock a telecomms machine out.
/obj/machinery/telecomms/proc/emp_outage(severity)
	if(!prob(100 / max(severity, 1)))
		return 0
	return 300 SECONDS / max(severity, 1)

/// A pulse knocked it out: the pulse sound.
/obj/machinery/telecomms/proc/emp_state_changed(datum/act/A)
	if(emp_disabled(src))
		play_sfx(src, SFX_MACHINES_TCOMMS_TCOMMS_PULSE)

/// Telecomms heat: idle_power_usage while on, 30% with no traffic. It goes
/// through the machine's heat body (heat_objects.dm); overheating is the
/// overheating rule at the telecomms heat limit (temperature_thresholds.dm).
/obj/machinery/telecomms/current_heat_output()
	if(!produces_heat || !running || !use_power)
		return 0
	return traffic > 0 ? idle_power_usage : idle_power_usage * 0.3

/*
	The receiver idles and receives messages from subspace-compatible radio equipment;
	primarily headsets. They then just relay this information to all linked devices,
	which can would probably be network hubs.

	Link to Processor Units in case receiver can't send to bus units.
*/

/obj/machinery/telecomms/receiver
	name = "Subspace Receiver"
	// icon = 'icons/obj/stationobjs.dmi' // Removal - use parent icon
	icon_state = "broadcast receiver"
	desc = "This machine has a dish-like shape and green lights. It is designed to detect and process subspace radio activity."
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 600
	machinetype = 1
	produces_heat = 0
	circuit = /obj/item/circuitboard/telecomms/receiver

	// Bluespace radios that transmit to this receiver are BS_TX_RADIOS(src).

/obj/machinery/telecomms/receiver/receive_signal(datum/signal/signal)
	if(!running) // has to be on to receive messages
		return
	if(!signal)
		return
	if(!check_receive_level(signal))
		return

	if(signal.transmission_method == TRANSMISSION_SUBSPACE)

		if(is_freq_listening(signal)) // detect subspace signals

			//Remove the level and then start adding levels that it is being broadcasted in.
			signal.data["level"] = list()

			var/can_send = relay_information(signal, /obj/machinery/telecomms/hub) // ideally relay the copied information to relays
			if(!can_send)
				relay_information(signal, /obj/machinery/telecomms/bus) // Send it to a bus instead, if it's linked to one

/obj/machinery/telecomms/receiver/proc/check_receive_level(datum/signal/signal)
	// If it's a direct message from a bluespace radio, we eat it and convert it into a subspace signal locally
	if(signal.transmission_method == TRANSMISSION_BLUESPACE)
		var/obj/item/radio/R = signal.data["radio"]

		//Who're you?
		if(!R || R?.bs_tx_target() != src)
			signal.data["reject"] = 1
			return 0

		//We'll resend this for you
		signal.data["level"] = z
		signal.transmission_method = TRANSMISSION_SUBSPACE
		return 1

	//Where can we hear?
	var/list/listening_levels = using_map.get_map_levels(listening_level, TRUE, overmap_range)

	// We couldn't 'hear' it, maybe a relay linked to our hub can 'hear' it
	if(!(signal.data["level"] in listening_levels))
		for(var/obj/machinery/telecomms/hub/H in links)
			var/list/relayed_levels = list()
			for(var/obj/machinery/telecomms/relay/R in H.links)
				if(R.can_receive(signal))
					relayed_levels |= R.listening_level
			if(signal.data["level"] in relayed_levels)
				return 1
		return 0
	return 1

/*
	The HUB idles until it receives information. It then passes on that information
	depending on where it came from.

	This is the heart of the Telecommunications Network, sending information where it
	is needed. It mainly receives information from long-distance Relays and then sends
	that information to be processed. Afterwards it gets the uncompressed information
	from Servers/Buses and sends that back to the relay, to then be broadcasted.
*/

/obj/machinery/telecomms/hub
	name = "Telecommunication Hub"
	// icon = 'icons/obj/stationobjs.dmi' // Removal - use parent icon
	icon_state = "hub"
	desc = "A mighty piece of hardware used to send/receive massive amounts of data."
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 1600
	machinetype = 7
	circuit = /obj/item/circuitboard/telecomms/hub
	long_range_link = 1
	netspeed = 40

/obj/machinery/telecomms/hub/receive_information(datum/signal/signal, obj/machinery/telecomms/machine_from)
	if(is_freq_listening(signal))
		if(istype(machine_from, /obj/machinery/telecomms/receiver))
			//If the signal is compressed, send it to the bus.
			relay_information(signal, /obj/machinery/telecomms/bus, 1) // ideally relay the copied information to bus units
		else
			// Get a list of relays that we're linked to, then send the signal to their levels.
			relay_information(signal, /obj/machinery/telecomms/relay, 1)
			relay_information(signal, /obj/machinery/telecomms/broadcaster, 1) // Send it to a broadcaster.

/*
	The relay idles until it receives information. It then passes on that information
	depending on where it came from.

	The relay is needed in order to send information pass Z levels. It must be linked
	with a HUB, the only other machine that can send/receive pass Z levels.
*/

/obj/machinery/telecomms/relay
	name = "Telecommunication Relay"
	// icon = 'icons/obj/stationobjs.dmi' // Removal - use parent icon
	icon_state = "relay"
	desc = "A mighty piece of hardware used to send massive amounts of data far away."
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 600
	machinetype = 8
	produces_heat = 0
	circuit = /obj/item/circuitboard/telecomms/relay
	netspeed = 5
	long_range_link = 1
	var/broadcasting = 1
	var/receiving = 1

/obj/machinery/telecomms/relay/forceMove(atom/destination, direction, movetime)
	. = ..(destination, direction, movetime)
	listening_level = z

/obj/machinery/telecomms/relay/receive_information(datum/signal/signal, obj/machinery/telecomms/machine_from)

	// Add our level and send it back
	if(can_send(signal))
		signal.data["level"] |= using_map.get_map_levels(listening_level)

// Checks to see if it can send/receive.

/obj/machinery/telecomms/relay/proc/can(datum/signal/signal)
	if(!running)
		return 0
	if(!is_freq_listening(signal))
		return 0
	return 1

/obj/machinery/telecomms/relay/proc/can_send(datum/signal/signal)
	if(!can(signal))
		return 0
	return broadcasting

/obj/machinery/telecomms/relay/proc/can_receive(datum/signal/signal)
	if(!can(signal))
		return 0
	return receiving

/*
	The bus mainframe idles and waits for hubs to relay them signals. They act
	as junctions for the network.

	They transfer uncompressed subspace packets to processor units, and then take
	the processed packet to a server for logging.

	Link to a subspace hub if it can't send to a server.
*/

/obj/machinery/telecomms/bus
	name = "Bus Mainframe"
	// icon = 'icons/obj/stationobjs.dmi' // Removal - use parent icon
	icon_state = "bus"
	desc = "A mighty piece of hardware used to send massive amounts of data quickly."
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 1000
	machinetype = 2
	circuit = /obj/item/circuitboard/telecomms/bus
	netspeed = 40
	var/change_frequency = ZERO_FREQ

/obj/machinery/telecomms/bus/receive_information(datum/signal/signal, obj/machinery/telecomms/machine_from)

	if(is_freq_listening(signal))

		if(change_frequency)
			signal.frequency = change_frequency

		if(!istype(machine_from, /obj/machinery/telecomms/processor) && machine_from != src) // Signal must be ready (stupid assuming machine), let's send it
			// send to one linked processor unit
			var/send_to_processor = relay_information(signal, /obj/machinery/telecomms/processor)

			if(send_to_processor)
				return
			// failed to send to a processor, relay information anyway
			signal.data["slow"] += rand(1, 5) // slow the signal down only slightly
			src.receive_information(signal, src)

		// Try sending it!
		var/static/list/try_send = list(/obj/machinery/telecomms/server, /obj/machinery/telecomms/hub, /obj/machinery/telecomms/broadcaster, /obj/machinery/telecomms/bus)
		var/i = 0
		for(var/send in try_send)
			if(i)
				signal.data["slow"] += rand(0, 1) // slow the signal down only slightly
			i++
			var/can_send = relay_information(signal, send)
			if(can_send)
				break

/*
	The processor is a very simple machine that decompresses subspace signals and
	transfers them back to the original bus. It is essential in producing audible
	data.

	Link to servers if bus is not present
*/

/obj/machinery/telecomms/processor
	name = "Processor Unit"
	// icon = 'icons/obj/stationobjs.dmi' // Removal - use parent icon
	icon_state = "processor"
	desc = "This machine is used to process large quantities of information."
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 600
	machinetype = 3
	delay = 5
	circuit = /obj/item/circuitboard/telecomms/processor
	var/process_mode = 1 // 1 = Uncompress Signals, 0 = Compress Signals

/obj/machinery/telecomms/processor/receive_information(datum/signal/signal, obj/machinery/telecomms/machine_from)

	if(is_freq_listening(signal))

		if(process_mode)
			signal.data["compression"] = 0 // uncompress subspace signal
		else
			signal.data["compression"] = 100 // even more compressed signal

		if(istype(machine_from, /obj/machinery/telecomms/bus))
			relay_direct_information(signal, machine_from) // send the signal back to the machine
		else // no bus detected - send the signal to servers instead
			signal.data["slow"] += rand(5, 10) // slow the signal down
			relay_information(signal, /obj/machinery/telecomms/server)

/*
	The server logs all traffic and signal data. Once it records the signal, it sends
	it to the subspace broadcaster.

	Store a maximum of 100 logs and then deletes them.
*/

/obj/machinery/telecomms/server
	name = "Telecommunication Server"
	// icon = 'icons/obj/stationobjs.dmi' // Removal - use parent icon
	icon_state = "comm_server"
	desc = "A machine used to store data and network statistics."
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 300
	machinetype = 4
	circuit = /obj/item/circuitboard/telecomms/server
	var/list/log_entries
	var/list/stored_names
	var/list/TrafficActions
	var/totaltraffic = 0 // gigabytes (if > 1024, divide by 1024 -> terrabytes)

	// ALLOW(instance_list): d: telecomms server state
	var/list/memory = list()	// stored memory
	var/rawcode = ""	// the code to compile (raw text)
	var/datum/TCS_Compiler/Compiler	// the compiler that compiles and runs the code
	var/autoruncode = 0		// 1 if the code is set to run every time a signal is picked up

	var/encryption = "null" // encryption key: ie "password"
	var/salt = "null"		// encryption salt: ie "123comsat"
							// would add up to md5("password123comsat")
	var/obj/item/radio/headset/server_radio = null


CAPABILITIES(/obj/machinery/telecomms/server)
	owns_one(nameof(Compiler), /datum/TCS_Compiler, starts = PROC_REF(make_compiler))
	owns_one(nameof(server_radio), /obj/item/radio/headset, starts = /obj/item/radio/headset)
	owns_many(nameof(log_entries))

/// The server's script compiler, held by it.
/obj/machinery/telecomms/server/proc/make_compiler(datum/act/A)
	var/datum/TCS_Compiler/C = new
	rel_set(C, nameof(C.Holder), src)
	return C

/obj/machinery/telecomms/server/receive_information(datum/signal/signal, obj/machinery/telecomms/machine_from)

	if(signal.data["message"])

		if(is_freq_listening(signal))

			if(traffic > 0)
				totaltraffic += traffic // add current traffic to total traffic

			//Is this a test signal? Bypass logging
			if(signal.data["type"] != SIGNAL_TEST)

				// If signal has a message and appropriate frequency

				update_logs()

				var/datum/comm_log_entry/log = new
				var/mob/M = signal.data["mob"]

				// Copy the signal.data entries we want
				LAZYSET(log.parameters, "mobtype", signal.data["mobtype"])
				log.parameters["job"] = signal.data["job"]
				log.parameters["key"] = signal.data["key"]
				log.parameters["vmessage"] = multilingual_to_message(signal.data["message"])
				log.parameters["vname"] = signal.data["vname"]
				log.parameters["message"] = multilingual_to_message(signal.data["message"])
				log.parameters["name"] = signal.data["name"]
				log.parameters["realname"] = signal.data["realname"]
				log.parameters["timecode"] = worldtime2stationtime(world.time)

				var/race = "unknown"
				if(ishuman(M))
					var/mob/living/carbon/human/H = M
					race = "[H.species.name]"
					log.parameters["intelligible"] = 1
				else if(isbrain(M))
					race = "Brain"
					log.parameters["intelligible"] = 1
				else if(M?.isMonkey())
					race = "Monkey"
				else if(issilicon(M))
					race = "Artificial Life"
					log.parameters["intelligible"] = 1
				else if(isslime(M))
					race = "Slime"
				else if(isanimal(M))
					race = "Domestic Animal"

				log.parameters["race"] = race

				if(!isnewplayer(M) && M)
					log.parameters["uspeech"] = M.universal_speak
				else
					log.parameters["uspeech"] = 0

				// If the signal is still compressed, make the log entry gibberish
				if(signal.data["compression"] > 0)
					log.parameters["message"] = Gibberish(multilingual_to_message(signal.data["message"]), signal.data["compression"] + 50)
					log.parameters["job"] = Gibberish(signal.data["job"], signal.data["compression"] + 50)
					log.parameters["name"] = Gibberish(signal.data["name"], signal.data["compression"] + 50)
					log.parameters["realname"] = Gibberish(signal.data["realname"], signal.data["compression"] + 50)
					log.parameters["vname"] = Gibberish(signal.data["vname"], signal.data["compression"] + 50)
					log.input_type = "Corrupt File"

				// Log and store everything that needs to be logged
				rel_add(src, nameof(log_entries), log)
				if(!(signal.data["name"] in stored_names))
					LAZYADD(stored_names, signal.data["name"])
				signal.data["server"] = src // ALLOW(ownership): signal payload data, transient message dict

				// Give the log a name
				var/identifier = num2text( rand(-1000,1000) + world.time )
				log.name = "data packet ([md5(identifier)])"

				if(Compiler && autoruncode)
					if(!Compiler.Run(signal, relay = TRUE))	// execute the code
						return // the script sleeps: it relays the signal when it is done

			relay_signal(signal)

/// Sends a processed signal on: to a hub, or straight to the broadcasters.
/obj/machinery/telecomms/server/proc/relay_signal(datum/signal/signal)
	var/can_send = relay_information(signal, /obj/machinery/telecomms/hub)
	if(!can_send)
		relay_information(signal, /obj/machinery/telecomms/broadcaster)

/obj/machinery/telecomms/server/proc/setcode(t)
	if(t)
		if(istext(t))
			rawcode = t

/obj/machinery/telecomms/server/proc/compile()
	if(Compiler)
		return Compiler.Compile(rawcode)

/// A full log drops its oldest entry that may be collected (the count is the log's own length, so a deleted entry frees its place).
/obj/machinery/telecomms/server/proc/update_logs()
	if(LAZYLEN(log_entries) < TCOMMS_SERVER_MAX_LOGS)
		return
	for(var/datum/comm_log_entry/L as anything in log_entries)
		if(L.garbage_collector)
			rel_remove(src, nameof(log_entries), L)
			return

/obj/machinery/telecomms/server/proc/add_entry(content, input)
	var/datum/comm_log_entry/log = new
	var/identifier = num2text( rand(-1000,1000) + world.time )
	log.name = "[input] ([md5(identifier)])"
	log.input_type = input
	LAZYSET(log.parameters, "message", content)
	log.parameters["timecode"] = stationtime2text()
	rel_add(src, nameof(log_entries), log)
	update_logs()

// Simple log entry datum

/datum/comm_log_entry
	var/parameters // lazily populated carbon-copy to signal.data[]
	var/name = "data packet (#)"
	var/garbage_collector = 1 // if set to 0, will not be garbage collected
	var/input_type = "Speech File"

//Generic telecomm connectivity test proc
/proc/can_telecomm(atom/A, atom/B, ad_hoc = FALSE)
	if(!A || !B)
		log_mapping("can_telecomm(): Undefined endpoints!")
		return FALSE

	//Can't in this case, obviously!
	if(is_jammed(A) || is_jammed(B))
		return FALSE

	//Items don't have a Z when inside an object or mob
	var/turf/src_z = get_z(A)
	var/turf/dst_z = get_z(B)

	//Nullspace, probably.
	if(!src_z || !dst_z)
		return FALSE

	//We can do the simple check first, if you have ad_hoc radios.
	if(ad_hoc && src_z == dst_z)
		return TRUE

	return src_z in using_map.get_map_levels(dst_z, TRUE, om_range = DEFAULT_OVERMAP_RANGE)
