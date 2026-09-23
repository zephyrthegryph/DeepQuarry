
/*
 * Distillery, used for over-time temperature-based mixes.
 */

/obj/machinery/portable_atmospherics/powered/reagent_distillery
	name = "chemical distillery"
	desc = "A complex machine utilizing state-of-the-art components to mix chemicals at different temperatures. Can be attached to a connector port to utilize gasses."
	use_power = USE_POWER_IDLE

	icon = 'icons/obj/machines/reagent.dmi'
	icon_state = "distiller"
	var/base_state	// The string var used in update icon for overlays, either set manually or initialized.

	power_rating = 3000
	power_losses = 240

	var/on = FALSE

	var/target_temp = T20C

	var/max_temp = T0C + 300
	var/min_temp = T0C - 10

	var/use_atmos = FALSE	// If true, this machine will use the temperature of the connected gas mixtures as the source of heat, rather than its internal controls.

	var/static/radial_examine = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_examine")
	var/static/radial_use = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_use")

	var/static/radial_pump = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_pump")

	var/static/radial_eject_input = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_eject_input")
	var/static/radial_eject_output = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_eject_output")

	var/static/radial_adjust_temp = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_temp")

	var/static/radial_install_input = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_add")
	var/static/radial_install_output = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_add")

	var/static/radial_inspectgauges = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_lookat")

	var/static/radial_mix = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_mix")

// Overlay holders so we don't have to constantly remake them.
	var/image/overlay_output_beaker
	var/image/overlay_input_beaker
	var/image/overlay_off
	var/image/overlay_ready
	var/image/overlay_cooling
	var/image/overlay_heating
	var/image/overlay_dumping
	var/image/overlay_connected

	var/obj/item/reagent_containers/glass/InputBeaker
	var/obj/item/reagent_containers/glass/OutputBeaker

// A multiplier for the production amount. This should really only ever be lower than one, otherwise you end up with duping.
	var/efficiency = 1

/obj/machinery/portable_atmospherics/powered/reagent_distillery/Initialize(mapload)
	. = ..()

	create_reagents(600, /datum/reagents/distilling)

	if(!base_state)
		base_state = icon_state

	setup_overlay_vars()

	update_icon()

/obj/machinery/portable_atmospherics/powered/reagent_distillery/RefreshParts()
	var/total_laser_rating = get_part_rating(/obj/item/stock_parts/micro_laser)

	max_temp = initial(max_temp) + (50 * (total_laser_rating - 1))
	min_temp = max(1, initial(min_temp) - (30 * (total_laser_rating - 1)))

	return

/obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/setup_overlay_vars()
	overlay_output_beaker = image(icon = src.icon, icon_state = "[base_state]-output")
	overlay_input_beaker = image(icon = src.icon, icon_state = "[base_state]-input")
	overlay_off = image(icon = src.icon, icon_state = "[base_state]-bad")
	overlay_ready = image(icon = src.icon, icon_state = "[base_state]-good")
	overlay_cooling = image(icon = src.icon, icon_state = "[base_state]-cool")
	overlay_heating = image(icon = src.icon, icon_state = "[base_state]-heat")
	overlay_dumping = image(icon = src.icon, icon_state = "[base_state]-dump")
	overlay_connected = image(icon = src.icon, icon_state = "[base_state]-connector")

/obj/machinery/portable_atmospherics/powered/reagent_distillery/Destroy()
	if(InputBeaker)
		qdel(InputBeaker)
		InputBeaker = null
	if(OutputBeaker)
		qdel(OutputBeaker)
		OutputBeaker = null

	. = ..()

