// the SMES
// stores power
//
// M3: charge, input and output run in Rust (verdigris/domains/power/src/smes.rs) every power step: the output is a supply on the SMES node's
// network, the input a demand on each terminal's. The SMES never polls Rust by hand: its settings reach Rust through push_to_rust() (generated:
// it runs once per frame after any state it reads changed), and power_poll() reads back what flowed (Rust's output_used, input_used and
// input_available) and shows it: the input and output lamps (inputting/outputting 0 off, 1 trying, 2 flowing), the window's readings, the hum.
//
// The SMES is declared (doc/rewrite/final_api.html section 16, doc/rewrite/conversion_guide.md): ONE CAPABILITIES list says what it is: a machine
// that works only while it is not broken and has an input terminal, its registry membership, its input terminals (a pair link) and its sound loop,
// its window and the buttons in it, the tools that build and cut a terminal and weld the casing, and what an electromagnetic pulse does to it.
// The imperative parts below are its own: the Rust push and poll, the charge arithmetic, the conditions and effects the declarations name, and the
// look.
//
// What the machine core still keeps until the machine track (phase 4): the BROKEN stat bit, read through stat_bits_allow() (only BROKEN: a SMES is
// its network's supply, so the area going dark must not stop it), the maintenance hatch (maintenance_flags: the screwdriver and the crowbar),
// RefreshParts() with the circuit board, and the power node binding of /obj/machinery/power.

MSG_DEF_SELF(smes/hatch_shut, "You need to open the access hatch first.")
MSG_DEF_SELF(smes/whole, "It is already fully repaired.")
MSG_DEF(smes/repaired, "You repair all structural damage to %T%.", "%U% repairs %T%.")
MSG_DEF_SELF(smes/on_the_unit, "You must not be on the same tile as it.")
MSG_DEF_SELF(smes/space, "You can't build a terminal on space.")
MSG_DEF_SELF(smes/plating, "You must remove the floor plating first.")
MSG_DEF_SELF(smes/terminal_there, "There is already a terminal here.")
MSG_DEF_SELF(smes/no_terminal_here, "There is no terminal on this tile.")
MSG_DEF_SELF(smes/unwired, "It has no input terminal.")
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

	/// The input switch (the window's button, a wire's pulse).
	var/input_attempt = 0
	/// What the input lamp shows: 0 off, 1 trying (nothing to take), 2 charging. Rust's reading, applied by power_poll().
	var/inputting = 0
	/// The power the unit asks of its input terminals (W).
	var/input_level = 50000
	/// The cap on input_level (W): its coils' I/O.
	var/input_level_max = 200000

	/// The output switch.
	var/output_attempt = 1
	/// What the output lamp shows: 0 off, 1 trying (nothing drawn), 2 feeding a load. Rust's reading, applied by power_poll().
	var/outputting = 0
	/// The power the unit offers its network (W).
	var/output_level = 50000
	/// The cap on output_level (W).
	var/output_level_max = 200000

	/// What Rust reported last step (W): the leftover supply the input terminals saw, and what the output delivered.
	var/input_available = 0
	var/output_used = 0

	/// The charge gauge the look shows (0..5).
	var/last_disp

	/// A wire is cut: the input, or the output, is off whatever its switch says.
	var/input_cut = 0
	var/output_cut = 0

	var/name_tag = null
	/// The unit's input terminals (a pair link: each one's `unit` is this unit).
	var/list/terminals // Lazy
	/// Placed with no input terminal: dark and idle until one is built (a unit that loses its terminal later keeps working).
	var/unwired = FALSE
	var/grid_check = FALSE // If true, suspends all I/O.
	/// What a power failure event emptied out of the unit (list(charge, output switch, input switch)), for power_restore() to put back.
	var/list/held_through_outage
	/// Power events applied (tests check that an idle SMES hears none).
	var/power_event_count = 0
	/// Whether initial_charge has been written into the Rust entity.
	var/charge_seeded = FALSE

	/// The hum while the output feeds a load (owned: made with the unit, deleted with it).
	var/datum/looping_sound/generator/smes/soundloop
	var/noisy = FALSE

