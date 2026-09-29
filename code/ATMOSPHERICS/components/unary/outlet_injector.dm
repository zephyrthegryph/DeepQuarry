//Basically a one way passive valve. If the pressure inside is greater than the environment then gas will flow passively,
//but it does not permit gas to flow back from the environment into the injector. Can be turned off to prevent any gas flow.
//When it receives the "inject" signal, it will try to pump it's entire contents into the environment regardless of pressure, using power.

/obj/machinery/atmospherics/unary/outlet_injector
	icon = 'icons/atmos/injector.dmi'
	icon_state = "map_injector"
	pipe_state = "injector"
	gas_dependency_mask = GAS_DEPENDENCY_ALL

	name = "air injector"
	desc = "Passively injects air into its surroundings. Has a valve attached to it that can control flow rate."

	use_power = USE_POWER_OFF
	idle_power_usage = 150		//internal circuitry, friction losses and stuff
	power_rating = 15000	//15000 W ~ 20 HP

	var/injecting = 0

	var/volume_rate = 50	//flow rate limit

	var/frequency = ZERO_FREQ
	var/id = null
	var/datum/radio_frequency/radio_connection

	level = 1

/obj/machinery/atmospherics/unary/outlet_injector/Initialize(mapload)
	. = ..()

	air_contents.set_volume(ATMOS_DEFAULT_VOLUME_PUMP + 500)	//Give it a small reservoir for injecting. Also allows it to have a higher flow rate limit than vent pumps, to differentiate injectors a bit more.
	if(frequency)
		set_frequency(frequency)

/obj/machinery/atmospherics/unary/outlet_injector/update_icon()
	if(!powered())
		icon_state = "off"
	else
		icon_state = "[use_power ? "on" : "off"]"

/obj/machinery/atmospherics/unary/outlet_injector/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	add_underlay(T, node, dir)

/obj/machinery/atmospherics/unary/outlet_injector/power_change()
	var/old_stat = stat
	..()
	if(old_stat != stat)
		update_icon()

/obj/machinery/atmospherics/unary/outlet_injector/machine_step()
	..()

	last_power_draw = 0
	last_flow_rate = 0

	if((stat & (NOPOWER|BROKEN)) || !use_power)
		register_gas_dependencies()
		return PROCESS_KILL

	var/power_draw = -1
	var/datum/gas_mixture/environment = loc.return_air()

	if(environment && air_contents.return_temperature() > 0)
		var/transfer_moles = (volume_rate/air_contents.return_volume())*air_contents.total_moles() //apply flow rate limit
		power_draw = queue_pump_gas(src, air_contents, environment, transfer_moles, power_rating)

	if (power_draw >= 0)
		// Power, turf publication, and network dirtiness are finalized by the
		// subsystem's single atomic Rust transfer commit.
	else
		register_gas_dependencies()
		return PROCESS_KILL

	return 1

/obj/machinery/atmospherics/unary/outlet_injector/pump_transaction_committed(actual_moles)
	if(actual_moles >= MINIMUM_MOLES_TO_PUMP)
		return
	register_gas_dependencies()

/// The same test process() makes before it pumps: powered, on, and holding enough warm gas.
/obj/machinery/atmospherics/unary/outlet_injector/gas_wake_condition()
	if((stat & (NOPOWER|BROKEN)) || !use_power)
		return FALSE
	return air_contents && air_contents.return_temperature() > 0 && air_contents.total_moles() >= MINIMUM_MOLES_TO_PUMP

/obj/machinery/atmospherics/unary/outlet_injector/proc/inject()
	if(injecting || (stat & NOPOWER))
		return 0

	var/datum/gas_mixture/environment = loc.return_air()
	if (!environment)
		return 0

	injecting = 1

	if(air_contents.return_temperature() > 0)
		var/power_used = pump_gas(src, air_contents, environment, air_contents.total_moles(), power_rating)
		use_power(power_used)
		// same enroll-turf reason as in process().
		if(isturf(loc))
			var/turf/open/T = loc
			if(istype(T))
				T.update_visuals()
				T.air_update_turf(FALSE, FALSE)

		if(network)
			network.mark_dirty()

	flick("inject", src)

/obj/machinery/atmospherics/unary/outlet_injector/proc/set_frequency(new_frequency)
	GLOB.radio_service.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		radio_connection = GLOB.radio_service.add_object(src, frequency)

/obj/machinery/atmospherics/unary/outlet_injector/proc/broadcast_status()
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, "source", src)

	signal.data = list(
		"tag" = id,
		"device" = "AO",
		"power" = use_power,
		"volume_rate" = volume_rate,
		"sigtype" = "status"
	)

	radio_connection.post_signal(src, signal)

	return 1

