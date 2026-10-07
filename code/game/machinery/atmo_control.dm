// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

#define SENSOR_PRESSURE		(1<<0)
#define SENSOR_TEMPERATURE	(1<<1)
#define SENSOR_O2			(1<<2)
#define SENSOR_PHORON		(1<<3)
#define SENSOR_N2			(1<<4)
#define SENSOR_CO2			(1<<5)
#define SENSOR_N2O			(1<<6)
#define SENSOR_CH4			(1<<7)

/obj/machinery/air_sensor
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "gsensor1"
	name = "Gas Sensor"
	desc = "Senses atmospheric conditions."

	anchored = TRUE

	var/id_tag
	var/frequency = PUMPS_FREQ

	on = 1
	var/output = 3
	//Flags:
	// 1 for pressure
	// 2 for temperature
	// Output >= 4 includes gas composition
	// 4 for oxygen concentration
	// 8 for phoron concentration
	// 16 for nitrogen concentration
	// 32 for carbon dioxide concentration

	var/datum/radio_frequency/radio_connection

/// The look (the draw sweep: from its template).
/obj/machinery/air_sensor/draw(datum/look/look)
	..()
	look.state("gsensor[on]")

TRACKED(/obj/machinery/air_sensor, output)

/// What the sensor reports from `air_sample`, at the resolution it broadcasts.
/obj/machinery/air_sensor/proc/sensor_readings(datum/gas_mixture/air_sample)
	var/list/readings = list()
	if(!air_sample)
		return readings
	if(output&1)
		readings["pressure"] = num2text(round(air_sample.return_pressure(),0.1),)
	if(output&2)
		readings["temperature"] = round(air_sample.return_temperature(),0.1)
	if(output>4)
		var/total_moles = air_sample.total_moles()
		if(total_moles > 0)
			if(output&4)
				readings[GAS_O2] = round(100*LINDA_GAS_AMT(air_sample, GAS_O2)/total_moles,0.1)
			if(output&8)
				readings[GAS_PHORON] = round(100*LINDA_GAS_AMT(air_sample, GAS_PHORON)/total_moles,0.1)
			if(output&16)
				readings[GAS_N2] = round(100*LINDA_GAS_AMT(air_sample, GAS_N2)/total_moles,0.1)
			if(output&32)
				readings[GAS_CO2] = round(100*LINDA_GAS_AMT(air_sample, GAS_CO2)/total_moles,0.1)
			if(output&64)
				readings[GAS_CH4] = round(100*LINDA_GAS_AMT(air_sample, GAS_CH4)/total_moles,0.1)
		else
			readings[GAS_O2] = 0
			readings[GAS_PHORON] = 0
			readings[GAS_N2] = 0
			readings[GAS_CO2] = 0
			readings[GAS_CH4] = 0
	return readings

/// The broadcast, flattened: the sensor's gas watch wakes it only when this changes.
/obj/machinery/air_sensor/proc/current_reading_signature()
	return list2params(sensor_readings(return_air()))

// The sensor broadcasts what it reads when it is placed and again whenever the rounded readings it sends change: a gas watch on the air it
// stands in hears every change, and the broadcast goes out only when the readings differ from the last one sent.
CAPABILITIES(/obj/machinery/air_sensor)
	gas_watch(changed = PROC_REF(air_changed))
	after_init(0, then(PROC_REF(broadcast_after_init)))
	op("unfasten", tool(TOOL_WRENCH), wait(0), label("Unfasten"), then(PROC_REF(unfastened)))
	op("configure", tool(TOOL_MULTITOOL), wait(0), label("Configure"),
		asks(/datum/prompt/choice, fields = list("title" = "Options!", "question" = computed(PROC_REF(options_question)), "choices" = computed(PROC_REF(option_names)), "timeout" = 0), step = "option"),
		asks(/datum/prompt/text, fields = list("title" = "Set ID Tag", "question" = computed(PROC_REF(tag_question)), "default" = computed(PROC_REF(tag_default)), "max_len" = MAX_NAME_LEN, "timeout" = 0), step = "tag", when = PROC_REF(saving_to_buffer)),
		then(PROC_REF(option_chosen)))

/obj/machinery/air_sensor
	/// The readings of the last broadcast (list2params), so an unchanged reading is not sent again.
	var/tmp/last_broadcast