/obj/machinery/portable_atmospherics/powered/reagent_distillery/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		. += span_notice("\The [src] is powered [on ? "on" : "off"].")

		. += span_notice("\The [src]'s gauges read:")
		if(!use_atmos)
			. += span_notice("- Target Temperature:") + span_warning("[target_temp]")
		. += span_notice("- Temperature:") + span_warning("[round(get_temperature(), 0.01)]")

		if(InputBeaker)
			if(InputBeaker.reagents.reagent_list.len)
				. += span_notice("\The [src]'s input beaker holds [InputBeaker.reagents.total_volume] units of liquid.")
			else
				. += span_notice("\The [src]'s input beaker is empty!")

		if(reagents.reagent_list.len)
			. += span_notice("\The [src]'s internal buffer holds [reagents.total_volume] units of liquid.")
		else
			. += span_notice("\The [src]'s internal buffer is empty!")

		if(OutputBeaker)
			if(OutputBeaker.reagents.reagent_list.len)
				. += span_notice("\The [src]'s output beaker holds [OutputBeaker.reagents.total_volume] units of liquid.")
			else
				. += span_notice("\The [src]'s output beaker is empty!")

/obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/toggle_power(mob/user = usr)
	if(powered())
		on = !on
		START_MACHINE_PROCESSING(src)
		to_chat(user, span_notice("You turn \the [src] [on ? "on" : "off"]."))
	else
		to_chat(user, span_notice(" Nothing happens."))

/obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/toggle_mixing(mob/user = usr)
	to_chat(user, span_notice("You press \the [src]'s chamber agitator button."))
	if(on)
		visible_message(span_infoplain(span_bold("\The [src]") + " rattles to life."))
		reagents.handle_reactions()
	else
		spawn(1 SECOND)
			to_chat(user, span_notice("Nothing happens.."))

/obj/machinery/portable_atmospherics/powered/reagent_distillery/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_verb/distillery_toggle_power,
		/datum/interaction/machine_verb/distillery_toggle_mixing,
		/datum/interaction/machine_item/distillery_install_beaker,
		/datum/interaction/machine_hand/ungated/distillery_radial,
	)
	..()

/datum/interaction/machine_verb/distillery_toggle_power
	id = "distillery_toggle_power"
	name = "Toggle Distillery Heating"
	effect = /obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/interaction_distillery_toggle_power

/obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/interaction_distillery_toggle_power(mob/user, obj/item/held, datum/interaction/interaction)
	toggle_power(user)
	return TRUE

/datum/interaction/machine_verb/distillery_toggle_mixing
	id = "distillery_toggle_mixing"
	name = "Start Distillery Mixing"
	effect = /obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/interaction_distillery_toggle_mixing

/obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/interaction_distillery_toggle_mixing(mob/user, obj/item/held, datum/interaction/interaction)
	toggle_mixing(user)
	return TRUE

/datum/interaction/machine_hand/ungated/distillery_radial
	id = "distillery_radial"
	name = "Use"
	effect = /obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/interaction_distillery_radial

/obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/interaction_distillery_radial(mob/user, obj/item/held, datum/interaction/interaction)
	var/list/options = list()
	options["examine"] = radial_examine
	options["use"] = radial_use
	options["inspect gauges"] = radial_inspectgauges
	options["pulse agitator"] = radial_mix

	if(InputBeaker)
		options["eject input"] = radial_eject_input
	if(OutputBeaker)
		options["eject output"] = radial_eject_output

	if(!use_atmos)
		options["adjust temp"] = radial_adjust_temp

	if(length(options) < 1)
		return TRUE

	var/list/choice = list()
	if(length(options) == 1)
		for(var/key in options)
			choice = key
	else
		choice = show_radial_menu(user, src, options, require_near = !issilicon(user))

	switch(choice)
		if("examine")
			user.examinate(src)

		if("use")
			toggle_power(user)

		if("inspect gauges")
			to_chat(user, span_notice("\The [src]'s gauges read:"))
			if(!use_atmos)
				to_chat(user, span_notice("- Target Temperature:") + span_warning("[target_temp]"))
			to_chat(user, span_notice("- Temperature:") + span_warning("[round(get_temperature(), 0.01)]"))

		if("pulse agitator")
			toggle_mixing(user)

		if("eject input")
			if(InputBeaker)
				InputBeaker.forceMove(get_turf(src))
				InputBeaker = null

		if("eject output")
			if(OutputBeaker)
				OutputBeaker.forceMove(get_turf(src))
				OutputBeaker = null

		if("adjust temp")
			var/new_temp = tgui_input_number(user, "Choose a target temperature.", "Temperature.", T20C, max_temp, min_temp, round_value = FALSE)
			if(isnum(new_temp))
				target_temp = new_temp

	update_icon()
	return TRUE

