// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

//--------------------------------------------
// Gas filter - omni variant
//--------------------------------------------
/obj/machinery/atmospherics/omni/atmos_filter
	name = "omni gas filter"
	desc = "An advanced version of the gas filter, able to be configured for filtering of multiple gasses."
	icon_state = "map_filter"
	pipe_state = "omni_filter"

	/// Port role views, derived from the owned `ports` by rebuild_port_roles().
	var/list/datum/omni_port/atmos_filters
	var/datum/omni_port/input
	var/datum/omni_port/output

	use_power = USE_POWER_IDLE
	idle_power_usage = 150		//internal circuitry, friction losses and stuff
	power_rating = 7500			//7500 W ~ 10 HP

	var/max_flow_rate = 200
	var/set_flow_rate = 200


/obj/machinery/atmospherics/omni/atmos_filter/Initialize(mapload)
	. = ..()

	for(var/datum/omni_port/P in ports)
		P.air.set_volume(ATMOS_DEFAULT_VOLUME_FILTER)

/obj/machinery/atmospherics/omni/atmos_filter/sort_ports()
	var/any_updated = FALSE
	for(var/datum/omni_port/P in ports)
		if(P.update)
			any_updated = TRUE
			P.air.set_volume(200)
	if(any_updated)
		rebuild_port_roles()

/// Derived view: input, output and the filter ports, recomputed from the owned ports' modes.
/obj/machinery/atmospherics/omni/atmos_filter/proc/rebuild_port_roles()
	rel_clear(src, nameof(input))
	rel_clear(src, nameof(output))
	rel_clear(src, nameof(atmos_filters))
	for(var/datum/omni_port/P as anything in ports)
		switch(P.mode)
			if(ATM_INPUT)
				rel_set(src, nameof(input), P)
			if(ATM_OUTPUT)
				rel_set(src, nameof(output), P)
			if(ATM_O2 to ATM_LASTGAS)
				rel_add(src, nameof(atmos_filters), P)

/obj/machinery/atmospherics/omni/atmos_filter/error_check()
	if(!input || !output || !atmos_filters)
		return 1
	if(length(atmos_filters) < 1) //requires at least 1 atmos_filter ~otherwise why are you using a filter?
		return 1

	return 0

/// The omni filter is a Rust budget group (rust_set_budget_leg()): a masked leg from the input to each configured filter port
/// plus a clean leg to the output. The requested moles from the input's live gas, the entropy/power budget and the split
/// across the legs are computed in Rust each device step (power_budget.rs); this only declares the ports and settings.
/obj/machinery/atmospherics/omni/atmos_filter/push_to_rust()
	if(QDELETED(src))
		return
	last_power_draw = 0
	last_flow_rate = 0
	rust_unregister_all_devices_n()
	if(!operable() || !use_power || !input || !output || !length(atmos_filters)) // ALLOW(derived_reads): set_use_power() and power_change() bump rust_device_rev, as do port binds and disconnect() (nodes, ports, modes)
		return
	var/available_power = material_pump_power(power_rating) // ALLOW(derived_reads): fixed by the material
	var/efficiency = ATMOS_FILTER_EFFICIENCY * (material_pump_efficiency() / 0.8)
	var/input_index = ports.Find(input) // ALLOW(derived_reads): set_use_power() and power_change() bump rust_device_rev, as do port binds and disconnect() (nodes, ports, modes)
	rust_set_budget_leg("output", input_index, ports.Find(output), RUST_FLOW_FILTER, 0, RUST_ROLE_CLEAN, 0, set_flow_rate, available_power, efficiency)
	for(var/datum/omni_port/P in atmos_filters)
		var/gasid = mode_to_gasid(P.mode)
		if(!gasid)
			continue
		rust_set_budget_leg("filter_[P]", input_index, ports.Find(P), RUST_FLOW_FILTER, 1 << GAS_IDX(gasid), RUST_ROLE_OUTPUT, 0, set_flow_rate, available_power, efficiency)

