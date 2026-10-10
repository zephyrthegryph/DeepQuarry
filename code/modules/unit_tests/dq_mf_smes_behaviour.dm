// Behaviour tests for the SMES review findings (rewrite/machines-full): written against the legacy code first, where each pins what the code did
// then (the bugs included), and edited in the commit that fixes a bug, with the change listed in doc/rewrite/intended_changes.md. They reuse the
// fixture of dq_p2_smes_behaviour.dm (the 5x5 block, p2_network(), p2_actor(), touch(), press(), p2_settle()).

// ---- adapters: today's accessors (only these bodies change with the conversion) ----

/// The unit does not work now (broken, or set aside for any other reason a player can see: dark and idle).
/proc/p2_smes_unworking(obj/machinery/power/smes/S)
	return !!(S.broken_now() || S.unwired)

/// The safety circuit is on.
/proc/p2_smes_safeties(obj/machinery/power/smes/buildable/S)
	return !!S.safeties_enabled

/// The units an RCON console lists now.
/proc/p2_rcon_units(datum/tgui_module/rcon/R)
	return R.known_smes()


/// What the unit shows of its flows: the window's inputting/outputting and the input-available and output-used readings, and the hum. A unit on a
/// supplied network with input and output on and a load drawing shows that both flow.
/datum/unit_test/dq_p2_smes/mf_flow_readings_follow_the_network

/datum/unit_test/dq_p2_smes/mf_flow_readings_follow_the_network/run_gate()
	var/obj/machinery/power/smes/S = p2_network()
	var/mob/living/carbon/human/H = p2_actor()
	press(H, S, "tryinput", list())
	TEST_ASSERT(S.input_attempt && S.output_attempt, "(input and output on)")
	var/area/load_area = get_area(p2_load_spot())
	var/requires = load_area.requires_power
	load_area.set_requires_power(TRUE)
	load_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	var/obj/machinery/power/apc/A = allocate(/obj/machinery/power/apc/p2_test, p2_load_spot())
	A.connect_to_network()
	p2_apc_load(A, 20000)
	p2_apc_resync(A)
	p2_steps(5)
	var/list/data = p2_smes_data(S, H)
	TEST_ASSERT_EQUAL(data["inputting"], 2, "the window shows input flowing")
	TEST_ASSERT(data["inputAvailable"] > 0, "and the supply the terminal sees ([data["inputAvailable"]])")
	TEST_ASSERT(data["outputUsed"] >= 0, "the output used is a reading ([data["outputUsed"]])")
	var/list/keys = p2_smes_overlay_keys(S)
	TEST_ASSERT_EQUAL(keys[2], "2", "the input overlay shows it charging")
	press(H, S, "tryinput", list())
	p2_steps(3)
	data = p2_smes_data(S, H)
	TEST_ASSERT_EQUAL(data["inputting"], 0, "input off: nothing in")
	p2_apc_load(A, -20000)
	load_area.set_requires_power(requires)
	load_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	qdel(A)

/// With no supply behind the terminal and input on, the unit shows it is trying (1), not flowing (2).
/datum/unit_test/dq_p2_smes/mf_input_on_without_supply_shows_trying

/datum/unit_test/dq_p2_smes/mf_input_on_without_supply_shows_trying/run_gate()
	var/obj/machinery/power/smes/S = p2_network(supply_watts = 0)
	var/mob/living/carbon/human/H = p2_actor()
	press(H, S, "tryinput", list())
	p2_steps(3)
	var/list/data = p2_smes_data(S, H)
	TEST_ASSERT_EQUAL(data["inputting"], 1, "trying, with nothing to take")
	TEST_ASSERT_EQUAL(data["inputAvailable"], 0, "nothing available")

/// An output that feeds a load hums; one that feeds nothing is silent.
/datum/unit_test/dq_p2_smes/mf_output_feeding_a_load_hums

/datum/unit_test/dq_p2_smes/mf_output_feeding_a_load_hums/run_gate()
	var/obj/machinery/power/smes/S = p2_network(supply_watts = 0)
	var/mob/living/carbon/human/H = p2_actor()
	p2_steps(3)
	TEST_ASSERT(!p2_smes_noisy(S), "no load: silent")
	var/area/load_area = get_area(p2_load_spot())
	var/requires = load_area.requires_power
	load_area.set_requires_power(TRUE)
	load_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	var/obj/machinery/power/apc/A = allocate(/obj/machinery/power/apc/p2_test, p2_load_spot())
	A.connect_to_network()
	p2_apc_load(A, 20000)
	p2_apc_resync(A)
	p2_steps(5)
	var/list/data = p2_smes_data(S, H)
	TEST_ASSERT_EQUAL(data["outputting"], 2, "the output is flowing")
	TEST_ASSERT(data["outputUsed"] > 0, "into the load ([data["outputUsed"]])")
	TEST_ASSERT(p2_smes_noisy(S), "and the unit hums")
	p2_apc_load(A, -20000)
	load_area.set_requires_power(requires)
	load_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	qdel(A)

