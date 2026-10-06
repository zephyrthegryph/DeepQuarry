/*
Every cycle, the pump uses the air in air_in to try and move a specific volume of gas into air_out.

node1, air1, network1 correspond to input
node2, air2, network2 correspond to output

Thus, the two variables affect pump operation are set in New():
	air1.volume
		This is the volume of gas available to the pump that may be transfered to the output
	air2.volume
		Higher quantities of this cause more air to be perfected later
		but overall network volume is also increased as this increases...
*/

/obj/machinery/atmospherics/binary/volume_pump
	icon = 'icons/atmos/volume_pump.dmi'
	icon_state = "map_off"
	construction_type = /obj/item/pipe/directional
	pipe_state = "volumepump"
	level = 1
	var/base_icon = "pump"

	name = "volumetric gas pump"
	desc = "A pump that moves gas by volume"

	use_power = USE_POWER_OFF
	idle_power_usage = 150		//internal circuitry, friction losses and stuff
	power_rating = 15000	//15000 W ~ 20.4 HP

	var/max_transfer_rate = ATMOS_DEFAULT_VOLUME_PUMP	// Ls
	var/transfer_rate = 20 // L

	var/frequency = ZERO_FREQ
	var/id = null
	var/datum/radio_frequency/radio_connection

	var/overclocked = FALSE
	var/mutable_appearance/overclock_overlay

/obj/machinery/atmospherics/binary/volume_pump/Initialize(mapload)
	. = ..()

	air1.set_volume(ATMOS_DEFAULT_VOLUME_PUMP)
	air2.set_volume(ATMOS_DEFAULT_VOLUME_PUMP)
	if(frequency)
		set_frequency(frequency)

// M2 (simulation.md §5): the flow law lives on the Rust device edge
// (device::DeviceParams::VolumePump). rust_bind_pipe_port fires once per
// port, after that port's region exists in Rust, so re-publishing once the
// second port is bound is the earliest point both are live.
/obj/machinery/atmospherics/binary/volume_pump/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	if(index == 2)
		rust_device_dirty()

/obj/machinery/atmospherics/binary/volume_pump/push_to_rust()
	// ALLOW(derived_reads): set_use_power() and power_change() bump rust_device_rev; power_rating is fixed by the material
	if((!operable()) || !use_power)
		rust_unregister_device()
		return
	var/effective_rate = transfer_rate * material_pump_power(power_rating) / max(power_rating, 1) // ALLOW(derived_reads): power_rating is fixed by the material
	var/max_output = overclocked ? 0 : VOLUME_PUMP_MAX_OUTPUT_PRESSURE
	rust_set_device(1, 2)
	rust_set_device_flow(0, RUST_FLOW_VOLUME, effective_rate, RUST_DIR_FORCED, RUST_SIDE_B, max_output > 0 ? RUST_STOP_AT_LEAST : RUST_STOP_NONE, max_output)

/obj/machinery/atmospherics/binary/volume_pump/rust_device_stepped(moles, power_w, target_reached)
	last_flow_rate = 0
	last_power_draw = 0
	if(moles <= 0)
		return

	// Overclocked pumps leak a share of what they just moved into air2 back
	// into the local turf (the Rust edge already merged it into air2).
	if(overclocked && isturf(loc))
		var/turf/open/T = loc
		if(istype(T) && T.air)
			var/air2_total = air2.total_moles()
			if(air2_total > 0)
				var/leak_fraction = min(VOLUME_PUMP_LEAK_AMOUNT * moles / air2_total, 1)
				var/datum/gas_mixture/leaked = air2.remove_ratio(leak_fraction)
				T.air.merge(leaked)
				spent(leaked)
				T.update_visuals()
				T.air_update_turf(FALSE, FALSE)

	last_flow_rate = moles
	// Matches the pre-M2 formula: power scales with the configured transfer
	// ratio (rate / volume, times the material power ratio), not with the
	// moles actually available this tick — a pump "tries" at a fixed power
	// draw regardless of how starved its input is.
	var/transfer_ratio = (transfer_rate / air1.return_volume()) * (material_pump_power(power_rating) / max(power_rating, 1))
	var/power_draw = transfer_ratio * power_rating * 0.8 / material_pump_efficiency()
	if(power_draw >= 0)
		last_power_draw = power_draw
		use_power(power_draw)
		record_material_pumping(power_draw, air2, moles * (overclocked ? 1 - VOLUME_PUMP_LEAK_AMOUNT : 1))