// What Rust is told (push_to_rust() reads these), and what the look and the window read.
TRACKED(/obj/machinery/power/smes, capacity)
TRACKED(/obj/machinery/power/smes, input_attempt)
TRACKED(/obj/machinery/power/smes, inputting)
TRACKED(/obj/machinery/power/smes, input_level)
TRACKED(/obj/machinery/power/smes, input_level_max)
TRACKED(/obj/machinery/power/smes, output_attempt)
TRACKED(/obj/machinery/power/smes, outputting)
TRACKED(/obj/machinery/power/smes, output_level)
TRACKED(/obj/machinery/power/smes, output_level_max)
TRACKED(/obj/machinery/power/smes, input_available)
TRACKED(/obj/machinery/power/smes, output_used)
TRACKED(/obj/machinery/power/smes, last_disp)
TRACKED(/obj/machinery/power/smes, input_cut)
TRACKED(/obj/machinery/power/smes, output_cut)
TRACKED(/obj/machinery/power/smes, unwired)
TRACKED(/obj/machinery/power/smes, grid_check)

/// The unit moves power now: it works (not broken, wired) and no grid check holds it. What push_to_rust() sends as the switches' gate.
STAT(/obj/machinery/power/smes, working, ALL)

CAPABILITIES(/obj/machinery/power/smes)
	after_init(0, then(PROC_REF(mapped_after_init)))
	machine_basics(repair = NONE, powered = FALSE)
	membership(joins = REGISTRY_SMES)
	contributes(STAT_OPERABLE, cond_not(nameof(unwired)), reason = MSG(smes/unwired))
	contributes(STAT_WORKING, STAT_OPERABLE)
	contributes(STAT_WORKING, cond_not(nameof(grid_check)))
	space(SPACE_PANEL, door = nameof(panel_open), closed = MSG(smes/hatch_shut))
	links(/obj/machinery/power/smes::terminals, /obj/machinery/power/terminal/smes_input::unit, a_many = TRUE)
	owns_one(nameof(soundloop), /datum/looping_sound/generator/smes, starts = PROC_REF(make_soundloop))
	on_change(nameof(outputting), ANY, then(PROC_REF(output_shown)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(emp_scramble)))
	examine_line(PROC_REF(examine_state))

	section(controls, "The unit's window and the buttons in it")
	interface("Smes")
	op("tryinput", ui_act(), toggles(nameof(input_attempt)), then(PROC_REF(input_switched)))
	op("tryoutput", ui_act(), toggles(nameof(output_attempt)), then(PROC_REF(output_switched)))
	op("input", ui_act(arg("adjust"), arg("target")), then(PROC_REF(ui_set_input)))
	op("output", ui_act(arg("adjust"), arg("target")), then(PROC_REF(ui_set_output)))

	section(hatch, "What the tools do behind the open hatch")
	op("add_cable", stack(/obj/item/stack/cable_coil, 10), at(SPACE_PANEL),
		needs(req(PROC_REF(terminal_site_ok), because = PROC_REF(terminal_site_refusal))),
		wait(5 SECONDS), then(PROC_REF(terminal_built)), says(MSG(smes/terminal_built)))
	op("cut_terminal", tool(TOOL_WIRECUTTER), at(SPACE_PANEL),
		needs(req(PROC_REF(terminal_cuttable), because = PROC_REF(terminal_cut_refusal))),
		wait(5 SECONDS), then(PROC_REF(terminal_taken_down)), says(MSG(smes/terminal_cut)))
	op("weld", lit_welder(fuel = 0), at(SPACE_PANEL), needs(req(PROC_REF(casing_damaged), because = MSG(smes/whole))),
		wait(PROC_REF(repair_time)), then(PROC_REF(casing_repaired)), says(MSG(smes/repaired)))
	op("swallow", item(/obj/item), at(SPACE_PANEL), priority(OP_PRIORITY_DEFAULT))

/// A unit's input terminal (rust_architecture.md step 3): its own entity, on its own region, naming the SMES unit
/// (verdigris/domains/power/src/components.rs's `SmesInputTerminal`) -- unlike the generic terminal, or an APC's own, this is a real network
/// node in its own right, not a construction anchor for another entity's. Its `unit` (declared on every terminal) is the pair end of the SMES's
/// `terminals`; master() answers it, so every reader of a terminal's master (its destruction, an overload) reaches the unit.
/obj/machinery/power/terminal/smes_input

/// The SMES's hum: the generator's loop, quieter at range and with a harsher falloff.
/datum/looping_sound/generator/smes
	extra_range = -6
	falloff = 0.2