/// A unit broken by damage stays broken when a terminal is built for it; a unit that only lacked a terminal works once one is built.
/datum/unit_test/dq_p2_smes/mf_terminal_build_does_not_repair_a_broken_unit

/datum/unit_test/dq_p2_smes/mf_terminal_build_does_not_repair_a_broken_unit/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	var/mob/living/carbon/human/H = p2_actor(p2_side_spot())
	p2_insulate(H)
	S.atom_break()
	p2_settle()
	TEST_ASSERT(p2_smes_broken(S), "(broken by damage)")
	bare_floor(p2_side_spot())
	open_panel(H, S)
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, get_turf(H))
	coil.amount = 30
	touch(H, S, coil)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 2, "(a second terminal was built)")
	TEST_ASSERT(p2_smes_broken(S), "the terminal does not mend a broken unit")

/// A unit placed with no terminal works once a terminal is built for it.
/datum/unit_test/dq_p2_smes/mf_terminal_build_wakes_an_unwired_unit

/datum/unit_test/dq_p2_smes/mf_terminal_build_wakes_an_unwired_unit/run_gate()
	var/obj/machinery/power/smes/S = p2_bare_smes()
	var/mob/living/carbon/human/H = p2_actor(p2_term_spot())
	p2_insulate(H)
	p2_settle()
	TEST_ASSERT(p2_smes_unworking(S), "(no terminal: not working)")
	bare_floor(p2_term_spot())
	open_panel(H, S)
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, p2_term_spot())
	coil.amount = 30
	touch(H, S, coil)
	TEST_ASSERT_EQUAL(length(p2_smes_terminals(S)), 1, "(the terminal was built)")
	TEST_ASSERT(!p2_smes_unworking(S), "and the unit works")

/// A hybrid unit that is full makes no charge and does nothing per frame beyond its gate (its charge stays at the capacity).
/datum/unit_test/dq_p2_smes/mf_full_hybrid_stays_full

/datum/unit_test/dq_p2_smes/mf_full_hybrid_stays_full/run_gate()
	var/obj/machinery/power/smes/buildable/hybrid/S = p2_smes(/obj/machinery/power/smes/buildable/hybrid)
	p2_smes_set_charge(S, S.capacity)
	test_time(20 SECONDS)
	TEST_ASSERT(same_charge(p2_smes_charge(S), S.capacity), "a full hybrid stays full")

/// The RCON tag window: the console's list of units drops a deleted unit.
/datum/unit_test/dq_p2_smes/mf_rcon_list_drops_a_deleted_unit

/datum/unit_test/dq_p2_smes/mf_rcon_list_drops_a_deleted_unit/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/p2_test)
	S.RCon_tag = "MF_TEST"
	var/datum/tgui_module/rcon/R = new(S)
	TEST_ASSERT(S in p2_rcon_units(R), "the console lists the tagged unit")
	qdel(S)
	TEST_ASSERT(!(S in p2_rcon_units(R)), "a deleted unit leaves the list")
	qdel(R)

/// The failsafe wire pulsed twice inside a second drops the safety once and it comes back a second after the first pulse.
/datum/unit_test/dq_p2_smes/mf_failsafe_pulse_comes_back_once

/datum/unit_test/dq_p2_smes/mf_failsafe_pulse_comes_back_once/run_gate()
	var/obj/machinery/power/smes/buildable/S = p2_smes(/obj/machinery/power/smes/buildable/p2_test)
	var/datum/wires_test_adapter/W = p2_smes_wires(S)
	W.pulse(WIRE_SMES_FAILSAFES)
	TEST_ASSERT(!p2_smes_safeties(S), "pulsed: the safety is off")
	test_time(0.5 SECONDS)
	W.pulse(WIRE_SMES_FAILSAFES)
	TEST_ASSERT(!p2_smes_safeties(S), "pulsed again: still off")
	test_time(0.6 SECONDS)
	TEST_ASSERT(p2_smes_safeties(S), "a second after the first pulse it is back on")
	test_time(2 SECONDS)
	TEST_ASSERT(p2_smes_safeties(S), "a second later it is back on")

/// A grid checker's failure tells the units upstream to suspend (do_grid_check()).
/datum/unit_test/dq_p2_smes/mf_grid_checker_reaches_the_unit

/datum/unit_test/dq_p2_smes/mf_grid_checker_reaches_the_unit/run_gate()
	var/obj/machinery/power/smes/S = p2_smes()
	S.do_grid_check()
	TEST_ASSERT(S.grid_check, "the grid check suspends the unit")
