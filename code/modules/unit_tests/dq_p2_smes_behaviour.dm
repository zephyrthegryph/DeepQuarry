// Behaviour-preservation tests for the SMES and its power terminals (phase 2): they pin what a player, an AI, a borg or an admin can
// observe of a power storage unit through public inputs (clicks, window buttons, wires, damage entry points, time), so the same file
// passes before and after the SMES moves from the legacy declaration forms to the engine forms. Same rules as dq_p2_apc_behaviour.dm:
//   - Input goes through test_click(), the window adapter p2_smes_ui(), the wires, the damage entry points and time; never an op key.
//   - State is read through the adapter block below (the only place that names today's accessors) and plain vars.
//   - Every input is followed by p2_settle(): converted tool ops carry waits where today's code is instant.
//   - Nothing depends on message text (except the examine hatch word), on an op key or on a click result being non-null.
//
// The block is five by five. Fixed spots: the SMES at p2_smes_spot(), its input terminal on the tile west of it (the terminal's tile is the
// one a builder stands on), a supply terminal north of that, a load terminal east of the SMES.
//
// Not pinned (and why): the explosion size of a destroyed charged SMES (the explosion would wreck the shared block and its size is not
// readable without a side effect); a terminal on a space turf (the block has no space tile to try); the RCON tag prompt of the multitool
// (a typed prompt needs the prompt driver); AI use of the window (no AI mob in the fixture; a cyborg stands for the silicon route);
// the shock and stun chance of cutting a live terminal's cable (the tests wear insulated gloves, so only the deterministic part is
// pinned); the 'inputting' display value (today's power_poll() shows 0 whatever flows, so only the transferred charge is asserted).

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: today's accessors, wrapped. After the conversion only these bodies change.
// ---------------------------------------------------------------------------------------------------------------------

/// The service hatch is open.
/proc/p2_smes_panel_open(obj/machinery/power/smes/S)
	return !!S.panel_open

/// The unit is broken (its overlays dark, its input and output off).
/proc/p2_smes_broken(obj/machinery/power/smes/S)
	return !!(S.broken_now() || S.unwired)

/// The charge held, in SMES units.
/proc/p2_smes_charge(obj/machinery/power/smes/S)
	return S.stored_charge()

/// Sets the charge held.
/proc/p2_smes_set_charge(obj/machinery/power/smes/S, value)
	S.set_stored_charge(value)

/// The input terminals the unit answers for.
/proc/p2_smes_terminals(obj/machinery/power/smes/S)
	return S.terminals ? S.terminals.Copy() : list()

/// The master a terminal answers to.
/proc/p2_terminal_master(obj/machinery/power/terminal/T)
	return T.master()

/// The terminals the unit adopted answer to it. Today the SMES's own attempt to link them is refused by the lifecycle layer (the terminal's
/// `master` relation is declared for an APC only), so the fixture writes the plain var the cutting code reads; once the link holds this is a no-op.
/proc/p2_smes_link_masters(obj/machinery/power/smes/S)
	for(var/obj/machinery/power/terminal/term as anything in p2_smes_terminals(S))
		if(!p2_terminal_master(term))
			term.master = S

/// The wire controller of the unit.
/proc/p2_smes_wires(obj/machinery/power/smes/S)
	var/obj/machinery/power/smes/buildable/B = S
	return (istype(B) && wiring_of(B)) ? new /datum/wires_test_adapter(B) : null

/// The window's data as a viewer is sent it.
/proc/p2_smes_data(obj/machinery/power/smes/S, mob/user)
	var/list/data = list()
	present_tgui_data(S, user, data)
	return data

/// Presses a window button as the actor: the engine's op if the SMES has one for the action, else today's tgui_act().
/proc/p2_smes_ui(mob/actor, obj/machinery/power/smes/S, action, list/args)
	var/datum/op_result/result = test_ui(actor, S, action, args)
	if(result)
		return result
	var/datum/tgui/ui = new(actor, S, "Smes")
	ui.status = STATUS_INTERACTIVE
	. = S.tgui_act(action, args || list(), ui)
	qdel(ui)

/// The actor works the SMES with a welding tool.
/proc/p2_smes_weld(mob/user, obj/machinery/power/smes/S, obj/item/weldingtool/welder)
	test_click(user, S, welder)

/// The actor works the SMES with wirecutters.
/proc/p2_smes_cut(mob/user, obj/machinery/power/smes/S, obj/item/tool/wirecutters/cutters)
	test_click(user, S, cutters)

/// The SMES's window was opened for `user` (a test mob has no client, so the type records the open).
/proc/p2_smes_interface_opened(obj/machinery/power/smes/S, mob/user)
	var/obj/machinery/power/smes/p2_test/P = S
	if(istype(P))
		return user in P.p2_opened
	var/obj/machinery/power/smes/buildable/p2_test/B = S
	return istype(B) && (user in B.p2_opened)

/// The sound loop of the unit is running.
/proc/p2_smes_noisy(obj/machinery/power/smes/S)
	return !!S.noisy

/// The unit is told its output is at `level` as the pipeline would show it (the one input the sound loop reads).
/proc/p2_smes_show_output(obj/machinery/power/smes/S, level)
	S.set_outputting(level)
	S.update_soundloop()

/// The output overlay key and the input overlay key and the charge gauge, as the unit draws them: "" and "" and "0" when nothing of that is drawn.
/proc/p2_smes_overlay_keys(obj/machinery/power/smes/S)
	var/datum/look/look = new
	S.draw(look)
	var/output = ""
	var/input = ""
	var/charge = "0"
	for(var/overlay in look.overlays)
		if(copytext(overlay, 1, 8) == "smes-op")
			output = copytext(overlay, 8)
		else if(copytext(overlay, 1, 8) == "smes-oc")
			input = copytext(overlay, 8)
		else if(copytext(overlay, 1, 8) == "smes-og")
			charge = copytext(overlay, 8)
	return list(output, input, charge)

/// A power company's grid check suspends all input and output.
/proc/p2_smes_set_grid_check(obj/machinery/power/smes/S, on)
	S.set_grid_check(on)

/// The mapper's late pass: coils laid on the tile, the preset's settings.
/proc/p2_smes_map_late(obj/machinery/power/smes/S)
	S.map_late()

/// The unit's explosion/damage entry: a hit of `amount` integrity.
/proc/p2_smes_hit(obj/machinery/power/smes/S, amount)
	S.take_damage(amount)

/// The unit's integrity left.
/proc/p2_smes_integrity(obj/machinery/power/smes/S)
	return S.get_integrity()

/// One power step as the game runs it.
/proc/p2_smes_power_step()
	refresh_flush()
	dq_power_test_step()

/// The power the network of `T` has available.
/proc/p2_net_avail(obj/machinery/power/T)
	return power_avail(T.power_region)

/// The test SMES: a real one, except that a test mob has no client and the type records who opened its window.
/obj/machinery/power/smes/p2_test
	var/list/p2_opened

/obj/machinery/power/smes/p2_test/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	LAZYADD(p2_opened, user)
	return ..()

/obj/machinery/power/smes/buildable/p2_test
	var/list/p2_opened

/obj/machinery/power/smes/buildable/p2_test/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	LAZYADD(p2_opened, user)
	return ..()

/// A master that records what a terminal tells it (the terminal's `master` link takes an APC today, so the probe is one).
/obj/machinery/power/apc/p2_overload_probe
	var/overloads = 0
	var/disconnects = 0

/obj/machinery/power/apc/p2_overload_probe/overload(obj/machinery/power/source)
	overloads++

/obj/machinery/power/apc/p2_overload_probe/disconnect_terminal(obj/machinery/power/terminal/term)
	disconnects++
	return ..()

// ---------------------------------------------------------------------------------------------------------------------
// The base: the kernel on its injected clock around the test, the floor as it was after.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_smes
	abstract_type = /datum/unit_test/dq_p2_smes
	var/list/p2_smeses
	var/list/p2_cables
	var/list/p2_terms
	var/list/p2_floors // turf -> its flooring before the test bared it
	var/obj/machinery/power/terminal/p2_supply
	var/obj/machinery/power/terminal/p2_load

/datum/unit_test/dq_p2_smes/Run()
	test_driver_begin()
	test_rng(1)
	// A terminal's `master` relation is declared for an APC only today, so every SMES that adopts a terminal reports a lifecycle refusal
	// (once per type per round). Reports are captured here, and any other kind of report fails the test.
	GLOB.dq_lifecycle_report_capture = list()
	run_gate()
	var/list/reports = GLOB.dq_lifecycle_report_capture
	GLOB.dq_lifecycle_report_capture = null
	for(var/report in reports)
		if(!findtext("[report]", ".master is declared"))
			Fail("an unexpected lifecycle report: [report]")
	for(var/obj/machinery/power/terminal/T as anything in p2_terms)
		if(!QDELETED(T))
			T.set_power_supply(0)
			qdel(T)
	for(var/obj/machinery/power/smes/S as anything in p2_smeses)
		if(!QDELETED(S))
			qdel(S)
	for(var/obj/structure/cable/C as anything in p2_cables)
		if(!QDELETED(C))
			qdel(C)
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		own_turf_contents(T)
	for(var/turf/simulated/floor/F as anything in p2_floors)
		F.install_flooring(p2_floors[F])
	test_driver_end()

