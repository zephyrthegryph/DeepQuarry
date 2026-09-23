// the SMES
// stores power


//# define SMESMAXCHARGELEVEL 250000 Unused
//# define SMESMAXOUTPUT 250000 Unused

/obj/machinery/power/smes
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "power storage unit"
	desc = "A high-capacity superconducting magnetic energy storage (SMES) unit."
	icon_state = "smes"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	use_power = USE_POWER_OFF
	circuit = /obj/item/circuitboard/smes
	clicksound = "switch"
	max_integrity = 500

	var/capacity = 5e6 // maximum charge
	var/charge = 1e6 // actual charge

	var/input_attempt = 0 			// 1 = attempting to charge, 0 = not attempting to charge
	var/inputting = 0 				// 1 = actually inputting, 0 = not inputting
	var/input_level = 50000 		// amount of power the SMES attempts to charge by
	var/input_level_max = 200000 	// cap on input_level
	var/input_available = 0 		// amount of charge available from input last tick

	var/output_attempt = 1 			// 1 = attempting to output, 0 = not attempting to output
	var/outputting = 0 				// 1 = actually outputting, 0 = not outputting
	var/output_level = 50000		// amount of power the SMES attempts to output
	var/output_level_max = 200000	// cap on output_level
	var/output_used = 0				// amount of power actually outputted. may be less than output_level if the powernet returns excess power

	//Holders for powerout event.
	var/last_output_attempt	= 0
	var/last_input_attempt	= 0
	var/last_charge			= 0

	//For icon overlay updates
	var/last_disp
	var/last_chrg
	var/last_onln

	var/input_cut = 0
	var/input_pulsed = 0
	var/output_cut = 0
	var/output_pulsed = 0
	var/target_load = 0

	var/name_tag = null
	var/building_terminal = 0 //Suggestions about how to avoid clickspam building several terminals accepted!
	var/list/terminals // Lazy
	var/should_be_mapped = 0 // If this is set to 0 it will send out warning on New()
	var/grid_check = FALSE // If true, suspends all I/O.

	// More humming noises
	var/datum/looping_sound/generator/soundloop
	var/noisy = FALSE

/obj/machinery/power/smes/drain_power(drain_check, surge, amount = 0)

	if(drain_check)
		return 1

	var/smes_amt = min((amount * SMESRATE), charge)
	charge -= smes_amt
	return smes_amt / SMESRATE

REGISTRY_MEMBERSHIP(/obj/machinery/power/smes, REGISTRY_SMES)

/obj/machinery/power/smes/Initialize(mapload)
	. = ..()
	add_nearby_terminals()
	soundloop = new(list(src), FALSE) // hmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm
	soundloop.extra_range = -6 // Doing this here bc we're reusing the generator hum, and can't directly edit that one
	soundloop.falloff = 0.2 // Harsher falloff.
	if(!check_terminals())
		stat |= BROKEN
		return
	update_icon()
	if(!powernet)
		connect_to_network()
	if(!should_be_mapped)
		WARNING("Non-buildable or Non-magical SMES at [src.x]X [src.y]Y [src.z]Z")
	if(mapload)
		return INITIALIZE_HINT_LATELOAD

/obj/machinery/power/smes/LateInitialize()
	apply_mapped_upgrades()
	apply_mapped_settings()

// Only the buildable smes type checks for mapped updates
/obj/machinery/power/smes/buildable/apply_mapped_upgrades()
	// Detect new coils placed by mappers
	var/list/parts_found = list()
	for(var/i = 1, i <= loc.contents.len, i++)
		var/obj/item/W = loc.contents[i]
		if(istype(W, /obj/item/smes_coil))
			parts_found.Add(W)
	// If any coils are on us, clear base coils and rebuild using these ones
	if(parts_found.len == 0)
		return
	while(TRUE)
		var/obj/item/smes_coil/C = locate(/obj/item/smes_coil) in component_parts
		if(isnull(C))
			break
		component_parts.Remove(C)
		qdel(C)
		cur_coils--
	// Rebuild from mapper's coils
	for(var/i = 1, i <= parts_found.len, i++)
		if (cur_coils < max_coils)
			var/obj/item/W = parts_found[i]
			cur_coils++
			component_parts.Add(W)
			W.forceMove(src)
	RefreshParts()