/obj/machinery/power/smes/drain_power(drain_check, surge, amount = 0)

	if(drain_check)
		return 1

	var/smes_amt = min((amount * SMESRATE), stored_charge())
	adjust_stored_charge(-smes_amt)
	return smes_amt / SMESRATE

// ALLOW(init/INSTANCE_STATE): the input terminals laid beside the unit are linked before anything reads `terminals`, and a unit placed with none is unwired; its output node binds when it is wired
/obj/machinery/power/smes/Initialize(mapload)
	. = ..()
	add_nearby_terminals()
	if(needs_terminals() && !LAZYLEN(terminals))
		set_unwired(TRUE)
		return
	if(!power_region)
		connect_to_network(!mapload)

/// The hum the unit owns: it plays from the unit.
/obj/machinery/power/smes/proc/make_soundloop(datum/act/A)
	return new /datum/looping_sound/generator/smes(list(src), FALSE)

/// A unit with no input terminal is unwired (a cell rack keeps its charge in cells and needs none).
/obj/machinery/power/smes/proc/needs_terminals()
	return TRUE

/// STAT_OPERABLE's reading of the machine core's bits, for a SMES: only BROKEN. The unit feeds its network, so the area going dark must not stop it.
/obj/machinery/power/smes/stat_bits_allow(datum/act/A)
	return !has_stat(BROKEN)

/// A mapped SMES's late pass: the coils laid on its tile and its preset settings.
/obj/machinery/power/smes/proc/mapped_after_init(datum/act/timer/A)
	if(A.mapload && !unwired) // one without terminals takes no late pass
		map_late()

/obj/machinery/power/smes/proc/map_late()
	apply_mapped_upgrades()
	apply_mapped_settings()

/// Allows subtypes to configure the smes for different input/output rates, and level of starting charge.
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

/// A terminal went (it was destroyed, or cut out): its link to the unit goes with it.
/obj/machinery/power/smes/disconnect_terminal(obj/machinery/power/terminal/term)
	rel_remove(src, nameof(terminals), term)

/// The grid checker upstream failed: the unit suspends its input and output until it is told the grid is back.
/obj/machinery/power/smes/do_grid_check()
	set_grid_check(TRUE)

/// Each input terminal's Rust entity learns which unit it feeds.
/obj/machinery/power/smes/proc/link_terminals()
	if(QDELETED(src) || !vg_entity)
		return
	var/unit_index = (vg_entity - 1) & VG_ENTITY_INDEX_MASK
	for(var/obj/machinery/power/terminal/smes_input/term as anything in terminals)
		if(term.vg_entity)
			native_write(term, NATIVE_SMESINPUTTERMINAL_UNIT, unit_index)

/// The node went (again) to Rust: the terminals learn their unit, the settings follow at the frame's refresh, and the starting charge is seeded once.
/obj/machinery/power/smes/power_registered()
	link_terminals()
	native_resync(src)
	// Rust's charge starts at zero: seed it once from the DM starting value.
	if(vg_entity && !charge_seeded)
		charge_seeded = TRUE
		adjust_charge(initial_charge - get_charge())
		set_last_disp(chargedisplay())

/// The unit's stored charge in SMES units: read from Rust, never cached in DM.
/obj/machinery/power/smes/proc/stored_charge()
	return vg_entity ? get_charge() : initial_charge // ALLOW(reads): the charge is Rust's own, read where it is asked (a requirement re-checks it, a gate is polled), never cached

/// Adds `delta` (negative removes) to the stored charge. Before the unit registers it moves the seed.
/obj/machinery/power/smes/proc/adjust_stored_charge(delta)
	if(vg_entity)
		adjust_charge(delta)
	else
		initial_charge = max(initial_charge + delta, 0)

/// Sets the stored charge (mapped presets, admin, tests).
/obj/machinery/power/smes/proc/set_stored_charge(value)
	adjust_stored_charge(value - stored_charge())

/// The input Rust is told to take: the unit works, the switch is on and the input wire is whole.
/obj/machinery/power/smes/proc/input_enabled()
	return working && input_attempt && !input_cut

/// The output Rust is told to give.
/obj/machinery/power/smes/proc/output_enabled()
	return working && output_attempt && !output_cut