/obj/machinery/atmospherics/unary/outlet_injector/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id) || (signal.data["sigtype"]!="command"))
		return 0

	if(signal.data["power"])
		update_use_power(text2num(signal.data["power"]))

	if(signal.data["power_toggle"])
		update_use_power(!use_power)

	if(signal.data["inject"])
		spawn inject()
		return

	if(signal.data["set_volume_rate"])
		var/number = text2num(signal.data["set_volume_rate"])
		volume_rate = between(0, number, air_contents.return_volume())

	if(signal.data["status"])
		om_after(src, 2, PROC_REF(broadcast_status))
		return //do not update_icon

	om_after(src, 2, PROC_REF(broadcast_status))
	update_icon()

/obj/machinery/atmospherics/unary/outlet_injector/hide(i)
	update_underlays()

/obj/machinery/atmospherics/unary/outlet_injector/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/outlet_injector_toggle,
	)
	..()

/// The old attack_hand: never called ..(), so it stays ungated.
/datum/interaction/machine_hand/ungated/outlet_injector_toggle
	id = "outlet_injector_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	message_self = "You toggle %TARGET%."
	effect = /obj/machinery/atmospherics/unary/outlet_injector/proc/interaction_toggle

/obj/machinery/atmospherics/unary/outlet_injector/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	injecting = !injecting
	update_use_power(injecting ? USE_POWER_IDLE : USE_POWER_OFF)
	update_icon()
	return TRUE

/obj/machinery/atmospherics/unary/outlet_injector/multitool_act(mob/user, obj/item/W)
	var/list/options = list("Frequency", "ID Tag", "-SAVE TO BUFFER-", "Cancel")
	var/answer = rerun_ask(user, "k197", TYPE_PROC_REF(/atom, multitool_act), args, /datum/om/prompt/choice/alert, message = "[src] has an ID of \"[id]\" and a frequency of [frequency]. What would you like to change?", title = "Options!", choices = options)
	if(isnull(answer))
		return ITEM_INTERACT_BLOCKING
	if(!answer || answer == "Cancel" || !Adjacent(user))
		return ITEM_INTERACT_BLOCKING

	switch(answer)
		if("Frequency")
			var/new_frequency = rerun_ask(user, "k203", TYPE_PROC_REF(/atom, multitool_act), args, /datum/om/prompt/number, message = "[src] has a frequency of [frequency]. What would you like it to be?", title = "[src] frequency", default = frequency, max = RADIO_HIGH_FREQ, min = RADIO_LOW_FREQ)
			if(isnull(new_frequency))
				return ITEM_INTERACT_BLOCKING
			if(new_frequency)
				new_frequency = sanitize_frequency(new_frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ)
				set_frequency(new_frequency)
				to_chat(user, span_notice("You set the [src]'s frequency to [frequency]."))

		if("ID Tag")
			var/_answer_k210 = rerun_ask(user, "k210", TYPE_PROC_REF(/atom, multitool_act), args, /datum/om/prompt/text, message = "Please insert an ID tag for [src], example 'exhaust_port'.", title = "Set ID Tag", default = id, max_length = MAX_NAME_LEN)
			if(isnull(_answer_k210))
				return ITEM_INTERACT_BLOCKING
			id = _answer_k210
			if(id)
				to_chat(user, span_notice("You set the [src]'s ID Tag to \"[id]\"."))

		if("-SAVE TO BUFFER-")
			var/obj/item/multitool/tool = W
			rel_set(tool, "connectable", src)
			to_chat(user, span_notice("You copied the [src] into the [tool]'s buffer!"))

	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/unary/outlet_injector/wrench_act(mob/user, obj/item/W)
	use_tool(user, W, src, delay = 40, volume = 50, message_self = "You begin to unfasten \the [src]...", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/unary/outlet_injector/proc/wrench_act_tool_done(mob/user)
	user.visible_message( \
		span_infoplain(span_bold("\The [user]") + " unfastens \the [src]."), \
		span_notice("You have unfastened \the [src]."), \
		"You hear a ratchet.")
	atom_deconstruct()

/obj/machinery/atmospherics/unary/outlet_injector/click_ctrl(mob/user)
	if (volume_rate == ATMOS_DEFAULT_VOLUME_PUMP + 500 || use_power == USE_POWER_OFF)
		return ..()

	volume_rate = ATMOS_DEFAULT_VOLUME_PUMP + 500
	to_chat(user, span_notice("You have set \the [src] to [volume_rate]"))
	update_icon()