/// A step's result: the moles the group moved and the power it drew, billed.
/obj/machinery/atmospherics/omni/atmos_filter/rust_device_stepped(moles, power_w, target_reached)
	last_power_draw = power_w
	if(power_w > 0)
		use_power(power_w)
	var/before = input?.air ? input.air.total_moles() + moles : moles
	last_flow_rate = (before > 0 && input?.air) ? (moles / before) * input.air.return_volume() : 0

TRACKED(/obj/machinery/atmospherics/omni/atmos_filter, set_flow_rate)

/// The Rust group is pushed (once per frame) when the rate or (through wake_for_state_change()) a port or mode changes.
/obj/machinery/atmospherics/omni/atmos_filter/derived()
	. = ..()
	. += rust_push(nameof(rust_device_rev), nameof(set_flow_rate))

/// The window's data.
/obj/machinery/atmospherics/omni/atmos_filter/ui_data(datum/act/eval/A)
	. = list()
	.["power"] = use_power
	.["config"] = configuring
	var/list/part = ui_data_part_atmos_filter(A)
	for(var/key in part)
		.[key] = part[key]

/// The computed part of the window's data.
/obj/machinery/atmospherics/omni/atmos_filter/proc/ui_data_part_atmos_filter(datum/act/eval/A)
	var/list/data = list()


	var/portData[0]
	for(var/datum/omni_port/P in ports)
		if(!configuring && P.mode == 0)
			continue

		var/input = 0
		var/output = 0
		var/atmo_filter = 1
		var/f_type = null
		switch(P.mode)
			if(ATM_INPUT)
				input = 1
				atmo_filter = 0
			if(ATM_OUTPUT)
				output = 1
				atmo_filter = 0
			if(ATM_O2 to ATM_LASTGAS)
				f_type = mode_send_switch(P.mode)

		portData[++portData.len] = list("dir" = dir_name(P.dir, capitalize = 1), \
										"input" = input, \
										"output" = output, \
										"atmo_filter" = atmo_filter, \
										"f_type" = f_type)

	if(portData.len)
		data["ports"] = portData
	if(output)
		data["set_flow_rate"] = round(set_flow_rate)
		data["last_flow_rate"] = round(last_flow_rate)

	return data

/obj/machinery/atmospherics/omni/atmos_filter/proc/mode_send_switch(mode = ATM_NONE)
	switch(mode)
		if(ATM_O2)
			return GASNAME_O2
		if(ATM_N2)
			return GASNAME_N2
		if(ATM_CO2)
			return GASNAME_CO2
		if(ATM_P)
			return GASNAME_PHORON //*cough* Plasma *cough*
		if(ATM_N2O)
			return GASNAME_N2O
		if(ATM_METHANE)
			return GASNAME_CH4
		else
			return null

/// Requirement: the ports and rates are changed only while configuring with the filter off (silent, as the old early returns were).
/obj/machinery/atmospherics/omni/atmos_filter/proc/configurable(datum/act/op/A)
	return (configuring && !use_power) ? null : /datum/msg/req_silent

/obj/machinery/atmospherics/omni/atmos_filter/proc/ui_act_power(datum/act/op/A)
	wake_for_state_change()
	if(!configuring)
		set_use_power(!use_power)
	else
		set_use_power(USE_POWER_OFF)
	. = TRUE
	wake_for_state_change()

/obj/machinery/atmospherics/omni/atmos_filter/proc/ui_act_configure(datum/act/op/A)
	wake_for_state_change()
	set_configuring(!configuring)
	if(configuring)
		set_use_power(USE_POWER_OFF)
	. = TRUE
	wake_for_state_change()

/obj/machinery/atmospherics/omni/atmos_filter/proc/set_flow_rate_question(datum/act/op/A)
	return "Enter new flow rate limit (0-[max_flow_rate]L/s)"

/obj/machinery/atmospherics/omni/atmos_filter/proc/ui_act_set_flow_rate(datum/act/op/A)
	wake_for_state_change()
	var/new_flow_rate = A.step_value("k236")
	set_set_flow_rate(between(0, new_flow_rate, max_flow_rate))
	. = TRUE
	wake_for_state_change()

