/*
Every cycle, the pump uses the air in air_in to try and make air_out the perfect pressure.

node1, air1, network1 correspond to input
node2, air2, network2 correspond to output

Thus, the two variables affect pump operation are set in New():
	air1.volume
		This is the volume of gas available to the pump that may be transfered to the output
	air2.volume
		Higher quantities of this cause more air to be perfected later
			but overall network volume is also increased as this increases...
*/

/obj/machinery/atmospherics/binary/pump
	material_template = /datum/material_template/pump
	material_total = 4 * SHEET_MATERIAL_AMOUNT
	icon = 'icons/atmos/pump.dmi'
	icon_state = "map_off"
	construction_type = /obj/item/pipe/directional
	pipe_state = "pump"
	level = 1
	var/base_icon = "pump"

	name = "gas pump"
	desc = "A pump that moves gas from one place to another."

	// R10 (doc/rewrite/rust_bindings.md §14): target_pressure and power_rating
	// are Rust-owned config, reached only through get_/set_target_pressure() (hand setters below over native_write())
	// and get_/set_power_rating() (code/__defines/verdigris/_bindings_types.dm).
	// There is no target_pressure var any more. power_rating is still declared
	// on the shared /obj/machinery/atmospherics ancestor (other, not-yet-migrated
	// devices still use it as a plain var, ATMOSPHERICS/atmospherics.dm:20); on
	// pump it is dead weight until every atmos device migrates (M2) and that
	// ancestor var is deleted.
	init_target_pressure = ONE_ATMOSPHERE


	use_power = USE_POWER_OFF
	idle_power_usage = 150		//internal circuitry, friction losses and stuff

	var/max_pressure_setting = 15000	//kPa

	var/frequency = ZERO_FREQ
	var/id = null
	var/datum/radio_frequency/radio_connection

/obj/machinery/atmospherics/binary/pump/Initialize(mapload)
	. = ..()

	air1.set_volume(ATMOS_DEFAULT_VOLUME_PUMP)
	air2.set_volume(ATMOS_DEFAULT_VOLUME_PUMP)
	if(frequency)
		set_frequency(frequency)

// M2 (simulation.md §5): the flow law lives on the Rust device edge
// (device::DeviceParams::Pump). rust_bind_pipe_port fires once per port,
// after that port's region exists in Rust, so re-publishing once the
// second port is bound is the earliest point both are live.
/obj/machinery/atmospherics/binary/pump/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	if(index == 2)
		rust_device_dirty()

/**
 * The generated push (rust_push(rust_device_rev), coalesced once per frame): target_pressure, power_rating and on are Rust-owned config
 * on the binding layer's own Pump component (get_/set_target_pressure() etc,
 * code/__defines/verdigris/_bindings_types.dm) — that is their one store.
 * This reads them through those generated getters and republishes them to
 * the legacy per-device-edge law (rust_pipenets.dm) that still does the
 * actual gas moving until M2 lands the generic Flow law on top of this
 * component (doc/rewrite/rust_bindings.md §14 step 2). No var is duplicated:
 * this is a read-then-forward, not a second copy.
 */
/obj/machinery/atmospherics/binary/pump/push_to_rust()
	// ALLOW(derived_reads): the entity is bound at materialize; a port bind bumps rust_device_rev
	if(!vg_entity)
		return
	if((!operable()) || !get_on())
		rust_unregister_device()
		return
	rust_set_device(1, 2)
	rust_set_device_flow(0, RUST_FLOW_POWER, get_power_rating(), RUST_DIR_FORCED, RUST_SIDE_B, RUST_STOP_AT_LEAST, get_target_pressure())

/// The three Rust-owned config fields have no DM var (rust_bindings.md section 1), so each has one hand
/// setter: write the field (native_write(), the one write door), then re-publish the law. Rust clamps
/// the value; the stored value is returned.
/obj/machinery/atmospherics/binary/pump/proc/set_target_pressure(value)
	. = native_write(src, NATIVE_PUMP_TARGET_PRESSURE, value)
	rust_device_dirty()

/obj/machinery/atmospherics/binary/pump/proc/set_power_rating(value)
	. = native_write(src, NATIVE_PUMP_POWER_RATING, value)
	rust_device_dirty()

/obj/machinery/atmospherics/binary/pump/proc/set_on(value)
	. = native_write(src, NATIVE_PUMP_ON, value)
	rust_device_dirty()

/// operable comes from anchored and integrity (rust_bindings.md §7's classes
/// 3-5) through the generated wiring: the atom_break()/atom_fix() hook pushes
/// it whenever integrity changes, and the reconciler covers anchored.
/obj/machinery/atmospherics/binary/pump/pump_input_operable()
	return anchored && !broken_now()

//Radio remote control

/obj/machinery/atmospherics/binary/pump/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, radio_filter = RADIO_ATMOSIA))

/obj/machinery/atmospherics/binary/pump/proc/broadcast_status()
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(signal.source), src)

	signal.data = list(
		"tag" = id,
		"device" = "AGP",
		"power" = use_power,
		"target_output" = get_target_pressure(),
		"sigtype" = "status"
	)

	radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)

	return 1

/// The window's data.
/obj/machinery/atmospherics/binary/pump/ui_data(datum/act/eval/A)
	// this is the data which will be sent to the ui
	var/list/data = list()

	data = list(
		"on" = use_power,
		"pressure_set" = round(get_target_pressure()*100),	//Nano UI can't handle rounded non-integers, apparently.
		"max_pressure" = max_pressure_setting,
		"last_flow_rate" = round(get_flow_rate()*10),
		"max_power_draw" = get_power_rating(),
	)

	return data

