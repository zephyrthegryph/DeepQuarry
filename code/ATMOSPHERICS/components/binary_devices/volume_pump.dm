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
	// M2: the flow law is a Rust device edge, stepped from SSair every gas
	// tick; this has no process() at all any more.
	STOP_MACHINE_PROCESSING(src)

/obj/machinery/atmospherics/binary/volume_pump/Destroy()
	unregister_radio(src, frequency)
	. = ..()

// M2 (simulation.md §5): the flow law lives on the Rust device edge
// (device::DeviceParams::VolumePump). rust_bind_pipe_port fires once per
// port, after that port's region exists in Rust, so re-publishing once the
// second port is bound is the earliest point both are live.
/obj/machinery/atmospherics/binary/volume_pump/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	if(index == 2)
		update_rust_device()

/obj/machinery/atmospherics/binary/volume_pump/proc/update_rust_device()
	if((stat & (NOPOWER|BROKEN)) || !use_power)
		rust_unregister_device()
		return
	var/effective_rate = transfer_rate * material_pump_power(power_rating) / max(power_rating, 1)
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
				qdel(leaked)
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

/obj/machinery/atmospherics/binary/volume_pump/update_icon()
	if(!powered())
		icon_state = "off"
	else
		icon_state = "[use_power ? "on" : "off"]"

	overclock_overlay = mutable_appearance('icons/atmos/volume_pump_overclock.dmi', "vpumpoverclock")
	if(powered() && use_power && overclocked)
		add_overlay(overclock_overlay)
	else
		cut_overlay(overclock_overlay)

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
		radio_connection = SSradio.add_object(src, frequency, radio_filter = RADIO_ATMOSIA)

/obj/machinery/atmospherics/binary/volume_pump/proc/broadcast_status()
	if(!radio_connection)
		return FALSE

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	signal.source = src

	signal.data = list(
		"tag" = id,
		"device" = "AGP",
		"power" = use_power,
		"transfer_rate" = transfer_rate,
		"sigtype" = "status"
	)

	radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)

	return TRUE

/obj/machinery/atmospherics/binary/volume_pump/tgui_interact(mob/user, datum/tgui/ui)
	if(stat & (BROKEN|NOPOWER))
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "GasPump", name)
		ui.open()

/obj/machinery/atmospherics/binary/volume_pump/tgui_data(mob/user)
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
			update_use_power(USE_POWER_IDLE)
		else
			update_use_power(USE_POWER_OFF)

	if("power_toggle" in signal.data)
		update_use_power(!use_power)

	if(signal.data["set_volume_rate"])
		transfer_rate = between(0, text2num(signal.data["set_volume_rate"]), air1.return_volume())

	update_rust_device()

	if(signal.data["status"])
		broadcast_status()
		return //do not update_icon

	broadcast_status()
	update_icon()
	return

/obj/machinery/atmospherics/binary/volume_pump/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/volume_pump_open_ui,
		/datum/interaction/machine_alt/volume_pump_max_output,
	)
	..()

/// Old attack_hand: fingerprint, access check, then the UI.
/datum/interaction/machine_hand/volume_pump_open_ui
	id = "volume_pump_open_ui"
	name = "Use"
	effect = /obj/machinery/atmospherics/binary/volume_pump/proc/interaction_volume_pump_open_ui

/obj/machinery/atmospherics/binary/volume_pump/proc/interaction_volume_pump_open_ui(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(!allowed(user))
		to_chat(user, span_warning("Access denied."))
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/atmospherics/binary/volume_pump/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	switch(action)
		if("power")
			update_use_power(!use_power)
			. = TRUE
		if("set_press")
			var/press = params["press"]
			switch(press)
				if("min")
					transfer_rate = 0
				if("max")
					transfer_rate = max_transfer_rate
				if("set")
					var/new_rate = tgui_input_number(ui.user,"Enter new transfer rate (0-[max_transfer_rate] L/s)","Flow Control",src.transfer_rate, max_transfer_rate, 0)
					src.transfer_rate = between(0, new_rate, max_transfer_rate)
			. = TRUE

	if(.)
		update_rust_device()
	add_fingerprint(ui.user)
	update_icon()

/obj/machinery/atmospherics/binary/volume_pump/power_change()
	var/old_stat = stat
	..()
	if(old_stat != stat)
		update_rust_device()
		update_icon()

/obj/machinery/atmospherics/binary/volume_pump/examine(mob/user)
	. = ..()
	. += "This device is designed to move large volumes of gasses quickly, but with no gurantee of exact pressures.\
	Meaning that this can naievely over-pressurize pipes and devices past the device's designed limit."
	. += span_bold("The [src]'s pressure limit is [VOLUME_PUMP_MAX_OUTPUT_PRESSURE].")
	. += span_notice("Its pressure limits could be [overclocked ? "en" : "dis"]abled with a" + span_bold("multitool") + ".")
	if(overclocked)
		. += "Its warning light is on[use_power ? " and it's spewing gas!" : "."]"


/obj/machinery/atmospherics/binary/volume_pump/wrench_act(mob/user, obj/item/W)
	if (!(stat & NOPOWER) && use_power)
		to_chat(user, span_warning("You cannot unwrench this [src], turn it off first."))
		return ITEM_INTERACT_BLOCKING
	if(!can_unwrench())
		to_chat(user, span_warning("You cannot unwrench this [src], it too exerted due to internal pressure."))
		add_fingerprint(user)
		return ITEM_INTERACT_BLOCKING
	if(use_tool(user, W, src, delay = 40, volume = 50, message_self = "You begin to unfasten \the [src]..."))
		user.visible_message( \
			span_infoplain(span_bold("\The [user]") + " unfastens \the [src]."), \
			span_notice("You have unfastened \the [src]."), \
			"You hear ratchet.")
		atom_deconstruct()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/binary/volume_pump/multitool_act(mob/user, obj/item/W)
	if(!overclocked)
		overclocked = TRUE
		to_chat(user, span_notice("The pump makes a grinding noise and air starts to hiss out as you disable its pressure limits."))
	else
		overclocked = FALSE
		to_chat(user, span_notice("The pump quiets down as you turn its limiters back on."))
	update_rust_device()
	update_icon()
	return ITEM_INTERACT_SUCCESS

/datum/interaction/machine_alt/volume_pump_max_output
	id = "volume_pump_max_output"
	name = "Set to max output"
	effect = /obj/machinery/atmospherics/binary/volume_pump/proc/interaction_max_output

/obj/machinery/atmospherics/binary/volume_pump/proc/interaction_max_output(mob/user, obj/item/held, datum/interaction/interaction)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(!allowed(user))
		to_chat(user, span_warning("Access denied."))
		return TRUE

	to_chat(user, span_notice("You set the [name] to max output"))
	transfer_rate = max_transfer_rate
	update_rust_device()
	add_fingerprint(user)
	return TRUE

/obj/machinery/atmospherics/binary/volume_pump/click_ctrl(mob/user)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(!allowed(user))
		to_chat(user, span_warning("Access denied."))
		return CLICK_ACTION_BLOCKING

	update_use_power(!use_power)
	update_rust_device()
	update_icon()
	add_fingerprint(user)
	to_chat(user, span_notice("You toggle the [name] [use_power ? "on" : "off"]."))
	return CLICK_ACTION_SUCCESS

// (No #undef here: VOLUME_PUMP_MAX_OUTPUT_PRESSURE / VOLUME_PUMP_LEAK_AMOUNT are
// globals from __defines/atmospherics_linda/atmos_piping.dm now; undef'ing them
// from a component file would break any later include that uses them.)
