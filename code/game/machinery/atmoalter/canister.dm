/obj/machinery/portable_atmospherics/canister
	name = "canister"
	icon = 'icons/obj/atmos.dmi'
	icon_state = "yellow"
	density = TRUE
	max_integrity = 100
	w_class = ITEMSIZE_HUGE

	layer = TABLE_LAYER	// Above catwalks, hopefully below other things

	var/valve_open = 0
	var/release_pressure = ONE_ATMOSPHERE
	var/release_flow_rate = ATMOS_DEFAULT_VOLUME_PUMP //in L/s

	var/canister_color = "yellow"
	var/can_label = 1
	start_pressure = 45 * ONE_ATMOSPHERE
	pressure_resistance = 7 * ONE_ATMOSPHERE
	var/temperature_resistance = 1000 + T0C
	/// Integrity of the material which actually touches the stored gas.
	var/material_liner_integrity = 100
	var/material_last_exposure = 0
	volume = 1000
	use_power = USE_POWER_OFF
	interact_offline = 1 // Allows this to be used when not in powered area.
	var/release_log = ""
	var/update_flag = 0

/obj/machinery/portable_atmospherics/canister/Initialize(mapload)
	. = ..()
	AddElement(/datum/element/climbable)

/obj/machinery/portable_atmospherics/canister/proc/effective_maximum_pressure()
	var/internal_temperature = air_contents?.return_temperature() || T20C
	return material_environment_pressure_limit(maximum_pressure, MATERIAL_CANISTER_REFERENCE_RADIUS, MATERIAL_CANISTER_REFERENCE_THICKNESS, internal_temperature)

/// Returns TRUE while continued chemical exposure needs another sample.
/obj/machinery/portable_atmospherics/canister/proc/process_material_vessel()
	material_liner_integrity = material_environment_liner_integrity
	return FALSE // Independent material service owns exposure and leak updates.

/obj/machinery/portable_atmospherics/canister/material_environment_begin_leak()
	if(!material_environment_leaking)
		visible_message(span_warning("Gas begins hissing through [src]'s compromised vessel wall."))
	return ..()

/obj/machinery/portable_atmospherics/canister/material_environment_owns_leak()
	return FALSE

/obj/machinery/portable_atmospherics/canister/material_environment_rupture()
	if(!destroyed)
		atom_destruction(BOMB)

/obj/machinery/portable_atmospherics/canister/drain_power()
	return -1

/obj/machinery/portable_atmospherics/canister/nitrous_oxide
	name = "Canister: \[N2O\]"
	icon_state = "redws"
	canister_color = "redws"
	can_label = 0

/obj/machinery/portable_atmospherics/canister/nitrogen
	name = "Canister: \[N2\]"
	icon_state = "red"
	canister_color = "red"
	can_label = 0

/obj/machinery/portable_atmospherics/canister/oxygen
	name = "Canister: \[O2\]"
	icon_state = "blue"
	canister_color = "blue"
	can_label = 0

/obj/machinery/portable_atmospherics/canister/oxygen/prechilled
	name = "Canister: \[O2 (Cryo)\]"

/obj/machinery/portable_atmospherics/canister/phoron
	name = "Canister \[Phoron\]"
	icon_state = "orangeps"
	canister_color = "orangeps"
	can_label = 0

/obj/machinery/portable_atmospherics/canister/carbon_dioxide
	name = "Canister \[CO2\]"
	icon_state = "black"
	canister_color = "black"
	can_label = 0

/obj/machinery/portable_atmospherics/canister/methane
	name = "Canister: \[CH4\]"
	icon_state = "green"
	canister_color = "green"
	can_label = 0

/obj/machinery/portable_atmospherics/canister/air
	name = "Canister \[Air\]"
	icon_state = "grey"
	canister_color = "grey"
	can_label = 0

/obj/machinery/portable_atmospherics/canister/air/airlock
	start_pressure = 3 * ONE_ATMOSPHERE

/obj/machinery/portable_atmospherics/canister/empty/
	start_pressure = 0
	can_label = 1

/obj/machinery/portable_atmospherics/canister/empty/oxygen
	name = "Canister: \[O2\]"
	icon_state = "blue"
	canister_color = "blue"
/obj/machinery/portable_atmospherics/canister/empty/phoron
	name = "Canister \[Phoron\]"
	icon_state = "orangeps"
	canister_color = "orangeps"