// Allows subtypes to configue the smes for different input/output rates, and level of starting charge
/obj/machinery/power/smes/proc/apply_mapped_settings()
	return

/obj/machinery/power/smes/Destroy()
	for(var/obj/machinery/power/terminal/T in terminals)
		T.powernet?.unregister_storage_terminal(T)
		T.master = null
	terminals = null
	QDEL_NULL(soundloop)
	return ..()

/obj/machinery/power/smes/proc/add_nearby_terminals()
	for(var/d in GLOB.cardinal)
		var/turf/T = get_step(src, d)
		for(var/obj/machinery/power/terminal/term in T)
			if(term && term.dir == turn(d, 180) && !term.master)
				LAZYOR(terminals, term)
				term.master = src
				term.connect_to_network()

/obj/machinery/power/smes/proc/check_terminals()
	if(!LAZYLEN(terminals))
		return FALSE
	return TRUE

/obj/machinery/power/smes/add_avail(amount)
	if(powernet)
		power_supply_generation = SSmachines.power_supply_generation
		powernet.register_power_supply(src, amount, TRUE)
		return 1
	return 0

/obj/machinery/power/smes/disconnect_terminal(obj/machinery/power/terminal/term)
	term.powernet?.unregister_storage_terminal(term)
	LAZYREMOVE(terminals, term)
	term.master = null

/obj/machinery/power/smes/update_icon()
	cut_overlays()
	if(stat & BROKEN)	return

	add_overlay("smes-op[outputting]")

	if(inputting == 2)
		add_overlay("smes-oc2")
	else if (inputting == 1)
		add_overlay("smes-oc1")
	else
		if(input_attempt)
			add_overlay("smes-oc0")

	var/clevel = chargedisplay()
	if(clevel>0)
		add_overlay("smes-og[clevel]")
	return


/obj/machinery/power/smes/proc/chargedisplay()
	return round(5.5*charge/(capacity ? capacity : 5e6))

/obj/machinery/power/smes/proc/input_power(percentage, obj/machinery/power/terminal/term)
	var/to_input = target_load * (percentage/100)
	to_input = between(0, to_input, target_load)
	if(percentage == 100)
		inputting = 2
	else if(percentage)
		inputting = 1
	// else inputting = 0, as set in process()

	var/inputted = term.powernet.draw_power(min(to_input, input_level - input_available), term)
	add_charge(inputted)
	input_available += inputted

// Mostly in place due to child types that may store power in other way (PSUs)
/obj/machinery/power/smes/proc/add_charge(amount)
	charge += amount*SMESRATE

/obj/machinery/power/smes/proc/remove_charge(amount)
	charge -= amount*SMESRATE

/obj/machinery/power/smes/process()
	if(stat & BROKEN)
		soundloop.stop()
		noisy = FALSE
		clear_power_supply()
		for(var/obj/machinery/power/terminal/term in terminals)
			term.powernet?.register_storage_demand(src, term, 0)
		return PROCESS_KILL

	// only update icon if state changed
	if(last_disp != chargedisplay() || last_chrg != inputting || last_onln != outputting)
		update_icon()
	//store machine state to see if we need to update the icon overlays
	last_disp = chargedisplay()
	last_chrg = inputting
	last_onln = outputting
	input_available = 0
	target_load = 0
	inputting = 0

	//inputting
	if(input_attempt && (!input_pulsed && !input_cut) && !grid_check)
		target_load = CLAMP((capacity-charge)/SMESRATE, 0, input_level)	// Amount we will request from the powernet.
		var/input_available = FALSE
		for(var/obj/machinery/power/terminal/term in terminals)
			if(!term.powernet)
				continue
			input_available = TRUE
			term.powernet.register_storage_demand(src, term, target_load)
		if(!input_available)
			target_load = 0 // We won't input any power without powernet connection.
		inputting = 0
	else
		for(var/obj/machinery/power/terminal/term in terminals)
			term.powernet?.register_storage_demand(src, term, 0)

	output_used = 0
	//outputting
	if(output_attempt && (!output_pulsed && !output_cut) && powernet && charge && !grid_check)
		output_used = min( charge/SMESRATE, output_level)		//limit output to that stored
		add_avail(output_used)				// add output to powernet (smes side)
		outputting = 2
	else if(!powernet || !charge)
		outputting = 1
	else
		output_used = 0

	if(!noisy && outputting) // Are we actually outputting power?
		soundloop.start()
		noisy = TRUE
	if(noisy && outputting)
		// Capped to 40 volume since higher volumes get annoying and it sounds worse.
		// Formula previously was min(round(power/10)+1, 20)
		soundloop.volume = CLAMP((output_used / 1000), 1, 40)
	if(!outputting)
		soundloop.stop()
		noisy = FALSE
	// Both directions are retained as powernet rates. Storage settlement wakes
	// this machine exactly at a full/empty boundary; settings and topology wake it
	// explicitly, so no charge-state polling remains.
	return PROCESS_KILL

