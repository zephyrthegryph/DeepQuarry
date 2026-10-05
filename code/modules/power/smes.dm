// the SMES
// stores power
//
// M3: charge, input and output run in Rust (verdigris/domains/power/src/smes.rs) every power step: the output is a supply on the SMES node's
// network, the input a demand on each terminal's. The SMES never polls: its settings reach Rust through push_to_rust() (generated: it runs once per
// frame after any state it reads changed), and power_poll() applies the charge and the shown state.
//
// The SMES is declared (doc/rewrite/final_api.html section 16, doc/rewrite/conversion_guide.md): ONE CAPABILITIES list says what it is: a machine
// that works only with a whole casing, its input terminals (a pair link), its window and the buttons in it, the tools that build and cut a
// terminal and weld the casing, and what an electromagnetic pulse does to it. The imperative parts below are its own: the Rust push and poll, the
// charge arithmetic, the conditions and effects the declarations name, and the look.
//
// What the machine core still keeps until the machine track (phase 4): the stat bits (BROKEN, ...) read through machine_basics()'s one bridge
// contribution, the maintenance hatch (maintenance_flags: the screwdriver and the crowbar), RefreshParts() with the circuit board, and `wires`.

//# define SMESMAXCHARGELEVEL 250000 Unused
//# define SMESMAXOUTPUT 250000 Unused

MSG_DEF_SELF(smes/hatch_shut, "You need to open the access hatch first.")
MSG_DEF_SELF(smes/whole, "It is already fully repaired.")
MSG_DEF_SELF(smes/welder_off, "Turn on the welding tool first!")
MSG_DEF(smes/repaired, "You repair all structural damage to %T%.", "%U% repairs %T%.")
MSG_DEF_SELF(smes/on_the_unit, "You must not be on the same tile as it.")
MSG_DEF_SELF(smes/space, "You can't build a terminal on space.")
MSG_DEF_SELF(smes/plating, "You must remove the floor plating first.")
MSG_DEF_SELF(smes/terminal_there, "There is already a terminal here.")
MSG_DEF_SELF(smes/no_terminal_here, "There is no terminal on this tile.")
MSG_DEF(smes/terminal_built, "You add cables to %T%.", "%U% has added cables to %T%.")
MSG_DEF(smes/terminal_cut, "You cut the cables and dismantle the power terminal.", "%U% cut the cables and dismantled the power terminal.")

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
	/// The unit's input terminals (a pair link: each one's `unit` is this unit).
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

// What Rust is told (push_to_rust() reads these), and what the look and the window read.
TRACKED(/obj/machinery/power/smes, capacity)
TRACKED(/obj/machinery/power/smes, input_attempt)
TRACKED(/obj/machinery/power/smes, inputting)
TRACKED(/obj/machinery/power/smes, input_level)
TRACKED(/obj/machinery/power/smes, output_attempt)
TRACKED(/obj/machinery/power/smes, outputting)
TRACKED(/obj/machinery/power/smes, output_level)
TRACKED(/obj/machinery/power/smes, last_disp)
TRACKED(/obj/machinery/power/smes, input_cut)
TRACKED(/obj/machinery/power/smes, input_pulsed)
TRACKED(/obj/machinery/power/smes, output_cut)
TRACKED(/obj/machinery/power/smes, output_pulsed)
TRACKED(/obj/machinery/power/smes, grid_check)

