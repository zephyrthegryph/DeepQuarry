/obj/machinery/portable_atmospherics/powered/pump
	name = "portable air pump"

	icon = 'icons/obj/atmos.dmi'
	icon_state = "psiphon:0"
	density = TRUE
	w_class = ITEMSIZE_NORMAL

	var/direction_out = 0 //0 = siphoning, 1 = releasing
	var/target_pressure = ONE_ATMOSPHERE

	var/pressuremin = 0
	var/pressuremax = 39.45 * ONE_ATMOSPHERE //The safest level you can get WITHOUT the tank exploding.

	volume = 1000

	power_rating = 7500 //7500 W ~ 10 HP
	power_losses = 150

/obj/machinery/portable_atmospherics/powered/pump/filled
	start_pressure = 90 * ONE_ATMOSPHERE

CAPABILITIES(/obj/machinery/portable_atmospherics/powered/pump)
	climb()
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(pump_step)), when = nameof(on))
	extend(/datum/act/hit/emp, instead(then(PROC_REF(pump_emp))))
	interface("PortablePump", state = nameof(GLOB.tgui_physical_state))
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("direction", ui_act("direction"), then(PROC_REF(ui_act_direction)))
	op("eject", ui_act("eject"), then(PROC_REF(ui_act_eject)))
	op("pressure", ui_act("pressure", arg("pressure")), then(PROC_REF(ui_act_pressure)))
	param(nameof(skip_cell), pos = 1)

/// Made without its cell (its constructor param).
/obj/machinery/portable_atmospherics/powered/pump/var/skip_cell = FALSE

/// A portable machine comes with its cell unless made without one.
/obj/machinery/portable_atmospherics/powered/pump/starting_cell(datum/act/A)
	return skip_cell ? null : /obj/item/cell/apc

// ALLOW(init/INSTANCE_STATE): a pump fills with air, a per-instance mixture
/obj/machinery/portable_atmospherics/powered/pump/Initialize(mapload)
	. = ..()

	var/list/air_mix = StandardAirMix()
	src.air_contents.adjust_multi(GAS_O2, air_mix[GAS_O2], GAS_N2, air_mix[GAS_N2])


/obj/machinery/portable_atmospherics/powered/pump/draw(datum/look/look)
	..()
	look.state((on && cell && cell.charge) ? "psiphon:1" : "psiphon:0") // ALLOW(derived_reads): a cell that runs dry calls power_change() and update_icon()
	look.overlay("siphon-open", when = !!holding) // ALLOW(derived_reads): the tank bay's insert and the eject button redraw it
	look.overlay("siphon-connector", when = !!connected_port())

/obj/machinery/portable_atmospherics/powered/pump/derived()
	. = ..()
	. += drawn_from(nameof(on))

/// An EMP scrambles a working pump's settings (before the hit lands; the hit goes on).
/obj/machinery/portable_atmospherics/powered/pump/proc/pump_emp(datum/act/hit/emp/A)
	if(!operable())
		return HOOK_DECLINE

	var/severity = A.packet.severity
	if(prob(50/severity))
		set_on(!on)

	if(prob(100/severity))
		direction_out = !direction_out

	target_pressure = rand(0,1300)
	return HOOK_DECLINE

/// One service interval of pumping while it is on (its every()): toward its target, between its tank or the room and its own gas.
/obj/machinery/portable_atmospherics/powered/pump/proc/pump_step(datum/act/A)
	react_or_update()
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

/obj/machinery/portable_atmospherics/powered/pump/return_air()
	return air_contents

/obj/machinery/portable_atmospherics/powered/pump/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["on"] = on ? TRUE : FALSE
	data["direction"] = !direction_out ? TRUE : FALSE
	data["connected"] = connected_port() ? TRUE : FALSE
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

/obj/machinery/portable_atmospherics/powered/pump/proc/ui_act_power(datum/act/op/A)
	set_on(!on)
	return OP_OK

/obj/machinery/portable_atmospherics/powered/pump/proc/ui_act_direction(datum/act/op/A)
	direction_out = !direction_out
	. = 1

/obj/machinery/portable_atmospherics/powered/pump/proc/ui_act_eject(datum/act/op/A)
	if(holding)
		holding.forceMove(loc)
		own_take(src, nameof(/datum/rule_binding::holding))
	. = 1