/// Debit the portion of a stable registered output rate that the network
/// actually consumed over elapsed machinery intervals.
/obj/machinery/power/smes/proc/consume_registered_output(used_rate, elapsed_ticks)
	if(used_rate <= 0 || elapsed_ticks <= 0)
		return
	output_used = min(used_rate, output_level)
	remove_charge(output_used * elapsed_ticks)
	charge = max(charge, 0)
	if((input_attempt && charge < capacity) || !charge)
		START_MACHINE_PROCESSING(src)

/obj/machinery/power/smes/proc/receive_registered_input(input_rate, elapsed_ticks)
	if(input_rate <= 0 || elapsed_ticks <= 0)
		return
	add_charge(input_rate * elapsed_ticks)
	charge = min(charge, capacity)
	if(charge >= capacity)
		START_MACHINE_PROCESSING(src)

/obj/machinery/power/smes/proc/set_registered_input(input_rate, requested_rate)
	input_available = input_rate
	if(input_rate <= 0)
		inputting = 0
	else if(input_rate + 0.01 >= requested_rate)
		inputting = 2
	else
		inputting = 1

// Compatibility hook for callers outside the persistent ledger.
/obj/machinery/power/smes/proc/restore(percent_load)
	return

//Will return 1 on failure
/obj/machinery/power/smes/proc/make_terminal(const/mob/user)
	if (user.loc == loc)
		to_chat(user, span_filter_notice(span_warning("You must not be on the same tile as the [src].")))
		return 1

	//Direction the terminal will face to
	var/tempDir = get_dir(user, src)
	switch(tempDir)
		if (NORTHEAST, SOUTHEAST)
			tempDir = EAST
		if (NORTHWEST, SOUTHWEST)
			tempDir = WEST
	var/turf/tempLoc = get_step(src, reverse_direction(tempDir))
	if (istype(tempLoc, /turf/space))
		to_chat(user, span_filter_notice(span_warning("You can't build a terminal on space.")))
		return 1
	else if (istype(tempLoc))
		if(!tempLoc.is_plating())
			to_chat(user, span_filter_notice(span_warning("You must remove the floor plating first.")))
			return 1
	if(check_terminal_exists(tempLoc, user, tempDir))
		return 1
	to_chat(user, span_filter_notice(span_notice("You start adding cable to the [src].")))
	if(do_after(user, 5 SECONDS, target = src))
		if(check_terminal_exists(tempLoc, user, tempDir))
			return 1
		var/obj/machinery/power/terminal/term = new/obj/machinery/power/terminal(tempLoc)
		term.set_dir(tempDir)
		term.master = src
		term.connect_to_network()
		LAZYOR(terminals, term)
		return 0
	return 1

/obj/machinery/power/smes/proc/check_terminal_exists(turf/location, mob/user, direction)
	for(var/obj/machinery/power/terminal/term in location)
		if(term.dir == direction)
			to_chat(user, span_filter_notice(span_notice("There is already a terminal here.")))
			return 1
	return 0

/obj/machinery/power/smes/draw_power(amount)
	var/drained = 0
	for(var/obj/machinery/power/terminal/term in terminals)
		if(!term.powernet)
			continue
		if((amount - drained) <= 0)
			return 0
		drained += term.powernet.draw_power(amount - drained, term)
	return drained