/obj/machinery/portable_atmospherics/canister/empty/nitrogen
	name = "Canister \[N2\]"
	icon_state = "red"
	canister_color = "red"
/obj/machinery/portable_atmospherics/canister/empty/carbon_dioxide
	name = "Canister \[CO2\]"
	icon_state = "black"
	canister_color = "black"
/obj/machinery/portable_atmospherics/canister/empty/nitrous_oxide
	name = "Canister \[N2O\]"
	icon_state = "redws"
	canister_color = "redws"

/obj/machinery/portable_atmospherics/canister/empty/methane
	name = "Canister \[CH4\]"
	icon_state = "green"
	canister_color = "green"


/obj/machinery/portable_atmospherics/canister/proc/check_change()
	var/old_flag = update_flag
	update_flag = desired_update_flag()

	if(update_flag == old_flag)
		return 1
	else
		return 0

/obj/machinery/portable_atmospherics/canister/proc/desired_update_flag()
	. = 0
	if(holding)
		. |= 1
	if(connected_port)
		. |= 2

	var/tank_pressure = air_contents.return_pressure()
	if(tank_pressure < 10)
		. |= 4
	else if(tank_pressure < ONE_ATMOSPHERE)
		. |= 8
	else if(tank_pressure < 15*ONE_ATMOSPHERE)
		. |= 16
	else
		. |= 32

/obj/machinery/portable_atmospherics/canister/gas_dependency_changed(mixture_id, change_mask)
	if(!..())
		return FALSE
	// An attached closed canister's gas reactions and pipe membership are owned
	// by the pipenet. Its machinery process only needs to refresh the gauge when
	// the pressure crosses a displayed band.
	if(connected_port && !valve_open)
		return desired_update_flag() != update_flag
	return TRUE

/obj/machinery/portable_atmospherics/canister/update_icon()
/*
update_flag
1 = holding
2 = connected_port
4 = tank_pressure < 10
8 = tank_pressure < ONE_ATMOS
16 = tank_pressure < 15*ONE_ATMOS
32 = tank_pressure go boom.
*/

	if (src.destroyed)
		src.overlays = 0
		src.icon_state = text("[]-1", src.canister_color)
		return

	if(icon_state != "[canister_color]")
		icon_state = "[canister_color]"

	if(check_change()) //Returns 1 if no change needed to icons.
		return

	cut_overlays()

	if(update_flag & 1)
		add_overlay("can-open")
	if(update_flag & 2)
		add_overlay("can-connector")
	if(update_flag & 4)
		add_overlay("can-o0")
	if(update_flag & 8)
		add_overlay("can-o1")
	else if(update_flag & 16)
		add_overlay("can-o2")
	else if(update_flag & 32)
		add_overlay("can-o3")
	return


// At zero integrity the canister ruptures: dumps its gas into the environment,
// frees any connected port, and becomes a non-dense wreck (it is NOT qdel'd).
/obj/machinery/portable_atmospherics/canister/atom_destruction(damage_flag)
	. = ..()
	if(destroyed)
		return

	var/atom/location = src.loc
	var/obj/machinery/atmospherics/portables_connector/port
	if(location)
		port = locate() in location // Finds if there's a port
		location.assume_air(air_contents)

	if(port && anchored) // if it blew up, frees up the port
		disconnect()
		anchored = 0

	src.destroyed = 1
	playsound(src, 'sound/effects/spray.ogg', 10, 1, -3)
	src.density = FALSE
	update_icon()

	if (src.holding)
		src.holding.loc = src.loc
		src.holding = null

