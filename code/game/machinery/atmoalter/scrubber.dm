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

/obj/machinery/portable_atmospherics/powered/scrubber/Initialize(mapload, skip_cell)
	. = ..()
	if(!skip_cell)
		cell = new/obj/item/cell/apc(src)
	make_climbable()

/obj/machinery/portable_atmospherics/powered/scrubber/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF || !operable())
		return

	if(prob(50/severity))
		set_on(!on)
		if(on)
			om_changed(src, CHANGE_MACHINE_SETTINGS)

DECLARE_APPEARANCE_PROC(/obj/machinery/portable_atmospherics/powered/scrubber, PROC_REF(appearance_overlays), list())
/obj/machinery/portable_atmospherics/powered/scrubber/appearance_overlays()
	. = list()

	if(on && cell && cell.charge)
		icon_state = "pscrubber:1"
	else
		icon_state = "pscrubber:0"

	if(holding)
		. += "scrubber-open"

	if(connected_port())
		. += "scrubber-connector"

	return .

// Machine pipeline (code/game/machinery/machine_pipeline.dm, "portable pumps and scrubbers"
// section): polls = FALSE (declared with the other vars above) moves this off SSmachines'
// process() roster. The body below is unchanged, just relocated to
// /datum/om/stage/machine/power/portable_scrubber/perform(); it never hibernates on its own (it
// runs every tick while `on`, exactly as process() did), so idle() there is simply `!on`.
/obj/machinery/portable_atmospherics/powered/scrubber/proc/scrubber_step()
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
			update_icon()

/obj/machinery/portable_atmospherics/powered/scrubber/return_air()
	return air_contents

/obj/machinery/portable_atmospherics/powered/scrubber/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/open_ui,
	)
	into += dq_interaction_from_spec(type, INTERACT_OBSERVER("View", TYPE_PROC_REF(/atom, interaction_as_touch)))
	..()

/obj/machinery/portable_atmospherics/powered/scrubber/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PortableScrubber", name)
		ui.open()

/obj/machinery/portable_atmospherics/powered/scrubber/tgui_data(mob/user)
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

/obj/machinery/portable_atmospherics/powered/scrubber/tgui_act(action, params)
	if(..())
		return TRUE

	switch(action)
		if("power")
			set_on(!on)
			if(on)
				om_changed(src, CHANGE_MACHINE_SETTINGS)
			. = TRUE
		if("eject")
			if(holding)
				holding.forceMove(loc)
				holding = null
			. = TRUE
		if("volume_adj")
			volume_rate = CLAMP(text2num(params["vol"]), minrate, maxrate)
			. = TRUE

	update_icon()


//Huge scrubber
/obj/machinery/portable_atmospherics/powered/scrubber/huge
	name = "Huge Air Scrubber"
	desc = "A larger variation of the portable scrubber, for industrial scrubbing of air. Must be turned on from a remote terminal."
	icon = 'icons/obj/atmos_vr.dmi' // New Sprite
	icon_state = "scrubber:0"
	anchored = TRUE
	volume = 500000
	volume_rate = 7000
	// Its own machine_step() (anchored/power checks every frame while on), on the machine
	// pipeline's step/huge_* stage (machine_pipeline.dm) rather than the base portable stages.

	use_power = USE_POWER_IDLE
	idle_power_usage = 50 // //internal circuitry, friction losses and stuff
	active_power_usage = 1000 // // Blowers running
	power_rating = 100000 // //100 kW ~ 135 HP

	var/global/gid = 1
	var/id = 0

/obj/machinery/portable_atmospherics/powered/scrubber/huge/Initialize(mapload)
	. = ..(mapload, TRUE)

	id = gid
	gid++

	name = "[name] (ID [id])"

	// Not climbable!
	unmake_climbable()

/obj/machinery/portable_atmospherics/powered/scrubber/huge/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/scrubber_huge_no_hand,
		/datum/interaction/machine_item/scrubber_huge_reject_cell_tank,
	)
	..()

/// Old attack_hand: always refuses, never calls ..().
/datum/interaction/machine_hand/ungated/scrubber_huge_no_hand
	id = "scrubber_huge_no_hand"
	name = "Use"
	effect = /obj/machinery/portable_atmospherics/powered/scrubber/huge/proc/interaction_no_hand

/obj/machinery/portable_atmospherics/powered/scrubber/huge/proc/interaction_no_hand(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("You can't directly interact with this machine. Use the scrubber control console."))
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/machinery/portable_atmospherics/powered/scrubber/huge, PROC_REF(appearance_overlays), list())
/obj/machinery/portable_atmospherics/powered/scrubber/huge/appearance_overlays()
	. = list()

	if(on && operable())
		icon_state = "scrubber:1"
	else
		icon_state = "scrubber:0"

/obj/machinery/portable_atmospherics/powered/scrubber/huge/machine_step()
	if(!anchored || (!operable()))
		set_on(0)
		last_flow_rate = 0
		last_power_draw = 0
		update_icon()
		return PROCESS_KILL
	var/new_use_power = 1 + on
	if(new_use_power != use_power)
		set_use_power(new_use_power)
	if(!on)
		return PROCESS_KILL

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

/// Old attackby: silently swallows cells and tanks (doesn't use power cells or hold tanks); anything else falls through to ..().
/datum/interaction/machine_item/scrubber_huge_reject_cell_tank
	id = "scrubber_huge_reject_cell_tank"
	name = "Use"
	held_type = list(/obj/item/cell, /obj/item/tank)
	effect = /atom/proc/interaction_swallow

/obj/machinery/portable_atmospherics/powered/scrubber/huge/wrench_act(mob/user, obj/item/tool)
	if(on)
		to_chat(user, span_warning("Turn \the [src] off first!"))
		return ITEM_INTERACT_BLOCKING
	set_anchored(!anchored)
	playsound(src, tool.usesound, 50, TRUE)
	to_chat(user, span_notice("You [anchored ? "wrench" : "unwrench"] \the [src]."))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/portable_atmospherics/powered/scrubber/huge/screwdriver_act(mob/user, obj/item/tool)
	return ITEM_INTERACT_BLOCKING


/obj/machinery/portable_atmospherics/powered/scrubber/huge/stationary
	name = "Stationary Air Scrubber"

/obj/machinery/portable_atmospherics/powered/scrubber/huge/stationary/Initialize(mapload)
	. = ..()
	desc += "This one seems to be tightly secured with large bolts."

/obj/machinery/portable_atmospherics/powered/scrubber/huge/stationary/wrench_act(mob/user, obj/item/tool)
	to_chat(user, span_warning("The bolts are too tight for you to unscrew!"))
	return ITEM_INTERACT_BLOCKING

/obj/machinery/portable_atmospherics/powered/scrubber/huge/step_has_work()
	return on && anchored && operable()


/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/portable_atmospherics/powered/scrubber/step_start_condition()
	return on