/obj/machinery/power/smes
	silicon_use = SILICON_USE_UI

/obj/machinery/power/smes/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/smes_add_cable,
		/datum/interaction/machine_item/smes_use_item,
		/datum/interaction/machine_hand/ungated/smes_use,
	)
	..()

/// Old attack_hand (never called ..()).
/datum/interaction/machine_hand/ungated/smes_use
	id = "smes_use"
	name = "Use"
	effect = /obj/machinery/power/smes/proc/interaction_use

/obj/machinery/power/smes/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	tgui_interact(user)
	return TRUE

/// Old attackby: /obj/item/fusion_coil was deleted with the fusion subsystem, so the
/// charge-from-coil branch is gone. SMES is still chargeable by other means.
/// Attach a terminal with cable coil. Requires the panel to be open.
/datum/interaction/machine_item/smes_add_cable
	id = "smes_add_cable"
	name = "Add cables"
	held_type = /obj/item/stack/cable_coil
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/power/smes/proc/not_building_terminal, null))
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/power/smes/proc/panel_is_open, "you need to open the access hatch first"))
	effect = /obj/machinery/power/smes/proc/interaction_add_cable

/obj/machinery/power/smes/proc/not_building_terminal(mob/actor, atom/target, obj/item/held)
	return !building_terminal

/obj/machinery/power/smes/proc/panel_is_open(mob/actor, atom/target, obj/item/held)
	return panel_open

/obj/machinery/power/smes/proc/interaction_add_cable(mob/user, obj/item/stack/cable_coil/CC, datum/interaction/interaction)
	building_terminal = 1
	if (CC.get_amount() < 10)
		to_chat(user, span_filter_notice(span_warning("You need more cables.")))
		building_terminal = 0
		return TRUE
	if (make_terminal(user))
		building_terminal = 0
		return TRUE
	building_terminal = 0
	CC.use(10)
	user.visible_message(\
			span_filter_notice(span_notice("[user.name] has added cables to the [src].")),\
			span_filter_notice(span_notice("You added cables to the [src].")))
	stat = 0
	if(!powernet)
		connect_to_network()
	return TRUE

/// Any other item, or a cable coil while a terminal is already being built: swallowed
/// silently (the old attackby never called ..(), so nothing further ran).
/datum/interaction/machine_item/smes_use_item
	id = "smes_use_item"
	name = "Use"
	held_type = /obj/item
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/power/smes/proc/panel_is_open, "you need to open the access hatch first"))
	effect = /obj/machinery/power/smes/proc/interaction_swallow

/obj/machinery/power/smes/proc/interaction_swallow(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

/obj/machinery/power/smes/screwdriver_act(mob/user, obj/item/tool)
	return ..()

/obj/machinery/power/smes/welder_act(mob/user, obj/item/tool)
	if(!panel_open)
		to_chat(user, span_filter_notice(span_warning("You need to open access hatch on [src] first!")))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder.isOn())
		to_chat(user, span_filter_notice("Turn on \the [welder] first!"))
		return ITEM_INTERACT_BLOCKING
	var/missing_integrity = max_integrity - get_integrity()
	if(!missing_integrity)
		to_chat(user, span_filter_notice("\The [src] is already fully repaired."))
		return ITEM_INTERACT_BLOCKING
	if(welder.remove_fuel(0, user) && do_after(user, missing_integrity, target = src))
		to_chat(user, span_filter_notice("You repair all structural damage to \the [src]"))
		repair_damage(missing_integrity)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/smes/wirecutter_act(mob/user, obj/item/tool)
	if(!panel_open)
		to_chat(user, span_filter_notice(span_warning("You need to open access hatch on [src] first!")))
		return ITEM_INTERACT_BLOCKING
	if(building_terminal)
		return ITEM_INTERACT_BLOCKING
	building_terminal = TRUE
	var/obj/machinery/power/terminal/term
	for(var/obj/machinery/power/terminal/candidate in get_turf(user))
		if(candidate.master == src)
			term = candidate
			break
	if(!term)
		to_chat(user, span_filter_notice(span_warning("There is no terminal on this tile.")))
		building_terminal = FALSE
		return ITEM_INTERACT_BLOCKING
	var/turf/terminal_turf = get_turf(term)
	if(terminal_turf && !terminal_turf.is_plating())
		to_chat(user, span_filter_notice(span_warning("You must remove the floor plating first.")))
	else
		playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
		if(use_tool(user, tool, src, delay = 5 SECONDS, volume = 0, message_self = "You begin to cut the cables..."))
			if(prob(50) && electrocute_mob(user, term.powernet, term))
				var/datum/effect/effect/system/spark_spread/sparks = new
				sparks.set_up(5, 1, src)
				sparks.start()
				building_terminal = FALSE
				if(user.stunned)
					return ITEM_INTERACT_SUCCESS
			new /obj/item/stack/cable_coil(loc, 10)
			user.visible_message(span_filter_notice(span_notice("[user.name] cut the cables and dismantled the power terminal.")), span_filter_notice(span_notice("You cut the cables and dismantle the power terminal.")))
			LAZYREMOVE(terminals, term)
			qdel(term)
	building_terminal = FALSE
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/smes/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Smes", name)
		ui.open()

