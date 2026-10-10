// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

//--------------------------------------------
// Gas mixer - omni variant
//--------------------------------------------
/obj/machinery/atmospherics/omni/mixer
	name = "omni gas mixer"
	icon_state = "map_mixer"
	pipe_state = "omni_mixer"

	use_power = USE_POWER_IDLE
	idle_power_usage = 150		//internal circuitry, friction losses and stuff
	power_rating = 3700			//3700 W ~ 5 HP

	/// Port role views, derived from the owned `ports` by rebuild_port_roles().
	var/list/datum/omni_port/inputs
	var/datum/omni_port/output

	//setup tags for initial concentration values (must be decimal)
	var/tag_north_con
	var/tag_south_con
	var/tag_east_con
	var/tag_west_con

	var/max_flow_rate = 200
	var/set_flow_rate = 200

/obj/machinery/atmospherics/omni/mixer/Initialize(mapload)
	. = ..()

	if(mapper_set())
		var/con = 0
		for(var/datum/omni_port/P in ports)
			switch(P.dir)
				if(NORTH)
					if(tag_north_con && tag_north == 1)
						P.concentration = tag_north_con
						con += max(0, tag_north_con)
				if(SOUTH)
					if(tag_south_con && tag_south == 1)
						P.concentration = tag_south_con
						con += max(0, tag_south_con)
				if(EAST)
					if(tag_east_con && tag_east == 1)
						P.concentration = tag_east_con
						con += max(0, tag_east_con)
				if(WEST)
					if(tag_west_con && tag_west == 1)
						P.concentration = tag_west_con
						con += max(0, tag_west_con)

	for(var/datum/omni_port/P in ports)
		P.air.set_volume(ATMOS_DEFAULT_VOLUME_MIXER)

/obj/machinery/atmospherics/omni/mixer/sort_ports()
	rebuild_port_roles()

	if(!mapper_set())
		for(var/datum/omni_port/P in inputs)
			P.concentration = 1 / max(1, length(inputs))

	if(output)
		output.air.set_volume(ATMOS_DEFAULT_VOLUME_MIXER * 0.75 * length(inputs))
		output.concentration = 1

/// Derived view: output and the input ports, recomputed from the owned ports' modes.
/obj/machinery/atmospherics/omni/mixer/proc/rebuild_port_roles()
	rel_clear(src, nameof(output))
	rel_clear(src, nameof(inputs))
	for(var/datum/omni_port/P as anything in ports)
		switch(P.mode)
			if(ATM_INPUT)
				rel_add(src, nameof(inputs), P)
			if(ATM_OUTPUT)
				rel_set(src, nameof(output), P)

/obj/machinery/atmospherics/omni/mixer/proc/mapper_set()
	return (tag_north_con || tag_south_con || tag_east_con || tag_west_con)

/obj/machinery/atmospherics/omni/mixer/error_check()
	if(!output || !inputs)
		return 1
	if(length(inputs) < 2) //requires at least 2 inputs ~otherwise why are you using a mixer?
		return 1

	//concentration must add to 1
	var/total = 0
	for (var/datum/omni_port/P in inputs)
		total += P.concentration

	if (total != 1)
		return 1

	return 0

/// The omni mixer is a Rust budget group (rust_set_budget_leg()): one input leg per input port into the output, each with its
/// concentration. The requested moles from the inputs' live gas, the entropy/power budget and the split are computed in Rust
/// each device step (power_budget.rs); this only declares the ports and settings.
/obj/machinery/atmospherics/omni/mixer/push_to_rust()
	if(QDELETED(src))
		return
	last_power_draw = 0
	last_flow_rate = 0
	rust_unregister_all_devices_n()
	if(!operable() || !use_power || !output || length(inputs) < 2) // ALLOW(derived_reads): set_use_power() and power_change() bump rust_device_rev, as do port binds and disconnect() (nodes, ports, modes)
		return
	var/available_power = material_pump_power(power_rating) // ALLOW(derived_reads): fixed by the material
	var/efficiency = ATMOS_FILTER_EFFICIENCY * (material_pump_efficiency() / 0.8)
	var/output_index = ports.Find(output) // ALLOW(derived_reads): set_use_power() and power_change() bump rust_device_rev, as do port binds and disconnect() (nodes, ports, modes)
	for(var/datum/omni_port/P in inputs)
		if(!P.concentration)
			continue
		rust_set_budget_leg("in_[P]", ports.Find(P), output_index, RUST_FLOW_MIX, 0, RUST_ROLE_OUTPUT, P.concentration, set_flow_rate, available_power, efficiency)