/obj/machinery/portable_atmospherics/canister/process()
	if (destroyed)
		return PROCESS_KILL
	var/turf/canister_turf = get_turf(src)
	var/datum/gas_mixture/canister_environment = canister_turf ? canister_turf.return_air() : null
	material_observe_gases(air_contents, canister_environment)

	var/reaction_result = ..()
	var/material_active = process_material_vessel()
	if(destroyed)
		return PROCESS_KILL

	if(valve_open)
		var/datum/gas_mixture/environment
		if(holding)
			environment = holding.air_contents
		else
			environment = loc.return_air()

		var/env_pressure = environment.return_pressure()
		var/pressure_delta = release_pressure - env_pressure

		if((air_contents.return_temperature() > 0) && (pressure_delta > 0))
			var/transfer_moles = calculate_transfer_moles(air_contents, environment, pressure_delta)
			transfer_moles = min(transfer_moles, (release_flow_rate/air_contents.return_volume())*air_contents.total_moles()) //flow rate limit

			var/returnval = pump_gas_passive(src, air_contents, environment, transfer_moles)
			if(returnval >= 0)
				src.update_icon()
				// pump_gas_passive directly mutates the turf's air mix via
				// the gas_mixture reference returned by loc.return_air(); it doesn't
				// know what type of sink it's writing to, so it can't enroll a turf
				// in SSair.active_turfs. Without this, under LINDA the gas lands on
				// the turf but never spreads (active_turfs stays empty) and the gas
				// overlay never updates (update_visuals is never called).
				if(!holding && isturf(loc))
					var/turf/open/T = loc
					if(istype(T))
						T.update_visuals()
						T.air_update_turf(FALSE, FALSE)

	if(air_contents.return_pressure() < 1)
		can_label = 1
	else
		can_label = 0

	if(!valve_open && reaction_result == NO_REACTION && !material_active)
		hibernate_until_gas_changes()
		return PROCESS_KILL


/obj/machinery/portable_atmospherics/canister/return_air()
	return air_contents

/obj/machinery/portable_atmospherics/canister/proc/return_pressure()
	var/datum/gas_mixture/GM = src.return_air()
	if(GM && GM.return_volume()>0)
		return GM.return_pressure()
	return 0

/// Canisters are thick-walled: they catch half of a round.
/obj/machinery/portable_atmospherics/canister/projectile_damage(obj/item/projectile/P, def_zone)
	return receive_projectile(P, def_zone, 0.5)

/obj/machinery/portable_atmospherics/canister/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/canister_liner,
		/datum/interaction/machine_item/canister_jetpack_refill,
		/datum/interaction/machine_item/canister_generic,
		/datum/interaction/machine_hand/ungated/open_ui,
	)
	..()

/datum/interaction/machine_item/canister_liner
	id = "canister_liner"
	name = "Install pressure liner"
	held_type = /obj/item/stack/material
	effect = /obj/machinery/portable_atmospherics/canister/proc/interaction_liner

/obj/machinery/portable_atmospherics/canister/proc/interaction_liner(mob/user, obj/item/stack/material/stock, datum/interaction/interaction)
	if(pressure_liner_material_id)
		to_chat(user, span_warning("[src] already has an engineered pressure liner."))
		return TRUE
	if(destroyed || air_contents.return_pressure() > ONE_ATMOSPHERE * 0.1)
		to_chat(user, span_warning("Drain and restore [src] before installing a pressure liner."))
		return TRUE
	if(stock.get_amount() < 2)
		to_chat(user, span_warning("A pressure liner requires two sheets."))
		return TRUE
	var/datum/material/liner = stock.material
	pressure_liner_material_id = liner.name
	stock.use(2)
	set_construction_material(MATERIAL_ROLE_LINER, liner.name)
	material_liner_integrity = 100
	material_environment_liner_integrity = 100
	name = "[liner.display_name]-lined [initial(name)]"
	color = liner.icon_colour
	to_chat(user, span_notice("You install a [liner.display_name] pressure liner in [src]."))
	return TRUE

/datum/interaction/machine_item/canister_jetpack_refill
	id = "canister_jetpack_refill"
	name = "Pulse-pressurize jetpack"
	held_type = /obj/item/tank/jetpack
	offered_when = list(REQ_ON(PRED_ACTOR, /obj/machinery/portable_atmospherics/canister/proc/actor_is_robot, null))
	effect = /obj/machinery/portable_atmospherics/canister/proc/interaction_jetpack_refill

/obj/machinery/portable_atmospherics/canister/proc/actor_is_robot(mob/actor, atom/target, obj/item/held)
	return isrobot(actor)

/obj/machinery/portable_atmospherics/canister/proc/interaction_jetpack_refill(mob/user, obj/item/tank/jetpack/the_jetpack_tank, datum/interaction/interaction)
	var/datum/gas_mixture/thejetpack = the_jetpack_tank.air_contents
	var/env_pressure = thejetpack.return_pressure()
	var/pressure_delta = min(10*ONE_ATMOSPHERE - env_pressure, (air_contents.return_pressure() - env_pressure)/2)
	//Can not have a pressure delta that would cause environment pressure > tank pressure
	var/transfer_moles = 0
	if((air_contents.return_temperature() > 0) && (pressure_delta > 0))
		transfer_moles = pressure_delta*thejetpack.return_volume()/(air_contents.return_temperature() * R_IDEAL_GAS_EQUATION)//Actually transfer the gas
		var/datum/gas_mixture/removed = air_contents.remove(transfer_moles)
		thejetpack.merge(removed)
		to_chat(user, "You pulse-pressurize your jetpack from the tank.")
	return TRUE