/datum/unit_test/dq_p2_smes/proc/run_gate()
	return

// ---- places ----

/// Where the SMES stands.
/datum/unit_test/dq_p2_smes/proc/p2_smes_spot()
	return get_step(run_loc_floor_bottom_left, EAST)

/// The tile of the input terminal (west of the SMES: the tile a builder stands on).
/datum/unit_test/dq_p2_smes/proc/p2_term_spot()
	return run_loc_floor_bottom_left

/// The tile of the supply that feeds the input terminal.
/datum/unit_test/dq_p2_smes/proc/p2_supply_spot()
	return get_step(run_loc_floor_bottom_left, NORTH)

/// The tile of the load on the SMES's output side.
/datum/unit_test/dq_p2_smes/proc/p2_load_spot()
	return get_step(p2_smes_spot(), EAST)

/// A tile beside the SMES where a bystander stands that is not the terminal's tile.
/datum/unit_test/dq_p2_smes/proc/p2_side_spot()
	return get_step(p2_smes_spot(), NORTH)

// ---- people ----

/// A conscious person with hands, who cannot be knocked out by the test's passing time.
/datum/unit_test/dq_p2_smes/proc/p2_actor(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || p2_side_spot())
	H.enable_godmode()
	return H

/// Insulated gloves on the actor: a shock from live cable does nothing to them.
/datum/unit_test/dq_p2_smes/proc/p2_insulate(mob/living/carbon/human/H)
	H.equip_to_slot_or_del(allocate(/obj/item/clothing/gloves/yellow, p2_side_spot()), SLOT_ID_GLOVES)

// ---- building the fixture ----

/// A cable end on `T` leading `d2`.
/datum/unit_test/dq_p2_smes/proc/p2_cable(turf/T, d2)
	var/obj/structure/cable/C = dq_power_test_cable(T, 0, d2)
	LAZYADD(p2_cables, C)
	return C

/// An input terminal on `T` facing the SMES (which is east of the default tile), made before the SMES so a mapped unit finds it.
/datum/unit_test/dq_p2_smes/proc/p2_input_terminal(turf/T, direction = EAST)
	var/obj/machinery/power/terminal/smes_input/term = allocate(/obj/machinery/power/terminal/smes_input, T || p2_term_spot())
	term.set_dir(direction)
	LAZYADD(p2_terms, term)
	return term

/// A generic terminal (a supply or a load stand-in) on `T`.
/datum/unit_test/dq_p2_smes/proc/p2_plain_terminal(turf/T)
	var/obj/machinery/power/terminal/term = allocate(/obj/machinery/power/terminal, T)
	LAZYADD(p2_terms, term)
	return term

/// A SMES as a map places it: its input terminal on the tile west of it, a unit that works.
/datum/unit_test/dq_p2_smes/proc/p2_smes(type = /obj/machinery/power/smes/p2_test, with_terminal = TRUE)
	if(with_terminal)
		p2_input_terminal()
	var/obj/machinery/power/smes/S = allocate(type, p2_smes_spot())
	LAZYADD(p2_smeses, S)
	p2_smes_link_masters(S)
	return S

/// A unit with no terminal at all (it breaks at init).
/datum/unit_test/dq_p2_smes/proc/p2_bare_smes(type = /obj/machinery/power/smes/p2_test)
	return p2_smes(type, FALSE)

/// The whole network fixture: cables, the SMES with its input terminal, a supply behind the terminal, a load beside the SMES.
/// Returns the SMES; the supply and load terminals are in `p2_supply` and `p2_load`.
/datum/unit_test/dq_p2_smes/proc/p2_network(type = /obj/machinery/power/smes/p2_test, supply_watts = 500000)
	p2_cable(p2_term_spot(), NORTH)
	p2_cable(p2_supply_spot(), SOUTH)
	p2_cable(p2_smes_spot(), EAST)
	p2_cable(p2_load_spot(), WEST)
	var/obj/machinery/power/smes/S = p2_smes(type)
	p2_supply = p2_plain_terminal(p2_supply_spot())
	p2_load = p2_plain_terminal(p2_load_spot())
	for(var/obj/machinery/power/terminal/term as anything in list(p2_supply, p2_load) + p2_smes_terminals(S))
		term.connect_to_network()
	S.connect_to_network()
	p2_supply.set_power_supply(supply_watts)
	p2_settle()
	return S

/// `n` power steps, as the game runs them.
/datum/unit_test/dq_p2_smes/proc/p2_steps(n)
	for(var/i in 1 to n)
		p2_smes_power_step()
	p2_settle()
	for(var/i in 1 to n)
		p2_smes_power_step()

// ---- doing things ----

/// Time for any wait a tool or a window press may start.
/datum/unit_test/dq_p2_smes/proc/p2_settle()
	test_time(10 SECONDS)
	if(GLOB.op_pure_depth)
		Fail("pure depth [GLOB.op_pure_depth] after settle")
		GLOB.op_pure_depth = 0

/// The actor puts `held` in the active hand (an empty hand when null), clicks the target and waits.
/datum/unit_test/dq_p2_smes/proc/touch(mob/living/carbon/human/H, atom/target, obj/item/held)
	H.drop_item()
	if(held)
		H.put_in_active_hand(held)
	test_click(H, target, held)
	p2_settle()

/// The actor presses a window button and waits.
/datum/unit_test/dq_p2_smes/proc/press(mob/actor, obj/machinery/power/smes/S, action, list/args)
	p2_smes_ui(actor, S, action, args)
	p2_settle()

/// The actor welds the SMES and waits.
/datum/unit_test/dq_p2_smes/proc/weld(mob/living/carbon/human/H, obj/machinery/power/smes/S, obj/item/weldingtool/welder)
	H.drop_item()
	H.put_in_active_hand(welder)
	p2_smes_weld(H, S, welder)
	test_time(1 MINUTES)

/// The actor cuts at the SMES with wirecutters and waits.
/datum/unit_test/dq_p2_smes/proc/cut(mob/living/carbon/human/H, obj/machinery/power/smes/S, obj/item/tool/wirecutters/cutters)
	H.drop_item()
	H.put_in_active_hand(cutters)
	p2_smes_cut(H, S, cutters)
	p2_settle()

/// A tool with no speed penalty.
/datum/unit_test/dq_p2_smes/proc/tool(path)
	return dq_fast_tool(path, p2_side_spot())

/// The service hatch open (the screwdriver).
/datum/unit_test/dq_p2_smes/proc/open_panel(mob/living/carbon/human/H, obj/machinery/power/smes/S)
	touch(H, S, tool(/obj/item/tool/screwdriver))

/// The floor of `T` bared to the plating (its flooring is put back when the test ends).
/datum/unit_test/dq_p2_smes/proc/bare_floor(turf/T)
	var/turf/simulated/floor/F = T
	if(!(F in p2_floors))
		LAZYSET(p2_floors, F, F.flooring)
	F.make_plating()

/// The total cable on the floor of `T`, in lengths.
/datum/unit_test/dq_p2_smes/proc/loose_cable(turf/T)
	var/total = 0
	for(var/obj/item/stack/cable_coil/C in T)
		total += C.amount
	return total

/// True when two charges are the same to within a small rounding.
/datum/unit_test/dq_p2_smes/proc/same_charge(a, b, tolerance = 5)
	return abs(a - b) <= tolerance

// ---------------------------------------------------------------------------------------------------------------------
// A mapped SMES
// ---------------------------------------------------------------------------------------------------------------------

/// A mapped plain SMES: anchored, solid, with its terminal found, output on and input off, a million charged.
/datum/unit_test/dq_p2_smes/mapped_smes_start_state

/datum/unit_test/dq_p2_smes/mapped_smes_start_state/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	p2_settle()
	TEST_ASSERT(S.anchored, "anchored")
	TEST_ASSERT(S.density, "solid")
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 1, "it found the terminal beside it")
	var/obj/machinery/power/terminal/term = p2_smes_terminals(S)[1]
	TEST_ASSERT_EQUAL(term.loc, p2_term_spot(), "on the tile beside it")
	if(p2_terminal_master(term))
		TEST_ASSERT_EQUAL(p2_terminal_master(term), S, "which answers to the unit")
	TEST_ASSERT(!S.input_attempt, "input starts off")
	TEST_ASSERT(S.output_attempt, "output starts on")
	TEST_ASSERT_EQUAL(S.capacity, 5e6, "capacity")
	TEST_ASSERT_EQUAL(S.input_level, 50000, "input level")
	TEST_ASSERT_EQUAL(S.output_level, 50000, "output level")
	TEST_ASSERT_EQUAL(S.input_level_max, 200000, "input cap")
	TEST_ASSERT_EQUAL(S.output_level_max, 200000, "output cap")
	TEST_ASSERT(same_charge(p2_smes_charge(S), 1e6), "a million charged to start")
	TEST_ASSERT(!p2_smes_broken(S), "working")
	TEST_ASSERT(!p2_smes_panel_open(S), "hatch shut")
	TEST_ASSERT(!p2_smes_noisy(S), "silent")