/// Broadcasts the readings now, whether or not they changed.
/obj/machinery/air_sensor/proc/broadcast_readings()
	last_broadcast = current_reading_signature()
	if(!on || !radio_connection())
		return
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	signal.data["tag"] = id_tag
	signal.data["timestamp"] = EXPIRY_AT(src, CLOCK_WORLD, 0)
	var/list/readings = sensor_readings(return_air())
	for(var/key in readings)
		signal.data[key] = readings[key]
	signal.data["sigtype"]="status"
	radio_connection().post_signal(src, signal, radio_filter = RADIO_ATMOSIA)

/obj/machinery/air_sensor/proc/broadcast_after_init(datum/act/timer/A)
	broadcast_readings()

/// The air changed: a broadcast when what the sensor reports changed.
/obj/machinery/air_sensor/proc/air_changed(list/observation, index)
	if(current_reading_signature() != last_broadcast)
		broadcast_readings()

/obj/machinery/air_sensor/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	gas_watch_arm(src)
	broadcast_readings()

/obj/machinery/air_sensor/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_ATMOSIA))
	last_broadcast = null

/obj/machinery/air_sensor/Initialize(mapload)
	. = ..()
	if(frequency)
		set_frequency(frequency)

/obj/machinery/air_sensor/proc/unfastened(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	playsound(src, W.usesound, 50, 1)
	act_message(user, src, MSG_SELF(span_notice("You have unfastened %T%.")), MSG_OTHERS("%U% unfastens %T%."), MSG_BLIND("You hear ratcheting."))
	var/obj/item/pipe_gsensor/gsensor = new /obj/item/pipe_gsensor(loc)
	gsensor.id_tag = id_tag
	gsensor.output = output
	replace_with(src, gsensor)
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)

#define ONOFF_TOGGLE(flag) "\[[(output & flag) ? "YES" : "NO"]]"
/// The multitool menu: each reading with whether it is sent, and saving the sensor to the multitool's buffer.
/obj/machinery/air_sensor/proc/sensor_options()
	return list(
		"Pressure: [ONOFF_TOGGLE(SENSOR_PRESSURE)]" 		= SENSOR_PRESSURE,
		"Temperature: [ONOFF_TOGGLE(SENSOR_TEMPERATURE)]" 	= SENSOR_TEMPERATURE,
		"[GASNAME_O2]: [ONOFF_TOGGLE(SENSOR_O2)]" 			= SENSOR_O2,
		"[GASNAME_PHORON]: [ONOFF_TOGGLE(SENSOR_PHORON)]" 	= SENSOR_PHORON,
		"[GASNAME_N2]: [ONOFF_TOGGLE(SENSOR_N2)]" 			= SENSOR_N2,
		"[GASNAME_CO2]: [ONOFF_TOGGLE(SENSOR_CO2)]" 		= SENSOR_CO2,
		"[GASNAME_N2O]: [ONOFF_TOGGLE(SENSOR_N2O)]" 		= SENSOR_N2O,
		"[GASNAME_CH4]: [ONOFF_TOGGLE(SENSOR_CH4)]" 		= SENSOR_CH4,
		"-SAVE TO BUFFER-" = "multitool"
	)
#undef ONOFF_TOGGLE

/obj/machinery/air_sensor/proc/option_names(datum/act/op/A)
	. = list()
	for(var/name in sensor_options())
		. += name

/obj/machinery/air_sensor/proc/options_question(datum/act/op/A)
	return "[src] has an ID of \"[id_tag]\" and a frequency of [frequency]. What would you like to change?"

/obj/machinery/air_sensor/proc/tag_question(datum/act/op/A)
	return "Please insert an ID tag for [src], example 'burn_chamber'."

/obj/machinery/air_sensor/proc/tag_default(datum/act/op/A)
	return id_tag

/// The second question (the tag) is asked only when the first answer saves the sensor to the buffer.
/obj/machinery/air_sensor/proc/saving_to_buffer(datum/act/op/A)
	return sensor_options()[A.step_value("option")] == "multitool"

/obj/machinery/air_sensor/proc/option_chosen(datum/act/op/A)
	var/mob/user = A.actor
	var/choice = sensor_options()[A.step_value("option")]
	if(isnull(choice))
		return
	if(choice == "multitool")
		var/new_tag = A.step_value("tag")
		if(!new_tag)
			return
		id_tag = new_tag
		var/obj/item/multitool/M = A.held
		if(istype(M) && M.loc == user)
			rel_set(M, nameof(M.connectable), src)
			to_chat(user, span_notice("You save [src] into [M]'s buffer."))
		return
	set_output(output ^ choice)
	broadcast_readings()


