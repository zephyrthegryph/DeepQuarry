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
	// are Rust-owned config, reached only through get_/set_target_pressure()
	// and get_/set_power_rating() (code/__defines/verdigris/_bindings_types.dm).
	// There is no target_pressure var any more. power_rating is still declared
	// on the shared /obj/machinery/atmospherics ancestor (other, not-yet-migrated
	// devices still use it as a plain var, ATMOSPHERICS/atmospherics.dm:20); on
	// pump it is dead weight until every atmos device migrates (M2) and that
	// ancestor var is deleted.
	init_target_pressure = ONE_ATMOSPHERE

	//var/max_volume_transfer = 10000

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
	// M2/R10: the flow law is a Rust device edge, stepped from SSair every gas
	// tick; this has no process() at all any more.
	STOP_MACHINE_PROCESSING(src)

/obj/machinery/atmospherics/binary/pump/Destroy()
	unregister_radio(src, frequency)
	. = ..()

/obj/machinery/atmospherics/binary/pump/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

// M2 (simulation.md §5): the flow law lives on the Rust device edge
// (device::DeviceParams::Pump). rust_bind_pipe_port fires once per port,
// after that port's region exists in Rust, so re-publishing once the
// second port is bound is the earliest point both are live.
/obj/machinery/atmospherics/binary/pump/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	if(index == 2)
		update_rust_device()

/**
 * R10/M2 bridge: target_pressure, power_rating and on are Rust-owned config
 * on the binding layer's own Pump component (get_/set_target_pressure() etc,
 * code/__defines/verdigris/_bindings_types.dm) — that is their one store.
 * This reads them through those generated getters and republishes them to
 * the legacy per-device-edge law (rust_pipenets.dm) that still does the
 * actual gas moving until M2 lands the generic Flow law on top of this
 * component (doc/rewrite/rust_bindings.md §14 step 2). No var is duplicated:
 * this is a read-then-forward, not a second copy.
 */
/obj/machinery/atmospherics/binary/pump/proc/update_rust_device()
	if(!vg_entity)
		return
	if((stat & (NOPOWER|BROKEN)) || !get_on())
		rust_unregister_device()
		return
	rust_set_device(1, 2)
	rust_set_device_flow(0, RUST_FLOW_POWER, get_power_rating(), RUST_DIR_FORCED, RUST_SIDE_B, RUST_STOP_AT_LEAST, get_target_pressure())

/// operable comes from anchored and integrity (rust_bindings.md §7's classes
/// 3-5) through the generated wiring: the atom_break()/atom_fix() hook pushes
/// it whenever integrity changes, and the reconciler covers anchored.
/obj/machinery/atmospherics/binary/pump/pump_input_operable()
	return anchored && !(stat & BROKEN)

//Radio remote control

/obj/machinery/atmospherics/binary/pump/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		radio_connection = SSradio.add_object(src, frequency, radio_filter = RADIO_ATMOSIA)

/obj/machinery/atmospherics/binary/pump/proc/broadcast_status()
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	signal.source = src

	signal.data = list(
		"tag" = id,
		"device" = "AGP",
		"power" = use_power,
		"target_output" = get_target_pressure(),
		"sigtype" = "status"
	)

	radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)

	return 1

/obj/machinery/atmospherics/binary/pump/tgui_interact(mob/user, datum/tgui/ui)
	if(stat & (BROKEN|NOPOWER))
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "GasPump", name)
		ui.open()

/obj/machinery/atmospherics/binary/pump/tgui_data(mob/user)
	// this is the data which will be sent to the ui
	var/data[0]

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
			update_use_power(USE_POWER_IDLE)
			set_on(TRUE)
		else
			update_use_power(USE_POWER_OFF)
			set_on(FALSE)

	if("power_toggle" in signal.data)
		update_use_power(!use_power)
		set_on(!!use_power)

	if(signal.data["set_output_pressure"])
		set_target_pressure(between(0, text2num(signal.data["set_output_pressure"]), ONE_ATMOSPHERE*50))

	update_rust_device()

	if(signal.data["status"])
		addtimer(CALLBACK(src, PROC_REF(broadcast_status)), 2, TIMER_DELETE_ME)
		return //do not update_icon

	addtimer(CALLBACK(src, PROC_REF(broadcast_status)), 2, TIMER_DELETE_ME)
	update_icon()
	return