/// A step's result: the moles the group moved and the power it drew, billed.
/obj/machinery/atmospherics/omni/mixer/rust_device_stepped(moles, power_w, target_reached)
	last_power_draw = power_w
	if(power_w > 0)
		use_power(power_w)
	last_flow_rate = moles

TRACKED(/obj/machinery/atmospherics/omni/mixer, set_flow_rate)

/// The Rust group is pushed (once per frame) when the rate or (through wake_for_state_change()) a port or share changes.
/obj/machinery/atmospherics/omni/mixer/derived()
	. = ..()
	. += rust_push(nameof(rust_device_rev), nameof(set_flow_rate))

CAPABILITIES(/obj/machinery/atmospherics/omni/mixer)
	ref_one(nameof(output))
	ref_many(nameof(inputs))
	pipe_device_window("OmniMixer")
	op("power", ui_act("power"), then(PROC_REF(ui_power_switched)))
	op("configure", ui_act("configure"), then(PROC_REF(ui_configure)))
	op("set_flow_rate", ui_act("set_flow_rate"), needs(req_bool(PROC_REF(configurable), silent = TRUE)),
		asks(/datum/prompt/number, fields = list("question" = computed(PROC_REF(set_flow_rate_question)), "title" = "Flow Rate Control", "default" = nameof(set_flow_rate), "max_value" = nameof(max_flow_rate), "timeout" = 0), step = "rate"),
		then(PROC_REF(ui_set_flow_rate)))
	op("switch_mode", ui_act("switch_mode", arg("dir"), arg("mode", schema_text(16))), needs(req_bool(PROC_REF(configurable), silent = TRUE)), then(PROC_REF(ui_switch_mode)))
	op("switch_con", ui_act("switch_con", arg("dir")), needs(req_bool(PROC_REF(configurable), silent = TRUE), req_bool(PROC_REF(share_free), silent = TRUE)),
		asks(/datum/prompt/number, fields = list("question" = computed(PROC_REF(share_question)), "title" = "Concentration control", "default" = computed(PROC_REF(share_default)), "max_value" = computed(PROC_REF(share_most)), "timeout" = 0), step = "share"),
		then(PROC_REF(ui_switch_con)))
	op("switch_conlock", ui_act("switch_conlock", arg("dir")), needs(req_bool(PROC_REF(configurable), silent = TRUE)), then(PROC_REF(ui_switch_conlock)))

/// The window's data.
/obj/machinery/atmospherics/omni/mixer/ui_data(datum/act/eval/A)
	var/list/data = list("power" = use_power, "config" = configuring)
	var/list/portData = list()
	for(var/datum/omni_port/P in ports)
		if(!configuring && P.mode == 0)
			continue
		portData[++portData.len] = list("dir" = dir_name(P.dir, capitalize = 1), "concentration" = P.concentration, "input" = P.mode == ATM_INPUT, "output" = P.mode == ATM_OUTPUT, "con_lock" = P.con_lock)
	if(portData.len)
		data["ports"] = portData
	if(output)
		data["set_flow_rate"] = round(set_flow_rate)
		data["last_flow_rate"] = round(last_flow_rate)
	return data

/// The ports, the rate and the shares are changed only while configuring with the mixer off (silent, as the old early returns were).
/obj/machinery/atmospherics/omni/mixer/proc/configurable(datum/act/op/A)
	return configuring && !use_power

/obj/machinery/atmospherics/omni/mixer/proc/ui_power_switched(datum/act/op/A)
	if(!configuring)
		set_use_power(!use_power)
	else
		set_use_power(USE_POWER_OFF)
	wake_for_state_change()
	return OP_OK

/obj/machinery/atmospherics/omni/mixer/proc/ui_configure(datum/act/op/A)
	set_configuring(!configuring)
	if(configuring)
		set_use_power(USE_POWER_OFF)
	wake_for_state_change()
	return OP_OK

/obj/machinery/atmospherics/omni/mixer/proc/set_flow_rate_question(datum/act/op/A)
	return "Enter new flow rate limit (0-[max_flow_rate]L/s)"

/obj/machinery/atmospherics/omni/mixer/proc/ui_set_flow_rate(datum/act/op/A)
	set_set_flow_rate(between(0, A.step_value("rate"), max_flow_rate))
	wake_for_state_change()
	return OP_OK