/obj/machinery/computer/general_air_control

	icon_keyboard = "atmos_key"
	icon_screen = "tank"
	name = "Computer"
	desc = "Control atmospheric systems, remotely."
	var/frequency = PUMPS_FREQ
	var/list/sensors
	var/list/sensor_information
	var/datum/radio_frequency/radio_connection
	circuit = /obj/item/circuitboard/air_management

/obj/machinery/computer/general_air_control/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/machinery/computer/general_air_control/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption) return

	var/id_tag = signal.data["tag"]
	if(!id_tag || !LAZYFIND(sensors, id_tag)) return

	LAZYSET(sensor_information, id_tag, signal.data)

CAPABILITIES(/obj/machinery/computer/general_air_control)
	interface("GeneralAtmoControl")
	op("configure", tool(TOOL_MULTITOOL), wait(0), label("Configure"),
		needs(req(PROC_REF(sensor_buffer_valid), because = MSG(air_control/bad_sensor)), req(PROC_REF(port_buffer_valid), because = MSG(air_control/bad_port)), req(PROC_REF(sensor_name_valid), because = MSG(air_control/no_name))),
		asks(/datum/prompt/choice, fields = list("title" = "Configuration", "question" = computed(PROC_REF(control_question)), "choices" = computed(PROC_REF(control_options)), "timeout" = 0), step = "option"),
		asks(/datum/prompt/choice, fields = list("title" = "Configuration", "question" = computed(PROC_REF(port_question)), "choices" = list("Set", "Clear", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "port", when = PROC_REF(configuring_port)),
		asks(/datum/prompt/number, fields = list("title" = computed(PROC_REF(frequency_title)), "question" = computed(PROC_REF(frequency_question)), "default" = computed(PROC_REF(frequency_default)), "min_value" = RADIO_LOW_FREQ, "max_value" = RADIO_HIGH_FREQ, "timeout" = 0), step = "frequency", when = PROC_REF(configuring_frequency)),
		asks(/datum/prompt/choice, fields = list("title" = "Configuration", "question" = "Would you like to add or remove a sensor/meter?", "choices" = list("Add", "Remove", "Cancel"), "timeout" = 0), step = "sensor_action", when = PROC_REF(configuring_sensors)),
		asks(/datum/prompt/text/air_control_sensor_name, fields = list("title" = "Name", "question" = "Enter a name for the Sensor/Meter.", "name_text" = TRUE, "device" = computed(PROC_REF(buffered_sensor)), "timeout" = 0), step = "sensor_name", when = PROC_REF(adding_sensor)),
		asks(/datum/prompt/choice, fields = list("title" = "Sensor/Meter Removal", "question" = "Select a sensor/meter to remove", "choices" = computed(PROC_REF(sensor_removal_choices)), "timeout" = 0), step = "sensor_remove", when = PROC_REF(removing_sensor)),
		asks(/datum/prompt/yes_no, fields = list("title" = "Warning", "question" = computed(PROC_REF(sensor_removal_question)), "timeout" = 0), step = "sensor_confirm", when = PROC_REF(removing_sensor)),
		then(PROC_REF(control_option_op)))
	ui_shape(sensors = list_of(row()))

/obj/machinery/computer/general_air_control/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/sensors_ui[0]
	if(length(sensors))
		for(var/id_tag in sensors)
			var/long_name = LAZYACCESS(sensors, id_tag)
			var/list/sensor_data = LAZYACCESS(sensor_information, id_tag)
			sensors_ui[++sensors_ui.len] = list("long_name" = long_name, "sensor_data" = sensor_data)
	else
		sensors_ui = null

	data["sensors"] = sensors_ui

	return data

/obj/machinery/computer/general_air_control/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_ATMOSIA))

/// The multitool menu of a console (a console with ports adds Inlet and Outlet).
/obj/machinery/computer/general_air_control/proc/control_options(datum/act/op/A)
	return TYPE_TABLE_GET(src, air_control_menu)

/// The multitool menu's choices (constant per type).
TYPE_TABLE_DECLARE(/obj/machinery/computer/general_air_control, air_control_menu, list("Sensors", "Frequency", "Cancel"))
TYPE_TABLE(/obj/machinery/computer/general_air_control/large_tank_control, air_control_menu, list("Inlet", "Outlet", "Sensors", "Frequency", "Cancel"))
TYPE_TABLE(/obj/machinery/computer/general_air_control/supermatter_core, air_control_menu, list("Inlet", "Outlet", "Sensors", "Frequency"))

/obj/machinery/computer/general_air_control/proc/control_question(datum/act/op/A)
	return "[src] has a frequency of [frequency]. What would you like to change?"

