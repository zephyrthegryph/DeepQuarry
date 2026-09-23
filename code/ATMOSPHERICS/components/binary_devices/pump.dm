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
	icon = 'icons/atmos/pump.dmi'
	icon_state = "map_off"
	construction_type = /obj/item/pipe/directional
	pipe_state = "pump"
	level = 1
	var/base_icon = "pump"

	name = "gas pump"
	desc = "A pump that moves gas from one place to another."

	var/target_pressure = ONE_ATMOSPHERE

	//var/max_volume_transfer = 10000

	use_power = USE_POWER_OFF
	idle_power_usage = 150		//internal circuitry, friction losses and stuff
	power_rating = 7500			//7500 W ~ 10 HP

	var/max_pressure_setting = 15000	//kPa

	var/frequency = ZERO_FREQ
	var/id = null
	var/datum/radio_frequency/radio_connection
	var/sleeping_input_mixture_id
	var/sleeping_input_revision = -1
	var/sleeping_input_temperature = 0
	var/sleeping_input_moles = 0
	var/sleeping_output_mixture_id
	var/sleeping_output_revision = -1
	var/sleeping_output_pressure = 0

/obj/machinery/atmospherics/binary/pump/Initialize(mapload)
	. = ..()
	ensure_pump_materials()

	air1.set_volume(ATMOS_DEFAULT_VOLUME_PUMP)
	air2.set_volume(ATMOS_DEFAULT_VOLUME_PUMP)
	if(frequency)
		set_frequency(frequency)

/obj/machinery/atmospherics/binary/pump/Destroy()
	clear_gas_dependencies()
	unregister_radio(src, frequency)
	. = ..()

/obj/machinery/atmospherics/binary/pump/disconnect(obj/machinery/atmospherics/reference)
	wake_for_state_change()
	return ..()

/obj/machinery/atmospherics/binary/pump/on
	icon_state = "map_on"
	use_power = USE_POWER_IDLE

/obj/machinery/atmospherics/binary/pump/fuel
	icon_state = "map_off-fuel"
	base_icon = "pump-fuel"
	icon_connect_type = "-fuel"
	connect_types = CONNECT_TYPE_FUEL

/obj/machinery/atmospherics/binary/pump/fuel/on
	icon_state = "map_on-fuel"
	use_power = USE_POWER_IDLE

/obj/machinery/atmospherics/binary/pump/aux
	icon_state = "map_off-aux"
	base_icon = "pump-aux"
	icon_connect_type = "-aux"
	connect_types = CONNECT_TYPE_AUX

/obj/machinery/atmospherics/binary/pump/aux/on
	icon_state = "map_on-aux"
	use_power = USE_POWER_IDLE

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

/obj/machinery/atmospherics/binary/pump/process()
	last_power_draw = 0
	last_flow_rate = 0

	if((stat & (NOPOWER|BROKEN)) || !use_power)
		return PROCESS_KILL

	var/power_draw = -1
	var/pressure_delta = target_pressure - air2.return_pressure()

	if(pressure_delta > BINARY_PUMP_PRESSURE_TOLERANCE && air1.return_temperature() > 0)
		//Figure out how much gas to transfer to meet the target pressure.
		var/transfer_moles = calculate_transfer_moles(air1, air2, pressure_delta, (network2)? network2.volume : 0)
		power_draw = queue_pump_gas(src, air1, air2, transfer_moles, power_rating)

	if(power_draw < 0)
		hibernate_until_gas_changes()
		return PROCESS_KILL

	return 1

/obj/machinery/atmospherics/binary/pump/pump_transaction_committed(actual_moles)
	if(actual_moles >= MINIMUM_MOLES_TO_PUMP)
		network1?.mark_dirty()
		network2?.mark_dirty()
	if(actual_moles < MINIMUM_MOLES_TO_PUMP || target_pressure - air2.return_pressure() <= BINARY_PUMP_PRESSURE_TOLERANCE || air1.total_moles() < MINIMUM_MOLES_TO_PUMP)
		hibernate_until_gas_changes()

/obj/machinery/atmospherics/binary/pump/proc/hibernate_until_gas_changes()
	var/datum/weakref/WR = WEAKREF(src)
	sleeping_input_mixture_id = air1?.arena_id()
	sleeping_input_revision = air1?.revision() || -1
	sleeping_input_temperature = air1?.return_temperature() || 0
	sleeping_input_moles = air1?.total_moles() || 0
	sleeping_output_mixture_id = air2?.arena_id()
	sleeping_output_revision = air2?.revision() || -1
	sleeping_output_pressure = air2?.return_pressure() || 0
	SSmachines.sleeping_gas_devices[WR.reference] = WR
	SSmachines.subscribe_gas_dependency(sleeping_input_mixture_id, WR)
	SSmachines.subscribe_gas_dependency(sleeping_output_mixture_id, WR)
	STOP_MACHINE_PROCESSING(src)

/obj/machinery/atmospherics/binary/pump/proc/clear_gas_dependencies()
	var/datum/weakref/WR = WEAKREF(src)
	SSmachines.unsubscribe_gas_dependency(sleeping_input_mixture_id, WR)
	SSmachines.unsubscribe_gas_dependency(sleeping_output_mixture_id, WR)
	sleeping_input_mixture_id = null
	sleeping_input_revision = -1
	sleeping_input_temperature = 0
	sleeping_input_moles = 0
	sleeping_output_mixture_id = null
	sleeping_output_revision = -1
	sleeping_output_pressure = 0
	if(WR?.reference)
		SSmachines.sleeping_gas_devices.Remove(WR.reference)