/datum/interaction/machine_item/canister_generic
	id = "canister_generic"
	name = "Use"
	held_type = /obj/item
	consumes_input = FALSE
	effect = /obj/machinery/portable_atmospherics/canister/proc/interaction_generic

/obj/machinery/portable_atmospherics/canister/proc/interaction_generic(mob/user, obj/item/W, datum/interaction/interaction)
	if(!istype(W, /obj/item/tank) && !istype(W, /obj/item/analyzer) && !istype(W, /obj/item/pda))
		visible_message(span_warning("\The [user] hits \the [src] with \a [W]!"))
		src.add_fingerprint(user)
		receive_weapon_hit(W, user, silent = FALSE)

	SStgui.update_uis(src) // Update all NanoUIs attached to src
	return FALSE

/obj/machinery/portable_atmospherics/canister/welder_act(mob/user, obj/item/tool)
	if(air_contents.return_pressure() > 1 && !destroyed)
		to_chat(user, span_warning("\The [src]'s internal pressure is too high! Empty the canister before attempting to weld it apart."))
		return ITEM_INTERACT_BLOCKING
	if(use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50))
		to_chat(user, span_notice("You deconstruct [src]."))
		new /obj/item/stack/material/steel(loc, 10)
		if(connected_port)
			disconnect()
		qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/portable_atmospherics/canister/tgui_state(mob/user)
	return GLOB.tgui_physical_state

/obj/machinery/portable_atmospherics/canister/tgui_interact(mob/user, datum/tgui/ui)
	if(destroyed)
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Canister", name)
		ui.open()

/obj/machinery/portable_atmospherics/canister/tgui_data(mob/user)
	var/list/data = list()
	data["can_relabel"] = can_label ? 1 : 0
	data["connected"] = connected_port ? 1 : 0
	data["pressure"] = round(air_contents.return_pressure() ? air_contents.return_pressure() : 0)
	data["releasePressure"] = round(release_pressure ? release_pressure : 0)
	data["defaultReleasePressure"] = round(initial(release_pressure))
	data["minReleasePressure"] = round(ONE_ATMOSPHERE/10)
	data["maxReleasePressure"] = round(10*ONE_ATMOSPHERE)
	data["valveOpen"] = valve_open ? 1 : 0

	if(holding)
		data["holding"] = list()
		data["holding"]["name"] = holding.name
		data["holding"]["pressure"] = round(holding.air_contents.return_pressure())
	else
		data["holding"] = null

	return data

/obj/machinery/portable_atmospherics/canister/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	switch(action)
		if("relabel")
			if(can_label)
				var/list/colors = list(\
					"\[N2O\]" = "redws", \
					"\[N2\]" = "red", \
					"\[O2\]" = "blue", \
					"\[Phoron\]" = "orangeps", \
					"\[CO2\]" = "black", \
					"\[CH4\]" = "green", \
					"\[Air\]" = "grey", \
					"\[CAUTION\]" = "yellow", \
				)
				var/label = tgui_input_list(ui.user, "Choose canister label", "Gas canister", colors)
				if(label)
					canister_color = colors[label]
					icon_state = colors[label]
					name = "Canister: [label]"
		if("pressure")
			var/pressure = params["pressure"]
			if(pressure == "reset")
				pressure = initial(release_pressure)
				. = TRUE
			else if(pressure == "min")
				pressure = ONE_ATMOSPHERE/10
				. = TRUE
			else if(pressure == "max")
				pressure = 10*ONE_ATMOSPHERE
				. = TRUE
			else if(pressure == "input")
				pressure = tgui_input_number(ui.user, "New release pressure ([ONE_ATMOSPHERE/10]-[10*ONE_ATMOSPHERE] kPa):", name, release_pressure, 10*ONE_ATMOSPHERE, ONE_ATMOSPHERE/10)
				if(!isnull(pressure) && !..())
					. = TRUE
			else if(text2num(pressure) != null)
				pressure = text2num(pressure)
				. = TRUE
			if(.)
				release_pressure = clamp(round(pressure), ONE_ATMOSPHERE/10, 10*ONE_ATMOSPHERE)
		if("valve")
			if(valve_open)
				if(holding)
					release_log += "Valve was " + span_bold("closed") + " by [ui.user] ([ui.user.ckey]), stopping the transfer into the [holding]<br>"
				else
					release_log += "Valve was " + span_bold("closed") + " by [ui.user] ([ui.user.ckey]), stopping the transfer into the " + span_red(span_bold("air")) + "<br>"
			else
				if(holding)
					release_log += "Valve was " + span_bold("opened") + " by [ui.user] ([ui.user.ckey]), starting the transfer into the [holding]<br>"
				else
					release_log += "Valve was " + span_bold("opened") + " by [ui.user] ([ui.user.ckey]), starting the transfer into the " + span_red(span_bold("air")) + "<br>"
					log_open()
			valve_open = !valve_open
			clear_gas_dependency()
			START_MACHINE_PROCESSING(src)
			. = TRUE
		if("eject")
			if(holding)
				if(valve_open)
					valve_open = 0
					release_log += "Valve was " + span_bold("closed") + " by [ui.user] ([ui.user.ckey]), stopping the transfer into the [holding]<br>"
				if(istype(holding, /obj/item/tank))
					holding.manipulated_by = ui.user.real_name
				holding.loc = loc
				holding = null
			. = TRUE

	add_fingerprint(ui.user)
	update_icon()