/obj/machinery/power/smes/tgui_data()
	var/list/data = list(
		"capacity" = capacity,
		"capacityPercent" = round(100*charge/capacity, 0.1),
		"charge" = charge,
		"inputAttempt" = input_attempt,
		"inputting" = inputting,
		"inputLevel" = input_level,
		"inputLevel_text" = DisplayPower(input_level),
		"inputLevelMax" = input_level_max,
		"inputAvailable" = input_available,
		"outputAttempt" = output_attempt,
		"outputting" = outputting,
		"outputLevel" = output_level,
		"outputLevel_text" = DisplayPower(output_level),
		"outputLevelMax" = output_level_max,
		"outputUsed" = output_used,
	)
	return data

/obj/machinery/power/smes/proc/Percentage()
	if(!capacity)
		return 0
	return round(100.0*charge/capacity, 0.1)

/obj/machinery/power/smes/tgui_act(action, params)
	if(..())
		return TRUE
	switch(action)
		if("tryinput")
			inputting(!input_attempt)
			update_icon()
			. = TRUE
		if("tryoutput")
			outputting(!output_attempt)
			if(output_attempt)
				playsound(loc, 'sound/effects/contactor_on.ogg', 50, FALSE)
			else
				playsound(loc, 'sound/effects/contactor_off.ogg', 50, FALSE)
			update_icon()
			. = TRUE
		if("input")
			tgui_set_io(SMES_TGUI_INPUT, params["target"], text2num(params["adjust"]))
		if("output")
			tgui_set_io(SMES_TGUI_OUTPUT, params["target"], text2num(params["adjust"]))

/obj/machinery/power/smes/proc/tgui_set_io(io, target, adjust)
	if(target == "min")
		target = 0
		. = TRUE
	else if(target == "max")
		switch(io)
			if(SMES_TGUI_INPUT)
				target = input_level_max
			if(SMES_TGUI_OUTPUT)
				target = output_level_max
		. = TRUE
	else if(adjust)
		switch(io)
			if(SMES_TGUI_INPUT)
				target = input_level + adjust
			if(SMES_TGUI_OUTPUT)
				target = output_level + adjust
		. = TRUE
	else if(text2num(target) != null)
		target = text2num(target)
		. = TRUE
	if(.)
		switch(io)
			if(SMES_TGUI_INPUT)
				set_input(target)
			if(SMES_TGUI_OUTPUT)
				set_output(target)


/obj/machinery/power/smes/proc/inputting(do_input)
	input_attempt = do_input
	if(!input_attempt)
		inputting = 0
	START_MACHINE_PROCESSING(src)

/obj/machinery/power/smes/proc/outputting(do_output)
	output_attempt = do_output
	if(!output_attempt)
		outputting = 0
		clear_power_supply()
	START_MACHINE_PROCESSING(src)