/obj/machinery/atmospherics/binary/volume_pump/on
	icon_state = "map_on"
	use_power = USE_POWER_IDLE

/obj/machinery/atmospherics/binary/volume_pump/fuel
	icon_state = "map_off-fuel"
	base_icon = "pump-fuel"
	icon_connect_type = "-fuel"
	connect_types = CONNECT_TYPE_FUEL

/obj/machinery/atmospherics/binary/volume_pump/fuel/on
	icon_state = "map_on-fuel"
	use_power = USE_POWER_IDLE

/obj/machinery/atmospherics/binary/volume_pump/aux
	icon_state = "map_off-aux"
	base_icon = "pump-aux"
	icon_connect_type = "-aux"
	connect_types = CONNECT_TYPE_AUX

/obj/machinery/atmospherics/binary/volume_pump/aux/on
	icon_state = "map_on-aux"
	use_power = USE_POWER_IDLE

/obj/machinery/atmospherics/binary/volume_pump/draw(datum/look/look)
	..()
	var/running = operable() && use_power
	look.state(running ? "on" : "off")
	look.overlay("vpumpoverclock", when = running && overclocked, icon = 'icons/atmos/volume_pump_overclock.dmi')

/obj/machinery/atmospherics/binary/volume_pump/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	add_underlay(T, node1, turn(dir, -180), node1?.icon_connect_type)
	add_underlay(T, node2, dir, node2?.icon_connect_type)

/obj/machinery/atmospherics/binary/volume_pump/hide(i)
	update_underlays()

// process() is deleted (M2, simulation.md §5): the flow law above is a Rust
// device edge, stepped every gas tick from SSair.fire() regardless of DM's
// process() scheduling.

//Radio remote control

/obj/machinery/atmospherics/binary/volume_pump/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, radio_filter = RADIO_ATMOSIA))

/obj/machinery/atmospherics/binary/volume_pump/proc/broadcast_status()
	if(!radio_connection)
		return FALSE

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(signal.source), src)

	signal.data = list(
		"tag" = id,
		"device" = "AGP",
		"power" = use_power,
		"transfer_rate" = transfer_rate,
		"sigtype" = "status"
	)

	radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)

	return TRUE

/// The window's data.
/obj/machinery/atmospherics/binary/volume_pump/ui_data(datum/act/eval/A)
	// this is the data which will be sent to the ui
	var/list/data = list(
		"on" = use_power,
		"rate" = transfer_rate*100,
		"max_rate" = max_transfer_rate,
		"last_flow_rate" = last_flow_rate*10,
		"last_power_draw" = last_power_draw,
		"max_power_draw" = power_rating,
	)

	return data

/obj/machinery/atmospherics/binary/volume_pump/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id) || (signal.data["sigtype"]!="command"))
		return FALSE

	if(signal.data["power"])
		if(text2num(signal.data["power"]))
			set_use_power(USE_POWER_IDLE)
		else
			set_use_power(USE_POWER_OFF)

	if("power_toggle" in signal.data)
		set_use_power(!use_power)

	if(signal.data["set_volume_rate"])
		set_transfer_rate(between(0, text2num(signal.data["set_volume_rate"]), air1.return_volume()))

	if(signal.data["status"])
		broadcast_status()
		return //do not update_icon

	broadcast_status()
	changed(src)
	return

MSG_DEF_SELF(volume_pump/overclocked, "The pump makes a grinding noise and air starts to hiss out as you disable its pressure limits.")
MSG_DEF_SELF(volume_pump/limited, "The pump quiets down as you turn its limiters back on.")

