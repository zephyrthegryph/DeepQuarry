// the SMES
// stores power
//
// M3: charge, input and output run in Rust (verdigris/domains/power/src/smes.rs)
// every power step: the output is a supply on the SMES node's network, the input
// a demand on each terminal's. The SMES never polls: it runs on the machine
// pipeline (machine_pipeline.dm), whose power stage calls power_step() once
// when a setting changes (CHANGE_MACHINE_SETTINGS) and then idles; power_event()
// applies the charge and the shown state.

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
	clicksound = SFX_SWITCH
	max_integrity = 500

	var/capacity = 5e6 // maximum charge
	/// Starting charge, seeded into Rust when the unit registers. Rust owns the live value:
	/// read it with stored_charge(), change it with adjust_stored_charge()/set_stored_charge().
	var/initial_charge = 1e6

	var/input_attempt = 0 			// 1 = attempting to charge, 0 = not attempting to charge
	var/inputting = 0 				// 1 = actually inputting, 0 = not inputting
	var/input_level = 50000 		// amount of power the SMES attempts to charge by
	var/input_level_max = 200000 	// cap on input_level

	var/output_attempt = 1 			// 1 = attempting to output, 0 = not attempting to output
	var/outputting = 0 				// 1 = actually outputting, 0 = not outputting
	var/output_level = 50000		// amount of power the SMES attempts to output
	var/output_level_max = 200000	// cap on output_level

	//Holders for powerout event.
	var/last_output_attempt	= 0
	var/last_input_attempt	= 0
	var/last_charge			= 0

	//For icon overlay updates
	var/last_disp

	var/input_cut = 0
	var/input_pulsed = 0
	var/output_cut = 0
	var/output_pulsed = 0

	var/name_tag = null
	var/building_terminal = 0 //Suggestions about how to avoid clickspam building several terminals accepted!
	var/list/terminals // Lazy
	var/should_be_mapped = 0 // If this is set to 0 it will send out warning on New()
	var/grid_check = FALSE // If true, suspends all I/O.
	/// Power events applied (tests check that an idle SMES hears none).
	var/power_event_count = 0
	/// Whether initial_charge has been written into the Rust entity.
	var/charge_seeded = FALSE

	// More humming noises
	var/datum/looping_sound/generator/soundloop
	var/noisy = FALSE

/obj/machinery/power/smes/drain_power(drain_check, surge, amount = 0)

	if(drain_check)
		return 1

	var/smes_amt = min((amount * SMESRATE), stored_charge())
	adjust_stored_charge(-smes_amt)
	return smes_amt / SMESRATE

REGISTRY_MEMBERSHIP(/obj/machinery/power/smes, REGISTRY_SMES)

/// A SMES's own input terminal (rust_architecture.md step 3): its own
/// entity, on its own region, naming the SMES unit
/// (verdigris/domains/power/src/components.rs's `SmesInputTerminal`) --
/// unlike the generic terminal, or an APC's own, this is a real network
/// node in its own right, not a construction anchor for another entity's.
/obj/machinery/power/terminal/smes_input

/obj/machinery/power/smes/Initialize(mapload)
	. = ..()
	add_nearby_terminals()
	own_set(src, nameof(soundloop), new /datum/looping_sound/generator(list(src), FALSE)) // hmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm
	soundloop.extra_range = -6 // Doing this here bc we're reusing the generator hum, and can't directly edit that one
	soundloop.falloff = 0.2 // Harsher falloff.
	if(!check_terminals())
		stat_add(BROKEN)
		return
	update_icon()
	if(!power_region)
		connect_to_network(!mapload)
	power_sync()
	if(!should_be_mapped)
		WARNING("Non-buildable or Non-magical SMES at [src.x]X [src.y]Y [src.z]Z")
	if(mapload)
		return INITIALIZE_HINT_LATELOAD

/obj/machinery/power/smes/LateInitialize()
	apply_mapped_upgrades()
	apply_mapped_settings()
	power_sync()

