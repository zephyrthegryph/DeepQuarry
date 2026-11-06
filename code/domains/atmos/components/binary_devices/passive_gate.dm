// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

// REGULATE_NONE / REGULATE_INPUT (shuts off when the input side is below the target pressure) / REGULATE_OUTPUT (shuts off when the output
// side is above it) are the Rust regulate_mode values (verdigris/domains/gas/src/kind/devices.rs, generated into the DM defines).

/obj/machinery/atmospherics/binary/passive_gate
	air2_volume = ATMOS_DEFAULT_VOLUME_PUMP * 2.5
	air1_volume = ATMOS_DEFAULT_VOLUME_PUMP * 2.5
	icon = 'icons/atmos/passive_gate.dmi'
	icon_state = "map"
	construction_type = /obj/item/pipe/directional
	pipe_state = "passivegate"
	level = 1

	name = "pressure regulator"
	desc = "A one-way air valve that can be used to regulate input or output pressure, and flow rate. Does not require power."

	use_power = USE_POWER_OFF

	var/unlocked = 0	//If 0, then the valve is locked closed, otherwise it is open(-able, it's a one-way valve so it closes if gas would flow backwards).
	// The settings are the gate's Rust component's (get_/set_ over native_write()): there is no var for them.
	init_target_pressure = ONE_ATMOSPHERE
	var/max_pressure_setting = 15000	//kPa
	init_set_flow_rate = ATMOS_DEFAULT_VOLUME_PUMP * 2.5
	init_regulate_mode = REGULATE_OUTPUT

	var/flowing = 0	//for icons - becomes zero if the valve closes itself due to regulation mode

	var/frequency = ZERO_FREQ
	var/id = null
	var/datum/radio_frequency/radio_connection

/// The gate's flow law is its own PassiveGate component (rust_bindings.md section 14); the device edge is the gate's entity, registered between
/// its two ports. Only its running input (unlocked) is DM's.
/obj/machinery/atmospherics/binary/passive_gate/push_to_rust()
	if(QDELETED(src))
		return
	rust_set_device(1, 2)
	rust_push_running()

/obj/machinery/atmospherics/binary/passive_gate/rust_device_binds_self()
	return TRUE

/// The three settings have no DM var, so each has one hand setter over the one write door. Rust clamps; the stored value is returned.
/obj/machinery/atmospherics/binary/passive_gate/proc/set_target_pressure(value)
	return native_write(src, NATIVE_PASSIVEGATE_TARGET_PRESSURE, value)

/obj/machinery/atmospherics/binary/passive_gate/proc/set_set_flow_rate(value)
	return native_write(src, NATIVE_PASSIVEGATE_SET_FLOW_RATE, value)

/obj/machinery/atmospherics/binary/passive_gate/proc/set_regulate_mode(value)
	return native_write(src, NATIVE_PASSIVEGATE_REGULATE_MODE, value)

/// It flows while its valve is unlocked.
/obj/machinery/atmospherics/binary/passive_gate/passive_gate_input_running()
	return !!unlocked

/obj/machinery/atmospherics/binary/passive_gate/rust_push_running()
	if(vg_entity)
		push_running(passive_gate_input_running())
	if(!unlocked)
		set_flowing(FALSE)

/obj/machinery/atmospherics/binary/passive_gate/rust_device_stepped(moles, power_w, target_reached)
	atmos_note_flow_rate(src, abs(moles))
	var/new_flowing = (moles != 0)
	if(new_flowing != flowing)
		set_flowing(new_flowing)

/obj/machinery/atmospherics/binary/passive_gate/draw(datum/look/look)
	..()
	look.state((unlocked && flowing) ? "on" : "off")

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
		rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, radio_filter = RADIO_ATMOSIA))

/obj/machinery/atmospherics/binary/passive_gate/proc/broadcast_status()
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(signal.source), src)

	signal.data = list(
		"tag" = id,
		"device" = "AGP",
		"power" = unlocked,
		"target_output" = get_target_pressure(),
		"regulate_mode" = get_regulate_mode(),
		"set_flow_rate" = get_set_flow_rate(),
		"sigtype" = "status"
	)

	radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)
	spent(signal) // the receivers read what they need while it is delivered

	return 1

/obj/machinery/atmospherics/binary/passive_gate/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id) || (signal.data["sigtype"]!="command"))
		return 0

	if("power" in signal.data)
		set_unlocked(text2num(signal.data["power"]))

	if("power_toggle" in signal.data)
		set_unlocked(!unlocked)

	if("set_target_pressure" in signal.data)
		set_target_pressure(between(0, text2num(signal.data["set_target_pressure"]), max_pressure_setting))

	if("set_regulate_mode" in signal.data)
		set_regulate_mode(text2num(signal.data["set_regulate_mode"]))

	if("set_flow_rate" in signal.data)
		set_set_flow_rate(between(0, text2num(signal.data["set_flow_rate"]), air1.return_volume()))

	if("status" in signal.data)
		after(src, 0.2 SECONDS, PROC_REF(broadcast_status))
		return //do not update_icon

	after(src, 0.2 SECONDS, PROC_REF(broadcast_status))
	return

// ---- the controls ----