/// A unit with no terminal breaks at init; one with a terminal does not.
/datum/unit_test/dq_p2_smes/smes_without_a_terminal_breaks_at_init

/datum/unit_test/dq_p2_smes/smes_without_a_terminal_breaks_at_init/run_gate()
	var/obj/machinery/power/smes/with = p2_smes()
	TEST_ASSERT(!p2_smes_broken(with), "a unit with a terminal works")
	var/obj/machinery/power/smes/bare = allocate(/obj/machinery/power/smes/p2_test, get_step(p2_smes_spot(), NORTH))
	LAZYADD(p2_smeses, bare)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(bare)), 0, "no terminal found")
	TEST_ASSERT(p2_smes_broken(bare), "so it broke at init")

/// Losing the terminal of a working unit does not break it (the check runs at init only).
/datum/unit_test/dq_p2_smes/losing_the_terminal_later_does_not_break_it

/datum/unit_test/dq_p2_smes/losing_the_terminal_later_does_not_break_it/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/obj/machinery/power/terminal/term = p2_smes_terminals(S)[1]
	qdel(term)
	p2_settle()
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 0, "the terminal left the list")
	TEST_ASSERT(!p2_smes_broken(S), "the unit still works")

/// A buildable unit starts empty with the safety on and the remote wire intact; its hatch has wires.
/datum/unit_test/dq_p2_smes/buildable_start_state

/datum/unit_test/dq_p2_smes/buildable_start_state/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/p2_test)
	p2_settle()
	TEST_ASSERT(S.anchored && S.density, "anchored and solid")
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 1, "it found the terminal")
	TEST_ASSERT(same_charge(p2_smes_charge(S), 0), "a built unit starts empty")
	TEST_ASSERT(S.RCon, "remote control on")
	TEST_ASSERT(S.safeties_enabled, "the safety circuit on")
	TEST_ASSERT(S.grounding, "grounded")
	TEST_ASSERT(!S.failing, "not failing")
	TEST_ASSERT(!S.input_attempt && S.output_attempt, "input off, output on")
	TEST_ASSERT_NOTNULL(p2_smes_wires(S), "it has wires")
	TEST_ASSERT(!p2_smes_broken(S), "working")

/// Coils laid on the tile become the unit's coils at the mapper's late pass: capacity and the I/O caps are their sums.
/datum/unit_test/dq_p2_smes/mapped_coils_set_capacity_and_io

/datum/unit_test/dq_p2_smes/mapped_coils_set_capacity_and_io/run_gate()
	allocate(/obj/item/smes_coil/weak, p2_smes_spot())
	allocate(/obj/item/smes_coil/weak, p2_smes_spot())
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/p2_test)
	TEST_ASSERT_EQUAL(S.capacity, 5e6, "before the late pass the default capacity")
	p2_smes_map_late(S)
	p2_settle()
	TEST_ASSERT_EQUAL(S.capacity, 2.4e6, "two basic coils")
	TEST_ASSERT_EQUAL(S.input_level_max, 300000, "input cap is the coils' I/O")
	TEST_ASSERT_EQUAL(S.output_level_max, 300000, "output cap too")

/// The mapped presets: the starting charge and the settings each names.
/datum/unit_test/dq_p2_smes/mapped_presets

/datum/unit_test/dq_p2_smes/mapped_presets/run_gate()
	var/obj/machinery/power/smes/buildable/full = p2_smes(/obj/machinery/power/smes/buildable/max_charge)
	p2_smes_map_late(full)
	p2_settle()
	TEST_ASSERT(same_charge(p2_smes_charge(full), full.capacity), "max_charge starts full")
	TEST_ASSERT(!full.input_attempt && full.output_attempt, "and keeps the default switches")
	for(var/obj/machinery/power/smes/S as anything in p2_smeses)
		qdel(S)
	for(var/obj/machinery/power/terminal/term as anything in p2_terms)
		qdel(term)
	p2_smeses = null
	p2_terms = null
	var/obj/machinery/power/smes/buildable/engine = p2_smes(/obj/machinery/power/smes/buildable/engine_default)
	p2_smes_map_late(engine)
	p2_settle()
	TEST_ASSERT(same_charge(p2_smes_charge(engine), engine.capacity * 0.5), "the engine unit starts half charged")
	TEST_ASSERT(engine.input_attempt && engine.output_attempt, "input and output on")
	TEST_ASSERT_EQUAL(engine.input_level, engine.input_level_max, "input at the cap")
	TEST_ASSERT_EQUAL(engine.output_level, engine.output_level_max, "output at the cap")

/// The mapped presets that only touch one side leave the other alone.
/datum/unit_test/dq_p2_smes/mapped_presets_one_sided

/datum/unit_test/dq_p2_smes/mapped_presets_one_sided/run_gate()
	var/obj/machinery/power/smes/buildable/off = p2_smes(/obj/machinery/power/smes/buildable/disable_output)
	p2_smes_map_late(off)
	TEST_ASSERT(!off.output_attempt, "disable_output: output off")
	TEST_ASSERT_EQUAL(off.output_level, 0, "and at zero")
	TEST_ASSERT(!off.input_attempt, "input untouched")
	for(var/obj/machinery/power/smes/S as anything in p2_smeses)
		qdel(S)
	for(var/obj/machinery/power/terminal/term as anything in p2_terms)
		qdel(term)
	p2_smeses = null
	p2_terms = null
	var/obj/machinery/power/smes/buildable/in_only = p2_smes(/obj/machinery/power/smes/buildable/max_input)
	p2_smes_map_late(in_only)
	TEST_ASSERT(in_only.input_attempt, "max_input: input on")
	TEST_ASSERT_EQUAL(in_only.input_level, in_only.input_level_max, "at the cap")
	TEST_ASSERT_EQUAL(in_only.output_level, 50000, "output level untouched")

/// The point-of-interest unit starts full with the remote wire off, input on and both levels at the cap.
/datum/unit_test/dq_p2_smes/point_of_interest_unit_starts_full_and_open

/datum/unit_test/dq_p2_smes/point_of_interest_unit_starts_full_and_open/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/point_of_interest)
	p2_settle()
	TEST_ASSERT(same_charge(p2_smes_charge(S), S.capacity), "full")
	TEST_ASSERT(!S.RCon, "remote control off")
	TEST_ASSERT(S.input_attempt, "input on")
	TEST_ASSERT_EQUAL(S.input_level, S.input_level_max, "input at the cap")
	TEST_ASSERT_EQUAL(S.output_level, S.output_level_max, "output at the cap")

/// A hybrid unit makes its own charge as time passes and stops at its capacity.
/datum/unit_test/dq_p2_smes/hybrid_makes_charge_up_to_capacity

/datum/unit_test/dq_p2_smes/hybrid_makes_charge_up_to_capacity/run_gate()
	var/obj/machinery/power/smes/buildable/hybrid/S = p2_smes(/obj/machinery/power/smes/buildable/hybrid)
	var/mob/living/carbon/human/H = p2_actor()
	p2_smes_set_charge(S, 0)
	press(H, S, "tryinput", list()) // any change of settings wakes the unit's pipeline stage
	var/before = p2_smes_charge(S)
	test_time(20 SECONDS)
	var/after = p2_smes_charge(S)
	TEST_ASSERT(after > before, "a hybrid unit grows its charge on its own ([before] to [after])")
	p2_smes_set_charge(S, S.capacity - 100)
	test_time(20 SECONDS)
	TEST_ASSERT(same_charge(p2_smes_charge(S), S.capacity), "and stops at its capacity")

/// An ordinary unit idles: no charge appears by itself.
/datum/unit_test/dq_p2_smes/plain_unit_makes_no_charge_by_itself

/datum/unit_test/dq_p2_smes/plain_unit_makes_no_charge_by_itself/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	p2_settle()
	var/before = p2_smes_charge(S)
	test_time(30 SECONDS)
	TEST_ASSERT(same_charge(p2_smes_charge(S), before), "an ordinary unit with no supply keeps its charge")

// ---------------------------------------------------------------------------------------------------------------------
// The window
// ---------------------------------------------------------------------------------------------------------------------

/// The data the window shows, key by key.
/datum/unit_test/dq_p2_smes/window_data_shows_the_state

/datum/unit_test/dq_p2_smes/window_data_shows_the_state/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	p2_settle()
	var/list/data = p2_smes_data(S, H)
	for(var/key in list("capacity", "capacityPercent", "charge", "inputAttempt", "inputting", "inputLevel", "inputLevelMax", "outputAttempt", "outputting", "outputLevel", "outputLevelMax", "inputAvailable", "outputUsed"))
		TEST_ASSERT(key in data, "the window is sent [key]")
	TEST_ASSERT_EQUAL(data["capacity"], 5e6, "capacity")
	TEST_ASSERT_EQUAL(data["capacityPercent"], 20, "a fifth full")
	TEST_ASSERT(same_charge(data["charge"], 1e6), "charge")
	TEST_ASSERT_EQUAL(data["inputAttempt"], 0, "input off")
	TEST_ASSERT_EQUAL(data["outputAttempt"], 1, "output on")
	TEST_ASSERT_EQUAL(data["inputLevel"], 50000, "input level")
	TEST_ASSERT_EQUAL(data["inputLevelMax"], 200000, "input cap")
	TEST_ASSERT_EQUAL(data["outputLevel"], 50000, "output level")
	TEST_ASSERT_EQUAL(data["outputLevelMax"], 200000, "output cap")
	p2_smes_set_charge(S, 2.5e6)
	press(H, S, "tryinput", list())
	data = p2_smes_data(S, H)
	TEST_ASSERT_EQUAL(data["capacityPercent"], 50, "half full after the charge moved")
	TEST_ASSERT_EQUAL(data["inputAttempt"], 1, "and input on after the button")