/obj/machinery/atmospherics/binary/pump/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/pump_open_ui,
		/datum/interaction/machine_alt/pump_max_output,
	)
	..()

/// Old attack_hand: `if(..()) return; add_fingerprint(user); if(!allowed(user)) ...; tgui_interact(user)`.
/datum/interaction/machine_hand/pump_open_ui
	id = "pump_open_ui"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null), REQ_ON(PRED_TARGET, /obj/machinery/atmospherics/binary/pump/proc/lets_in, "access denied"))
	effect = /obj/machinery/atmospherics/binary/pump/proc/interaction_open_ui_impl

/obj/machinery/atmospherics/binary/pump/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	tgui_interact(user)
	return TRUE

/// Old click_alt: sets the pump to max output.
/datum/interaction/machine_alt/pump_max_output
	id = "pump_max_output"
	name = "Set to max output"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/atmospherics/binary/pump/proc/lets_in, "access denied"))
	effect = /obj/machinery/atmospherics/binary/pump/proc/interaction_max_output

/obj/machinery/atmospherics/binary/pump/proc/interaction_max_output(mob/user, obj/item/held, datum/interaction/interaction)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	to_chat(user, span_notice("You set the [name] to max output"))
	set_target_pressure(max_pressure_setting)
	update_rust_device()
	add_fingerprint(user)
	return TRUE

/obj/machinery/atmospherics/binary/pump/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	switch(action)
		if("power")
			update_use_power(!use_power)
			set_on(!!use_power)
			. = TRUE
		if("set_press")
			var/press = params["press"]
			switch(press)
				if("min")
					set_target_pressure(0)
				if("max")
					set_target_pressure(max_pressure_setting)
				if("set")
					var/new_pressure = tgui_input_number(ui.user,"Enter new output pressure (0-[max_pressure_setting]kPa)","Pressure control",get_target_pressure(),max_pressure_setting,0)
					set_target_pressure(between(0, new_pressure, max_pressure_setting))
			. = TRUE

	if(.)
		update_rust_device()
	add_fingerprint(ui.user)
	update_icon()

/obj/machinery/atmospherics/binary/pump/power_change()
	var/old_stat = stat
	..()
	if(old_stat != stat)
		update_rust_device()
		update_icon()

/obj/machinery/atmospherics/binary/pump/on_pump_target_reached()
	update_icon()

/obj/machinery/atmospherics/binary/pump/update_icon()
	if(!powered())
		icon_state = "[base_icon]-off"
	else
		icon_state = "[use_power ? "[base_icon]-on" : "[base_icon]-off"]"

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

/obj/machinery/atmospherics/binary/pump/wrench_act(mob/user, obj/item/W)
	if (!(stat & NOPOWER) && use_power)
		to_chat(user, span_warning("You cannot unwrench this [src], turn it off first."))
		return ITEM_INTERACT_BLOCKING
	if(!can_unwrench())
		to_chat(user, span_warning("You cannot unwrench this [src], it too exerted due to internal pressure."))
		add_fingerprint(user)
		return ITEM_INTERACT_BLOCKING
	if (use_tool(user, W, src, delay = 40, volume = 50, message_self = "You begin to unfasten \the [src]..."))
		user.visible_message( \
			span_infoplain(span_bold("\The [user]") + " unfastens \the [src]."), \
			span_notice("You have unfastened \the [src]."), \
			"You hear ratchet.")
		atom_deconstruct()
	return ITEM_INTERACT_SUCCESS

// click_alt is now /datum/interaction/machine_alt/pump_max_output (above),
// from the interaction-framework conversion landed on master.
/obj/machinery/atmospherics/binary/pump/click_ctrl(mob/user)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(!allowed(user))
		to_chat(user, span_warning("Access denied."))
		return CLICK_ACTION_BLOCKING

	update_use_power(!use_power)
	set_on(!!use_power)
	update_rust_device()
	update_icon()
	add_fingerprint(user)
	to_chat(user, span_notice("You toggle the [name] [use_power ? "on" : "off"]."))

	return CLICK_ACTION_SUCCESS

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

/obj/machinery/atmospherics/binary/pump/high_power/update_icon()
	if(!powered())
		icon_state = "off"
	else
		icon_state = "[use_power ? "on" : "off"]"