// Only the buildable smes type checks for mapped updates
/obj/machinery/power/smes/buildable/apply_mapped_upgrades()
	// Detect new coils placed by mappers
	var/list/parts_found = list()
	for(var/i = 1, i <= contents_count(loc), i++)
		var/obj/item/W = loc.contents[i]
		if(istype(W, /obj/item/smes_coil))
			parts_found.Add(W)
	// If any coils are on us, clear base coils and rebuild using these ones
	if(parts_found.len == 0)
		return
	while(TRUE)
		var/obj/item/smes_coil/C = locate_in_list(component_parts, /obj/item/smes_coil)
		if(isnull(C))
			break
		own_take_member(src, nameof(component_parts), C)
		qdel(C)
		cur_coils--
	// Rebuild from mapper's coils
	for(var/i = 1, i <= parts_found.len, i++)
		if (cur_coils < max_coils)
			var/obj/item/W = parts_found[i]
			cur_coils++
			own_add(src, nameof(component_parts), W)
			W.forceMove(src)
	RefreshParts()

// Allows subtypes to configue the smes for different input/output rates, and level of starting charge
/obj/machinery/power/smes/proc/apply_mapped_settings()
	return


/obj/machinery/power/smes/proc/add_nearby_terminals()
	for(var/d in GLOB.cardinal)
		var/turf/T = get_step(src, d)
		for(var/obj/machinery/power/terminal/smes_input/term in turf_contents_of_type(T, /obj/machinery/power/terminal/smes_input))
			if(term && term.dir == turn(d, 180) && !term.master())
				rel_add(src, nameof(terminals), term)
				rel_set(term, nameof(term.master), src)
				term.connect_to_network(FALSE)
	power_sync()

/obj/machinery/power/smes/proc/check_terminals()
	if(!LAZYLEN(terminals))
		return FALSE
	return TRUE

/obj/machinery/power/smes/disconnect_terminal(obj/machinery/power/terminal/term)
	rel_remove(src, nameof(terminals), term)
	rel_clear(term, nameof(term.master))
	power_sync()

/obj/machinery/power/smes/power_registered()
	power_sync()
	// Rust's charge starts at zero: seed it once from the DM starting value.
	if(vg_entity && !charge_seeded)
		charge_seeded = TRUE
		adjust_charge(initial_charge - get_charge())

/// The unit's stored charge in SMES units: read from Rust, never cached in DM.
/obj/machinery/power/smes/proc/stored_charge()
	return vg_entity ? get_charge() : initial_charge

/// Adds `delta` (negative removes) to the stored charge. Before the unit registers it moves the seed.
/obj/machinery/power/smes/proc/adjust_stored_charge(delta)
	if(vg_entity)
		adjust_charge(delta)
	else
		initial_charge = max(initial_charge + delta, 0)

/// Sets the stored charge (mapped presets, admin, tests).
/obj/machinery/power/smes/proc/set_stored_charge(value)
	adjust_stored_charge(value - stored_charge())

/// Sends settings and capacity to Rust (generated accessors,
/// verdigris/domains/power/src/components.rs). Charge is Rust's own
/// (`Smes.charge` is conserved, laws drive it) -- DM's absolute writes to
/// it (drain_power(), the EMP hit) cross as `adjust_charge` deltas, and
/// power_poll() reads the settled value back.
/obj/machinery/power/smes/proc/power_sync()
	if(QDELETED(src) || !vg_entity)
		return
	var/working = !has_stat(BROKEN) && !grid_check
	set_input_enabled(working && input_attempt && !input_pulsed && !input_cut ? 1 : 0)
	set_output_enabled(working && output_attempt && !output_pulsed && !output_cut ? 1 : 0)
	set_capacity(capacity)
	set_input_level(input_level)
	set_output_level(output_level)
	var/unit_index = (vg_entity - 1) & VG_ENTITY_INDEX_MASK
	for(var/obj/machinery/power/terminal/smes_input/term as anything in terminals)
		if(term.vg_entity)
			term.set_unit(unit_index)

/// Reads back what Rust's SmesOutputPlan/Apply and SmesInputApply did this
/// step (verdigris/domains/power/src/laws.rs): the settled charge and the
/// shown input/output state.
/obj/machinery/power/smes/proc/power_poll()
	if(!vg_entity)
		return
	var/new_inputting = 0
	var/new_outputting = output_attempt ? 1 : 0
	var/display = chargedisplay()
	if(new_inputting != inputting || new_outputting != outputting || last_disp != display)
		power_event_count++
		inputting = new_inputting
		outputting = new_outputting
		last_disp = display
		native_changed(src, CHANGE_MACHINE_CHARGE, NATIVE_SRC_POWER)
		update_icon()
	update_soundloop()

/obj/machinery/power/smes/proc/update_soundloop()
	if(outputting == 2)
		if(!noisy)
			soundloop.start()
			noisy = TRUE
		// Capped to 40 volume since higher volumes get annoying and it sounds worse.
		soundloop.volume = 1
	else if(noisy)
		soundloop.stop()
		noisy = FALSE