/// The input button toggles the input switch, both ways.
/datum/unit_test/dq_p2_smes/ui_tryinput_toggles_input

/datum/unit_test/dq_p2_smes/ui_tryinput_toggles_input/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	TEST_ASSERT(!S.input_attempt, "off to start")
	press(H, S, "tryinput", list())
	TEST_ASSERT(S.input_attempt, "the button turned input on")
	press(H, S, "tryinput", list())
	TEST_ASSERT(!S.input_attempt, "and off again")

/// The output button toggles the output switch, both ways, and an output turned off shows as not outputting.
/datum/unit_test/dq_p2_smes/ui_tryoutput_toggles_output

/datum/unit_test/dq_p2_smes/ui_tryoutput_toggles_output/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	TEST_ASSERT(S.output_attempt, "on to start")
	press(H, S, "tryoutput", list())
	TEST_ASSERT(!S.output_attempt, "the button turned output off")
	TEST_ASSERT_EQUAL(S.outputting, 0, "not outputting")
	press(H, S, "tryoutput", list())
	TEST_ASSERT(S.output_attempt, "and on again")

/// The input level moves by an adjustment and stays inside 0 to the cap.
/datum/unit_test/dq_p2_smes/ui_input_level_adjust_and_clamp

/datum/unit_test/dq_p2_smes/ui_input_level_adjust_and_clamp/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	press(H, S, "input", list("adjust" = 20000))
	TEST_ASSERT_EQUAL(S.input_level, 70000, "raised by the adjustment")
	press(H, S, "input", list("adjust" = -30000))
	TEST_ASSERT_EQUAL(S.input_level, 40000, "lowered by the adjustment")
	press(H, S, "input", list("adjust" = -1000000))
	TEST_ASSERT_EQUAL(S.input_level, 0, "never below zero")
	press(H, S, "input", list("adjust" = 5000000))
	TEST_ASSERT_EQUAL(S.input_level, 200000, "never above the cap")
	TEST_ASSERT_EQUAL(S.output_level, 50000, "the output level was not touched")

/// The input level takes min, max and a number typed in; a number out of range is clamped, a word is refused.
/datum/unit_test/dq_p2_smes/ui_input_level_targets

/datum/unit_test/dq_p2_smes/ui_input_level_targets/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	press(H, S, "input", list("target" = "max"))
	TEST_ASSERT_EQUAL(S.input_level, 200000, "max")
	press(H, S, "input", list("target" = "min"))
	TEST_ASSERT_EQUAL(S.input_level, 0, "min")
	press(H, S, "input", list("target" = "12345"))
	TEST_ASSERT_EQUAL(S.input_level, 12345, "a typed number")
	press(H, S, "input", list("target" = "99999999"))
	TEST_ASSERT_EQUAL(S.input_level, 200000, "a typed number over the cap is clamped")
	press(H, S, "input", list("target" = "-40"))
	TEST_ASSERT_EQUAL(S.input_level, 0, "a typed negative is clamped")
	press(H, S, "input", list("target" = "12345"))
	press(H, S, "input", list("target" = "not a number"))
	TEST_ASSERT_EQUAL(S.input_level, 12345, "a word changes nothing")

/// The output level behaves the same way on its own cap.
/datum/unit_test/dq_p2_smes/ui_output_level_adjust_targets_and_clamp

/datum/unit_test/dq_p2_smes/ui_output_level_adjust_targets_and_clamp/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	press(H, S, "output", list("adjust" = 10000))
	TEST_ASSERT_EQUAL(S.output_level, 60000, "raised")
	press(H, S, "output", list("adjust" = -100000))
	TEST_ASSERT_EQUAL(S.output_level, 0, "floor zero")
	press(H, S, "output", list("target" = "max"))
	TEST_ASSERT_EQUAL(S.output_level, 200000, "max")
	press(H, S, "output", list("adjust" = 1))
	TEST_ASSERT_EQUAL(S.output_level, 200000, "the cap holds")
	press(H, S, "output", list("target" = "min"))
	TEST_ASSERT_EQUAL(S.output_level, 0, "min")
	press(H, S, "output", list("target" = "777"))
	TEST_ASSERT_EQUAL(S.output_level, 777, "typed")
	press(H, S, "output", list("target" = "junk"))
	TEST_ASSERT_EQUAL(S.output_level, 777, "a word changes nothing")
	TEST_ASSERT_EQUAL(S.input_level, 50000, "the input level was not touched")

/// A touch opens the window for a person; a person across the room gets nothing.
/datum/unit_test/dq_p2_smes/touch_opens_the_window

/datum/unit_test/dq_p2_smes/touch_opens_the_window/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	var/mob/living/carbon/human/far = p2_actor(run_loc_floor_top_right)
	touch(far, S, null)
	TEST_ASSERT(!p2_smes_interface_opened(S, far), "out of reach: no window")
	touch(H, S, null)
	TEST_ASSERT(p2_smes_interface_opened(S, H), "a person's touch opens the window")

// ---------------------------------------------------------------------------------------------------------------------
// The service hatch
// ---------------------------------------------------------------------------------------------------------------------

/// A screwdriver opens and shuts the hatch.
/datum/unit_test/dq_p2_smes/screwdriver_toggles_the_hatch

/datum/unit_test/dq_p2_smes/screwdriver_toggles_the_hatch/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/tool/screwdriver/driver = tool(/obj/item/tool/screwdriver)
	touch(H, S, driver)
	TEST_ASSERT(p2_smes_panel_open(S), "the screwdriver opens the hatch")
	touch(H, S, driver)
	TEST_ASSERT(!p2_smes_panel_open(S), "and shuts it")

/// Another tool does not open the hatch.
/datum/unit_test/dq_p2_smes/other_tools_leave_the_hatch_shut

/datum/unit_test/dq_p2_smes/other_tools_leave_the_hatch_shut/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	touch(H, S, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT(!p2_smes_panel_open(S), "wirecutters leave the hatch shut")
	touch(H, S, tool(/obj/item/tool/crowbar))
	TEST_ASSERT(!p2_smes_panel_open(S), "a crowbar too")
	TEST_ASSERT(!QDELETED(S), "and the unit is not taken apart with the hatch shut")
	open_panel(H, S)
	TEST_ASSERT(p2_smes_panel_open(S), "the screwdriver does")

/// With the hatch open, a crowbar takes a plain unit apart into a frame.
/datum/unit_test/dq_p2_smes/crowbar_takes_a_plain_unit_apart_with_the_hatch_open

/datum/unit_test/dq_p2_smes/crowbar_takes_a_plain_unit_apart_with_the_hatch_open/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/tool/crowbar/bar = tool(/obj/item/tool/crowbar)
	touch(H, S, bar)
	TEST_ASSERT(!QDELETED(S), "hatch shut: the crowbar does nothing")
	open_panel(H, S)
	touch(H, S, bar)
	test_time(30 SECONDS)
	TEST_ASSERT(QDELETED(S), "hatch open: the unit comes apart")
	TEST_ASSERT_NOTNULL(locate(/obj/structure/frame) in p2_smes_spot(), "leaving a frame behind")

/// A welder with the hatch open repairs every point of damage.
/datum/unit_test/dq_p2_smes/welder_repairs_with_the_hatch_open

/datum/unit_test/dq_p2_smes/welder_repairs_with_the_hatch_open/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/weldingtool/welder = dq_fueled_welder(p2_side_spot())
	var/whole = p2_smes_integrity(S)
	p2_smes_hit(S, 5)
	var/hurt = p2_smes_integrity(S)
	TEST_ASSERT(hurt < whole, "the unit is damaged")
	weld(H, S, welder)
	test_time(1 MINUTES)
	TEST_ASSERT_EQUAL(p2_smes_integrity(S), hurt, "hatch shut: the welder repairs nothing")
	open_panel(H, S)
	weld(H, S, welder)
	test_time(1 MINUTES)
	TEST_ASSERT_EQUAL(p2_smes_integrity(S), whole, "hatch open: all the damage is repaired")

/// A welder that is off, or a unit that is whole, changes nothing.
/datum/unit_test/dq_p2_smes/welder_refused_when_off_or_when_whole

/datum/unit_test/dq_p2_smes/welder_refused_when_off_or_when_whole/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/weldingtool/welder = dq_fueled_welder(p2_side_spot())
	open_panel(H, S)
	var/whole = p2_smes_integrity(S)
	weld(H, S, welder)
	TEST_ASSERT_EQUAL(p2_smes_integrity(S), whole, "a whole unit stays whole")
	p2_smes_hit(S, 5)
	var/hurt = p2_smes_integrity(S)
	welder.setWelding(FALSE)
	weld(H, S, welder)
	test_time(1 MINUTES)
	TEST_ASSERT_EQUAL(p2_smes_integrity(S), hurt, "an unlit welder repairs nothing")
	welder.setWelding(TRUE)
	weld(H, S, welder)
	test_time(1 MINUTES)
	TEST_ASSERT_EQUAL(p2_smes_integrity(S), whole, "lit, it does")

/// With the hatch open an item with force is swallowed: it does not hit the unit.
/datum/unit_test/dq_p2_smes/item_with_the_hatch_open_is_swallowed

/datum/unit_test/dq_p2_smes/item_with_the_hatch_open_is_swallowed/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/bat = allocate(/obj/item, p2_side_spot())
	bat.force = 15
	bat.w_class = ITEMSIZE_NORMAL
	open_panel(H, S)
	var/whole = p2_smes_integrity(S)
	touch(H, S, bat)
	TEST_ASSERT_EQUAL(p2_smes_integrity(S), whole, "the item does no damage with the hatch open")
	TEST_ASSERT(!QDELETED(bat), "and is not used up")

// ---------------------------------------------------------------------------------------------------------------------
// The terminal: build and cut
// ---------------------------------------------------------------------------------------------------------------------

/// Ten lengths of cable, the hatch open, the person standing on the tile next to it with the floor bared: after five seconds a terminal stands there, joined to the cable under it.
/datum/unit_test/dq_p2_smes/cable_builds_a_terminal_after_a_wait

/datum/unit_test/dq_p2_smes/cable_builds_a_terminal_after_a_wait/run_gate()
	var/obj/machinery/power/smes/S = p2_bare_smes()
	var/mob/living/carbon/human/H = p2_actor(p2_term_spot())
	var/obj/structure/cable/C = p2_cable(p2_term_spot(), NORTH)
	open_panel(H, S)
	bare_floor(p2_term_spot())
	TEST_ASSERT(p2_smes_broken(S), "the unit with no terminal is broken")
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, p2_side_spot(), 10)
	H.put_in_active_hand(coil)
	test_click(H, S, coil)
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 0, "a second in, no terminal yet")
	p2_settle()
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 1, "after the wait there is a terminal")
	var/obj/machinery/power/terminal/term = p2_smes_terminals(S)[1]
	LAZYADD(p2_terms, term)
	TEST_ASSERT_EQUAL(term.loc, p2_term_spot(), "on the tile the person stood on")
	TEST_ASSERT_EQUAL(term.dir, EAST, "facing the unit")
	if(p2_terminal_master(term))
		TEST_ASSERT_EQUAL(p2_terminal_master(term), S, "answering to the unit")
	TEST_ASSERT(QDELETED(coil) || coil.amount == 0, "ten lengths used up")
	TEST_ASSERT(!p2_smes_broken(S), "and the unit works again")
	TEST_ASSERT_EQUAL(term.power_region, C.get_power_region(), "the terminal joined the cable's network")