/obj/machinery/power/smes/atom_destruction(damage_flag)
	visible_message(span_filter_notice(span_danger("\The [src] explodes in large shower of sparks and smoke!")))
	switch(Percentage())
		if(75 to INFINITY)
			explosion(get_turf(src), 1, 2, 4)
		if(40 to 74)
			explosion(get_turf(src), 0, 2, 3)
		if(5 to 39)
			explosion(get_turf(src), 0, 1, 2)
	return ..()

/obj/machinery/power/smes/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	inputting(rand(0,1))
	outputting(rand(0,1))
	output_level = rand(0, output_level_max)
	input_level = rand(0, input_level_max)
	charge -= 1e6/severity
	if (charge < 0)
		charge = 0
	update_icon()

/obj/machinery/power/smes/examine(mob/user)
	. = ..()
	. += span_filter_notice("The service hatch is [panel_open ? "open" : "closed"].")
	var/missing_integrity = max_integrity - get_integrity()
	if(!missing_integrity)
		return
	var/damage_percentage = round((missing_integrity / max_integrity) * 100)
	switch(damage_percentage)
		if(75 to INFINITY)
			. += span_filter_notice(span_danger("It's casing is severely damaged, and sparking circuitry may be seen through the holes!"))
		if(50 to 74)
			. += span_filter_notice(span_notice("It's casing is considerably damaged, and some of the internal circuits appear to be exposed!"))
		if(25 to 49)
			. += span_filter_notice(span_notice("It's casing is quite seriously damaged."))
		if(0 to 24)
			. += span_filter_notice("It's casing has some minor damage.")


// Proc: toggle_input()
// Parameters: None
// Description: Switches the input on/off depending on previous setting
/obj/machinery/power/smes/proc/toggle_input()
	inputting(!input_attempt)
	update_icon()

// Proc: toggle_output()
// Parameters: None
// Description: Switches the output on/off depending on previous setting
/obj/machinery/power/smes/proc/toggle_output()
	outputting(!output_attempt)
	update_icon()

// Proc: set_input()
// Parameters: 1 (new_input - New input value in Watts)
// Description: Sets input setting on this SMES. Trims it if limits are exceeded.
/obj/machinery/power/smes/proc/set_input(new_input = 0)
	input_level = between(0, new_input, input_level_max)
	START_MACHINE_PROCESSING(src)
	update_icon()

// Proc: set_output()
// Parameters: 1 (new_output - New output value in Watts)
// Description: Sets output setting on this SMES. Trims it if limits are exceeded.
/obj/machinery/power/smes/proc/set_output(new_output = 0)
	output_level = between(0, new_output, output_level_max)
	START_MACHINE_PROCESSING(src)
	update_icon()

/obj/machinery/power/smes/buildable/hybrid
	name = "hybrid power storage unit"
	desc = "A high-capacity superconducting magnetic energy storage (SMES) unit, modified with alien technology to generate small amounts of power from seemingly nowhere."
	icon = 'icons/obj/power_vr.dmi'
	var/recharge_rate = 10000
	var/overlay_icon = 'icons/obj/power_vr.dmi'

/obj/machinery/power/smes/buildable/hybrid/screwdriver_act(mob/user, obj/item/tool)
	to_chat(user, span_warning("\The [src] is full of weird alien technology that's best not messed with."))
	return ITEM_INTERACT_BLOCKING

/obj/machinery/power/smes/buildable/hybrid/wirecutter_act(mob/user, obj/item/tool)
	to_chat(user, span_warning("\The [src] is full of weird alien technology that's best not messed with."))
	return ITEM_INTERACT_BLOCKING

/obj/machinery/power/smes/buildable/hybrid/update_icon()
	cut_overlays()
	if(stat & BROKEN)	return

	add_overlay("smes-op[outputting]")

	if(inputting == 2)
		add_overlay("smes-oc2")
	else if (inputting == 1)
		add_overlay("smes-oc1")
	else
		if(input_attempt)
			add_overlay("smes-oc0")

	var/clevel = chargedisplay()
	if(clevel>0)
		add_overlay("smes-og[clevel]")
	return

/obj/machinery/power/smes/buildable/hybrid/process()
	charge += min(recharge_rate, capacity - charge)
	..()