CAPABILITIES(/obj/machinery/power/smes)
	after_init(0, then(PROC_REF(mapped_after_init)))
	machine_basics(repair = NONE, powered = FALSE)
	space(SPACE_PANEL, door = nameof(panel_open), closed = MSG(smes/hatch_shut))
	links(/obj/machinery/power/smes::terminals, /obj/machinery/power/terminal/smes_input::unit, a_many = TRUE)
	interface("Smes")
	op("tryinput", ui_act("tryinput"), then(PROC_REF(ui_toggle_input)))
	op("tryoutput", ui_act("tryoutput"), then(PROC_REF(ui_toggle_output)))
	op("input", ui_act("input", arg("adjust"), arg("target")), then(PROC_REF(ui_set_input)))
	op("output", ui_act("output", arg("adjust"), arg("target")), then(PROC_REF(ui_set_output)))
	op("add_cable", stack(/obj/item/stack/cable_coil, 10), at(SPACE_PANEL),
		needs(req(PROC_REF(terminal_site_ok), because = PROC_REF(terminal_site_refusal))),
		wait(5 SECONDS), then(PROC_REF(terminal_built)), says(MSG(smes/terminal_built)))
	op("cut_terminal", tool(TOOL_WIRECUTTER), at(SPACE_PANEL),
		needs(req(PROC_REF(terminal_cuttable), because = PROC_REF(terminal_cut_refusal))),
		wait(5 SECONDS), then(PROC_REF(terminal_taken_down)), says(MSG(smes/terminal_cut)))
	op("weld", tool(TOOL_WELDER), at(SPACE_PANEL), costs(RES_FUEL, 0),
		needs(req(PROC_REF(welder_lit), because = MSG(smes/welder_off))),
		wait(PROC_REF(repair_time)), then(PROC_REF(casing_repaired)), says(MSG(smes/repaired)))
	op("swallow", item(/obj/item), at(SPACE_PANEL), priority(OP_PRIORITY_DEFAULT), then(PROC_REF(swallowed)))
	examine_line(PROC_REF(examine_state))
	on_change(nameof(stat), ANY, then(PROC_REF(stat_changed)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(emp_scramble)))
	owns_one(nameof(soundloop), /datum/looping_sound/generator)

/// A unit's input terminal (rust_architecture.md step 3): its own entity, on its own region, naming the SMES unit
/// (verdigris/domains/power/src/components.rs's `SmesInputTerminal`) -- unlike the generic terminal, or an APC's own, this is a real network
/// node in its own right, not a construction anchor for another entity's. Its `unit` (declared on every terminal) is the pair end of the SMES's
/// `terminals`; master() answers it, so every reader of a terminal's master (its destruction, an overload) reaches the unit.
/obj/machinery/power/terminal/smes_input

/obj/machinery/power/smes/drain_power(drain_check, surge, amount = 0)

	if(drain_check)
		return 1

	var/smes_amt = min((amount * SMESRATE), stored_charge())
	adjust_stored_charge(-smes_amt)
	return smes_amt / SMESRATE

REGISTRY_MEMBERSHIP(/obj/machinery/power/smes, REGISTRY_SMES)

/obj/machinery/power/smes/Initialize(mapload)
	. = ..()
	add_nearby_terminals()
	rel_set(src, nameof(soundloop), new /datum/looping_sound/generator(list(src), FALSE)) // hmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm
	soundloop.extra_range = -6 // Doing this here bc we're reusing the generator hum, and can't directly edit that one
	soundloop.falloff = 0.2 // Harsher falloff.
	if(!check_terminals())
		atom_break()
		return
	if(!power_region)
		connect_to_network(!mapload)
	push_to_rust()
	if(!should_be_mapped)
		WARNING("Non-buildable or Non-magical SMES at [src.x]X [src.y]Y [src.z]Z")

/// A mapped SMES's late pass: the coils laid on its tile and its preset settings.
/obj/machinery/power/smes/proc/mapped_after_init(datum/act/timer/A)
	if(A.mapload && !has_stat(BROKEN)) // one without terminals broke in Initialize() and takes no late pass
		map_late()

/obj/machinery/power/smes/proc/map_late()
	apply_mapped_upgrades()
	apply_mapped_settings()
	push_to_rust()

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
			rel_add(src, nameof(component_parts), W)
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
				term.connect_to_network(FALSE)
	link_terminals()

/obj/machinery/power/smes/proc/check_terminals()
	if(!LAZYLEN(terminals))
		return FALSE
	return TRUE

/// A terminal went (it was destroyed, or cut out): its link to the unit goes with it, and Rust hears of the rest.
/obj/machinery/power/smes/disconnect_terminal(obj/machinery/power/terminal/term)
	rel_remove(src, nameof(terminals), term)
	changed(src)

/// Each input terminal's Rust entity learns which unit it feeds.
/obj/machinery/power/smes/proc/link_terminals()
	if(QDELETED(src) || !vg_entity)
		return
	var/unit_index = (vg_entity - 1) & VG_ENTITY_INDEX_MASK
	for(var/obj/machinery/power/terminal/smes_input/term as anything in terminals)
		if(term.vg_entity)
			native_write(term, NATIVE_SMESINPUTTERMINAL_UNIT, unit_index)

/obj/machinery/power/smes/power_registered()
	link_terminals()
	push_to_rust()
	// Rust's charge starts at zero: seed it once from the DM starting value.
	if(vg_entity && !charge_seeded)
		charge_seeded = TRUE
		adjust_charge(initial_charge - get_charge())
		set_last_disp(chargedisplay())

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