/obj/machinery/atmospherics/binary/pump/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id) || (signal.data["sigtype"]!="command"))
		return 0

	if(signal.data["power"])
		if(text2num(signal.data["power"]))
			set_use_power(USE_POWER_IDLE)
			set_on(TRUE)
		else
			set_use_power(USE_POWER_OFF)
			set_on(FALSE)

	if("power_toggle" in signal.data)
		set_use_power(!use_power)
		set_on(!!use_power)

	if(signal.data["set_output_pressure"])
		set_target_pressure(between(0, text2num(signal.data["set_output_pressure"]), ONE_ATMOSPHERE*50))

	if(signal.data["status"])
		after(src, 0.2 SECONDS, PROC_REF(broadcast_status))
		return //do not update_icon

	after(src, 0.2 SECONDS, PROC_REF(broadcast_status))
	changed(src)
	return

CAPABILITIES(/obj/machinery/atmospherics/binary/pump)
	pipe_device_window("GasPump")
	pipe_device_switch()
	pipe_device_max(PROC_REF(max_output_set))
	pipe_device_unwrench()
	op("power", ui_act("power"), then(PROC_REF(power_switched)))
	// "set" asks for the value; "min" and "max" set it at once
	op("set_press", ui_act("set_press", arg("press", schema_text(4096))),
		asks(/datum/prompt/number, fields = list("question" = computed(PROC_REF(set_press_question)), "title" = "Pressure control", "default" = computed(PROC_REF(set_press_default)), "max_value" = nameof(max_pressure_setting), "timeout" = 0), step = "k231", when = PROC_REF(press_is_set)),
		then(PROC_REF(ui_act_set_press)))

/obj/machinery/atmospherics/binary/pump/proc/power_switched(datum/act/op/A)
	toggle_power()
	return OP_OK

/// The switch also sets the pump's Rust-owned on flag.
/obj/machinery/atmospherics/binary/pump/toggle_power()
	..()
	set_on(!!use_power)

/// The alt-click's highest output.
/obj/machinery/atmospherics/binary/pump/proc/max_output_set(datum/act/op/A)
	set_target_pressure(max_pressure_setting)
	return OP_OK

/obj/machinery/atmospherics/binary/pump/proc/press_is_set(datum/act/op/A)
	return A.args["press"] == "set"

/obj/machinery/atmospherics/binary/pump/proc/set_press_question(datum/act/op/A)
	return "Enter new output pressure (0-[max_pressure_setting]kPa)"

/obj/machinery/atmospherics/binary/pump/proc/set_press_default(datum/act/op/A)
	return get_target_pressure()

/obj/machinery/atmospherics/binary/pump/proc/ui_act_set_press(datum/act/op/A, press)
	switch(press)
		if("min")
			set_target_pressure(0)
		if("max")
			set_target_pressure(max_pressure_setting)
		if("set")
			var/new_pressure = A.step_value("k231")
			set_target_pressure(between(0, new_pressure, max_pressure_setting))
	return OP_OK

/obj/machinery/atmospherics/binary/pump/on_pump_target_reached()
	changed(src)

/obj/machinery/atmospherics/binary/pump/draw(datum/look/look)
	..()
	look.state("[base_icon]-[running_state()]")

/// "on" while it works and runs, else "off".
/obj/machinery/atmospherics/binary/pump/proc/running_state()
	return (operable() && use_power) ? "on" : "off"

/obj/machinery/atmospherics/binary/pump/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	add_underlay(T, node1, turn(dir, -180), node1?.icon_connect_type)
	add_underlay(T, node2, dir, node2?.icon_connect_type)

/obj/machinery/atmospherics/binary/pump/hide(i)
	update_underlays()

// process() and its hibernate/gas-dependency machinery are deleted (M2,
// simulation.md §5): the flow law is a Rust device edge, stepped every gas
// tick from SSair.fire() regardless of DM's process() scheduling, so there
// is nothing left to run and nothing to hibernate.

/obj/machinery/atmospherics/binary/pump/on
	icon_state = "map_on"
	use_power = USE_POWER_IDLE
	init_on = TRUE

/obj/machinery/atmospherics/binary/pump/fuel
	icon_state = "map_off-fuel"
	base_icon = "pump-fuel"
	icon_connect_type = "-fuel"
	connect_types = CONNECT_TYPE_FUEL

/obj/machinery/atmospherics/binary/pump/fuel/on
	icon_state = "map_on-fuel"
	use_power = USE_POWER_IDLE
	init_on = TRUE

/obj/machinery/atmospherics/binary/pump/aux
	icon_state = "map_off-aux"
	base_icon = "pump-aux"
	icon_connect_type = "-aux"
	connect_types = CONNECT_TYPE_AUX

/obj/machinery/atmospherics/binary/pump/aux/on
	icon_state = "map_on-aux"
	use_power = USE_POWER_IDLE
	init_on = TRUE

/obj/machinery/atmospherics/binary/pump/high_power
	icon = 'icons/atmos/volume_pump.dmi'
	icon_state = "map_off"
	construction_type = /obj/item/pipe/directional
	pipe_state = "volumepump"
	level = 1

	name = "high power gas pump"
	desc = "A pump that moves gas from one place to another. Has double the power rating of the standard gas pump."

	init_power_rating = 15000	//15000 W ~ 20 HP

/obj/machinery/atmospherics/binary/pump/high_power/on
	use_power = USE_POWER_IDLE
	init_on = TRUE
	icon_state = "map_on"

/obj/machinery/atmospherics/binary/pump/high_power/draw(datum/look/look)
	..()
	look.state(running_state())


/// The Rust device law is pushed (once per frame) when any of these change.
/obj/machinery/atmospherics/binary/pump/derived()
	. = ..()
	. += rust_push(nameof(rust_device_rev))
	. += drawn_from(nameof(use_power))