/obj/machinery/atmospherics/omni/mixer/proc/ui_switch_mode(datum/act/op/A, dir, mode)
	switch_mode(dir_flag(dir), mode)
	wake_for_state_change()
	return OP_OK

/obj/machinery/atmospherics/omni/mixer/proc/ui_switch_conlock(datum/act/op/A, dir)
	con_lock(dir_flag(dir))
	wake_for_state_change()
	return OP_OK

// ---- an input's share ----

/// The share the locked inputs leave (the asked port itself is never counted).
/obj/machinery/atmospherics/omni/mixer/proc/share_left(port)
	. = 1
	for(var/datum/omni_port/P in inputs)
		if(P.dir != port && P.con_lock)
			. -= P.concentration

/// Another input is free to take up the rest.
/obj/machinery/atmospherics/omni/mixer/proc/share_free(datum/act/op/A)
	var/port = dir_flag(A.args["dir"])
	for(var/datum/omni_port/P in inputs)
		if(P.dir != port && !P.con_lock) // ALLOW(reads): the ports are asked when the button is pressed, never from a cached menu or look
			return TRUE
	return FALSE

/obj/machinery/atmospherics/omni/mixer/proc/share_most(datum/act/op/A)
	return round(share_left(dir_flag(A.args["dir"])) * 100, 0.5)

/obj/machinery/atmospherics/omni/mixer/proc/share_question(datum/act/op/A)
	return "Enter a new concentration (0-[share_most(A)])%"

/obj/machinery/atmospherics/omni/mixer/proc/share_default(datum/act/op/A)
	var/port = dir_flag(A.args["dir"])
	for(var/datum/omni_port/P in inputs)
		if(P.dir == port)
			return min(share_left(port), P.concentration) * 100
	return 0

/// The asked share goes to its port; the rest is spread evenly over the inputs that are not locked.
/obj/machinery/atmospherics/omni/mixer/proc/ui_switch_con(datum/act/op/A, dir)
	set_share(dir_flag(dir), A.step_value("share") / 100)
	wake_for_state_change()
	return OP_OK

/obj/machinery/atmospherics/omni/mixer/proc/switch_mode(port = NORTH, mode = ATM_NONE)
	wake_for_state_change()
	if(mode != ATM_INPUT && mode != ATM_OUTPUT)
		switch(mode)
			if("in")
				mode = ATM_INPUT
			if("out")
				mode = ATM_OUTPUT
			else
				mode = ATM_NONE

	for(var/datum/omni_port/P in ports)
		var/old_mode = P.mode
		if(P.dir == port)
			switch(mode)
				if(ATM_INPUT)
					if(P.mode == ATM_OUTPUT)
						return
					P.mode = mode
				if(ATM_OUTPUT)
					P.mode = mode
				if(ATM_NONE)
					if(P.mode == ATM_OUTPUT)
						return
					if(P.mode == ATM_INPUT && length(inputs) > 2)
						P.mode = mode
		else if(P.mode == ATM_OUTPUT && mode == ATM_OUTPUT)
			P.mode = ATM_INPUT
		if(P.mode != old_mode)
			switch(P.mode)
				if(ATM_NONE)
					initialize_directions &= ~P.dir
					P.disconnect()
				else
					initialize_directions |= P.dir
					P.connect()
			P.update = 1

	update_ports()

/// Sets the share of `port` (clamped to what the locked inputs leave) and spreads the rest over the unlocked inputs.
/obj/machinery/atmospherics/omni/mixer/proc/set_share(port, new_con)
	tag_north_con = null
	tag_south_con = null
	tag_east_con = null
	tag_west_con = null
	var/remain_con = share_left(port)
	var/non_locked = 0
	for(var/datum/omni_port/P in inputs)
		if(P.dir != port && !P.con_lock)
			non_locked++
	if(non_locked < 1)
		return
	new_con = between(0, new_con, remain_con)
	remain_con = max(0, remain_con - new_con) / max(1, non_locked)
	for(var/datum/omni_port/P in inputs)
		if(P.dir == port)
			P.concentration = new_con
		else if(!P.con_lock)
			P.concentration = remain_con

/obj/machinery/atmospherics/omni/mixer/proc/con_lock(port = NORTH)
	for(var/datum/omni_port/P in inputs)
		if(P.dir == port)
			P.con_lock = !P.con_lock