DECLARE_APPEARANCE(/obj/machinery/power/smes, "appearance_smes_output", list("0" = list(APPEARANCE_OVERLAYS = list("smes-op0")), "1" = list(APPEARANCE_OVERLAYS = list("smes-op1")), "2" = list(APPEARANCE_OVERLAYS = list("smes-op2"))))
DECLARE_APPEARANCE(/obj/machinery/power/smes, "appearance_smes_input", list("0" = list(APPEARANCE_OVERLAYS = list("smes-oc0")), "1" = list(APPEARANCE_OVERLAYS = list("smes-oc1")), "2" = list(APPEARANCE_OVERLAYS = list("smes-oc2"))))
DECLARE_APPEARANCE(/obj/machinery/power/smes, "appearance_smes_charge", list("1" = list(APPEARANCE_OVERLAYS = list("smes-og1")), "2" = list(APPEARANCE_OVERLAYS = list("smes-og2")), "3" = list(APPEARANCE_OVERLAYS = list("smes-og3")), "4" = list(APPEARANCE_OVERLAYS = list("smes-og4")), "5" = list(APPEARANCE_OVERLAYS = list("smes-og5")), "6" = list(APPEARANCE_OVERLAYS = list("smes-og6"))))

/// TRUE when the status overlays are hidden (broken).
/obj/machinery/power/smes/proc/appearance_smes_dark()
	return has_stat(BROKEN)

/// Output overlay key: "[outputting]", or "" while dark.
/obj/machinery/power/smes/proc/appearance_smes_output()
	if(appearance_smes_dark())
		return ""
	return "[outputting]"

/// Input overlay key: "2"/"1" while inputting, "0" while only attempting, else "".
/obj/machinery/power/smes/proc/appearance_smes_input()
	if(appearance_smes_dark())
		return ""
	if(inputting == 2)
		return "2"
	if(inputting == 1)
		return "1"
	return input_attempt ? "0" : ""

/// Charge gauge overlay key: chargedisplay(), or 0 (no gauge) while dark.
/obj/machinery/power/smes/proc/appearance_smes_charge()
	if(appearance_smes_dark())
		return 0
	return chargedisplay()

/obj/machinery/power/smes/proc/chargedisplay()
	return round(5.5*stored_charge()/(capacity ? capacity : 5e6))

// Mostly in place due to child types that may store power in other way (PSUs)
/obj/machinery/power/smes/proc/add_charge(amount)
	adjust_stored_charge(amount*SMESRATE)
	power_sync()

/obj/machinery/power/smes/proc/remove_charge(amount)
	adjust_stored_charge(-amount*SMESRATE)
	power_sync()

/// One machine pipeline frame (the power/smes stage). Rust charges and discharges the unit;
/// a wake (a settings change, damage, a new terminal) resends the settings once. Returns
/// STAGE_IDLE when the unit has nothing more to do until the next wake.
/obj/machinery/power/smes/proc/power_step()
	if(has_stat(BROKEN))
		soundloop.stop()
		noisy = FALSE
	power_sync()
	return STAGE_IDLE

/// TRUE when power_step() has nothing to do until the next wake.
/obj/machinery/power/smes/proc/power_settled()
	return TRUE

// Compatibility hook for callers outside the persistent ledger.
/obj/machinery/power/smes/proc/restore(percent_load)
	return

//Will return 1 on failure
/// Starts attaching a terminal with `CC` (a timed action). 1 if it could not start.
/obj/machinery/power/smes/proc/make_terminal(const/mob/user, obj/item/stack/cable_coil/CC)
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
	var/started = om_task_start(/datum/om/task/timed/smes_terminal, user, src, receiver = src, CC = CC, tempLoc = tempLoc, tempDir = tempDir)
	return istext(started) ? 1 : 0

/obj/machinery/power/smes/proc/terminal_ended(datum/om/task/timed/smes_terminal/task)
	building_terminal = 0

/datum/om/task/timed/smes_terminal
	duration = 5 SECONDS
	complete_proc = /obj/machinery/power/smes/proc/terminal_done
	cancel_proc = /obj/machinery/power/smes/proc/terminal_ended
	var/obj/item/stack/cable_coil/CC
	var/turf/tempLoc
	var/tempDir

