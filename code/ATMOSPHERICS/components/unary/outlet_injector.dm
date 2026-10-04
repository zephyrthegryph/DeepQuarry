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

/// Appearance reader: powered and switched on.
/obj/machinery/atmospherics/unary/outlet_injector/proc/appearance_injecting()
	return powered() && use_power

APPEARANCE_TEMPLATE(/obj/machinery/atmospherics/unary/outlet_injector, "{appearance_injecting?on:off}")

/obj/machinery/atmospherics/unary/outlet_injector/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	add_underlay(T, node, dir)

/obj/machinery/atmospherics/unary/outlet_injector/machine_step()
	..()

	last_power_draw = 0
	last_flow_rate = 0

	if((!operable()) || !use_power)
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
	if((!operable()) || !use_power)
		return FALSE
	return air_contents && air_contents.return_temperature() > 0 && air_contents.total_moles() >= MINIMUM_MOLES_TO_PUMP

/obj/machinery/atmospherics/unary/outlet_injector/proc/inject()
	if(injecting || (has_stat(NOPOWER)))
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
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency))

/obj/machinery/atmospherics/unary/outlet_injector/proc/broadcast_status()
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(signal.source), src)

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
		set_use_power(text2num(signal.data["power"]))

	if(signal.data["power_toggle"])
		set_use_power(!use_power)

	if(signal.data["inject"])
		spawn inject()
		return

	if(signal.data["set_volume_rate"])
		var/number = text2num(signal.data["set_volume_rate"])
		volume_rate = between(0, number, air_contents.return_volume())

	if(signal.data["status"])
		after(src, 0.2 SECONDS, PROC_REF(broadcast_status))
		return //do not update_icon

	after(src, 0.2 SECONDS, PROC_REF(broadcast_status))
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
	feedback = /datum/msg/interaction/machine_hand/ungated/outlet_injector_toggle
	id = "outlet_injector_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/machinery/atmospherics/unary/outlet_injector/proc/interaction_toggle

/datum/msg/interaction/machine_hand/ungated/outlet_injector_toggle
	self = "You toggle %T%."

/obj/machinery/atmospherics/unary/outlet_injector/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	injecting = !injecting
	set_use_power(injecting ? USE_POWER_IDLE : USE_POWER_OFF)
	return TRUE

/obj/machinery/atmospherics/unary/outlet_injector/multitool_act(mob/user, obj/item/W)
	return injector_config_stage(user, W, list())

/obj/machinery/atmospherics/unary/outlet_injector/proc/injector_config_stage(mob/user, obj/item/W, list/config_answers)
	var/static/list/options = list("Frequency", "ID Tag", "-SAVE TO BUFFER-", "Cancel")
	if(!("k197" in config_answers))
		open_request(src, /datum/prompt/choice/atmos_config_review, PROC_REF(injector_config_answered), answerer = user, config_operator = user, config_tool = W, config_answers = config_answers, config_key = "k197", question = "[src] has an ID of \"[id]\" and a frequency of [frequency]. What would you like to change?", title = "Options!", choices = options, buttons = TRUE)
		return ITEM_INTERACT_BLOCKING
	var/answer = config_answers["k197"]
	if(isnull(answer))
		return ITEM_INTERACT_BLOCKING
	if(!answer || answer == "Cancel" || !Adjacent(user))
		return ITEM_INTERACT_BLOCKING

	switch(answer)
		if("Frequency")
			if(!("k203" in config_answers))
				open_request(src, /datum/prompt/number/atmos_config_review, PROC_REF(injector_config_answered), answerer = user, config_operator = user, config_tool = W, config_answers = config_answers, config_key = "k203", question = "[src] has a frequency of [frequency]. What would you like it to be?", title = "[src] frequency", default = frequency, config_max = RADIO_HIGH_FREQ, config_min = RADIO_LOW_FREQ)
				return ITEM_INTERACT_BLOCKING
			var/new_frequency = config_answers["k203"]
			if(isnull(new_frequency))
				return ITEM_INTERACT_BLOCKING
			if(new_frequency)
				new_frequency = sanitize_frequency(new_frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ)
				set_frequency(new_frequency)
				to_chat(user, span_notice("You set the [src]'s frequency to [frequency]."))

		if("ID Tag")
			if(!("k210" in config_answers))
				open_request(src, /datum/prompt/text/atmos_config_review, PROC_REF(injector_config_answered), answerer = user, config_operator = user, config_tool = W, config_answers = config_answers, config_key = "k210", question = "Please insert an ID tag for [src], example 'exhaust_port'.", title = "Set ID Tag", default = id, max_len = MAX_NAME_LEN, name_text = TRUE)
				return ITEM_INTERACT_BLOCKING
			var/_answer_k210 = config_answers["k210"]
			if(isnull(_answer_k210))
				return ITEM_INTERACT_BLOCKING
			id = _answer_k210
			if(id)
				to_chat(user, span_notice("You set the [src]'s ID Tag to \"[id]\"."))

		if("-SAVE TO BUFFER-")
			var/obj/item/multitool/tool = W
			rel_set(tool, nameof(tool.connectable), src)
			to_chat(user, span_notice("You copied the [src] into the [tool]'s buffer!"))

	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/unary/outlet_injector/wrench_act(mob/user, obj/item/W)
	use_tool(user, W, src, delay = 40, volume = 50, start_self = "You begin to unfasten \the [src]...", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/unary/outlet_injector/proc/wrench_act_tool_done(mob/user)
	act_message(user, src, MSG_SELF(span_notice("You have unfastened %T%.")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " unfastens %T%.")), \
		MSG_BLIND("You hear a ratchet."))
	atom_deconstruct()