/obj/machinery/portable_atmospherics/powered/pump/proc/ui_act_pressure(datum/act/op/A, raw_pressure)
	var/pressure = raw_pressure
	if(pressure == "reset")
		pressure = initial(target_pressure)
		. = TRUE
	else if(pressure == "min")
		pressure = pressuremin
		. = TRUE
	else if(pressure == "max")
		pressure = pressuremax
		. = TRUE
	else if(isnum(pressure))
		. = TRUE
	if(.)
		target_pressure = clamp(round(pressure), pressuremin, pressuremax)


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

MSG_DEF_SELF(huge_portable/console_only, "You can't directly interact with this machine. Use its control console.")
MSG_DEF_SELF(huge_portable/turn_off, "Turn it off first!")
MSG_DEF_SELF(huge_portable/bolted, "The bolts are too tight for you to unscrew!")
MSG_DEF_SELF(huge_portable/anchored, "You wrench it down.")
MSG_DEF_SELF(huge_portable/unanchored, "You unwrench it.")

CAPABILITIES(/obj/machinery/portable_atmospherics/powered/pump/huge)
	huge_portable_controls()
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(huge_step)), when = nameof(on))

/// What a huge portable (a pump or a scrubber) is to a hand: worked only from its console; it takes no cell or tank; its wrench bolts it down
/// while it is off. A plain proc returning entries (the pump and the scrubber share it).
/proc/huge_portable_controls()
	return list(without("ui_open"), without("cell_in"), without("cell_out"), without("tank_bay.holding.insert"), without("port"),
		op("console_only", hand(), label("Use"), wait(0), when(cond_not(req(/obj/item))), says(MSG(huge_portable/console_only)), then(TYPE_PROC_REF(/obj/machinery/portable_atmospherics/powered, swallowed))),
		op("swallow_cell", item(/obj/item/cell), label("Use"), wait(0), then(TYPE_PROC_REF(/obj/machinery/portable_atmospherics/powered, swallowed))),
		op("swallow_tank", item(/obj/item/tank), label("Use"), wait(0), then(TYPE_PROC_REF(/obj/machinery/portable_atmospherics/powered, swallowed))),
		op("anchor", tool(TOOL_WRENCH), label("Wrench"), wait(0), needs(req(TYPE_PROC_REF(/obj/machinery/portable_atmospherics/powered, is_off), because = MSG(huge_portable/turn_off))),
			says(TYPE_PROC_REF(/obj/machinery/portable_atmospherics/powered, anchor_message)), then(TYPE_PROC_REF(/obj/machinery/portable_atmospherics/powered, anchor_toggled))))

/// Switching it keeps the power draw in step.
/obj/machinery/portable_atmospherics/powered/pump/huge/set_on(value)
	. = ..()
	if(.)
		set_use_power(1 + on)

/obj/machinery/portable_atmospherics/powered/pump/huge/Initialize(mapload)
	. = ..(mapload, TRUE)

	id = gid
	gid++

	name = "[name] (ID [id])"

/obj/machinery/portable_atmospherics/powered/pump/huge/draw(datum/look/look)
	..()
	look.state((on && operable()) ? "siphon:1" : "siphon:0")

/// One service interval while it is on: loose or dead, it switches off.
/obj/machinery/portable_atmospherics/powered/pump/huge/proc/huge_step(datum/act/A)
	if(!anchored || (!operable()))
		set_on(0)
		last_flow_rate = 0
		last_power_draw = 0
		return
	var/new_use_power = 1 + on
	if(new_use_power != use_power)
		set_use_power(new_use_power)

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

/obj/machinery/portable_atmospherics/powered/pump/huge/stationary
	name = "Stationary Air Pump"

CAPABILITIES(/obj/machinery/portable_atmospherics/powered/pump/huge/stationary)
	extend("anchor", needs(req(TYPE_PROC_REF(/obj/machinery/portable_atmospherics/powered, never), because = MSG(huge_portable/bolted))))

/obj/machinery/portable_atmospherics/powered/pump/huge/stationary/purge
	on = 1
	start_pressure = 0
	target_pressure = 0

/obj/machinery/portable_atmospherics/powered/pump/huge/stationary/purge/power_change()
	. = ..()
	if(operable())
		set_on(1)
