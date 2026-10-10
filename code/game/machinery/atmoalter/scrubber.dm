/obj/machinery/portable_atmospherics/powered/scrubber
	name = "Portable Air Scrubber"
	desc = "Similar to room scrubbers, this device contains an internal tank to scrub gasses from the atmosphere."

	icon = 'icons/obj/atmos.dmi'
	icon_state = "pscrubber:0"
	density = TRUE
	w_class = ITEMSIZE_NORMAL

	var/volume_rate = 800

	volume = 750

	power_rating = 7500 //7500 W ~ 10 HP
	power_losses = 150

	var/minrate = 0
	var/maxrate = 10 * ONE_ATMOSPHERE

	var/list/scrubbing_gas = list(GAS_PHORON, GAS_CO2, GAS_N2O, GAS_VOLATILE_FUEL, GAS_CH4) // ALLOW(instance_list): d: replaced per instance at runtime (4 assignments)

CAPABILITIES(/obj/machinery/portable_atmospherics/powered/scrubber)
	climb()
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(scrubber_step)), when = nameof(on))
	extend(/datum/act/hit/emp, instead(then(PROC_REF(scrubber_emp))))
	interface("PortableScrubber")
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("eject", ui_act("eject"), then(PROC_REF(ui_act_eject)))
	op("volume_adj", ui_act("volume_adj", arg("vol", num())), then(PROC_REF(ui_act_volume_adj)))
	param(nameof(skip_cell), pos = 1)

/// Made without its cell (its constructor param).
/obj/machinery/portable_atmospherics/powered/scrubber/var/skip_cell = FALSE

/// A portable machine comes with its cell unless made without one.
/obj/machinery/portable_atmospherics/powered/scrubber/starting_cell(datum/act/A)
	return skip_cell ? null : /obj/item/cell/apc

/// An EMP may toggle a working scrubber (before the hit lands; the hit goes on).
/obj/machinery/portable_atmospherics/powered/scrubber/proc/scrubber_emp(datum/act/hit/emp/A)
	if(!operable())
		return HOOK_DECLINE

	if(prob(50/A.packet.severity))
		set_on(!on)
	return HOOK_DECLINE

/obj/machinery/portable_atmospherics/powered/scrubber/draw(datum/look/look)
	..()
	look.state((on && cell && cell.charge) ? "pscrubber:1" : "pscrubber:0") // ALLOW(derived_reads): a cell that runs dry calls power_change() and update_icon()
	look.overlay("scrubber-open", when = !!holding) // ALLOW(derived_reads): the tank bay's insert and the eject button redraw it
	look.overlay("scrubber-connector", when = !!connected_port())

/obj/machinery/portable_atmospherics/powered/scrubber/derived()
	. = ..()
	. += drawn_from(nameof(on))

// Machine pipeline (code/game/machinery/machine_pipeline.dm, "portable pumps and scrubbers"
// section): polls = FALSE (declared with the other vars above) moves this off SSmachines'
// process() roster. The body below is unchanged, just relocated to
// /datum/work_stage/machine/power/portable_scrubber/perform(); it never hibernates on its own (it
// runs every tick while `on`, exactly as process() did), so idle() there is simply `!on`.
/obj/machinery/portable_atmospherics/powered/scrubber/proc/scrubber_step(datum/act/A)
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

		var/transfer_moles = min(1, volume_rate/environment.return_volume())*environment.total_moles()

		power_draw = scrub_gas(src, scrubbing_gas, environment, air_contents, transfer_moles, power_rating)

	if (power_draw < 0)
		last_flow_rate = 0
		last_power_draw = 0
	else
		last_power_draw = pay_material_pump_energy(power_draw)

		update_connected_network()
		// scrub_gas pulled from loc.return_air() directly when not
		// piped to a holding tank. Enroll the turf so SSair re-processes it.
		if(!holding && isturf(loc))
			var/turf/open/T = loc
			if(istype(T))
				T.update_visuals()
				T.air_update_turf(FALSE, FALSE)

		//ran out of charge
		if (!cell.charge)
			power_change()