/// The refusals: hatch shut, too little cable, standing on the unit's own tile, the floor tile still on. Each leaves the world as it was; then the build works.
/datum/unit_test/dq_p2_smes/cable_refusals_leave_everything_as_it_was

/datum/unit_test/dq_p2_smes/cable_refusals_leave_everything_as_it_was/run_gate()
	var/obj/machinery/power/smes/S = p2_bare_smes()
	var/mob/living/carbon/human/H = p2_actor(p2_term_spot())
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, p2_side_spot(), 10)
	touch(H, S, coil)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 0, "hatch shut: no terminal")
	TEST_ASSERT_EQUAL(coil.amount, 10, "and the cable is kept")
	open_panel(H, S)
	touch(H, S, coil)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 0, "floor tile on: no terminal")
	TEST_ASSERT_EQUAL(coil.amount, 10, "cable kept")
	bare_floor(p2_term_spot())
	var/obj/item/stack/cable_coil/short = allocate(/obj/item/stack/cable_coil, p2_side_spot(), 9)
	touch(H, S, short)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 0, "nine lengths: not enough")
	TEST_ASSERT_EQUAL(short.amount, 9, "cable kept")
	var/mob/living/carbon/human/on_unit = p2_actor(p2_smes_spot())
	touch(on_unit, S, coil)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 0, "standing on the unit's own tile: no terminal")
	TEST_ASSERT_EQUAL(coil.amount, 10, "cable kept")
	touch(H, S, coil)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 1, "with everything right the same coil builds it")

/// A second terminal cannot be built on a tile that has one, and the cable is kept.
/datum/unit_test/dq_p2_smes/cable_refused_where_a_terminal_already_stands

/datum/unit_test/dq_p2_smes/cable_refused_where_a_terminal_already_stands/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor(p2_term_spot())
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, p2_side_spot(), 10)
	open_panel(H, S)
	bare_floor(p2_term_spot())
	touch(H, S, coil)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 1, "still the one terminal")
	TEST_ASSERT_EQUAL(coil.amount, 10, "the cable is kept")

/// Wirecutters on the terminal's tile with the hatch open cut the terminal out and give the ten lengths back.
/datum/unit_test/dq_p2_smes/wirecutters_remove_the_terminal

/datum/unit_test/dq_p2_smes/wirecutters_remove_the_terminal/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor(p2_term_spot())
	p2_insulate(H)
	var/obj/item/tool/wirecutters/cutters = tool(/obj/item/tool/wirecutters)
	bare_floor(p2_term_spot())
	var/obj/machinery/power/terminal/term = p2_smes_terminals(S)[1]
	cut(H, S, cutters)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 1, "hatch shut: the terminal stays")
	open_panel(H, S)
	cut(H, S, cutters)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 0, "hatch open: the terminal is gone")
	TEST_ASSERT(QDELETED(term), "it was taken down")
	TEST_ASSERT_EQUAL(loose_cable(p2_smes_spot()), 10, "ten lengths of cable came back")

/// The cut is refused with nothing to cut on the person's tile, and where the floor tile covers the terminal.
/datum/unit_test/dq_p2_smes/wirecutters_refused_off_the_terminal_or_under_a_tile

/datum/unit_test/dq_p2_smes/wirecutters_refused_off_the_terminal_or_under_a_tile/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/side = p2_actor()
	var/mob/living/carbon/human/at_term = p2_actor(p2_term_spot())
	p2_insulate(side)
	p2_insulate(at_term)
	var/obj/machinery/power/terminal/term = p2_smes_terminals(S)[1]
	open_panel(side, S)
	cut(side, S, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 1, "no terminal on this tile: nothing is cut")
	cut(at_term, S, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 1, "the floor tile still over it: nothing is cut")
	TEST_ASSERT(!QDELETED(term), "the terminal stands")
	TEST_ASSERT_EQUAL(loose_cable(p2_smes_spot()), 0, "no cable came back")
	bare_floor(p2_term_spot())
	cut(at_term, S, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 0, "with the plating bared it is cut")

/// A terminal can be built again after one was cut out: the loop of cutting and building.
/datum/unit_test/dq_p2_smes/terminal_can_be_cut_and_built_again

/datum/unit_test/dq_p2_smes/terminal_can_be_cut_and_built_again/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor(p2_term_spot())
	p2_insulate(H)
	open_panel(H, S)
	bare_floor(p2_term_spot())
	cut(H, S, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 0, "cut out")
	var/obj/item/stack/cable_coil/coil
	for(var/obj/item/stack/cable_coil/C in p2_smes_spot())
		coil = C
	TEST_ASSERT_NOTNULL(coil, "the cable is on the floor")
	touch(H, S, coil)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 1, "built again with the same cable")

// ---------------------------------------------------------------------------------------------------------------------
// The terminal itself
// ---------------------------------------------------------------------------------------------------------------------

/// A terminal hides under a floor tile and shows on bare plating.
/datum/unit_test/dq_p2_smes/terminal_hides_under_flooring

/datum/unit_test/dq_p2_smes/terminal_hides_under_flooring/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/obj/machinery/power/terminal/term = p2_smes_terminals(S)[1]
	TEST_ASSERT(term.hides_under_flooring(), "a terminal is the kind that hides")
	TEST_ASSERT_EQUAL(term.invisibility, INVISIBILITY_ABSTRACT, "under the tile it is hidden")
	bare_floor(p2_term_spot())
	term.hide(FALSE)
	TEST_ASSERT_EQUAL(term.invisibility, INVISIBILITY_NONE, "shown when told to (the plating bared)")
	term.hide(TRUE)
	TEST_ASSERT_EQUAL(term.invisibility, INVISIBILITY_ABSTRACT, "hidden when told to")

/// A terminal made on bare plating starts shown.
/datum/unit_test/dq_p2_smes/terminal_on_plating_starts_shown

/datum/unit_test/dq_p2_smes/terminal_on_plating_starts_shown/run_gate()
	bare_floor(p2_term_spot())
	var/obj/machinery/power/terminal/smes_input/term = p2_input_terminal()
	TEST_ASSERT_EQUAL(term.invisibility, INVISIBILITY_NONE, "on the plating it is shown")

/// A terminal's overload goes to its master, destroying a terminal tells its master to let it go, and a terminal with no master tells nobody.
/datum/unit_test/dq_p2_smes/terminal_destroy_and_overload_reach_the_master

