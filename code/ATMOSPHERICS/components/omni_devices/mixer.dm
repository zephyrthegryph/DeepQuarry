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

	var/list/inputs = new() // ALLOW(instance_list): atmos area (M1a): omni mixer pipe device; listed in memory_lists_audit.md, not edited here
	var/datum/omni_port/output

	//setup tags for initial concentration values (must be decimal)
	var/tag_north_con
	var/tag_south_con
	var/tag_east_con
	var/tag_west_con

	var/max_flow_rate = 200
	var/set_flow_rate = 200

	var/list/mixing_inputs = list() // ALLOW(instance_list): atmos area (M1a): omni mixer pipe device; listed in memory_lists_audit.md, not edited here

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
	for(var/datum/omni_port/P in ports)
		if(P.update)
			if(output == P)
				output = null
			if(inputs.Find(P))
				inputs -= P

			switch(P.mode)
				if(ATM_INPUT)
					// ALLOW(object_keyed_lists): subset of the owned ports list (DECLARE_REF(..., OWNED_LIST) on /omni), rebuilt from it
					inputs += P
				if(ATM_OUTPUT)
					output = P

	if(!mapper_set())
		for(var/datum/omni_port/P in inputs)
			P.concentration = 1 / max(1, inputs.len)

	if(output)
		output.air.set_volume(ATMOS_DEFAULT_VOLUME_MIXER * 0.75 * inputs.len)
		output.concentration = 1

	rebuild_mixing_inputs()

/obj/machinery/atmospherics/omni/mixer/proc/mapper_set()
	return (tag_north_con || tag_south_con || tag_east_con || tag_west_con)

/obj/machinery/atmospherics/omni/mixer/error_check()
	if(!output || !inputs)
		return 1
	if(inputs.len < 2) //requires at least 2 inputs ~otherwise why are you using a mixer?
		return 1

	//concentration must add to 1
	var/total = 0
	for (var/datum/omni_port/P in inputs)
		total += P.concentration

	if (total != 1)
		return 1

	return 0

/// R10/M2 bridge (rust_architecture.md §8.5 step 6's filter/mixer slice):
/// the omni mixer's N-way generalization of the trinary mixer's two input
/// flows -- one plain `DeviceFlow` (mask 0: every gas) per input port,
/// `RUST_FLOW_MOLES`, ratio-scaled by `vg_mix_transfer()` (already N-way,
/// no separate Rust function needed here). The actual gas movement is
/// Rust's own device-edge step.
/obj/machinery/atmospherics/omni/mixer/machine_step()
	if(!..())
		return PROCESS_KILL // off or unpowered: its power and settings channels wake it

	// Ports are rebound to their pipe region's air whenever the topology
	// commits (the old datum is deleted), so the gas -> concentration list is
	// rebuilt from the ports' current air every step, never kept across one.
	rebuild_mixing_inputs()
	//Figure out the amount of moles to transfer
	var/requested = 0
	for (var/datum/omni_port/P in inputs)
		requested += (set_flow_rate*P.concentration/P.air.return_volume())*P.air.total_moles()
	if(requested <= MINIMUM_MOLES_TO_FILTER)
		unregister_omni_mixer_edges()
		hibernate_until_gas_changes()
		return PROCESS_KILL

	var/available_power = material_pump_power(power_rating)
	var/efficiency = ATMOS_FILTER_EFFICIENCY * (material_pump_efficiency() / 0.8)
	var/list/result = vg_mix_transfer(mixing_inputs, output.air, requested, available_power, efficiency)
	if(!result)
		unregister_omni_mixer_edges()
		hibernate_until_gas_changes()
		return PROCESS_KILL

	var/power_draw = result[2]
	var/dt = SSvg.wait / (1 SECONDS)

	last_power_draw = power_draw
	use_power(power_draw)

	// result[3..] is one moles figure per `mixing_inputs` entry, in that
	// same order, REGARDLESS of concentration (mix_transfer() gives every
	// source a slot, zero-ratio or not) -- so this must walk every port in
	// lockstep with it, not skip zero-concentration ones.
	var/i = 3
	for(var/datum/omni_port/P in inputs)
		var/slot = "in_[P]"
		var/moles = result[i++]
		if(!P.concentration || !moles)
			rust_unregister_device_n(slot)
			continue
		rust_set_device_n(slot, ports.Find(P), ports.Find(output))
		rust_set_device_flow_n(slot, 0, RUST_FLOW_MOLES, moles / dt, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_NONE, 0)

	for(var/datum/omni_port/P in inputs)
		if(P.concentration && P.network)
			P.network.mark_dirty()

	if(output.network)
		output.network.mark_dirty()

	return 1

/obj/machinery/atmospherics/omni/mixer/proc/unregister_omni_mixer_edges()
	for(var/datum/omni_port/P in inputs)
		rust_unregister_device_n("in_[P]")

/obj/machinery/atmospherics/omni/mixer/can_process_gas()
	var/transfer_moles = 0
	for(var/datum/omni_port/P in inputs)
		// Runs inside SSmachines' dirty-batch drain; a port whose mixture was
		// torn down (topology rebuild, deconstruction) must not runtime here.
		if(!P.air)
			continue
		transfer_moles += (set_flow_rate * P.concentration / P.air.return_volume()) * P.air.total_moles()
	return transfer_moles > MINIMUM_MOLES_TO_FILTER

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
	configuring = !configuring
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
	set_flow_rate = between(0, new_flow_rate, max_flow_rate)
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
					if(P.mode == ATM_INPUT && inputs.len > 2)
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
	rebuild_mixing_inputs()

/obj/machinery/atmospherics/omni/mixer/proc/change_concentration(port = NORTH, mob/user)
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

	var/_answer_k321 = rerun_ask(user, "k321", PROC_REF(change_concentration), args, /datum/om/prompt/number, message = "Enter a new concentration (0-[round(remain_con * 100, 0.5)])%", title = "Concentration control", default = min(remain_con, old_con)*100, max = round(remain_con * 100, 0.5))
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

	rebuild_mixing_inputs()

/obj/machinery/atmospherics/omni/mixer/proc/rebuild_mixing_inputs()
	mixing_inputs.Cut()
	for(var/datum/omni_port/P in inputs)
		mixing_inputs[P.air] = P.concentration

/obj/machinery/atmospherics/omni/mixer/proc/con_lock(port = NORTH)
	for(var/datum/omni_port/P in inputs)
		if(P.dir == port)
			P.con_lock = !P.con_lock

DECLARE_REF(/obj/machinery/atmospherics/omni/mixer, "output", HELD, null)