/// Sends settings and capacity to Rust (generated accessors, verdigris/domains/power/src/components.rs). The framework runs it once per frame after
/// any state it reads changed, so no setter calls it by hand. Charge is Rust's own (`Smes.charge` is conserved, laws drive it) -- DM's absolute
/// writes to it (drain_power(), the EMP hit) cross as `adjust_charge` deltas, and power_poll() reads the settled value back.
/obj/machinery/power/smes/push_to_rust()
	if(QDELETED(src) || !vg_entity)
		return
	// The gates are written out here (not through input_enabled()/output_enabled()) so the generated reads see every var they read.
	native_write(src, NATIVE_SMES_INPUT_ENABLED, (working && input_attempt && !input_cut) ? 1 : 0)
	native_write(src, NATIVE_SMES_OUTPUT_ENABLED, (working && output_attempt && !output_cut) ? 1 : 0)
	native_write(src, NATIVE_SMES_CAPACITY, capacity)
	native_write(src, NATIVE_SMES_INPUT_LEVEL, input_level)
	native_write(src, NATIVE_SMES_OUTPUT_LEVEL, output_level)

/// Reads back what Rust's SmesOutputApply and SmesInputApply did this step (verdigris/domains/power/src/laws.rs): what the output delivered, what
/// the input took and what its terminals' regions had to spare, and the settled charge; shows them as the lamps, the window's readings and the gauge.
/obj/machinery/power/smes/proc/power_poll()
	if(!vg_entity)
		return
	var/new_output_used = round(get_output_used(), 1)
	var/new_input_used = round(get_input_used(), 1)
	var/new_input_available = round(get_input_available(), 1)
	var/new_inputting = input_enabled() ? (new_input_used > 0 ? 2 : 1) : 0
	var/new_outputting = output_enabled() ? (new_output_used > 0 ? 2 : 1) : 0
	var/display = chargedisplay()
	if(new_inputting != inputting || new_outputting != outputting || last_disp != display || new_output_used != output_used || new_input_available != input_available)
		power_event_count++
		set_inputting(new_inputting)
		set_outputting(new_outputting)
		set_last_disp(display)
		set_output_used(new_output_used)
		set_input_available(new_input_available)

/// The output lamp changed: the unit hums while it feeds a load.
/obj/machinery/power/smes/proc/output_shown(datum/act/A)
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

// ---- what it shows ----

/// TRUE when the status overlays are hidden: broken, or unwired.
/obj/machinery/power/smes/proc/status_dark()
	return has_stat(BROKEN) || unwired

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

// ---- the terminals: building one and cutting one out ----

/// Where a terminal built from this actor's spot goes: list(the turf, its direction). The actor stands next to the unit; the terminal goes on the far
/// side of the unit's line to the actor (the tile the actor stands on, for an orthogonal spot).
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

/// The ten lengths went in after the wait (the site was asked again before this ran): the terminal is made and joins the network, and an unwired
/// unit is wired now. A broken unit stays broken.
/obj/machinery/power/smes/proc/terminal_built(datum/act/op/A)
	var/list/site = terminal_site_of(A.actor)
	var/obj/machinery/power/terminal/smes_input/term = new(site[1])
	term.set_dir(site[2])
	rel_add(src, nameof(terminals), term)
	term.connect_to_network()
	link_terminals()
	set_unwired(FALSE)
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

/// The wait is over (the terminal was asked for again before this ran): the cable is cut (with a chance of a shock from the live cable that can
/// stun the cutter before the job is done), the ten lengths drop and the terminal goes.
/obj/machinery/power/smes/proc/terminal_taken_down(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/machinery/power/terminal/term = terminal_under(user)
	if(prob(50) && electrocute_mob(user, term.power_region, term))
		fx_sparks(src, 5)
		if(user.has_status(STAT_STUNNED))
			return OP_OK
	new /obj/item/stack/cable_coil(loc, 10)
	rel_remove(src, nameof(terminals), term)
	spent(term)
	return OP_OK

// ---- the casing ----

/// The casing has damage to weld.
/obj/machinery/power/smes/proc/casing_damaged(datum/act/A)
	return get_integrity() < max_integrity // ALLOW(reads): a unit's max_integrity is its type's constant

/// The weld is done: every point of damage is repaired.
/obj/machinery/power/smes/proc/casing_repaired(datum/act/op/A)
	repair_damage(max_integrity)
	return OP_OK

/// The welder takes as long as there is damage: a decisecond for every point.
/obj/machinery/power/smes/proc/repair_time(datum/act/A)
	return max_integrity - get_integrity()

/obj/machinery/power/smes/draw_power(amount)
	var/drained = 0
	for(var/obj/machinery/power/terminal/term in terminals)
		if(!term.power_region)
			continue
		if((amount - drained) <= 0)
			return 0
		drained += power_draw(term.power_region, amount - drained, term)
	return drained

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
		"inputAvailable" = input_available,
		"outputAttempt" = output_attempt,
		"outputting" = outputting,
		"outputLevel" = output_level,
		"outputLevel_text" = DisplayPower(output_level),
		"outputLevelMax" = output_level_max,
		"outputUsed" = output_used)