CAPABILITIES(/obj/machinery/atmospherics/binary/passive_gate)
	pipe_device_port()
	on_change(nameof(unlocked), ANY, then(TYPE_PROC_REF(/obj/machinery/atmospherics, pipe_port_resync)))
	configure(machine_usage(interact_offline = TRUE))
	ref_one(nameof(radio_connection), /datum/radio_frequency)
	radio_listen(freq = nameof(frequency), via = PROC_REF(set_frequency)) // its radio follows its frequency from init
	pipe_device_window("PressureRegulator")
	pipe_device_unwrench()
	op("toggle_valve", ui_act("toggle_valve"), then(PROC_REF(valve_switched)))
	op("regulate_mode", ui_act("regulate_mode", arg("mode", schema_text(16))), then(PROC_REF(ui_set_regulate_mode)))
	// "set" asks for the value; "min" and "max" set it at once
	op("set_press", ui_act("set_press", arg("press", schema_text(16))),
		asks(/datum/prompt/number, fields = list("question" = computed(PROC_REF(set_press_question)), "title" = "Pressure Control", "default" = computed(PROC_REF(set_press_default)), "max_value" = nameof(max_pressure_setting), "timeout" = 0), step = "gate_press", when = PROC_REF(press_is_set)),
		then(PROC_REF(ui_set_press)))
	op("set_flow_rate", ui_act("set_flow_rate", arg("press", schema_text(16))),
		asks(/datum/prompt/number, fields = list("question" = computed(PROC_REF(set_flow_question)), "title" = "Flow Rate Control", "default" = computed(PROC_REF(set_flow_default)), "max_value" = computed(PROC_REF(flow_limit)), "timeout" = 0), step = "gate_flow", when = PROC_REF(press_is_set)),
		then(PROC_REF(ui_set_flow_rate)))

/// A regulator runs while its valve is open: the wrench waits for it to be shut.
/obj/machinery/atmospherics/binary/passive_gate/pipe_device_idle(datum/act/A)
	return (!unlocked) ? null : MSG(pipe_device/running)

/// It needs no power: its window opens unless it is broken.
/obj/machinery/atmospherics/binary/passive_gate/device_works(datum/act/A)
	return (!broken_now()) ? null : MSG(machine/inoperable)

/// The window's data.
/obj/machinery/atmospherics/binary/passive_gate/ui_data(datum/act/eval/A)
	return list(
		"on" = unlocked,
		"pressure_set" = round(get_target_pressure()*100),	//Nano UI can't handle rounded non-integers, apparently.
		"max_pressure" = max_pressure_setting,
		"input_pressure" = round(air1.return_pressure()*100),
		"output_pressure" = round(air2.return_pressure()*100),
		"regulate_mode" = get_regulate_mode(),
		"set_flow_rate" = round(get_set_flow_rate()*10),
		"last_flow_rate" = round(last_flow_rate*10),
	)

/obj/machinery/atmospherics/binary/passive_gate/proc/valve_switched(datum/act/op/A)
	set_unlocked(!unlocked)
	return OP_OK

/obj/machinery/atmospherics/binary/passive_gate/proc/ui_set_regulate_mode(datum/act/op/A, mode)
	switch(mode)
		if("off")
			set_regulate_mode(REGULATE_NONE)
		if("input")
			set_regulate_mode(REGULATE_INPUT)
		if("output")
			set_regulate_mode(REGULATE_OUTPUT)
	return OP_OK

/obj/machinery/atmospherics/binary/passive_gate/proc/press_is_set(datum/act/op/A)
	return A.args["press"] == "set"

/obj/machinery/atmospherics/binary/passive_gate/proc/set_press_question(datum/act/op/A)
	return "Enter new output pressure (0-[max_pressure_setting]kPa)"

/obj/machinery/atmospherics/binary/passive_gate/proc/set_press_default(datum/act/op/A)
	return get_target_pressure()

/obj/machinery/atmospherics/binary/passive_gate/proc/set_flow_default(datum/act/op/A)
	return get_set_flow_rate()

/obj/machinery/atmospherics/binary/passive_gate/proc/set_flow_question(datum/act/op/A)
	return "Enter new flow rate limit (0-[flow_limit(A)]L/s)"

/// The most the flow limit can be: the input side's volume.
/obj/machinery/atmospherics/binary/passive_gate/proc/flow_limit(datum/act/A)
	return air1.return_volume()

/obj/machinery/atmospherics/binary/passive_gate/proc/ui_set_press(datum/act/op/A, press)
	switch(press)
		if("min")
			set_target_pressure(0)
		if("max")
			set_target_pressure(max_pressure_setting)
		if("set")
			set_target_pressure(between(0, A.step_value("gate_press"), max_pressure_setting))
	return OP_OK

/obj/machinery/atmospherics/binary/passive_gate/proc/ui_set_flow_rate(datum/act/op/A, press)
	switch(press)
		if("min")
			set_set_flow_rate(0)
		if("max")
			set_set_flow_rate(air1.return_volume())
		if("set")
			set_set_flow_rate(between(0, A.step_value("gate_flow"), air1.return_volume()))
	return OP_OK

/obj/machinery/atmospherics/binary/passive_gate/on
	unlocked = 1
	icon_state = "on"



/// The edge is registered again (once per frame) when a pipe comes or goes.
/obj/machinery/atmospherics/binary/passive_gate/derived()
	. = ..()
	. += rust_push(nameof(node1), nameof(node2))
	. += drawn_from(nameof(unlocked), nameof(flowing))