/obj/machinery/atmospherics/omni/atmos_filter/proc/ui_act_switch_mode(datum/act/op/A, dir, mode)
	wake_for_state_change()
	switch_mode(dir_flag(dir), mode_return_switch(mode))
	. = TRUE
	wake_for_state_change()

/obj/machinery/atmospherics/omni/atmos_filter/proc/ui_act_switch_filter(datum/act/op/A, dir)
	wake_for_state_change()
	var/new_filter = A.step_value("k247")
	if(!new_filter)
		return
	switch_filter(dir_flag(dir), mode_return_switch(new_filter))
	. = TRUE
	wake_for_state_change()

/obj/machinery/atmospherics/omni/atmos_filter/proc/mode_return_switch(mode)
	switch(mode)
		if(GASNAME_O2)
			return ATM_O2
		if(GASNAME_N2)
			return ATM_N2
		if(GASNAME_CO2)
			return ATM_CO2
		if(GASNAME_PHORON)
			return ATM_P
		if(GASNAME_N2O)
			return ATM_N2O
		if(GASNAME_CH4)
			return ATM_METHANE
		if("in")
			return ATM_INPUT
		if("out")
			return ATM_OUTPUT
		if("None")
			return ATM_NONE
		else
			return null

/obj/machinery/atmospherics/omni/atmos_filter/proc/switch_filter(dir, mode)
	//check they aren't trying to disable the input or output ~this can only happen if they hack the cached tmpl file
	for(var/datum/omni_port/P in ports)
		if(P.dir == dir)
			if(P.mode == ATM_INPUT || P.mode == ATM_OUTPUT)
				return

	switch_mode(dir, mode)

/obj/machinery/atmospherics/omni/atmos_filter/proc/switch_mode(port, mode)
	if(mode == null || !port)
		return
	var/datum/omni_port/target_port = null
	var/list/other_ports = new()

	for(var/datum/omni_port/P in ports)
		if(P.dir == port)
			target_port = P
		else
			other_ports += P

	var/previous_mode = null
	if(target_port)
		previous_mode = target_port.mode
		target_port.mode = mode
		if(target_port.mode != previous_mode)
			handle_port_change(target_port)
		else
			return
	else
		return

	for(var/datum/omni_port/P in other_ports)
		if(P.mode == mode)
			var/old_mode = P.mode
			P.mode = previous_mode
			if(P.mode != old_mode)
				handle_port_change(P)

	update_ports()

/obj/machinery/atmospherics/omni/atmos_filter/proc/handle_port_change(datum/omni_port/P)
	wake_for_state_change()
	switch(P.mode)
		if(ATM_NONE)
			initialize_directions &= ~P.dir
			P.disconnect()
		else
			initialize_directions |= P.dir
			P.connect()
	P.update = 1

CAPABILITIES(/obj/machinery/atmospherics/omni/atmos_filter)
	pipe_device_window("OmniFilter")
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("configure", ui_act("configure"), then(PROC_REF(ui_act_configure)))
	op("set_flow_rate", ui_act("set_flow_rate"), needs(req(PROC_REF(configurable))),
		asks(/datum/prompt/number, fields = list("question" = computed(PROC_REF(set_flow_rate_question)), "title" = "Flow Rate Control", "default" = nameof(set_flow_rate), "max_value" = nameof(max_flow_rate), "timeout" = 0), step = "k236"),
		then(PROC_REF(ui_act_set_flow_rate)))
	op("switch_mode", ui_act("switch_mode", arg("dir"), arg("mode", schema_text(4096))), needs(req(PROC_REF(configurable))), then(PROC_REF(ui_act_switch_mode)))
	op("switch_filter", ui_act("switch_filter", arg("dir")), needs(req(PROC_REF(configurable))),
		asks(/datum/prompt/choice, fields = list("question" = "Select filter mode:", "title" = "Change filter", "choices" = list("None", GASNAME_O2, GASNAME_N2, GASNAME_CO2, GASNAME_PHORON, GASNAME_N2O, GASNAME_CH4), "timeout" = 0), step = "k247"),
		then(PROC_REF(ui_act_switch_filter)))
	ref_one(nameof(input))
	ref_one(nameof(output))
	ref_many(nameof(atmos_filters))