/obj/machinery/power/smes/proc/terminal_done(datum/om/task/timed/smes_terminal/task)
	var/mob/user = task.actor
	var/obj/item/stack/cable_coil/CC = task.CC
	var/turf/tempLoc = task.tempLoc
	var/tempDir = task.tempDir
	building_terminal = 0
	if(check_terminal_exists(tempLoc, user, tempDir) || !CC.use(10))
		return
	var/obj/machinery/power/terminal/smes_input/term = new(tempLoc)
	term.set_dir(tempDir)
	rel_set(term, nameof(term.master), src)
	term.connect_to_network()
	rel_add(src, nameof(terminals), term)
	power_sync()
	act_message(user, src, MSG_SELF(span_filter_notice(span_notice("You added cables to %T%."))), \
		MSG_OTHERS(span_filter_notice(span_notice("[user.name] has added cables to %T%."))))
	set_stat(0)
	if(!power_region)
		connect_to_network()

/obj/machinery/power/smes/proc/check_terminal_exists(turf/location, mob/user, direction)
	for(var/obj/machinery/power/terminal/term in turf_contents_of_type(location, /obj/machinery/power/terminal))
		if(term.dir == direction)
			to_chat(user, span_filter_notice(span_notice("There is already a terminal here.")))
			return 1
	return 0

/obj/machinery/power/smes/draw_power(amount)
	var/drained = 0
	for(var/obj/machinery/power/terminal/term in terminals)
		if(!term.power_region)
			continue
		if((amount - drained) <= 0)
			return 0
		drained += power_draw(term.power_region, amount - drained, term)
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
	if (make_terminal(user, CC))
		building_terminal = 0
	return TRUE