/datum/unit_test/dq_p2_smes/terminal_destroy_and_overload_reach_the_master/run_gate()
	var/obj/machinery/power/apc/p2_overload_probe/probe = allocate(/obj/machinery/power/apc/p2_overload_probe, p2_load_spot())
	var/obj/machinery/power/terminal/term = p2_plain_terminal(p2_supply_spot())
	TEST_ASSERT_NULL(p2_terminal_master(term), "a bare terminal has no master")
	term.overload(probe)
	TEST_ASSERT_EQUAL(probe.overloads, 0, "and an overload goes nowhere")
	rel_set(term, nameof(term.master), probe)
	TEST_ASSERT_EQUAL(p2_terminal_master(term), probe, "now it answers to the probe")
	term.overload(probe)
	TEST_ASSERT_EQUAL(probe.overloads, 1, "an overload is passed to the master")
	qdel(term)
	TEST_ASSERT_EQUAL(probe.disconnects, 1, "destroying the terminal told its master to let it go")
	qdel(probe)

/// A SMES's terminal list shrinks when a terminal is destroyed.
/datum/unit_test/dq_p2_smes/destroying_a_terminal_shrinks_the_units_list

/datum/unit_test/dq_p2_smes/destroying_a_terminal_shrinks_the_units_list/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/obj/machinery/power/terminal/own = p2_smes_terminals(S)[1]
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 1, "one terminal")
	qdel(own)
	p2_settle()
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 0, "a destroyed terminal leaves its unit's list")

// ---------------------------------------------------------------------------------------------------------------------
// Power: the Rust domain
// ---------------------------------------------------------------------------------------------------------------------

/// With input on and supply behind the terminal the unit charges; with input off it does not.
/datum/unit_test/dq_p2_smes/input_on_charges_and_input_off_does_not

/datum/unit_test/dq_p2_smes/input_on_charges_and_input_off_does_not/run_gate()
	var/obj/machinery/power/smes/S = p2_network()
	var/mob/living/carbon/human/H = p2_actor()
	TEST_ASSERT(!S.input_attempt, "input off")
	var/before = p2_smes_charge(S)
	p2_steps(5)
	TEST_ASSERT(same_charge(p2_smes_charge(S), before), "input off: the charge does not rise with supply there")
	press(H, S, "tryinput", list())
	TEST_ASSERT(S.input_attempt, "input on")
	press(H, S, "output", list("target" = "min"))
	before = p2_smes_charge(S)
	p2_steps(5)
	TEST_ASSERT(p2_smes_charge(S) > before + 100, "input on: the charge rose ([before] to [p2_smes_charge(S)])")

/// A lower input level charges more slowly than a higher one.
/datum/unit_test/dq_p2_smes/input_level_limits_the_rate

/datum/unit_test/dq_p2_smes/input_level_limits_the_rate/run_gate()
	var/obj/machinery/power/smes/S = p2_network()
	var/mob/living/carbon/human/H = p2_actor()
	press(H, S, "tryinput", list())
	press(H, S, "tryoutput", list())
	press(H, S, "input", list("target" = "10000"))
	var/before = p2_smes_charge(S)
	p2_steps(5)
	var/slow = p2_smes_charge(S) - before
	press(H, S, "input", list("target" = "100000"))
	before = p2_smes_charge(S)
	p2_steps(5)
	var/fast = p2_smes_charge(S) - before
	TEST_ASSERT(slow > 0, "it charged at the low level")
	TEST_ASSERT(fast > slow, "and faster at the higher one ([slow] against [fast])")

/// A unit with input on but no supply behind the terminal does not charge.
/datum/unit_test/dq_p2_smes/no_supply_no_charge

/datum/unit_test/dq_p2_smes/no_supply_no_charge/run_gate()
	var/obj/machinery/power/smes/S = p2_network(supply_watts = 0)
	var/mob/living/carbon/human/H = p2_actor()
	press(H, S, "tryinput", list())
	press(H, S, "tryoutput", list())
	var/before = p2_smes_charge(S)
	p2_steps(5)
	TEST_ASSERT(same_charge(p2_smes_charge(S), before), "no supply: no charge")
	p2_supply.set_power_supply(500000)
	p2_steps(5)
	TEST_ASSERT(p2_smes_charge(S) > before + 100, "supply returns: it charges")

/// With output on and charge held the unit supplies its network; with output off it does not.
/datum/unit_test/dq_p2_smes/output_feeds_the_network_only_while_on

/datum/unit_test/dq_p2_smes/output_feeds_the_network_only_while_on/run_gate()
	var/obj/machinery/power/smes/S = p2_network(supply_watts = 0)
	var/mob/living/carbon/human/H = p2_actor()
	TEST_ASSERT(S.output_attempt, "output on")
	p2_steps(3)
	TEST_ASSERT(p2_net_avail(p2_load) > 0, "output on: the load's network has power")
	press(H, S, "tryoutput", list())
	TEST_ASSERT(!S.output_attempt, "output off")
	p2_steps(3)
	TEST_ASSERT_EQUAL(p2_net_avail(p2_load), 0, "output off: nothing on the network")
	press(H, S, "tryoutput", list())
	p2_steps(3)
	TEST_ASSERT(p2_net_avail(p2_load) > 0, "output on again: power again")

/// A load on the unit's network (an APC serving an area with a static load) lowers its charge; with nothing held it supplies nothing.
/datum/unit_test/dq_p2_smes/load_discharges_the_unit

/datum/unit_test/dq_p2_smes/load_discharges_the_unit/run_gate()
	var/obj/machinery/power/smes/S = p2_network(supply_watts = 0)
	var/area/load_area = get_area(p2_load_spot())
	var/requires = load_area.requires_power
	load_area.requires_power = TRUE
	var/obj/machinery/power/apc/A = allocate(/obj/machinery/power/apc/p2_test, p2_load_spot())
	A.connect_to_network()
	p2_apc_load(A, 20000)
	p2_apc_resync(A)
	p2_smes_set_charge(S, 1e6)
	for(var/i in 1 to 5)
		p2_smes_power_step()
	var/before = p2_smes_charge(S)
	for(var/i in 1 to 20)
		p2_smes_power_step()
	TEST_ASSERT(p2_smes_charge(S) < before - 100, "a load on the network lowers the charge ([before] to [p2_smes_charge(S)])")
	p2_smes_set_charge(S, 0)
	p2_steps(3)
	TEST_ASSERT_EQUAL(p2_net_avail(p2_load), 0, "an empty unit supplies nothing")
	p2_apc_load(A, -20000)
	load_area.requires_power = requires
	qdel(A)

/// A broken unit neither takes nor gives.
/datum/unit_test/dq_p2_smes/broken_unit_stops_input_and_output

/datum/unit_test/dq_p2_smes/broken_unit_stops_input_and_output/run_gate()
	var/obj/machinery/power/smes/S = p2_network()
	var/mob/living/carbon/human/H = p2_actor()
	press(H, S, "tryinput", list())
	p2_steps(3)
	TEST_ASSERT(p2_net_avail(p2_load) > 0, "working: it gives")
	var/before = p2_smes_charge(S)
	var/list/keys = p2_smes_overlay_keys(S)
	TEST_ASSERT(keys[1] != "" && keys[2] != "" && keys[3] != "0", "working: its status overlays are drawn")
	S.atom_break()
	p2_settle()
	TEST_ASSERT(p2_smes_broken(S), "broken")
	p2_steps(3)
	TEST_ASSERT_EQUAL(p2_net_avail(p2_load), 0, "broken: it gives nothing")
	TEST_ASSERT(same_charge(p2_smes_charge(S), before), "and takes nothing")
	keys = p2_smes_overlay_keys(S)
	TEST_ASSERT(keys[1] == "" && keys[2] == "" && keys[3] == "0", "broken: the status overlays are hidden")

/// A grid check suspends all input and output; lifting it restores them.
/datum/unit_test/dq_p2_smes/grid_check_suspends_input_and_output

/datum/unit_test/dq_p2_smes/grid_check_suspends_input_and_output/run_gate()
	var/obj/machinery/power/smes/S = p2_network()
	var/mob/living/carbon/human/H = p2_actor()
	press(H, S, "tryinput", list())
	p2_steps(3)
	TEST_ASSERT(p2_net_avail(p2_load) > 0, "working: it gives")
	p2_smes_set_grid_check(S, TRUE)
	p2_steps(3)
	TEST_ASSERT_EQUAL(p2_net_avail(p2_load), 0, "grid check: it gives nothing")
	var/before = p2_smes_charge(S)
	p2_steps(3)
	TEST_ASSERT(same_charge(p2_smes_charge(S), before), "and takes nothing")
	p2_smes_set_grid_check(S, FALSE)
	p2_steps(3)
	TEST_ASSERT(p2_net_avail(p2_load) > 0, "lifted: it gives again")

// ---------------------------------------------------------------------------------------------------------------------
// The wires
// ---------------------------------------------------------------------------------------------------------------------

/// The wires answer only behind the open hatch.
/datum/unit_test/dq_p2_smes/wires_reachable_only_behind_the_open_hatch