/datum/interaction/machine_item/distillery_install_beaker
	id = "distillery_install_beaker"
	name = "Install beaker"
	held_type = /obj/item/reagent_containers/glass
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/has_free_beaker_slot, null))
	effect = /obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/interaction_distillery_install_beaker

/obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/has_free_beaker_slot(mob/actor, atom/target, obj/item/held)
	return !InputBeaker || !OutputBeaker

/obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/interaction_distillery_install_beaker(mob/user, obj/item/W, datum/interaction/interaction)
	var/list/options = list()
	if(!InputBeaker)
		options["install input"] = radial_install_input
	if(!OutputBeaker)
		options["install output"] = radial_install_output

	if(!options || !options.len)
		update_icon()
		return FALSE

	var/list/choice = list()
	if(length(options) == 1)
		for(var/key in options)
			choice = key
	else
		choice = show_radial_menu(user, src, options, require_near = TRUE) // No telekinetics.

	switch(choice)
		if("install input")
			if(!InputBeaker)
				user.drop_from_inventory(W)
				W.add_fingerprint(user)
				W.forceMove(src)
				InputBeaker = W

		if("install output")
			if(!OutputBeaker)
				user.drop_from_inventory(W)
				W.add_fingerprint(user)
				W.forceMove(src)
				OutputBeaker = W

	update_icon()
	return TRUE

/obj/machinery/portable_atmospherics/powered/reagent_distillery/use_power(amount, chan = -1)
	last_power_draw = amount
	if(use_cell && cell && cell.charge)
		var/cellcharge = cell.charge
		cell.use(amount)

		var/celldifference = max(0, cellcharge - cell.charge)

		amount = celldifference

	var/area/A = get_area(src)
	if(!A || !isarea(A))
		return
	if(chan == -1)
		chan = power_channel
	A.use_power_oneoff(amount, chan)

/obj/machinery/portable_atmospherics/powered/reagent_distillery/process()
	..()

	var/run_pump = FALSE

	if(InputBeaker || OutputBeaker)
		run_pump = TRUE

	var/avg_temp = 0
	var/avg_pressure = 0

	if(connected_port && connected_port.network.line_members.len)
		var/list/members = list()
		var/datum/pipe_network/Net = connected_port.network
		members = Net.line_members.Copy()

		for(var/datum/pipeline/Line in members)
			avg_pressure += Line.air.return_pressure()
			avg_temp += Line.air.return_temperature()

		avg_temp /= members.len
		avg_pressure /= members.len

	if(!powered())
		on = FALSE

	var/current_temp = get_temperature()
	if(!on || (use_atmos && (!connected_port || (avg_pressure / avg_temp) < (1000 / T20C)))) // This mostly respects gas laws by ignoring volume but it should make it usable at low temps
		distillery_heat(0, null)

	else if(on)
		if(!use_atmos)
			// Heater/cooler: a heat source on the distillery's body driven
			// towards the target, at most power_rating watts either way.
			var/target = clamp(target_temp, min_temp, max_temp)
			distillery_heat(clamp((target - current_temp) * DISTILLERY_THERMOSTAT_GAIN, -power_rating, power_rating), null)
			if(abs(target - current_temp) > 0.5)
				use_power(power_rating * CELLRATE)
				distillery_pinged = FALSE
			else if(!distillery_pinged)
				distillery_pinged = TRUE
				playsound(src, 'sound/machines/ping.ogg', 50, 0)
				src.visible_message(span_infoplain(span_bold("\The [src]") + " pings as it reaches the target temperature."))

		else if(connected_port && avg_pressure > 1000)
			// Heat exchanger: the body couples to the port's gas, conserving energy.
			var/datum/pipeline/line = connected_port.network.line_members[1]
			distillery_heat(0, line?.air)
		else if(!run_pump)
			visible_message(span_notice("\The [src]'s motors wind down."))
			on = FALSE

		if(InputBeaker && reagents.total_volume < reagents.maximum_volume)
			InputBeaker.reagents.trans_to_holder(reagents, amount = rand(10,20))

		if(OutputBeaker && OutputBeaker.reagents.total_volume < OutputBeaker.reagents.maximum_volume)
			use_power(power_rating * CELLRATE * 0.5)
			reagents.trans_to_holder(OutputBeaker.reagents, amount = rand(1, 5))

	update_icon()
	if(!on)
		distillery_heat(0, null)
		if(isnull(heat_body))
			return PROCESS_KILL

