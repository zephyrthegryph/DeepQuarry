/obj/machinery/portable_atmospherics/powered/pump
	name = "portable air pump"

	icon = 'icons/obj/atmos.dmi'
	icon_state = "psiphon:0"
	density = TRUE
	w_class = ITEMSIZE_NORMAL

	var/on = 0
	var/direction_out = 0 //0 = siphoning, 1 = releasing
	var/target_pressure = ONE_ATMOSPHERE

	var/pressuremin = 0
	var/pressuremax = 39.45 * ONE_ATMOSPHERE //The safest level you can get WITHOUT the tank exploding.

	volume = 1000

	power_rating = 7500 //7500 W ~ 10 HP
	power_losses = 150

/obj/machinery/portable_atmospherics/powered/pump/filled
	start_pressure = 90 * ONE_ATMOSPHERE

/obj/machinery/portable_atmospherics/powered/pump/Initialize(mapload, skip_cell)
	. = ..()

	if(!skip_cell)
		cell = new/obj/item/cell/apc(src)

	var/list/air_mix = StandardAirMix()
	src.air_contents.adjust_multi(GAS_O2, air_mix[GAS_O2], GAS_N2, air_mix[GAS_N2])

	AddElement(/datum/element/climbable)

/obj/machinery/portable_atmospherics/powered/pump/update_icon()
	cut_overlays()

	if(on && cell && cell.charge)
		icon_state = "psiphon:1"
	else
		icon_state = "psiphon:0"

	if(holding)
		add_overlay("siphon-open")

	if(connected_port)
		add_overlay("siphon-connector")

	return

/obj/machinery/portable_atmospherics/powered/pump/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF || stat & (BROKEN|NOPOWER))
		return

	if(prob(50/severity))
		on = !on

	if(prob(100/severity))
		direction_out = !direction_out

	target_pressure = rand(0,1300)
	if(on)
		START_MACHINE_PROCESSING(src)
	update_icon()

/obj/machinery/portable_atmospherics/powered/pump/process()
	..()
	if(!on)
		return PROCESS_KILL
	var/power_draw = -1

	if(on && cell && cell.charge)
		var/datum/gas_mixture/environment
		if(holding)
			environment = holding.air_contents
		else
			environment = loc.return_air()

		var/pressure_delta
		var/output_volume
		var/air_temperature
		// `* group_multiplier` dropped (always 1 under LINDA).
		if(direction_out)
			pressure_delta = target_pressure - environment.return_pressure()
			output_volume = environment.return_volume()
			air_temperature = environment.return_temperature()? environment.return_temperature() : air_contents.return_temperature()
		else
			pressure_delta = environment.return_pressure() - target_pressure
			output_volume = air_contents.return_volume()
			air_temperature = air_contents.return_temperature()? air_contents.return_temperature() : environment.return_temperature()

		var/transfer_moles = pressure_delta*output_volume/(air_temperature * R_IDEAL_GAS_EQUATION)

		if (pressure_delta > 0.01)
			if (direction_out)
				power_draw = pump_gas(src, air_contents, environment, transfer_moles, power_rating)
			else
				power_draw = pump_gas(src, environment, air_contents, transfer_moles, power_rating)

	if (power_draw < 0)
		last_flow_rate = 0
		last_power_draw = 0
	else
		last_power_draw = pay_material_pump_energy(power_draw)

		update_connected_network()
		// pump_gas mutated loc.return_air() directly when not piped
		// to a holding tank. Enroll the turf so SSair sees the change.
		if(!holding && isturf(loc))
			var/turf/open/T = loc
			if(istype(T))
				T.update_visuals()
				T.air_update_turf(FALSE, FALSE)

		//ran out of charge
		if (!cell.charge)
			power_change()
			update_icon()

/obj/machinery/portable_atmospherics/powered/pump/return_air()
	return air_contents

/obj/machinery/portable_atmospherics/powered/pump/attack_ghost(mob/user)
	return src.attack_hand(user)

/obj/machinery/portable_atmospherics/powered/pump/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/open_ui,
	)
	..()

/obj/machinery/portable_atmospherics/powered/pump/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PortablePump", name)
		ui.open()


/obj/machinery/portable_atmospherics/powered/pump/tgui_state(mob/user)
	return GLOB.tgui_physical_state

/obj/machinery/portable_atmospherics/powered/pump/tgui_data(mob/user)
	var/list/data[0]
	data["on"] = on ? TRUE : FALSE
	data["direction"] = !direction_out ? TRUE : FALSE
	data["connected"] = connected_port ? TRUE : FALSE
	data["pressure"] = round(air_contents.return_pressure() > 0 ? air_contents.return_pressure() : 0)
	data["target_pressure"] = round(target_pressure ? target_pressure : 0)
	data["default_pressure"] = round(initial(target_pressure))
	data["min_pressure"] = round(pressuremin)
	data["max_pressure"] = round(pressuremax)

	data["powerDraw"] = round(last_power_draw)
	data["cellCharge"] = cell ? cell.charge : 0
	data["cellMaxCharge"] = cell ? cell.maxcharge : 1

	if(holding)
		data["holding"] = list()
		data["holding"]["name"] = holding.name
		data["holding"]["pressure"] = round(holding.air_contents.return_pressure() > 0 ? holding.air_contents.return_pressure() : 0)
	else
		data["holding"] = null

	return data