/datum/unit_test/dq_p2_smes/wires_reachable_only_behind_the_open_hatch/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/p2_test)
	var/mob/living/carbon/human/H = p2_actor()
	var/datum/wires_test_adapter/W = p2_smes_wires(S)
	TEST_ASSERT(!W.interactable(H), "shut: not reachable")
	open_panel(H, S)
	TEST_ASSERT(W.interactable(H), "open: reachable")

/// Cutting the input wire stops charging; mending it lets it go on.
/datum/unit_test/dq_p2_smes/input_wire_cut_stops_charging

/datum/unit_test/dq_p2_smes/input_wire_cut_stops_charging/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_network(/obj/machinery/power/smes/buildable/p2_test)
	var/mob/living/carbon/human/H = p2_actor()
	var/datum/wires_test_adapter/W = p2_smes_wires(S)
	press(H, S, "tryinput", list())
	press(H, S, "tryoutput", list())
	W.cut(WIRE_SMES_INPUT)
	p2_settle()
	TEST_ASSERT(S.input_cut, "the input wire is cut")
	var/before = p2_smes_charge(S)
	p2_steps(5)
	TEST_ASSERT(same_charge(p2_smes_charge(S), before), "cut: no charge although input is on")
	W.cut(WIRE_SMES_INPUT)
	p2_settle()
	TEST_ASSERT(!S.input_cut, "mended")
	p2_smes_set_charge(S, 1e6)
	before = p2_smes_charge(S)
	p2_steps(5)
	TEST_ASSERT(p2_smes_charge(S) > before + 100, "mended: it charges")

/// Cutting the output wire stops the unit giving; mending it restores it.
/datum/unit_test/dq_p2_smes/output_wire_cut_stops_output

/datum/unit_test/dq_p2_smes/output_wire_cut_stops_output/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_network(/obj/machinery/power/smes/buildable/p2_test, supply_watts = 0)
	var/datum/wires_test_adapter/W = p2_smes_wires(S)
	p2_smes_set_charge(S, 1e6)
	p2_steps(3)
	TEST_ASSERT(p2_net_avail(p2_load) > 0, "output on: it gives")
	W.cut(WIRE_SMES_OUTPUT)
	p2_settle()
	TEST_ASSERT(S.output_cut, "the output wire is cut")
	p2_steps(3)
	TEST_ASSERT_EQUAL(p2_net_avail(p2_load), 0, "cut: it gives nothing")
	W.cut(WIRE_SMES_OUTPUT)
	p2_settle()
	p2_steps(3)
	TEST_ASSERT(p2_net_avail(p2_load) > 0, "mended: it gives again")

/// Pulsing the input or output wire flips that switch.
/datum/unit_test/dq_p2_smes/input_and_output_wire_pulses_flip_the_switches

/datum/unit_test/dq_p2_smes/input_and_output_wire_pulses_flip_the_switches/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/p2_test)
	var/datum/wires_test_adapter/W = p2_smes_wires(S)
	TEST_ASSERT(!S.input_attempt && S.output_attempt, "input off, output on to start")
	W.pulse(WIRE_SMES_INPUT)
	TEST_ASSERT(S.input_attempt, "a pulse turned input on")
	W.pulse(WIRE_SMES_INPUT)
	TEST_ASSERT(!S.input_attempt, "and off")
	W.pulse(WIRE_SMES_OUTPUT)
	TEST_ASSERT(!S.output_attempt, "a pulse turned output off")
	W.pulse(WIRE_SMES_OUTPUT)
	TEST_ASSERT(S.output_attempt, "and on")

/// The remote wire: cut, the remote control is off for good; pulsed, off for a second.
/datum/unit_test/dq_p2_smes/remote_wire_cut_and_pulse

/datum/unit_test/dq_p2_smes/remote_wire_cut_and_pulse/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/p2_test)
	var/datum/wires_test_adapter/W = p2_smes_wires(S)
	TEST_ASSERT(S.RCon, "remote control on")
	W.pulse(WIRE_SMES_RCON)
	TEST_ASSERT(!S.RCon, "a pulse switches it off")
	test_time(3 SECONDS)
	TEST_ASSERT(S.RCon, "for a moment only")
	W.cut(WIRE_SMES_RCON)
	TEST_ASSERT(!S.RCon, "cut, it stays off")
	test_time(1 MINUTES)
	TEST_ASSERT(!S.RCon, "for good")
	W.cut(WIRE_SMES_RCON)
	TEST_ASSERT(S.RCon, "mended, it is back")

/// The failsafe wire: cut, the safety is off; pulsed, off for a second; mended, on.
/datum/unit_test/dq_p2_smes/failsafe_wire_cut_and_pulse

/datum/unit_test/dq_p2_smes/failsafe_wire_cut_and_pulse/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/p2_test)
	var/datum/wires_test_adapter/W = p2_smes_wires(S)
	TEST_ASSERT(S.safeties_enabled, "safety on")
	W.pulse(WIRE_SMES_FAILSAFES)
	TEST_ASSERT(!S.safeties_enabled, "a pulse switches it off")
	test_time(3 SECONDS)
	TEST_ASSERT(S.safeties_enabled, "for a moment only")
	W.cut(WIRE_SMES_FAILSAFES)
	TEST_ASSERT(!S.safeties_enabled, "cut, it stays off")
	test_time(1 MINUTES)
	TEST_ASSERT(!S.safeties_enabled, "for good")
	W.cut(WIRE_SMES_FAILSAFES)
	TEST_ASSERT(S.safeties_enabled, "mended, it is back")

/// The grounding wire: cut, the unit dumps its charge step after step; mended, it stops.
/datum/unit_test/dq_p2_smes/grounding_wire_cut_discharges_the_unit

/datum/unit_test/dq_p2_smes/grounding_wire_cut_discharges_the_unit/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/p2_test)
	var/datum/wires_test_adapter/W = p2_smes_wires(S)
	press(p2_actor(), S, "tryoutput", list())
	p2_smes_set_charge(S, S.capacity)
	var/before = p2_smes_charge(S)
	test_time(10 SECONDS)
	TEST_ASSERT(same_charge(p2_smes_charge(S), before), "grounded: a full unit holds its charge")
	W.cut(WIRE_SMES_GROUNDING)
	TEST_ASSERT(!S.grounding, "the grounding wire is cut")
	test_time(20 SECONDS)
	var/low = p2_smes_charge(S)
	TEST_ASSERT(low < before - 1000, "cut: the unit dumps its charge ([before] to [low])")
	W.cut(WIRE_SMES_GROUNDING)
	TEST_ASSERT(S.grounding, "mended")
	test_time(10 SECONDS)
	var/settled = p2_smes_charge(S)
	test_time(20 SECONDS)
	TEST_ASSERT(same_charge(p2_smes_charge(S), settled), "and the discharge stops")

/// Pulsing the grounding wire ungrounds the unit and stays so after a cut; mending grounds it.
/datum/unit_test/dq_p2_smes/grounding_wire_pulse_leaves_it_grounded

/datum/unit_test/dq_p2_smes/grounding_wire_pulse_leaves_it_grounded/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/p2_test)
	var/datum/wires_test_adapter/W = p2_smes_wires(S)
	W.pulse(WIRE_SMES_GROUNDING)
	TEST_ASSERT(!S.grounding, "a pulse on the grounding wire ungrounds the unit")
	W.cut(WIRE_SMES_GROUNDING)
	TEST_ASSERT(!S.grounding, "cutting after a pulse leaves it ungrounded")
	W.cut(WIRE_SMES_GROUNDING)
	TEST_ASSERT(S.grounding, "mending grounds it")

// ---------------------------------------------------------------------------------------------------------------------
// Coils
// ---------------------------------------------------------------------------------------------------------------------

/// A coil goes in with the hatch open, the switches off and little charge: capacity and the I/O caps follow it.
/datum/unit_test/dq_p2_smes/coil_install_raises_capacity_and_io

/datum/unit_test/dq_p2_smes/coil_install_raises_capacity_and_io/run_gate()
	allocate(/obj/item/smes_coil/weak, p2_smes_spot())
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/p2_test)
	p2_smes_map_late(S)
	var/mob/living/carbon/human/H = p2_actor()
	var/capacity = S.capacity
	var/io = S.input_level_max
	var/coils = S.cur_coils
	open_panel(H, S)
	press(H, S, "tryoutput", list())
	p2_smes_set_charge(S, 0)
	var/obj/item/smes_coil/coil = allocate(/obj/item/smes_coil, p2_side_spot())
	touch(H, S, coil)
	TEST_ASSERT(S.capacity > capacity, "the coil raised the capacity ([capacity] to [S.capacity])")
	TEST_ASSERT(S.input_level_max > io, "and the input cap")
	TEST_ASSERT(S.output_level_max > io, "and the output cap")
	TEST_ASSERT_EQUAL(S.cur_coils, coils + 1, "one more coil counted")

/// A coil is refused with the hatch shut, with a switch on, or with charge held while the safety is on.
/datum/unit_test/dq_p2_smes/coil_install_refusals