MSG_DEF_SELF(air_control/bad_sensor, "Error: No device in multitool buffer, or incompatible device is not a sensor or meter.")
MSG_DEF_SELF(air_control/bad_port, "Error: The multitool buffer does not contain the required vent or injector.")
MSG_DEF_SELF(air_control/no_name, "Error: No name was given for the sensor/meter.")

/obj/machinery/computer/general_air_control/proc/configuring_port(datum/act/op/A)
	return A.step_value("option") in list("Inlet", "Outlet")

/obj/machinery/computer/general_air_control/proc/configuring_frequency(datum/act/op/A)
	return A.step_value("option") == "Frequency"

/obj/machinery/computer/general_air_control/proc/configuring_sensors(datum/act/op/A)
	return A.step_value("option") == "Sensors"

/obj/machinery/computer/general_air_control/proc/adding_sensor(datum/act/op/A)
	return configuring_sensors(A) && A.step_value("sensor_action") == "Add"

/obj/machinery/computer/general_air_control/proc/removing_sensor(datum/act/op/A)
	return configuring_sensors(A) && A.step_value("sensor_action") == "Remove"

/obj/machinery/computer/general_air_control/proc/port_question(datum/act/op/A)
	return "Would you like to set an [lowertext(A.step_value("option"))] or clear it?"

/obj/machinery/computer/general_air_control/proc/frequency_question(datum/act/op/A)
	return "[src] has a frequency of [frequency]. What would you like it to be?"

/obj/machinery/computer/general_air_control/proc/frequency_title(datum/act/op/A)
	return "[src] frequency"

/obj/machinery/computer/general_air_control/proc/frequency_default(datum/act/op/A)
	return frequency

/obj/machinery/computer/general_air_control/proc/buffered_sensor(datum/act/op/A)
	var/obj/item/multitool/tool = A.held
	return tool?.connectable()

/obj/machinery/computer/general_air_control/proc/sensor_buffer_valid(datum/act/op/A)
	if(!adding_sensor(A))
		return TRUE
	var/datum/prompt/text/air_control_sensor_name/R = A.step_answer("sensor_name")
	if(R && !R.device)
		return FALSE
	var/obj/machinery/device = buffered_sensor(A)
	return istype(device, /obj/machinery/meter) || istype(device, /obj/machinery/air_sensor)

/obj/machinery/computer/general_air_control/proc/port_buffer_valid(datum/act/op/A)
	if(!configuring_port(A) || A.step_value("port") != "Set")
		return TRUE
	var/obj/machinery/device = buffered_sensor(A)
	if(A.step_value("option") == "Inlet")
		return istype(device, /obj/machinery/atmospherics/unary/outlet_injector)
	return istype(device, /obj/machinery/atmospherics/unary/vent_pump)

/obj/machinery/computer/general_air_control/proc/sensor_name_valid(datum/act/op/A)
	return !A.step_answer("sensor_name") || !!A.step_value("sensor_name")

/// Naming the sensor/meter being added keeps the captured device alive by relation.
/datum/prompt/text/air_control_sensor_name
	var/obj/machinery/device

CAPABILITIES(/datum/prompt/text/air_control_sensor_name)
	ref_one(nameof(device), /obj/machinery)

/obj/machinery/computer/general_air_control/proc/sensor_removal_choices(datum/act/op/A)
	var/list/options = list()
	for(var/tag in sensors)
		options[LAZYACCESS(sensors, tag)] = tag
	return options

/obj/machinery/computer/general_air_control/proc/sensor_removal_question(datum/act/op/A)
	return "Are you sure you want to remove the sensor/meter '[A.step_value("sensor_remove")]'?"

/obj/machinery/computer/general_air_control/proc/control_option_op(datum/act/op/A)
	switch(A.step_value("option"))
		if("Inlet")
			configure_inlet(A)
		if("Outlet")
			configure_outlet(A)
		if("Sensors")
			configure_sensors(A)
		if("Frequency")
			set_frequency(sanitize_frequency(A.step_value("frequency"), RADIO_LOW_FREQ, RADIO_HIGH_FREQ))

/obj/machinery/computer/general_air_control/proc/configure_inlet(datum/act/op/A)
	return

/obj/machinery/computer/general_air_control/proc/configure_outlet(datum/act/op/A)
	return