/obj/machinery/atmospherics/binary/pump/gas_dependency_interest_mask()
	// A pump only needs P/T. Total moles follows pV=nRT; composition-only
	// changes cannot make its pressure transfer predicate actionable.
	return GAS_DEPENDENCY_PRESSURE | GAS_DEPENDENCY_TEMPERATURE

/obj/machinery/atmospherics/binary/pump/gas_dependency_changed(mixture_id, change_mask, list/observation, observation_index)
	if(!(change_mask & gas_dependency_interest_mask()) || !use_power || (stat & (NOPOWER|BROKEN)))
		return FALSE
	var/observed_revision = observation && observation_index ? observation[observation_index + 2] : null
	if(mixture_id == sleeping_input_mixture_id)
		if(!air1 || air1.arena_id() != sleeping_input_mixture_id)
			return TRUE
		if(!isnull(observed_revision))
			sleeping_input_temperature = observation[observation_index + 4]
			sleeping_input_moles = observation[observation_index + 14]
		else if(air1.revision() == sleeping_input_revision)
			return FALSE
		else
			sleeping_input_temperature = air1.return_temperature()
			sleeping_input_moles = air1.total_moles()
	else if(mixture_id == sleeping_output_mixture_id)
		if(!air2 || air2.arena_id() != sleeping_output_mixture_id)
			return TRUE
		if(!isnull(observed_revision))
			sleeping_output_pressure = observation[observation_index + 3]
		else if(air2.revision() == sleeping_output_revision)
			return FALSE
		else
			sleeping_output_pressure = air2.return_pressure()
	else
		return FALSE
	return target_pressure - sleeping_output_pressure > BINARY_PUMP_PRESSURE_TOLERANCE && sleeping_input_temperature > 0 && sleeping_input_moles >= MINIMUM_MOLES_TO_PUMP

/obj/machinery/atmospherics/binary/pump/proc/wake_for_state_change()
	clear_gas_dependencies()
	START_MACHINE_PROCESSING(src)

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
		"target_output" = target_pressure,
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
		"pressure_set" = round(target_pressure*100),	//Nano UI can't handle rounded non-integers, apparently.
		"max_pressure" = max_pressure_setting,
		"last_flow_rate" = round(last_flow_rate*10),
		"last_power_draw" = round(last_power_draw),
		"max_power_draw" = power_rating,
	)

	return data

/obj/machinery/atmospherics/binary/pump/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id) || (signal.data["sigtype"]!="command"))
		return 0
	wake_for_state_change()

	if(signal.data["power"])
		if(text2num(signal.data["power"]))
			update_use_power(USE_POWER_IDLE)
		else
			update_use_power(USE_POWER_OFF)

	if("power_toggle" in signal.data)
		update_use_power(!use_power)

	if(signal.data["set_output_pressure"])
		target_pressure = between(0, text2num(signal.data["set_output_pressure"]), ONE_ATMOSPHERE*50)

	if(signal.data["status"])
		addtimer(CALLBACK(src, PROC_REF(broadcast_status)), 2, TIMER_DELETE_ME)
		return //do not update_icon

	addtimer(CALLBACK(src, PROC_REF(broadcast_status)), 2, TIMER_DELETE_ME)
	update_icon()
	return

/obj/machinery/atmospherics/binary/pump/attack_ghost(mob/user)
	tgui_interact(user)

/obj/machinery/atmospherics/binary/pump/attack_hand(mob/user)
	if(..())
		return
	add_fingerprint(user)
	if(!allowed(user))
		to_chat(user, span_warning("Access denied."))
		return
	tgui_interact(user)

/obj/machinery/atmospherics/binary/pump/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE
	wake_for_state_change()

	switch(action)
		if("power")
			update_use_power(!use_power)
			. = TRUE
		if("set_press")
			var/press = params["press"]
			switch(press)
				if("min")
					target_pressure = 0
				if("max")
					target_pressure = max_pressure_setting
				if("set")
					var/new_pressure = tgui_input_number(ui.user,"Enter new output pressure (0-[max_pressure_setting]kPa)","Pressure control",src.target_pressure,max_pressure_setting,0)
					src.target_pressure = between(0, new_pressure, max_pressure_setting)
			. = TRUE

	add_fingerprint(ui.user)
	update_icon()

/obj/machinery/atmospherics/binary/pump/power_change()
	var/old_stat = stat
	..()
	if(old_stat != stat)
		wake_for_state_change()
		update_icon()

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

/obj/machinery/atmospherics/binary/pump/click_alt(mob/user)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(!allowed(user))
		to_chat(user, span_warning("Access denied."))
		return CLICK_ACTION_BLOCKING

	to_chat(user, span_notice("You set the [name] to max output"))
	target_pressure = max_pressure_setting
	wake_for_state_change()
	add_fingerprint(user)
	return CLICK_ACTION_SUCCESS


/obj/machinery/atmospherics/binary/pump/click_ctrl(mob/user)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(!allowed(user))
		to_chat(user, span_warning("Access denied."))
		return CLICK_ACTION_BLOCKING

	update_use_power(!use_power)
	wake_for_state_change()
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

	power_rating = 15000	//15000 W ~ 20 HP

/obj/machinery/atmospherics/binary/pump/high_power/on
	use_power = USE_POWER_IDLE
	icon_state = "map_on"

/obj/machinery/atmospherics/binary/pump/high_power/update_icon()
	if(!powered())
		icon_state = "off"
	else
		icon_state = "[use_power ? "on" : "off"]"