/obj/machinery/power/smes/proc/Percentage()
	if(!capacity)
		return 0
	return round(100.0*stored_charge()/capacity, 0.1)

/// The input switch went over: switched off, the lamp goes out at once.
/obj/machinery/power/smes/proc/input_switched(datum/act/op/A)
	if(!input_attempt)
		set_inputting(0)
	return OP_OK

/// The output switch went over: the contactor clicks, and switched off the lamp goes out at once.
/obj/machinery/power/smes/proc/output_switched(datum/act/op/A)
	if(output_attempt)
		play_sfx(loc, SFX_EFFECTS_CONTACTOR_ON)
	else
		set_outputting(0)
		play_sfx(loc, SFX_EFFECTS_CONTACTOR_OFF)
	return OP_OK

/obj/machinery/power/smes/proc/ui_set_input(datum/act/op/A, adjust, target)
	set_io_level(SMES_TGUI_INPUT, target, adjust)
	return OP_OK

/obj/machinery/power/smes/proc/ui_set_output(datum/act/op/A, adjust, target)
	set_io_level(SMES_TGUI_OUTPUT, target, adjust)
	return OP_OK

/// A level from the window or an RCON console: "min", "max", a step (`adjust`) or a number, clamped to the unit's cap.
/obj/machinery/power/smes/proc/set_io_level(io, target, adjust)
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

/// The input switch on or off (a pulse, an event, a pulse's scramble); switched off, the lamp goes out at once.
/obj/machinery/power/smes/proc/set_input_on(on)
	set_input_attempt(on)
	if(!input_attempt)
		set_inputting(0)

/// The output switch on or off.
/obj/machinery/power/smes/proc/set_output_on(on)
	set_output_attempt(on)
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
	set_input_on(rand(0,1))
	set_output_on(rand(0,1))
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

/// Switches the input on/off depending on the previous setting (a wire's pulse, an RCON console).
/obj/machinery/power/smes/proc/toggle_input()
	set_input_on(!input_attempt)

/// Switches the output on/off depending on the previous setting.
/obj/machinery/power/smes/proc/toggle_output()
	set_output_on(!output_attempt)

/// The input level, in watts, clamped to the unit's cap.
/obj/machinery/power/smes/proc/set_input(new_input = 0)
	set_input_level(clamp(new_input, 0, input_level_max))

/// The output level, in watts, clamped to the unit's cap.
/obj/machinery/power/smes/proc/set_output(new_output = 0)
	set_output_level(clamp(new_output, 0, output_level_max))

/obj/machinery/power/smes/buildable/hybrid
	name = "hybrid power storage unit"
	desc = "A high-capacity superconducting magnetic energy storage (SMES) unit, modified with alien technology to generate small amounts of power from seemingly nowhere."
	icon = 'icons/obj/power_vr.dmi'
	var/recharge_rate = 10000
	var/overlay_icon = 'icons/obj/power_vr.dmi'

// A hybrid unit's casing is full of alien technology: the wirecutters are not for its terminals, and it makes its own charge every frame while
// there is room for it.
CAPABILITIES(/obj/machinery/power/smes/buildable/hybrid)
	without("cut_terminal")
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(hybrid_charge)), when = PROC_REF(hybrid_has_room))

/// There is room for more charge.
/obj/machinery/power/smes/buildable/hybrid/proc/hybrid_has_room(datum/act/A)
	return stored_charge() < capacity

/// Hybrid units make their own charge every frame, never more than there is room for.
/obj/machinery/power/smes/buildable/hybrid/proc/hybrid_charge(datum/act/timer/A)
	adjust_stored_charge(min(recharge_rate, capacity - stored_charge()))