/obj/machinery/computer/general_air_control/proc/configure_sensors(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, "CONFIGURE SENSOR FUNC")
	if(adding_sensor(A))
		var/datum/prompt/text/air_control_sensor_name/R = A.step_answer("sensor_name")
		var/obj/machinery/device = R.device
		var/device_name = A.step_value("sensor_name")
		if(!device_name)
			to_chat(user, span_warning("Error: No name was given for [device]."))
			return
		if(istype(device, /obj/machinery/air_sensor))
			var/obj/machinery/air_sensor/AS = device
			LAZYSET(sensors, AS.id_tag, device_name)
		else
			var/obj/machinery/meter/M = device
			LAZYSET(sensors, M.id, device_name)
		to_chat(user, span_notice("You have added the [device] to the [src] under the name [device_name]!"))
	else if(removing_sensor(A) && A.step_value("sensor_confirm"))
		var/datum/prompt/choice/R = A.step_answer("sensor_remove")
		var/to_remove = A.step_value("sensor_remove")
		LAZYREMOVE(sensors, R.choices[to_remove])
		to_chat(user, span_notice("Successfully removed sensor/meter with name [to_remove]"))

/obj/machinery/computer/general_air_control/Initialize(mapload)
	. = ..()
	if(frequency)
		set_frequency(frequency)

/obj/machinery/computer/general_air_control/large_tank_control
	icon = 'icons/obj/computer.dmi'
	frequency = PUBLIC_LOW_FREQ
	name = "Large Tank Computer"
	desc = "Controls various devices for managing a gas tank."
	var/input_tag
	var/output_tag
	var/list/input_info
	var/list/output_info
	var/input_flow_setting = 200
	var/pressure_setting = ONE_ATMOSPHERE * 45
	circuit = /obj/item/circuitboard/air_management/tank_control

CAPABILITIES(/obj/machinery/computer/general_air_control/large_tank_control)
	op("adj_pressure", ui_act("adj_pressure", arg("adj_pressure", num(0, 50*ONE_ATMOSPHERE))), then(PROC_REF(ui_act_adj_pressure)))
	op("adj_input_flow_rate", ui_act("adj_input_flow_rate", arg("adj_input_flow_rate", num(0, ATMOS_DEFAULT_VOLUME_PUMP + 500))), then(PROC_REF(ui_act_adj_input_flow_rate)))
	op("in_refresh_status", ui_act("in_refresh_status"), then(PROC_REF(ui_act_tank_command)))
	op("in_toggle_injector", ui_act("in_toggle_injector"), then(PROC_REF(ui_act_tank_command)))
	op("in_set_flowrate", ui_act("in_set_flowrate"), then(PROC_REF(ui_act_tank_command)))
	op("out_refresh_status", ui_act("out_refresh_status"), then(PROC_REF(ui_act_tank_command)))
	op("out_toggle_power", ui_act("out_toggle_power"), then(PROC_REF(ui_act_tank_command)))
	op("out_set_pressure", ui_act("out_set_pressure"), then(PROC_REF(ui_act_tank_command)))

/obj/machinery/computer/general_air_control/large_tank_control/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["pressure_setting"] = pressure_setting

	data["tanks"] = 1

	if(input_info)
		data["input_info"] = list("power" = input_info["power"], "volume_rate" = round(input_info["volume_rate"], 0.1))
	else
		data["input_info"] = null

	if(output_info)
		data["output_info"] = list("power" = output_info["power"], "output_pressure" = output_info["internal"])
	else
		data["output_info"] = null

	data["input_flow_setting"] = round(input_flow_setting, 0.1)
	data["max_pressure"] = 50*ONE_ATMOSPHERE
	data["max_flowrate"] = ATMOS_DEFAULT_VOLUME_PUMP + 500

	return data

/obj/machinery/computer/general_air_control/large_tank_control/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption) return

	var/id_tag = signal.data["tag"]

	if(input_tag == id_tag)
		input_info = signal.data
	else if(output_tag == id_tag)
		output_info = signal.data
	else
		..(signal)

/obj/machinery/computer/general_air_control/large_tank_control/proc/ui_act_adj_pressure(datum/act/op/A, adj_pressure)
	if(isnull(adj_pressure))
		return FALSE
	pressure_setting = adj_pressure
	return TRUE

/obj/machinery/computer/general_air_control/large_tank_control/proc/ui_act_adj_input_flow_rate(datum/act/op/A, adj_input_flow_rate)
	if(isnull(adj_input_flow_rate))
		return FALSE
	input_flow_setting = adj_input_flow_rate //default flow rate limit for air injectors
	return TRUE

