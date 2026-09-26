// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

#define REGULATE_NONE	0
#define REGULATE_INPUT	1	//shuts off when input side is below the target pressure
#define REGULATE_OUTPUT	2	//shuts off when output side is above the target pressure

/obj/machinery/atmospherics/binary/passive_gate
	icon = 'icons/atmos/passive_gate.dmi'
	icon_state = "map"
	construction_type = /obj/item/pipe/directional
	pipe_state = "passivegate"
	level = 1

	name = "pressure regulator"
	desc = "A one-way air valve that can be used to regulate input or output pressure, and flow rate. Does not require power."

	use_power = USE_POWER_OFF
	interact_offline = TRUE

	var/unlocked = 0	//If 0, then the valve is locked closed, otherwise it is open(-able, it's a one-way valve so it closes if gas would flow backwards).
	var/target_pressure = ONE_ATMOSPHERE
	var/max_pressure_setting = 15000	//kPa
	var/set_flow_rate = ATMOS_DEFAULT_VOLUME_PUMP * 2.5
	var/regulate_mode = REGULATE_OUTPUT

	var/flowing = 0	//for icons - becomes zero if the valve closes itself due to regulation mode

	var/frequency = ZERO_FREQ
	var/id = null
	var/datum/radio_frequency/radio_connection

/obj/machinery/atmospherics/binary/passive_gate/Initialize(mapload)
	. = ..()
	air1.set_volume(ATMOS_DEFAULT_VOLUME_PUMP * 2.5)
	air2.set_volume(ATMOS_DEFAULT_VOLUME_PUMP * 2.5)
	if(frequency)
		set_frequency(frequency)
	// M2: the base /obj/machinery/Initialize() always schedules new machines
	// onto SSmachines; this one has no process() at all (its flow law is a
	// Rust device edge, stepped from SSair, not DM's process() scheduler).
	STOP_MACHINE_PROCESSING(src)

/obj/machinery/atmospherics/binary/passive_gate/Destroy()
	unregister_radio(src, frequency)
	. = ..()

// M2 (simulation.md §5): the flow law lives on the Rust device edge and runs
// every gas tick regardless of DM's process() scheduling. rust_bind_pipe_port
// fires once per port, after that port's region exists in Rust (map setup's
// setup_rust_pipenets() and runtime construction's rust_register_pipe_topology()
// both commit topology before binding), so re-publishing the device edge once
// the second port is bound is the earliest point both of its ports are live.
/obj/machinery/atmospherics/binary/passive_gate/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	if(index == 2)
		update_rust_device()

/obj/machinery/atmospherics/binary/passive_gate/proc/update_rust_device()
	if(!unlocked)
		rust_unregister_device()
		flowing = FALSE
		return
	rust_set_device(1, 2)
	switch(regulate_mode)
		if(REGULATE_INPUT)
			rust_set_device_flow(0, RUST_FLOW_VOLUME, set_flow_rate, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_AT_MOST, target_pressure)
		if(REGULATE_OUTPUT)
			rust_set_device_flow(0, RUST_FLOW_VOLUME, set_flow_rate, RUST_DIR_FORCED, RUST_SIDE_B, RUST_STOP_AT_LEAST, target_pressure)
		else
			rust_set_device_flow(0, RUST_FLOW_VOLUME, set_flow_rate, RUST_DIR_DOWNHILL, RUST_SIDE_A, RUST_STOP_NONE, 0)

/obj/machinery/atmospherics/binary/passive_gate/rust_device_stepped(moles, power_w, target_reached)
	last_flow_rate = abs(moles)
	var/new_flowing = (moles != 0)
	if(new_flowing != flowing)
		flowing = new_flowing
		update_icon()

/obj/machinery/atmospherics/binary/passive_gate/disconnect(obj/machinery/atmospherics/reference)
	update_rust_device()
	return ..()

/obj/machinery/atmospherics/binary/passive_gate/update_icon()
	icon_state = (unlocked && flowing)? "on" : "off"

/obj/machinery/atmospherics/binary/passive_gate/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	add_underlay(T, node1, turn(dir, 180))
	add_underlay(T, node2, dir)

/obj/machinery/atmospherics/binary/passive_gate/hide(i)
	update_underlays()

// process() is deleted (M2, simulation.md §5): the flow law is a Rust
// device edge (device.rs's PassiveGate), stepped every gas tick from
// SSair.fire()'s process_pipenets() regardless of DM's process()
// scheduling, so there is nothing left for this proc to do, and nothing to
// hibernate — an idle Rust edge costs one struct comparison per tick, not a
// DM process() slot.

//Radio remote control

/obj/machinery/atmospherics/binary/passive_gate/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		radio_connection = SSradio.add_object(src, frequency, radio_filter = RADIO_ATMOSIA)

/obj/machinery/atmospherics/binary/passive_gate/proc/broadcast_status()
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	signal.source = src

	signal.data = list(
		"tag" = id,
		"device" = "AGP",
		"power" = unlocked,
		"target_output" = target_pressure,
		"regulate_mode" = regulate_mode,
		"set_flow_rate" = set_flow_rate,
		"sigtype" = "status"
	)

	radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)

	return 1