/obj/machinery/portable_atmospherics/powered/reagent_distillery/update_icon()
	..()
	cut_overlays()

	if(InputBeaker)
		add_overlay(overlay_input_beaker)

	if(OutputBeaker)
		add_overlay(overlay_output_beaker)

	if(on)
		if(OutputBeaker && OutputBeaker.reagents.total_volume < OutputBeaker.reagents.maximum_volume)
			add_overlay(overlay_dumping)
		else if(abs(get_temperature() - target_temp) <= 0.5)
			add_overlay(overlay_ready)
		else if(get_temperature() < target_temp)
			add_overlay(overlay_heating)
		else
			add_overlay(overlay_cooling)

	else
		add_overlay(overlay_off)

	if(connected_port)
		add_overlay(overlay_connected)

/*
 * Subtypes
 */

/obj/machinery/portable_atmospherics/powered/reagent_distillery/industrial
	name = "industrial chemical distillery"
	desc = "A gas-operated variant of a chemical distillery. Able to reach much higher, and lower, temperatures through the use of treated gas at the cost of not having an internal heater/cooler."

	use_atmos = TRUE

	min_temp = T0C - 270

/obj/machinery/portable_atmospherics/powered/reagent_distillery/return_air()
	if(connected_port)
		var/obj/machinery/atmospherics/portables_connector/our_port = connected_port
		if(our_port.network)
			return our_port.network.gases[1]
	. = ..()


/obj/machinery/portable_atmospherics/powered/reagent_distillery
	/// Pinged at the target since it last left it.
	var/tmp/distillery_pinged = FALSE

/// Sets the distillery's heat source (W; negative cools) and its coupling to
/// a gas mixture (null: none). Its body is kept while either is active.
/obj/machinery/portable_atmospherics/powered/reagent_distillery/proc/distillery_heat(watts, datum/gas_mixture/gas)
	if(!watts && !gas)
		if(!isnull(heat_body))
			vg_heat_body_power(heat_body, 0)
			vg_heat_body_couple(heat_body, 1, HEAT_TARGET_NONE, 0, 0)
			vg_heat_body_keep(heat_body, FALSE)
		return
	if(!create_heat_body(TRUE))
		return
	vg_heat_body_keep(heat_body, TRUE)
	vg_heat_body_power(heat_body, watts)
	if(gas)
		vg_heat_body_couple(heat_body, 1, HEAT_TARGET_MIXTURE, gas, DISTILLERY_GAS_CONDUCTANCE)
	else
		vg_heat_body_couple(heat_body, 1, HEAT_TARGET_NONE, 0, 0)

/// The distillery's body carries the reagents it holds.
/obj/machinery/portable_atmospherics/powered/reagent_distillery/thermal_properties()
	. = ..()
	if(reagents)
		.[THERMAL_CAPACITY] += reagents.heat_capacity()