/// The injector / vent commands: one radio signal each (the op's key says which).
/obj/machinery/computer/general_air_control/large_tank_control/proc/ui_act_tank_command(datum/act/op/A)
	if(!radio_connection())
		return FALSE
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(/datum/admin_rank::source), src)
	switch(A.key)
		if("in_refresh_status")
			input_info = null
			signal.data = list ("tag" = input_tag, "status" = 1)
		if("in_toggle_injector")
			input_info = null
			signal.data = list ("tag" = input_tag, "power_toggle" = 1)
		if("in_set_flowrate")
			input_info = null
			signal.data = list ("tag" = input_tag, "set_volume_rate" = "[input_flow_setting]")
		if("out_refresh_status")
			output_info = null
			signal.data = list ("tag" = output_tag, "status" = 1)
		if("out_toggle_power")
			output_info = null
			signal.data = list ("tag" = output_tag, "power_toggle" = 1)
		if("out_set_pressure")
			output_info = null
			signal.data = list ("tag" = output_tag, "set_internal_pressure" = "[pressure_setting]")
	signal.data["sigtype"]="command"
	radio_connection().post_signal(src, signal, radio_filter = RADIO_ATMOSIA)
	return TRUE


/obj/machinery/computer/general_air_control/large_tank_control/configure_outlet(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/multitool/tool = A.held
	switch(A.step_value("port"))
		if ("Set")
			to_chat(user, span_notice("The buffer is [tool.connectable()]"))
			if (!istype(tool.connectable(), /obj/machinery/atmospherics/unary/vent_pump))
				to_chat(user, span_notice("Error: Buffer is either empty, or object in buffer is invalid. Device should be a Unary Vent."))
				return

			var/obj/machinery/atmospherics/unary/vent_pump/pump = tool.connectable()
			output_tag = pump.id_tag
			pump.set_external_pressure_bound(0)
			pump.external_pressure_bound_default = 0
			to_chat(user, span_notice("You have set the outlet!"))
			return

		if ("Clear")
			output_tag = null
			to_chat(user, span_notice("You have cleared the outlet!"))
			return

/obj/machinery/computer/general_air_control/large_tank_control/configure_inlet(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/multitool/tool = A.held
	switch(A.step_value("port"))
		if ("Set")
			if (!istype(tool.connectable(), /obj/machinery/atmospherics/unary/outlet_injector))
				to_chat(user, span_notice("Error: Buffer is either empty, or object in buffer is invalid. Device should be Injector"))
				return

			var/obj/machinery/atmospherics/unary/outlet_injector/injector = tool.connectable()
			input_tag = injector.id
			to_chat(user, span_notice("You have set the inlet"))
			return

		if ("Clear")
			input_tag = null
			to_chat(user, span_notice("You have cleared the inlet!"))
			return

/obj/machinery/computer/general_air_control/supermatter_core
	icon = 'icons/obj/computer.dmi'
	frequency = ENGINE_FREQ
	var/input_tag
	var/output_tag
	var/list/input_info
	var/list/output_info
	var/input_flow_setting = 700
	var/pressure_setting = 100
	circuit = /obj/item/circuitboard/air_management/supermatter_core

CAPABILITIES(/obj/machinery/computer/general_air_control/supermatter_core)
	op("adj_pressure", ui_act("adj_pressure", arg("adj_pressure", num(0, 10*ONE_ATMOSPHERE))), then(PROC_REF(ui_act_adj_pressure)))
	op("adj_input_flow_rate", ui_act("adj_input_flow_rate", arg("adj_input_flow_rate", num(0, ATMOS_DEFAULT_VOLUME_PUMP + 500))), then(PROC_REF(ui_act_adj_input_flow_rate)))
	op("in_refresh_status", ui_act("in_refresh_status"), then(PROC_REF(ui_act_tank_command)))
	op("in_toggle_injector", ui_act("in_toggle_injector"), then(PROC_REF(ui_act_tank_command)))
	op("in_set_flowrate", ui_act("in_set_flowrate"), then(PROC_REF(ui_act_tank_command)))
	op("out_refresh_status", ui_act("out_refresh_status"), then(PROC_REF(ui_act_tank_command)))
	op("out_toggle_power", ui_act("out_toggle_power"), then(PROC_REF(ui_act_tank_command)))
	op("out_set_pressure", ui_act("out_set_pressure"), then(PROC_REF(ui_act_tank_command)))

/obj/machinery/computer/general_air_control/supermatter_core/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["pressure_setting"] = pressure_setting
	data["core"] = 1

	if(input_info)
		data["input_info"] = list("power" = input_info["power"], "volume_rate" = round(input_info["volume_rate"], 0.1))
	else
		data["input_info"] = null

	if(output_info)
		// Yes, TECHNICALLY this is not output pressure, it's a pressure LIMIT. HOWEVER. The fact that the UI uses "output_pressure"
		// in EXACTLY THE SAME WAY as "pressure_limit" means this should just pass it as the other fucking data argument because holy shit what the
		// fuck
		data["output_info"] = list("power" = output_info["power"], "output_pressure" = output_info["external"])
	else
		data["output_info"] = null

	data["input_flow_setting"] = round(input_flow_setting, 0.1)
	data["max_pressure"] = 10*ONE_ATMOSPHERE
	data["max_flowrate"] = ATMOS_DEFAULT_VOLUME_PUMP + 500

	return data

/obj/machinery/computer/general_air_control/supermatter_core/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption) return

	var/id_tag = signal.data["tag"]

	if(input_tag == id_tag)
		input_info = signal.data
	else if(output_tag == id_tag)
		output_info = signal.data
	else
		..(signal)

/obj/machinery/computer/general_air_control/supermatter_core/proc/ui_act_adj_pressure(datum/act/op/A, adj_pressure)
	if(isnull(adj_pressure))
		return FALSE
	pressure_setting = adj_pressure
	return TRUE

/obj/machinery/computer/general_air_control/supermatter_core/proc/ui_act_adj_input_flow_rate(datum/act/op/A, adj_input_flow_rate)
	if(isnull(adj_input_flow_rate))
		return FALSE
	input_flow_setting = adj_input_flow_rate //default flow rate limit for air injectors
	return TRUE

/// The injector / vent commands: one radio signal each (the op's key says which).
/obj/machinery/computer/general_air_control/supermatter_core/proc/ui_act_tank_command(datum/act/op/A)
	if(!radio_connection())
		return FALSE
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(/datum/admin_rank::source), src)
	switch(A.key)
		if("in_refresh_status")
			input_info = null
			signal.data = list ("tag" = input_tag, "status" = 1)
		if("in_toggle_injector")
			input_info = null
			signal.data = list ("tag" = input_tag, "power_toggle" = 1)
		if("in_set_flowrate")
			input_info = null
			signal.data = list ("tag" = input_tag, "set_volume_rate" = "[input_flow_setting]")
		if("out_refresh_status")
			output_info = null
			signal.data = list ("tag" = output_tag, "status" = 1)
		if("out_toggle_power")
			output_info = null
			signal.data = list ("tag" = output_tag, "power_toggle" = 1)
		if("out_set_pressure")
			output_info = null
			signal.data = list ("tag" = output_tag, "set_external_pressure" = "[pressure_setting]", "checks" = 1)
	signal.data["sigtype"]="command"
	radio_connection().post_signal(src, signal, radio_filter = RADIO_ATMOSIA)
	return TRUE