/// Sends settings and capacity to Rust (generated accessors, verdigris/domains/power/src/components.rs). The framework runs it once per frame after
/// any state it reads changed, so no setter calls it by hand. Charge is Rust's own (`Smes.charge` is conserved, laws drive it) -- DM's absolute
/// writes to it (drain_power(), the EMP hit) cross as `adjust_charge` deltas, and power_poll() reads the settled value back.
/obj/machinery/power/smes/push_to_rust()
	if(QDELETED(src) || !vg_entity)
		return
	var/working = !has_stat(BROKEN) && !grid_check
	native_write(src, NATIVE_SMES_INPUT_ENABLED, working && input_attempt && !input_pulsed && !input_cut ? 1 : 0)
	native_write(src, NATIVE_SMES_OUTPUT_ENABLED, working && output_attempt && !output_pulsed && !output_cut ? 1 : 0)
	native_write(src, NATIVE_SMES_CAPACITY, capacity)
	native_write(src, NATIVE_SMES_INPUT_LEVEL, input_level)
	native_write(src, NATIVE_SMES_OUTPUT_LEVEL, output_level)

/// Reads back what Rust's SmesOutputPlan/Apply and SmesInputApply did this step (verdigris/domains/power/src/laws.rs): the settled charge and the
/// shown input/output state.
/obj/machinery/power/smes/proc/power_poll()
	if(!vg_entity)
		return
	var/new_inputting = 0
	var/new_outputting = output_attempt ? 1 : 0
	var/display = chargedisplay()
	if(new_inputting != inputting || new_outputting != outputting || last_disp != display)
		power_event_count++
		set_inputting(new_inputting)
		set_outputting(new_outputting)
		set_last_disp(display)
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

/// The casing broke or was mended: a broken unit falls silent.
/obj/machinery/power/smes/proc/stat_changed(datum/act/A)
	if(has_stat(BROKEN))
		soundloop.stop()
		noisy = FALSE

// ---- what it shows ----

/// TRUE when the status overlays are hidden (broken).
/obj/machinery/power/smes/proc/status_dark()
	return has_stat(BROKEN)

/// The unit's look: its output, input and charge overlays, none while it is dark.
/obj/machinery/power/smes/draw(datum/look/look)
	..()
	draw_status(look)

/obj/machinery/power/smes/proc/draw_status(datum/look/look)
	if(status_dark())
		return
	look.overlay("smes-op[outputting]")
	if(inputting == 2)
		look.overlay("smes-oc2")
	else if(inputting == 1)
		look.overlay("smes-oc1")
	else if(input_attempt)
		look.overlay("smes-oc0")
	var/gauge = last_disp
	if(gauge > 0)
		look.overlay("smes-og[gauge]")

/obj/machinery/power/smes/proc/chargedisplay()
	return round(5.5*stored_charge()/(capacity ? capacity : 5e6))

// Mostly in place due to child types that may store power in other way (PSUs)
/obj/machinery/power/smes/proc/add_charge(amount)
	adjust_stored_charge(amount*SMESRATE)

/obj/machinery/power/smes/proc/remove_charge(amount)
	adjust_stored_charge(-amount*SMESRATE)

// Compatibility hook for callers outside the persistent ledger.
/obj/machinery/power/smes/proc/restore(percent_load)
	return

// ---- the terminals: building one and cutting one out ----

/// Where a terminal built from this actor's spot goes: list(the turf, its direction), or null with the reason in `why`'s place. The actor stands next
/// to the unit; the terminal goes on the far side of the unit's line to the actor (the tile the actor stands on, for an orthogonal spot).
/obj/machinery/power/smes/proc/terminal_site_of(mob/user)
	var/tempDir = get_dir(user, src)
	switch(tempDir)
		if (NORTHEAST, SOUTHEAST)
			tempDir = EAST
		if (NORTHWEST, SOUTHWEST)
			tempDir = WEST
	var/turf/tempLoc = get_step(src, REVERSE_DIR(tempDir))
	return list(tempLoc, tempDir)

