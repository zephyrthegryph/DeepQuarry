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

TRACKED_BRIDGED(/obj/machinery/atmospherics/omni/mixer, set_flow_rate, CHANGE_MACHINE_SETTINGS)

/// The Rust group is pushed (once per frame) when the rate or (through wake_for_state_change()) a port or share changes.
/obj/machinery/atmospherics/omni/mixer/derived()
	. = ..()
	. += rust_push(nameof(rust_device_rev), nameof(set_flow_rate))

DECLARE_UI(/obj/machinery/atmospherics/omni/mixer, "OmniMixer")

UI_DATA_REPLACE(/obj/machinery/atmospherics/omni/mixer, "power=use_power", "config=configuring:num", "merge:ui_data_obj_machinery_atmospherics_omni_mixer{ports:list,set_flow_rate:num,last_flow_rate:num}")

/// The computed part of /obj/machinery/atmospherics/omni/mixer's window data (declared on its UI_DATA row).
/obj/machinery/atmospherics/omni/mixer/proc/ui_data_obj_machinery_atmospherics_omni_mixer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()


	var/list/portData = list()
	for(var/datum/omni_port/P in ports)
		if(!configuring && P.mode == 0)
			continue

		var/input = 0
		var/output = 0
		switch(P.mode)
			if(ATM_INPUT)
				input = 1
			if(ATM_OUTPUT)
				output = 1

		portData[++portData.len] = list("dir" = dir_name(P.dir, capitalize = 1), \
										"concentration" = P.concentration, \
										"input" = input, \
										"output" = output, \
										"con_lock" = P.con_lock)

	if(portData.len)
		data["ports"] = portData
	if(output)
		data["set_flow_rate"] = round(set_flow_rate)
		data["last_flow_rate"] = round(last_flow_rate)

	return data

/obj/machinery/atmospherics/omni/mixer/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	wake_for_state_change()
	return TRUE

UI_ACT(/obj/machinery/atmospherics/omni/mixer, "power", ui_act_power)
UI_ACT_PROC(/obj/machinery/atmospherics/omni/mixer, ui_act_power)
	. = TRUE
	if(!configuring)
		set_use_power(!use_power)
	else
		set_use_power(USE_POWER_OFF)
	wake_for_state_change()
	update_icon()

UI_ACT(/obj/machinery/atmospherics/omni/mixer, "configure", ui_act_configure)
UI_ACT_PROC(/obj/machinery/atmospherics/omni/mixer, ui_act_configure)
	. = TRUE
	set_configuring(!configuring)
	if(configuring)
		set_use_power(USE_POWER_OFF)
	wake_for_state_change()
	update_icon()

UI_ACT(/obj/machinery/atmospherics/omni/mixer, "set_flow_rate", ui_act_set_flow_rate)
UI_ACT_PROC(/obj/machinery/atmospherics/omni/mixer, ui_act_set_flow_rate)
	. = TRUE
	if(!configuring || use_power)
		return
	var/new_flow_rate = act_ask(ui.user, action, params, ui, "k237", /datum/om/prompt/number, message = "Enter new flow rate limit (0-[max_flow_rate]L/s)", title = "Flow Rate Control", default = set_flow_rate, max = max_flow_rate)
	if(isnull(new_flow_rate))
		return
	set_set_flow_rate(between(0, new_flow_rate, max_flow_rate))
	wake_for_state_change()
	update_icon()

UI_ACT(/obj/machinery/atmospherics/omni/mixer, "switch_mode", ui_act_switch_mode, UI_ARG_VALUE("dir"), UI_ARG_TEXT("mode"))
UI_ACT_PROC(/obj/machinery/atmospherics/omni/mixer, ui_act_switch_mode)
	. = TRUE
	if(!configuring || use_power)
		return
	switch_mode(dir_flag(params["dir"]), params["mode"])
	wake_for_state_change()
	update_icon()

UI_ACT(/obj/machinery/atmospherics/omni/mixer, "switch_con", ui_act_switch_con, UI_ARG_VALUE("dir"))
UI_ACT_PROC(/obj/machinery/atmospherics/omni/mixer, ui_act_switch_con)
	. = TRUE
	if(!configuring || use_power)
		return
	change_concentration(dir_flag(params["dir"]), ui.user)
	wake_for_state_change()
	update_icon()

UI_ACT(/obj/machinery/atmospherics/omni/mixer, "switch_conlock", ui_act_switch_conlock, UI_ARG_VALUE("dir"))
UI_ACT_PROC(/obj/machinery/atmospherics/omni/mixer, ui_act_switch_conlock)
	. = TRUE
	if(!configuring || use_power)
		return
	con_lock(dir_flag(params["dir"]))
	wake_for_state_change()
	update_icon()

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

/obj/machinery/atmospherics/omni/mixer/proc/change_concentration(port = NORTH, mob/user)
	return mixer_concentration_stage(port, user, list())

/obj/machinery/atmospherics/omni/mixer/proc/mixer_concentration_stage(port, mob/user, list/config_answers)
	tag_north_con = null
	tag_south_con = null
	tag_east_con = null
	tag_west_con = null

	var/old_con = 0
	var/non_locked = 0
	var/remain_con = 1

	for(var/datum/omni_port/P in inputs)
		if(P.dir == port)
			old_con = P.concentration
		else if(!P.con_lock)
			non_locked++
		else
			remain_con -= P.concentration

	if(non_locked < 1)
		return

	if(!("k321" in config_answers))
		open_request(src, /datum/prompt/number/atmos_config_review, PROC_REF(mixer_concentration_answered), answerer = user, config_operator = user, config_port = port, config_answers = config_answers, config_key = "k321", question = "Enter a new concentration (0-[round(remain_con * 100, 0.5)])%", title = "Concentration control", default = min(remain_con, old_con)*100, config_max = round(remain_con * 100, 0.5))
		return
	var/_answer_k321 = config_answers["k321"]
	if(isnull(_answer_k321))
		return
	var/new_con = (_answer_k321) / 100

	//cap it between 0 and the max remaining concentration
	new_con = between(0, new_con, remain_con)

	//new_con = min(remain_con, new_con)

	//clamp remaining concentration so we don't go into negatives
	remain_con = max(0, remain_con - new_con)

	//distribute remaining concentration between unlocked ports evenly
	remain_con /= max(1, non_locked)

	for(var/datum/omni_port/P in inputs)
		if(P.dir == port)
			P.concentration = new_con
		else if(!P.con_lock)
			P.concentration = remain_con


/obj/machinery/atmospherics/omni/mixer/proc/con_lock(port = NORTH)
	for(var/datum/omni_port/P in inputs)
		if(P.dir == port)
			P.con_lock = !P.con_lock

CAPABILITIES(/obj/machinery/atmospherics/omni/mixer)
	ref_one(nameof(output))
	ref_many(nameof(inputs))

/obj/machinery/atmospherics/omni/mixer/proc/mixer_concentration_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/number/atmos_config_review/ask = context.answer
	var/list/config_answers = ask.config_answers.Copy()
	config_answers[ask.config_key] = ask.answer_value
	// Recovery: old kept.finished refreshed the target even if replay failed.
	. = mixer_concentration_stage(ask.config_port, ask.config_operator, config_answers)
	SStgui.update_uis(src)