CAPABILITIES(/obj/machinery/atmospherics/binary/volume_pump)
	pipe_device_window("GasPump")
	pipe_device_switch()
	pipe_device_max(PROC_REF(max_output_set))
	pipe_device_unwrench()
	op("overclock", tool(TOOL_MULTITOOL), label("Toggle pressure limiter"), wait(0), says(PROC_REF(overclock_message)), then(PROC_REF(overclock_toggled)))
	op("power", ui_act("power"), then(PROC_REF(power_switched)))
	// "set" asks for the value; "min" and "max" set it at once
	op("set_press", ui_act("set_press", arg("press", schema_text(4096))),
		asks(/datum/prompt/number, fields = list("question" = computed(PROC_REF(set_press_question)), "title" = "Flow Control", "default" = computed(PROC_REF(set_press_default)), "max_value" = nameof(max_transfer_rate), "timeout" = 0), step = "k269", when = PROC_REF(press_is_set)),
		then(PROC_REF(ui_act_set_press)))

/obj/machinery/atmospherics/binary/volume_pump/proc/power_switched(datum/act/op/A)
	toggle_power()
	return OP_OK

/// The alt-click's highest rate.
/obj/machinery/atmospherics/binary/volume_pump/proc/max_output_set(datum/act/op/A)
	set_transfer_rate(max_transfer_rate)
	return OP_OK

/// The multitool lifts the pump's pressure limiter, or puts it back.
/obj/machinery/atmospherics/binary/volume_pump/proc/overclock_toggled(datum/act/op/A)
	set_overclocked(!overclocked)
	return OP_OK

/obj/machinery/atmospherics/binary/volume_pump/proc/overclock_message(datum/act/A)
	return overclocked ? /datum/msg/volume_pump/overclocked : /datum/msg/volume_pump/limited

/obj/machinery/atmospherics/binary/volume_pump/proc/press_is_set(datum/act/op/A)
	return A.args["press"] == "set"

/obj/machinery/atmospherics/binary/volume_pump/proc/set_press_question(datum/act/op/A)
	return "Enter new transfer rate (0-[max_transfer_rate] L/s)"

/obj/machinery/atmospherics/binary/volume_pump/proc/set_press_default(datum/act/op/A)
	return src.transfer_rate

/obj/machinery/atmospherics/binary/volume_pump/proc/ui_act_set_press(datum/act/op/A, press)
	switch(press)
		if("min")
			set_transfer_rate(0)
		if("max")
			set_transfer_rate(max_transfer_rate)
		if("set")
			var/new_rate = A.step_value("k269")
			set_transfer_rate(between(0, new_rate, max_transfer_rate))
	return OP_OK

/obj/machinery/atmospherics/binary/volume_pump/examine(mob/user)
	. = ..()
	. += "This device is designed to move large volumes of gasses quickly, but with no gurantee of exact pressures.\
	Meaning that this can naievely over-pressurize pipes and devices past the device's designed limit."
	. += span_bold("The [src]'s pressure limit is [VOLUME_PUMP_MAX_OUTPUT_PRESSURE].")
	. += span_notice("Its pressure limits could be [overclocked ? "en" : "dis"]abled with a" + span_bold("multitool") + ".")
	if(overclocked)
		. += "Its warning light is on[use_power ? " and it's spewing gas!" : "."]"

// (No #undef here: VOLUME_PUMP_MAX_OUTPUT_PRESSURE / VOLUME_PUMP_LEAK_AMOUNT are
// globals from __defines/atmospherics_linda/atmos_piping.dm now; undef'ing them
// from a component file would break any later include that uses them.)


TRACKED(/obj/machinery/atmospherics/binary/volume_pump, transfer_rate)
TRACKED(/obj/machinery/atmospherics/binary/volume_pump, overclocked)

/// The Rust device law is pushed (once per frame) when any of these change.
/obj/machinery/atmospherics/binary/volume_pump/derived()
	. = ..()
	. += rust_push(nameof(rust_device_rev), nameof(transfer_rate), nameof(overclocked))
	. += drawn_from(nameof(use_power), nameof(overclocked))