/// Why a terminal cannot be built by this actor now, or null.
/obj/machinery/power/smes/proc/terminal_site_refusal(datum/act/op/A)
	var/mob/user = A.actor
	if(!user)
		return /datum/msg/op/failed
	if(user.loc == loc) // ALLOW(reads): where the actor stands is legacy mob state, read when the cable is offered
		return /datum/msg/smes/on_the_unit
	var/list/site = terminal_site_of(user)
	var/turf/tempLoc = site[1]
	if(istype(tempLoc, /turf/space))
		return /datum/msg/smes/space
	if(istype(tempLoc) && !tempLoc.is_plating())
		return /datum/msg/smes/plating
	if(terminal_exists_at(tempLoc, site[2]))
		return /datum/msg/smes/terminal_there
	return null

/obj/machinery/power/smes/proc/terminal_site_ok(datum/act/op/A)
	return isnull(terminal_site_refusal(A))

/// A terminal already stands on `location` facing `direction`.
/obj/machinery/power/smes/proc/terminal_exists_at(turf/location, direction)
	for(var/obj/machinery/power/terminal/term in location)
		if(term.dir == direction)
			return TRUE
	return FALSE

/// The ten lengths went in after the wait: the terminal is made and joins the network.
/obj/machinery/power/smes/proc/terminal_built(datum/act/op/A)
	var/list/site = terminal_site_of(A.actor)
	var/turf/tempLoc = site[1]
	var/tempDir = site[2]
	if(terminal_exists_at(tempLoc, tempDir))
		A.reason = /datum/msg/smes/terminal_there
		return OP_REFUSED
	var/obj/machinery/power/terminal/smes_input/term = new(tempLoc)
	term.set_dir(tempDir)
	rel_add(src, nameof(terminals), term)
	term.connect_to_network()
	link_terminals()
	changed(src)
	set_stat(0)
	if(!power_region)
		connect_to_network()
	return OP_OK

/// The terminal this actor's tile holds that answers to this unit, or null.
/obj/machinery/power/smes/proc/terminal_under(mob/user)
	for(var/obj/machinery/power/terminal/candidate in get_turf(user))
		if(candidate.master() == src)
			return candidate
	return null

/// Why the wirecutters cannot take a terminal out now, or null.
/obj/machinery/power/smes/proc/terminal_cut_refusal(datum/act/op/A)
	var/obj/machinery/power/terminal/term = A.actor ? terminal_under(A.actor) : null
	if(!term)
		return /datum/msg/smes/no_terminal_here
	var/turf/terminal_turf = get_turf(term)
	if(terminal_turf && !terminal_turf.is_plating())
		return /datum/msg/smes/plating
	return null

/obj/machinery/power/smes/proc/terminal_cuttable(datum/act/op/A)
	return isnull(terminal_cut_refusal(A))