/// Any other item, or a cable coil while a terminal is already being built: swallowed
/// silently (the old attackby never called ..(), so nothing further ran).
/datum/interaction/machine_item/smes_use_item
	id = "smes_use_item"
	name = "Use"
	held_type = /obj/item
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/power/smes/proc/panel_is_open, "you need to open the access hatch first"))
	effect = /atom/proc/interaction_swallow

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
	if(welder.remove_fuel(0, user))
		om_task_timed(user, missing_integrity, src, src, PROC_REF(weld_repair_done), list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/smes/proc/weld_repair_done(mob/user)
	var/missing_integrity = max_integrity - get_integrity()
	to_chat(user, span_filter_notice("You repair all structural damage to \the [src]"))
	repair_damage(missing_integrity)

/obj/machinery/power/smes/wirecutter_act(mob/user, obj/item/tool)
	if(!panel_open)
		to_chat(user, span_filter_notice(span_warning("You need to open access hatch on [src] first!")))
		return ITEM_INTERACT_BLOCKING
	if(building_terminal)
		return ITEM_INTERACT_BLOCKING
	building_terminal = TRUE
	var/obj/machinery/power/terminal/term
	for(var/obj/machinery/power/terminal/candidate in get_turf(user))
		if(candidate.master() == src)
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
		play_sfx(src, SFX_ITEMS_DECONSTRUCT)
		use_tool(user, tool, src, delay = 5 SECONDS, volume = 0, start_self = "You begin to cut the cables...", receiver = src, on_done = PROC_REF(wirecutter_act_tool_done), done_args = list(user, term))
	building_terminal = FALSE
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/smes/proc/wirecutter_act_tool_done(mob/user, obj/machinery/power/terminal/term)
	if(prob(50) && electrocute_mob(user, term.power_region, term))
		fx_sparks(src, 5)
		building_terminal = FALSE
		if(user.has_status(EFFECT_STUNNED))
			return ITEM_INTERACT_SUCCESS
	new /obj/item/stack/cable_coil(loc, 10)
	act_message(user, null, MSG_SELF(span_filter_notice(span_notice("You cut the cables and dismantle the power terminal."))), \
		MSG_OTHERS(span_filter_notice(span_notice("[user.name] cut the cables and dismantled the power terminal."))))
	rel_remove(src, nameof(terminals), term)
	qdel(term)

DECLARE_UI(/obj/machinery/power/smes, "Smes")

UI_DATA_REPLACE(/obj/machinery/power/smes, "merge:ui_data_obj_machinery_power_smes{capacity:num,capacityPercent:num,charge:num,inputAttempt:num,inputting:num,inputLevel:num,inputLevel_text:unknown,inputLevelMax:num,inputAvailable:num,outputAttempt:num,outputting:num,outputLevel:num,outputLevel_text:unknown,outputLevelMax:num,outputUsed:num}")

/// The computed part of /obj/machinery/power/smes's window data (declared on its UI_DATA row).
/obj/machinery/power/smes/proc/ui_data_obj_machinery_power_smes(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list(
		"capacity" = capacity,
		"capacityPercent" = Percentage(),
		"charge" = stored_charge(),
		"inputAttempt" = input_attempt,
		"inputting" = inputting,
		"inputLevel" = input_level,
		"inputLevel_text" = DisplayPower(input_level),
		"inputLevelMax" = input_level_max,
		"inputAvailable" = 0,
		"outputAttempt" = output_attempt,
		"outputting" = outputting,
		"outputLevel" = output_level,
		"outputLevel_text" = DisplayPower(output_level),
		"outputLevelMax" = output_level_max,
		"outputUsed" = 0,
	)
	return data

/obj/machinery/power/smes/proc/Percentage()
	if(!capacity)
		return 0
	return round(100.0*stored_charge()/capacity, 0.1)

UI_ACT(/obj/machinery/power/smes, "tryinput", ui_act_tryinput)
UI_ACT_PROC(/obj/machinery/power/smes, ui_act_tryinput)
	inputting(!input_attempt)
	update_icon()
	. = TRUE

UI_ACT(/obj/machinery/power/smes, "tryoutput", ui_act_tryoutput)
UI_ACT_PROC(/obj/machinery/power/smes, ui_act_tryoutput)
	outputting(!output_attempt)
	if(output_attempt)
		play_sfx(loc, SFX_EFFECTS_CONTACTOR_ON)
	else
		play_sfx(loc, SFX_EFFECTS_CONTACTOR_OFF)
	update_icon()
	. = TRUE

UI_ACT(/obj/machinery/power/smes, "input", ui_act_input, UI_ARG_NUM("adjust"), UI_ARG_VALUE("target"))
UI_ACT_PROC(/obj/machinery/power/smes, ui_act_input)
	tgui_set_io(SMES_TGUI_INPUT, params["target"], params["adjust"])

UI_ACT(/obj/machinery/power/smes, "output", ui_act_output, UI_ARG_NUM("adjust"), UI_ARG_VALUE("target"))
UI_ACT_PROC(/obj/machinery/power/smes, ui_act_output)
	tgui_set_io(SMES_TGUI_OUTPUT, params["target"], params["adjust"])

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
	om_changed(src, CHANGE_MACHINE_SETTINGS)

/obj/machinery/power/smes/proc/outputting(do_output)
	output_attempt = do_output
	if(!output_attempt)
		outputting = 0
	om_changed(src, CHANGE_MACHINE_SETTINGS)

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

DAMAGE_REACTION(/obj/machinery/power/smes, DAMAGE_EMP, PROC_REF(smes_emp_scramble))

/// A pulse scrambles the settings and drains charge.
/obj/machinery/power/smes/proc/smes_emp_scramble(datum/damage_packet/packet)
	inputting(rand(0,1))
	outputting(rand(0,1))
	output_level = rand(0, output_level_max)
	input_level = rand(0, input_level_max)
	set_stored_charge(max(stored_charge() - 1e6/packet.severity, 0))
	power_sync()
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
	om_changed(src, CHANGE_MACHINE_SETTINGS)
	update_icon()

// Proc: set_output()
// Parameters: 1 (new_output - New output value in Watts)
// Description: Sets output setting on this SMES. Trims it if limits are exceeded.
/obj/machinery/power/smes/proc/set_output(new_output = 0)
	output_level = between(0, new_output, output_level_max)
	om_changed(src, CHANGE_MACHINE_SETTINGS)
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

APPEARANCE_NONE(/obj/machinery/power/smes/buildable/hybrid)
DECLARE_APPEARANCE_PROC(/obj/machinery/power/smes/buildable/hybrid, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/power/smes/buildable/hybrid/appearance_overlays()
	. = list()
	if(has_stat(BROKEN))	return

	. += "smes-op[outputting]"

	if(inputting == 2)
		. += "smes-oc2"
	else if (inputting == 1)
		. += "smes-oc1"
	else
		if(input_attempt)
			. += "smes-oc0"

	var/clevel = chargedisplay()
	if(clevel>0)
		. += "smes-og[clevel]"
	return .

/// Hybrid units make their own charge every frame, so they never idle.
/obj/machinery/power/smes/buildable/hybrid/power_step()
	adjust_stored_charge(min(recharge_rate, capacity - stored_charge()))
	power_sync()

/obj/machinery/power/smes/buildable/hybrid/power_settled()
	return FALSE