/datum/unit_test/dq_p2_smes/coil_install_refusals/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/p2_test)
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/smes_coil/coil = allocate(/obj/item/smes_coil, p2_side_spot())
	var/capacity = S.capacity
	var/coils = S.cur_coils
	p2_smes_set_charge(S, 0)
	press(H, S, "tryoutput", list())
	touch(H, S, coil)
	TEST_ASSERT_EQUAL(S.cur_coils, coils, "hatch shut: no coil goes in")
	open_panel(H, S)
	press(H, S, "tryoutput", list())
	TEST_ASSERT(S.output_attempt, "(output on)")
	touch(H, S, coil)
	TEST_ASSERT_EQUAL(S.cur_coils, coils, "a switch on: no coil goes in")
	press(H, S, "tryoutput", list())
	p2_smes_set_charge(S, S.capacity / 2)
	touch(H, S, coil)
	TEST_ASSERT_EQUAL(S.cur_coils, coils, "charged with the safety on: no coil goes in")
	TEST_ASSERT_EQUAL(S.capacity, capacity, "the capacity is as it was")
	p2_smes_set_charge(S, 0)
	touch(H, S, coil)
	TEST_ASSERT_EQUAL(S.cur_coils, coils + 1, "with everything right the coil goes in")

// ---------------------------------------------------------------------------------------------------------------------
// Charge in and out: drain, add, remove, the pulse
// ---------------------------------------------------------------------------------------------------------------------

/// drain_power(): a check says yes; a real drain takes the SMES rate off the charge and gives back the power; an empty unit gives what it has.
/datum/unit_test/dq_p2_smes/drain_power_takes_charge_and_clamps

/datum/unit_test/dq_p2_smes/drain_power_takes_charge_and_clamps/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	p2_smes_set_charge(S, 1e6)
	TEST_ASSERT(S.drain_power(TRUE), "a drain check says it can be drained")
	TEST_ASSERT(same_charge(p2_smes_charge(S), 1e6), "the check takes nothing")
	var/got = S.drain_power(FALSE, 0, 1000)
	TEST_ASSERT(got > 0, "a drain gives power")
	TEST_ASSERT(same_charge(p2_smes_charge(S), 1e6 - 1000 * SMESRATE, 5), "and takes the SMES rate of it off the charge")
	p2_smes_set_charge(S, 10)
	var/rest = S.drain_power(FALSE, 0, 1e9)
	TEST_ASSERT(same_charge(rest, 10 / SMESRATE, 5), "an almost empty unit gives what it has")
	TEST_ASSERT(same_charge(p2_smes_charge(S), 0, 1), "and ends empty")

/// add_charge() and remove_charge() move the charge by the SMES rate, and the charge never goes negative.
/datum/unit_test/dq_p2_smes/add_and_remove_charge

/datum/unit_test/dq_p2_smes/add_and_remove_charge/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	p2_smes_set_charge(S, 1e6)
	S.add_charge(30000)
	TEST_ASSERT(same_charge(p2_smes_charge(S), 1e6 + 30000 * SMESRATE, 5), "added at the SMES rate")
	S.remove_charge(30000)
	TEST_ASSERT(same_charge(p2_smes_charge(S), 1e6, 5), "and taken off again")
	S.remove_charge(1e12)
	TEST_ASSERT(p2_smes_charge(S) >= 0, "the charge does not go below nothing")
	TEST_ASSERT(p2_smes_charge(S) < 1, "the unit is emptied")

/// A pulse drains a million over its severity and scrambles the settings inside their limits.
/datum/unit_test/dq_p2_smes/emp_scrambles_settings_and_drains

/datum/unit_test/dq_p2_smes/emp_scrambles_settings_and_drains/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	p2_smes_set_charge(S, 3e6)
	S.input_level = 12345
	S.output_level = 54321
	S.emp_act(1)
	p2_settle()
	TEST_ASSERT(same_charge(p2_smes_charge(S), 2e6, 50), "a severity one pulse took a million")
	TEST_ASSERT(S.input_level != 12345 && S.output_level != 54321, "both levels were scrambled")
	TEST_ASSERT(S.input_level >= 0 && S.input_level <= S.input_level_max, "the input level stays inside its limits")
	TEST_ASSERT(S.output_level >= 0 && S.output_level <= S.output_level_max, "the output level stays inside its limits")
	TEST_ASSERT(S.input_attempt == 0 || S.input_attempt == 1, "the input switch is on or off")
	TEST_ASSERT(S.output_attempt == 0 || S.output_attempt == 1, "the output switch is on or off")
	S.emp_act(2)
	p2_settle()
	TEST_ASSERT(same_charge(p2_smes_charge(S), 1.5e6, 50), "a severity two pulse took half a million")
	p2_smes_set_charge(S, 100)
	S.emp_act(1)
	TEST_ASSERT(same_charge(p2_smes_charge(S), 0, 1), "an almost empty unit ends empty, not negative")

// ---------------------------------------------------------------------------------------------------------------------
// Damage, the sound loop, examine
// ---------------------------------------------------------------------------------------------------------------------

/// A hit that takes the unit past its integrity destroys it (an empty one, so no explosion is made).
/datum/unit_test/dq_p2_smes/destroyed_unit_is_deleted

/datum/unit_test/dq_p2_smes/destroyed_unit_is_deleted/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	p2_smes_set_charge(S, 0)
	p2_smes_hit(S, 10)
	TEST_ASSERT(!QDELETED(S), "a light hit leaves it standing")
	p2_smes_hit(S, S.max_integrity * 2)
	p2_settle()
	TEST_ASSERT(QDELETED(S), "a hit past its integrity destroys an empty unit")

/// The sound loop runs only while the unit shows output level two.
/datum/unit_test/dq_p2_smes/sound_loop_runs_only_at_output_level_two

/datum/unit_test/dq_p2_smes/sound_loop_runs_only_at_output_level_two/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	TEST_ASSERT(!p2_smes_noisy(S), "silent to start")
	p2_smes_show_output(S, 1)
	TEST_ASSERT(!p2_smes_noisy(S), "outputting at level one: silent")
	p2_smes_show_output(S, 2)
	TEST_ASSERT(p2_smes_noisy(S), "level two: the loop runs")
	p2_smes_show_output(S, 0)
	TEST_ASSERT(!p2_smes_noisy(S), "level zero: the loop stops")

/// Examining the unit says whether the hatch is open or shut.
/datum/unit_test/dq_p2_smes/examine_says_the_hatch_state

/datum/unit_test/dq_p2_smes/examine_says_the_hatch_state/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor()
	var/shut = jointext(S.examine(H), " ")
	TEST_ASSERT(findtext(shut, "closed") && !findtext(shut, "open"), "shut: the examine says closed")
	open_panel(H, S)
	var/open = jointext(S.examine(H), " ")
	TEST_ASSERT(findtext(open, "open") && !findtext(open, "closed"), "open: the examine says open")

// ---------------------------------------------------------------------------------------------------------------------
// The battery rack (a unit that keeps its legacy forms and shares the SMES's base): it still works beside the declared unit
// ---------------------------------------------------------------------------------------------------------------------

/// A cell goes into the rack, its capacity follows the cells, the rack draws its own look (none of the SMES status overlays) and sends its own window
/// data (none of the SMES's).
/datum/unit_test/dq_p2_smes/battery_rack_takes_cells_and_keeps_its_own_look_and_window

/datum/unit_test/dq_p2_smes/battery_rack_takes_cells_and_keeps_its_own_look_and_window/run_gate()
	var/obj/machinery/power/smes/batteryrack/R = allocate(/obj/machinery/power/smes/batteryrack, p2_smes_spot())
	LAZYADD(p2_smeses, R)
	var/mob/living/carbon/human/H = p2_actor()
	p2_settle()
	TEST_ASSERT_EQUAL(R.capacity, 0, "an empty rack stores nothing")
	var/obj/item/cell/cell = allocate(/obj/item/cell/high, p2_side_spot())
	touch(H, R, cell)
	TEST_ASSERT(cell in R.internal_cells, "the cell is in the rack")
	TEST_ASSERT(R.capacity > 0, "and the rack's capacity follows it")
	var/list/keys = p2_smes_overlay_keys(R)
	TEST_ASSERT(keys[1] == "" && keys[2] == "" && keys[3] == "0", "a rack draws none of the SMES status overlays")
	var/list/data = list()
	present_tgui_data(R, H, data)
	TEST_ASSERT(!("capacityPercent" in data), "and sends none of the SMES window data")

/// A unit with no input terminal (unwired, so not operable) still opens its window for a hand. Its buttons are not behind the operable gate
/// (window buttons never were: only TAG_CONTROL ops and the hand gate read operable), so the input button still moves its switch.
/datum/unit_test/dq_p2_smes/unwired_window_opens_buttons_keep_working

/datum/unit_test/dq_p2_smes/unwired_window_opens_buttons_keep_working/run_gate()
	var/obj/machinery/power/smes/S = p2_bare_smes()
	var/mob/living/carbon/human/H = p2_actor()
	TEST_ASSERT(S.unwired, "a unit with no terminal is unwired")
	var/datum/op_result/opened = test_menu(H, S, "ui_open")
	TEST_ASSERT_EQUAL(opened?.outcome, ACT_COMMITTED, "the window of an unwired unit opens for a human")
	var/before = S.input_attempt
	press(H, S, "tryinput", list())
	TEST_ASSERT(S.input_attempt != before, "its input button still toggles the switch")