/// The wait is over: the cable is cut (with a chance of a shock from the live cable), the ten lengths drop and the terminal goes.
/obj/machinery/power/smes/proc/terminal_taken_down(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/machinery/power/terminal/term = terminal_under(user)
	if(!term)
		A.reason = /datum/msg/smes/no_terminal_here
		return OP_REFUSED
	if(prob(50) && electrocute_mob(user, term.power_region, term))
		fx_sparks(src, 5)
		if(user.has_status(EFFECT_STUNNED))
			return OP_OK
	new /obj/item/stack/cable_coil(loc, 10)
	rel_remove(src, nameof(terminals), term)
	qdel(term)
	return OP_OK

// ---- the casing ----

/// The welding tool in hand is lit.
/obj/machinery/power/smes/proc/welder_lit(datum/act/op/A)
	var/obj/item/weldingtool/welder = A.held
	return istype(welder) && welder.isOn()

/// The weld is done: every point of damage is repaired (a whole casing refuses).
/obj/machinery/power/smes/proc/casing_repaired(datum/act/op/A)
	if(get_integrity() >= max_integrity)
		A.reason = /datum/msg/smes/whole
		return OP_REFUSED
	repair_damage(max_integrity)
	return OP_OK

/// The welder takes as long as there is damage: a decisecond for every point.
/obj/machinery/power/smes/proc/repair_time(datum/act/A)
	return max_integrity - get_integrity()

/// Anything else with the hatch open is taken and does nothing.
/obj/machinery/power/smes/proc/swallowed(datum/act/op/A)
	return OP_OK

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

// ---- the window ----

/obj/machinery/power/smes/ui_data(datum/act/eval/A)
	return list(
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
		"outputUsed" = 0)

/obj/machinery/power/smes/proc/Percentage()
	if(!capacity)
		return 0
	return round(100.0*stored_charge()/capacity, 0.1)

/obj/machinery/power/smes/proc/ui_toggle_input(datum/act/op/A)
	inputting(!input_attempt)
	return OP_OK

/obj/machinery/power/smes/proc/ui_toggle_output(datum/act/op/A)
	outputting(!output_attempt)
	if(output_attempt)
		play_sfx(loc, SFX_EFFECTS_CONTACTOR_ON)
	else
		play_sfx(loc, SFX_EFFECTS_CONTACTOR_OFF)
	return OP_OK

/obj/machinery/power/smes/proc/ui_set_input(datum/act/op/A, adjust, target)
	tgui_set_io(SMES_TGUI_INPUT, target, adjust)
	return OP_OK

/obj/machinery/power/smes/proc/ui_set_output(datum/act/op/A, adjust, target)
	tgui_set_io(SMES_TGUI_OUTPUT, target, adjust)
	return OP_OK

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
	set_input_attempt(do_input)
	if(!input_attempt)
		set_inputting(0)

/obj/machinery/power/smes/proc/outputting(do_output)
	set_output_attempt(do_output)
	if(!output_attempt)
		set_outputting(0)

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

/// A pulse scrambles the settings and drains charge.
/obj/machinery/power/smes/proc/emp_scramble(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/severity = max(N.packet?.severity, 1)
	inputting(rand(0,1))
	outputting(rand(0,1))
	set_output_level(rand(0, output_level_max))
	set_input_level(rand(0, input_level_max))
	set_stored_charge(max(stored_charge() - 1e6/severity, 0))

/// The hatch and the damage, as examine says them.
/obj/machinery/power/smes/proc/examine_state(datum/act/A)
	var/list/lines = list(span_filter_notice("The service hatch is [panel_open ? "open" : "closed"]."))
	var/missing_integrity = max_integrity - get_integrity()
	if(!missing_integrity)
		return lines
	var/damage_percentage = round((missing_integrity / max_integrity) * 100)
	switch(damage_percentage)
		if(75 to INFINITY)
			lines += span_filter_notice(span_danger("It's casing is severely damaged, and sparking circuitry may be seen through the holes!"))
		if(50 to 74)
			lines += span_filter_notice(span_notice("It's casing is considerably damaged, and some of the internal circuits appear to be exposed!"))
		if(25 to 49)
			lines += span_filter_notice(span_notice("It's casing is quite seriously damaged."))
		if(0 to 24)
			lines += span_filter_notice("It's casing has some minor damage.")
	return lines

// Proc: toggle_input()
// Parameters: None
// Description: Switches the input on/off depending on previous setting
/obj/machinery/power/smes/proc/toggle_input()
	inputting(!input_attempt)

// Proc: toggle_output()
// Parameters: None
// Description: Switches the output on/off depending on previous setting
/obj/machinery/power/smes/proc/toggle_output()
	outputting(!output_attempt)

// Proc: set_input()
// Parameters: 1 (new_input - New input value in Watts)
// Description: Sets input setting on this SMES. Trims it if limits are exceeded.
/obj/machinery/power/smes/proc/set_input(new_input = 0)
	set_input_level(between(0, new_input, input_level_max))

// Proc: set_output()
// Parameters: 1 (new_output - New output value in Watts)
// Description: Sets output setting on this SMES. Trims it if limits are exceeded.
/obj/machinery/power/smes/proc/set_output(new_output = 0)
	set_output_level(between(0, new_output, output_level_max))

/obj/machinery/power/smes/buildable/hybrid
	name = "hybrid power storage unit"
	desc = "A high-capacity superconducting magnetic energy storage (SMES) unit, modified with alien technology to generate small amounts of power from seemingly nowhere."
	icon = 'icons/obj/power_vr.dmi'
	var/recharge_rate = 10000
	var/overlay_icon = 'icons/obj/power_vr.dmi'

// A hybrid unit's casing is full of alien technology: the wirecutters are not for its terminals, and it makes its own charge every frame.
CAPABILITIES(/obj/machinery/power/smes/buildable/hybrid)
	without("cut_terminal")
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(hybrid_charge)))

/// Hybrid units make their own charge every frame, never more than there is room for.
/obj/machinery/power/smes/buildable/hybrid/proc/hybrid_charge(datum/act/timer/A)
	adjust_stored_charge(min(recharge_rate, capacity - stored_charge()))