/obj/machinery/atmospherics/binary/passive_gate/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id) || (signal.data["sigtype"]!="command"))
		return 0

	if("power" in signal.data)
		unlocked = text2num(signal.data["power"])

	if("power_toggle" in signal.data)
		unlocked = !unlocked

	if("set_target_pressure" in signal.data)
		target_pressure = between(0, text2num(signal.data["set_target_pressure"]), max_pressure_setting)

	if("set_regulate_mode" in signal.data)
		regulate_mode = text2num(signal.data["set_regulate_mode"])

	if("set_flow_rate" in signal.data)
		set_flow_rate = between(0, text2num(signal.data["set_flow_rate"]), air1.return_volume())

	if("status" in signal.data)
		spawn(2)
			broadcast_status()
			return //do not update_icon
	update_rust_device()

	spawn(2)
		broadcast_status()
	update_icon()
	return

/obj/machinery/atmospherics/binary/passive_gate/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/passive_gate_open_ui,
	)
	..()

/// The old attack_hand's access check.
/datum/interaction/machine_hand/passive_gate_open_ui
	id = "passive_gate_open_ui"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null), REQ_ON(PRED_TARGET, /obj/machinery/atmospherics/binary/passive_gate/proc/lets_in, "access denied"))
	effect = /obj/machinery/atmospherics/binary/passive_gate/proc/interaction_open_ui_impl

/obj/machinery/atmospherics/binary/passive_gate/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

/obj/machinery/atmospherics/binary/passive_gate/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	tgui_interact(user)
	return TRUE

/obj/machinery/atmospherics/binary/passive_gate/tgui_interact(mob/user, datum/tgui/ui)
	if(stat & BROKEN)
		return FALSE
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PressureRegulator", name)
		ui.open()

/obj/machinery/atmospherics/binary/passive_gate/tgui_data(mob/user)
	// this is the data which will be sent to the ui
	var/data[0]

	data = list(
		"on" = unlocked,
		"pressure_set" = round(target_pressure*100),	//Nano UI can't handle rounded non-integers, apparently.
		"max_pressure" = max_pressure_setting,
		"input_pressure" = round(air1.return_pressure()*100),
		"output_pressure" = round(air2.return_pressure()*100),
		"regulate_mode" = regulate_mode,
		"set_flow_rate" = round(set_flow_rate*10),
		"last_flow_rate" = round(last_flow_rate*10),
	)

	return data


/obj/machinery/atmospherics/binary/passive_gate/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	switch(action)
		if("toggle_valve")
			. = TRUE
			unlocked = !unlocked
		if("regulate_mode")
			. = TRUE
			switch(params["mode"])
				if("off") regulate_mode = REGULATE_NONE
				if("input") regulate_mode = REGULATE_INPUT
				if("output") regulate_mode = REGULATE_OUTPUT

		if("set_press")
			. = TRUE
			switch(params["press"])
				if("min")
					target_pressure = 0
				if("max")
					target_pressure = max_pressure_setting
				if("set")
					var/new_pressure = tgui_input_number(ui.user,"Enter new output pressure (0-[max_pressure_setting]kPa)","Pressure Control",src.target_pressure,max_pressure_setting,0)
					src.target_pressure = between(0, new_pressure, max_pressure_setting)

		if("set_flow_rate")
			. = TRUE
			switch(params["press"])
				if("min")
					set_flow_rate = 0
				if("max")
					set_flow_rate = air1.return_volume()
				if("set")
					var/new_flow_rate = tgui_input_number(ui.user,"Enter new flow rate limit (0-[air1.return_volume()]L/s)","Flow Rate Control",src.set_flow_rate,air1.return_volume(),0)
					src.set_flow_rate = between(0, new_flow_rate, air1.return_volume())

	update_icon()
	if(.)
		update_rust_device()
	add_fingerprint(ui.user)

/obj/machinery/atmospherics/binary/passive_gate/wrench_act(mob/user, obj/item/W)
	if (unlocked)
		to_chat(user, span_warning("You cannot unwrench \the [src], turn it off first."))
		return ITEM_INTERACT_BLOCKING
	if(!can_unwrench())
		to_chat(user, span_warning("You cannot unwrench \the [src], it too exerted due to internal pressure."))
		add_fingerprint(user)
		return ITEM_INTERACT_BLOCKING
	if (use_tool(user, W, src, delay = 40, volume = 50, message_self = "You begin to unfasten \the [src]..."))
		user.visible_message( \
			span_infoplain(span_bold("\The [user]") + " unfastens \the [src]."), \
			span_notice("You have unfastened \the [src]."), \
			"You hear ratchet.")
		atom_deconstruct()
	return ITEM_INTERACT_SUCCESS

#undef REGULATE_NONE
#undef REGULATE_INPUT
#undef REGULATE_OUTPUT


/obj/machinery/atmospherics/binary/passive_gate/on
	unlocked = 1
	icon_state = "on"