/obj/machinery/portable_atmospherics/powered/pump/tgui_act(action, params)
	if(..())
		return TRUE

	switch(action)
		if("power")
			on = !on
			if(on)
				START_MACHINE_PROCESSING(src)
			. = 1
		if("direction")
			direction_out = !direction_out
			. = 1
		if("eject")
			if(holding)
				holding.loc = loc
				holding = null
			. = 1
		if("pressure")
			var/pressure = params["pressure"]
			if(pressure == "reset")
				pressure = initial(target_pressure)
				. = TRUE
			else if(pressure == "min")
				pressure = pressuremin
				. = TRUE
			else if(pressure == "max")
				pressure = pressuremax
				. = TRUE
			else if(text2num(pressure) != null)
				pressure = text2num(pressure)
				. = TRUE
			if(.)
				target_pressure = clamp(round(pressure), pressuremin, pressuremax)

	update_icon()


/obj/machinery/portable_atmospherics/powered/pump/huge
	name = "Huge Air Pump"
	icon = 'icons/obj/atmos.dmi'
	icon_state = "siphon:0"
	anchored = TRUE
	volume = 500000

	use_power = USE_POWER_IDLE
	idle_power_usage = 50		//internal circuitry, friction losses and stuff
	active_power_usage = 1000	// Blowers running
	power_rating = 100000	//100 kW ~ 135 HP

	var/static/gid = 1
	var/id = 0

/obj/machinery/portable_atmospherics/powered/pump/huge/Initialize(mapload)
	. = ..(mapload, TRUE)

	id = gid
	gid++

	name = "[name] (ID [id])"

/obj/machinery/portable_atmospherics/powered/pump/huge/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/pump_huge_no_interact,
		/datum/interaction/machine_item/pump_huge_reject_item,
	)
	..()

/// The huge pump can't be used by hand at all; direct the player to the console.
/datum/interaction/machine_hand/ungated/pump_huge_no_interact
	id = "pump_huge_no_interact"
	name = "Use"
	category = INTERACTION_CAT_CONFIGURE
	effect = /obj/machinery/portable_atmospherics/powered/pump/huge/proc/interaction_no_interact

/obj/machinery/portable_atmospherics/powered/pump/huge/proc/interaction_no_interact(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("You can't directly interact with this machine. Use the pump control console."))
	return TRUE

/obj/machinery/portable_atmospherics/powered/pump/huge/update_icon()
	cut_overlays()

	if(on && !(stat & (NOPOWER|BROKEN)))
		icon_state = "siphon:1"
	else
		icon_state = "siphon:0"

/obj/machinery/portable_atmospherics/powered/pump/huge/power_change()
	var/old_stat = stat
	..()
	if (old_stat != stat)
		update_icon()

/obj/machinery/portable_atmospherics/powered/pump/huge/process()
	if(!anchored || (stat & (NOPOWER|BROKEN)))
		on = 0
		last_flow_rate = 0
		last_power_draw = 0
		update_icon()
	var/new_use_power = 1 + on
	if(new_use_power != use_power)
		update_use_power(new_use_power)
	if(!on)
		return

	var/power_draw = -1

	var/datum/gas_mixture/environment = loc.return_air()

	var/pressure_delta
	var/output_volume
	var/air_temperature
	// `* group_multiplier` dropped (always 1 under LINDA).
	if(direction_out)
		pressure_delta = target_pressure - environment.return_pressure()
		output_volume = environment.return_volume()
		air_temperature = environment.return_temperature()? environment.return_temperature() : air_contents.return_temperature()
	else
		pressure_delta = environment.return_pressure() - target_pressure
		output_volume = air_contents.return_volume()
		air_temperature = air_contents.return_temperature()? air_contents.return_temperature() : environment.return_temperature()

	var/transfer_moles = pressure_delta*output_volume/(air_temperature * R_IDEAL_GAS_EQUATION)

	if(pressure_delta > 0.01)
		if(direction_out)
			power_draw = pump_gas(src, air_contents, environment, transfer_moles, power_rating)
		else
			power_draw = pump_gas(src, environment, air_contents, transfer_moles, power_rating)

	if (power_draw < 0)
		last_flow_rate = 0
		last_power_draw = 0
	else
		use_power(power_draw)
		update_connected_network()

/// The huge pump doesn't use power cells or hold tanks; using either on it does nothing.
/datum/interaction/machine_item/pump_huge_reject_item
	id = "pump_huge_reject_item"
	name = "Use"
	category = INTERACTION_CAT_INSERT
	held_type = list(/obj/item/cell, /obj/item/tank)
	effect = /obj/machinery/portable_atmospherics/powered/pump/huge/proc/interaction_reject_item

/obj/machinery/portable_atmospherics/powered/pump/huge/proc/interaction_reject_item(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

/obj/machinery/portable_atmospherics/powered/pump/huge/wrench_act(mob/user, obj/item/tool)
	if(on)
		to_chat(user, span_warning("Turn \the [src] off first!"))
		return ITEM_INTERACT_BLOCKING
	anchored = !anchored
	playsound(src, tool.usesound, 50, TRUE)
	to_chat(user, span_notice("You [anchored ? "wrench" : "unwrench"] \the [src]."))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/portable_atmospherics/powered/pump/huge/screwdriver_act(mob/user, obj/item/tool)
	return ITEM_INTERACT_BLOCKING


/obj/machinery/portable_atmospherics/powered/pump/huge/stationary
	name = "Stationary Air Pump"

/obj/machinery/portable_atmospherics/powered/pump/huge/stationary/wrench_act(mob/user, obj/item/tool)
	to_chat(user, span_warning("The bolts are too tight for you to unscrew!"))
	return ITEM_INTERACT_BLOCKING

/obj/machinery/portable_atmospherics/powered/pump/huge/stationary/purge
	on = 1
	start_pressure = 0
	target_pressure = 0

/obj/machinery/portable_atmospherics/powered/pump/huge/stationary/purge/power_change()
	..()
	if(!(stat & (NOPOWER|BROKEN)))
		on = 1
		update_icon()