/obj/machinery/computer/general_air_control/supermatter_core/configure_outlet(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/multitool/tool = A.held
	switch(A.step_value("port"))
		if ("Set")
			if (!istype(tool.connectable(), /obj/machinery/atmospherics/unary/vent_pump))
				to_chat(user, span_warning("Error: Buffer is either empty, or object in buffer is invalid. Device should be Air Vent"))
				return

			var/obj/machinery/atmospherics/unary/vent_pump/pump = tool.connectable()
			output_tag = pump.id_tag
			pump.set_external_pressure_bound(0)
			pump.external_pressure_bound_default = 0
			to_chat(user, span_notice("You have set the outlet!"))
			return

		if ("Clear")
			output_tag = null
			to_chat(user, span_notice("You have cleared the outlet!"))
			return

/obj/machinery/computer/general_air_control/supermatter_core/configure_inlet(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/multitool/tool = A.held
	switch(A.step_value("port"))
		if ("Set")
			to_chat(user, span_notice("The buffer is [tool.connectable()]"))
			if (!istype(tool.connectable(), /obj/machinery/atmospherics/unary/outlet_injector))
				to_chat(user, span_warning("Error: Buffer is either empty, or object in buffer is invalid. Device should be Injector"))
				return

			var/obj/machinery/atmospherics/unary/outlet_injector/injector = tool.connectable()
			input_tag = injector.id
			to_chat(user, span_notice("You have set the inlet!"))
			return

		if ("Clear")
			input_tag = null
			to_chat(user, span_notice("You have cleared the inlet!"))
			return

/obj/machinery/computer/general_air_control/fuel_injection
	icon = 'icons/obj/computer.dmi'
	icon_screen = "alert:0"
	var/device_tag
	var/list/device_info
	var/cutoff_temperature = 2000
	var/on_temperature = 1200
	circuit = /obj/item/circuitboard/air_management/injector_control

/// Automation: each step re-reads the latest sensor broadcasts and commands the injectors.
/obj/machinery/computer/general_air_control/fuel_injection/var/automation = 0
TRACKED(/obj/machinery/computer/general_air_control/fuel_injection, automation)

/// While its automation is on, every machine service interval; without a radio the work stops until automation is switched again.
/obj/machinery/computer/general_air_control/fuel_injection/proc/work_step(datum/act/timer/A)
	if(!radio_connection())
		return PROCESS_KILL
	if(automation)

		var/injecting = 0
		for(var/id_tag in sensor_information)
			var/list/data = LAZYACCESS(sensor_information, id_tag)
			if(data["temperature"])
				if(data["temperature"] >= cutoff_temperature)
					injecting = 0
					break
				if(data["temperature"] <= on_temperature)
					injecting = 1

		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO //radio signal
		rel_set(signal, nameof(signal.source), src)

		signal.data = list(
			"tag" = device_tag,
			"power" = injecting,
			"sigtype"="command"
		)

		radio_connection().post_signal(src, signal, radio_filter = RADIO_ATMOSIA)

CAPABILITIES(/obj/machinery/computer/general_air_control/fuel_injection)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(automation), wakes_on = list(nameof(automation)))
	op("refresh_status", ui_act("refresh_status"), then(PROC_REF(ui_act_refresh_status)))
	op("toggle_automation", ui_act("toggle_automation"), then(PROC_REF(ui_act_toggle_automation)))
	op("toggle_injector", ui_act("toggle_injector"), then(PROC_REF(ui_act_toggle_injector)))
	op("injection", ui_act("injection"), then(PROC_REF(ui_act_injection)))

/obj/machinery/computer/general_air_control/fuel_injection/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["automation"] = automation
	data["fuel"] = 1

	if(device_info)
		data["device_info"] = list("power" = device_info["power"], "volume_rate" = device_info["volume_rate"])
	else
		data["device_info"] = null

	return data

/obj/machinery/computer/general_air_control/fuel_injection/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption) return

	var/id_tag = signal.data["tag"]

	if(device_tag == id_tag)
		device_info = signal.data
	else
		..(signal)