/obj/machinery/atmospherics/unary/outlet_injector/click_ctrl(mob/user)
	if (volume_rate == ATMOS_DEFAULT_VOLUME_PUMP + 500 || use_power == USE_POWER_OFF)
		return ..()

	volume_rate = ATMOS_DEFAULT_VOLUME_PUMP + 500
	to_chat(user, span_notice("You have set \the [src] to [volume_rate]"))
	update_icon()


/obj/machinery/atmospherics/unary/outlet_injector/proc/injector_config_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/list/config_answers
	var/mob/config_operator
	var/obj/item/config_tool
	if(istype(context.answer, /datum/prompt/choice/atmos_config_review))
		var/datum/prompt/choice/atmos_config_review/choice_request = context.answer
		config_answers = choice_request.config_answers.Copy()
		config_answers[choice_request.config_key] = choice_request.answer_value
		config_operator = choice_request.config_operator
		config_tool = choice_request.config_tool
	else if(istype(context.answer, /datum/prompt/text/atmos_config_review))
		var/datum/prompt/text/atmos_config_review/text_request = context.answer
		config_answers = text_request.config_answers.Copy()
		config_answers[text_request.config_key] = text_request.answer_value
		config_operator = text_request.config_operator
		config_tool = text_request.config_tool
	else if(istype(context.answer, /datum/prompt/number/atmos_config_review))
		var/datum/prompt/number/atmos_config_review/number_request = context.answer
		config_answers = number_request.config_answers.Copy()
		config_answers[number_request.config_key] = number_request.answer_value
		config_operator = number_request.config_operator
		config_tool = number_request.config_tool
	else
		return
	// Recovery: old kept.finished refreshed the target even if replay failed.
	var/datum/result/replay = safe_call(PROC_REF(injector_config_stage), config_operator, config_tool, config_answers)
	if(!replay.ok)
		stack_trace("Atmos configuration replay: [replay.error]")
	SStgui.update_uis(src)
	return replay.value

/datum/prompt/choice/atmos_config_review
	timeout = 0
	var/list/config_answers
	var/config_key
	var/config_port
	var/mob/config_operator
	var/config_operator_expected = FALSE
	var/obj/item/config_tool
	var/config_tool_expected = FALSE

CAPABILITIES(/datum/prompt/choice/atmos_config_review)
	ref_one(nameof(config_operator), /mob)
	ref_one(nameof(config_tool), /obj/item)

/datum/prompt/choice/atmos_config_review/prepare(datum/act/context)
	. = ..()
	var/mob/captured_operator = config_operator
	config_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(config_operator))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(config_operator), captured_operator)
	var/obj/item/captured_tool = config_tool
	config_tool_expected = !isnull(captured_tool)
	rel_clear(src, nameof(config_tool))
	if(captured_tool && !QDELETED(captured_tool))
		rel_set(src, nameof(config_tool), captured_tool)

/datum/prompt/choice/atmos_config_review/recheck_extra()
	if((config_operator_expected && QDELETED(config_operator)) || (config_tool_expected && QDELETED(config_tool)))
		return "gone"

/datum/prompt/text/atmos_config_review
	timeout = 0
	var/list/config_answers
	var/config_key
	var/config_port
	var/mob/config_operator
	var/config_operator_expected = FALSE
	var/obj/item/config_tool
	var/config_tool_expected = FALSE

CAPABILITIES(/datum/prompt/text/atmos_config_review)
	ref_one(nameof(config_operator), /mob)
	ref_one(nameof(config_tool), /obj/item)

/datum/prompt/text/atmos_config_review/prepare(datum/act/context)
	. = ..()
	var/mob/captured_operator = config_operator
	config_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(config_operator))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(config_operator), captured_operator)
	var/obj/item/captured_tool = config_tool
	config_tool_expected = !isnull(captured_tool)
	rel_clear(src, nameof(config_tool))
	if(captured_tool && !QDELETED(captured_tool))
		rel_set(src, nameof(config_tool), captured_tool)

/datum/prompt/text/atmos_config_review/recheck_extra()
	if((config_operator_expected && QDELETED(config_operator)) || (config_tool_expected && QDELETED(config_tool)))
		return "gone"

/datum/prompt/number/atmos_config_review
	timeout = 0
	var/list/config_answers
	var/config_key
	var/config_port
	var/mob/config_operator
	var/config_operator_expected = FALSE
	var/obj/item/config_tool
	var/config_tool_expected = FALSE
	var/config_max = INFINITY
	var/config_min = 0

CAPABILITIES(/datum/prompt/number/atmos_config_review)
	ref_one(nameof(config_operator), /mob)
	ref_one(nameof(config_tool), /obj/item)

/datum/prompt/number/atmos_config_review/prepare(datum/act/context)
	. = ..()
	var/mob/captured_operator = config_operator
	config_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(config_operator))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(config_operator), captured_operator)
	var/obj/item/captured_tool = config_tool
	config_tool_expected = !isnull(captured_tool)
	rel_clear(src, nameof(config_tool))
	if(captured_tool && !QDELETED(captured_tool))
		rel_set(src, nameof(config_tool), captured_tool)

/datum/prompt/number/atmos_config_review/recheck_extra()
	if((config_operator_expected && QDELETED(config_operator)) || (config_tool_expected && QDELETED(config_tool)))
		return "gone"

/datum/prompt/number/atmos_config_review/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default || 0, config_max, config_min, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/text/atmos_config_review/normalize(given)
	return strip_name_tokens(given)