/obj/machinery/portable_atmospherics/powered/scrubber/return_air()
	return air_contents

/obj/machinery/portable_atmospherics/powered/scrubber/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["on"] = on ? 1 : 0
	data["connected"] = connected_port() ? 1 : 0
	data["pressure"] = round(air_contents.return_pressure() > 0 ? air_contents.return_pressure() : 0)

	data["rate"] = round(volume_rate)
	data["minrate"] = round(minrate)
	data["maxrate"] = round(maxrate)
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

/obj/machinery/portable_atmospherics/powered/scrubber/proc/ui_act_power(datum/act/op/A)
	set_on(!on)
	return OP_OK

/obj/machinery/portable_atmospherics/powered/scrubber/proc/ui_act_eject(datum/act/op/A)
	if(holding)
		holding.forceMove(loc)
		rel_take(src, nameof(src.holding))
	. = TRUE

/obj/machinery/portable_atmospherics/powered/scrubber/proc/ui_act_volume_adj(datum/act/op/A, vol)
	volume_rate = CLAMP(vol, minrate, maxrate)
	. = TRUE


//Huge scrubber
/obj/machinery/portable_atmospherics/powered/scrubber/huge
	name = "Huge Air Scrubber"
	desc = "A larger variation of the portable scrubber, for industrial scrubbing of air. Must be turned on from a remote terminal."
	icon = 'icons/obj/atmos_vr.dmi' // New Sprite
	icon_state = "scrubber:0"
	anchored = TRUE
	volume = 500000
	volume_rate = 7000

	use_power = USE_POWER_IDLE
	idle_power_usage = 50 // //internal circuitry, friction losses and stuff
	active_power_usage = 1000 // // Blowers running
	power_rating = 100000 // //100 kW ~ 135 HP

	var/global/gid = 1
	var/id = 0


/// Switching it keeps the power draw in step.
/obj/machinery/portable_atmospherics/powered/scrubber/huge/set_on(value)
	. = ..()
	if(.)
		set_use_power(1 + on)

CAPABILITIES(/obj/machinery/portable_atmospherics/powered/scrubber/huge)
	without(CAP_CLIMB) // not climbable
	huge_portable_controls()
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(huge_step)), when = nameof(on))

/obj/machinery/portable_atmospherics/powered/scrubber/huge/Initialize(mapload)
	. = ..(mapload, TRUE)

	id = gid
	gid++

	name = "[name] (ID [id])"


/obj/machinery/portable_atmospherics/powered/scrubber/huge/draw(datum/look/look)
	..()
	look.state((on && operable()) ? "scrubber:1" : "scrubber:0")

/// One service interval while it is on: loose or dead, it switches off.
/obj/machinery/portable_atmospherics/powered/scrubber/huge/proc/huge_step(datum/act/A)
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

	var/transfer_moles = min(1, volume_rate/environment.return_volume())*environment.total_moles()

	power_draw = scrub_gas(src, scrubbing_gas, environment, air_contents, transfer_moles, active_power_usage)

	if (power_draw < 0)
		last_flow_rate = 0
		last_power_draw = 0
	else
		use_power(power_draw)
		update_connected_network()

/obj/machinery/portable_atmospherics/powered/scrubber/huge/stationary
	name = "Stationary Air Scrubber"

/obj/machinery/portable_atmospherics/powered/scrubber/huge/stationary/Initialize(mapload)
	. = ..()
	desc += "This one seems to be tightly secured with large bolts."

CAPABILITIES(/obj/machinery/portable_atmospherics/powered/scrubber/huge/stationary)
	extend("anchor", needs(req_bool(TYPE_PROC_REF(/obj/machinery/portable_atmospherics/powered, never), because = MSG(huge_portable/bolted))))