/obj/machinery/computer/general_air_control/fuel_injection/proc/ui_act_refresh_status(datum/act/op/A)
	device_info = null
	if(!radio_connection())
		return FALSE

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(/datum/admin_rank::source), src)
	signal.data = list(
		"tag" = device_tag,
		"status" = 1,
		"sigtype"="command"
	)
	radio_connection().post_signal(src, signal, radio_filter = RADIO_ATMOSIA)
	. = TRUE

/obj/machinery/computer/general_air_control/fuel_injection/proc/ui_act_toggle_automation(datum/act/op/A)
	set_automation(!automation)
	return OP_OK

/obj/machinery/computer/general_air_control/fuel_injection/proc/ui_act_toggle_injector(datum/act/op/A)
	device_info = null
	if(!radio_connection())
		return FALSE

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(/datum/admin_rank::source), src)
	signal.data = list(
		"tag" = device_tag,
		"power_toggle" = 1,
		"sigtype"="command"
	)

	radio_connection().post_signal(src, signal, radio_filter = RADIO_ATMOSIA)
	. = TRUE

/obj/machinery/computer/general_air_control/fuel_injection/proc/ui_act_injection(datum/act/op/A)
	if(!radio_connection())
		return FALSE

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(/datum/admin_rank::source), src)
	signal.data = list(
		"tag" = device_tag,
		"inject" = 1,
		"sigtype"="command"
	)

	radio_connection().post_signal(src, signal, radio_filter = RADIO_ATMOSIA)
	. = TRUE

#undef SENSOR_PRESSURE
#undef SENSOR_TEMPERATURE
#undef SENSOR_O2
#undef SENSOR_PHORON
#undef SENSOR_N2
#undef SENSOR_CO2
#undef SENSOR_N2O
#undef SENSOR_CH4

/// radio connection (a relation view: it reads null once the target is deleted).
/obj/machinery/air_sensor/proc/radio_connection() as /datum/radio_frequency
	return radio_connection

/// radio connection (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/general_air_control/proc/radio_connection() as /datum/radio_frequency
	return radio_connection