/obj/machinery/portable_atmospherics/canister/phoron/Initialize(mapload)
	. = ..()

	air_contents.adjust_gas(GAS_PHORON, MolesForPressure())
	update_icon()

/obj/machinery/portable_atmospherics/canister/oxygen/Initialize(mapload)
	. = ..()

	air_contents.adjust_gas(GAS_O2, MolesForPressure())
	update_icon()

/obj/machinery/portable_atmospherics/canister/oxygen/prechilled/Initialize(mapload)
	. = ..()

	air_contents.adjust_gas(GAS_O2, MolesForPressure())
	air_contents.set_temperature(80)
	update_icon()

/obj/machinery/portable_atmospherics/canister/nitrous_oxide/Initialize(mapload)
	. = ..()

	air_contents.adjust_gas(GAS_N2O, MolesForPressure())
	update_icon()

//Dirty way to fill room with gas. However it is a bit easier to do than creating some floor/engine/n2o -rastaf0
/obj/machinery/portable_atmospherics/canister/nitrous_oxide/roomfiller/Initialize(mapload)
	. = ..()
	air_contents.set_moles(/datum/gas/nitrous_oxide, 9*4000) // was XGM .gas[id] = X
	var/turf/simulated/location = src.loc
	if (istype(src.loc))
		location.assume_air(air_contents)
		air_contents = new

/obj/machinery/portable_atmospherics/canister/nitrogen/Initialize(mapload)
	. = ..()

	air_contents.adjust_gas(GAS_N2, MolesForPressure())
	update_icon()

/obj/machinery/portable_atmospherics/canister/carbon_dioxide/Initialize(mapload)
	. = ..()
	air_contents.adjust_gas(GAS_CO2, MolesForPressure())
	update_icon()

/obj/machinery/portable_atmospherics/canister/methane/Initialize(mapload)
	. = ..()
	air_contents.adjust_gas(GAS_CH4, MolesForPressure())
	update_icon()

/obj/machinery/portable_atmospherics/canister/air/Initialize(mapload)
	. = ..()
	var/list/air_mix = StandardAirMix()
	air_contents.adjust_multi(GAS_O2, air_mix[GAS_O2], GAS_N2, air_mix[GAS_N2])

	update_icon()

//R-UST port
// Special types used for engine setup admin verb, they contain double amount of that of normal canister.
/obj/machinery/portable_atmospherics/canister/nitrogen/engine_setup/Initialize(mapload)
	. = ..()
	air_contents.adjust_gas(GAS_N2, MolesForPressure())
	update_icon()

/obj/machinery/portable_atmospherics/canister/carbon_dioxide/engine_setup/Initialize(mapload)
	. = ..()
	air_contents.adjust_gas(GAS_CO2, MolesForPressure())
	update_icon()

/obj/machinery/portable_atmospherics/canister/phoron/engine_setup/Initialize(mapload)
	. = ..()
	air_contents.adjust_gas(GAS_PHORON, MolesForPressure())
	update_icon()
