// Behaviour tests for the pipe network's devices: the pumps, the regulator, the valves, the filters and mixers, the omni devices, the connector,
// the injector, the meter and the pipes themselves. They pin what a player, the radio or time can observe (clicks with a hand or a tool, ctrl- and
// alt-clicks, window buttons, radio packets, the gas in the pipes), so the same file passes before and after each device moves to the final forms.
//
// Rules the tests keep (as dq_atmos_machines_behaviour.dm's):
//   - Input goes through clicks (ap_click), window buttons (ap_press), answers (am_answer), radio packets (ap_radio) and time (am_settle).
//   - State is read through the adapter block below and plain vars.
//   - A test that pins a bug says so ("BUG:") and is flipped, with a line in doc/rewrite/intended_changes.md, in the commit that fixes it.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------------------------------------------------

/// The pressure pump's target, kPa.
/proc/ap_pump_target(obj/machinery/atmospherics/binary/pump/P)
	return P.get_target_pressure()

/// The pressure pump runs (its switch, as the window shows it).
/proc/ap_pump_on(obj/machinery/atmospherics/binary/pump/P)
	return !!P.use_power

/// The injector's own work happens once (what a gas tick of its flow does).
/proc/ap_injector_tick(obj/machinery/atmospherics/unary/outlet_injector/I)
	I.push_to_rust()
	SSair.rust_step_pipe_devices()
	SSair.run_gas_frames(1)

/// Time for a meter to follow its pipe's gas.
/proc/ap_meter_settle(obj/machinery/meter/M)
	var/before = M.needle
	for(var/i in 1 to 300)
		SSair.run_gas_frames(1)
		native_system().drain()
		if(M.needle != before)
			break
		stoplag()
	am_settle()

/// Time for the algae farm's own work (one service interval of it).
/proc/ap_algae_tick(obj/machinery/atmospherics/binary/algae_farm/F)
	var/was = F.working
	for(var/i in 1 to 300)
		SSair.run_gas_frames(1)
		native_system().drain()
		if(F.working != was)
			break
		stoplag()
	am_settle()

/// A radio command packet to a pipe device with radio tag `tag` (its `id`).
/proc/ap_radio(obj/machinery/atmospherics/D, tag, list/command)
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO
	signal.data = command.Copy()
	signal.data["tag"] = tag
	signal.data["sigtype"] = "command"
	D.receive_signal(signal, TRANSMISSION_RADIO, 0)
	qdel(signal)
	am_settle()

/// A click as ap_click() makes it; a type still on the legacy handlers (a tool's *_act(), click_ctrl(), click_alt()) is reached the way a
/// client's click reaches it once no op answers.
/proc/ap_click(mob/living/actor, atom/target, obj/item/held, gesture = GESTURE_CLICK)
	if(held && actor.get_active_hand() != held)
		if(actor.get_active_hand())
			actor.drop_item()
		actor.put_in_active_hand(held)
	else if(!held && actor.get_active_hand())
		actor.drop_item()
	actor.next_click = 0
	var/datum/op_result/R = test_click(actor, target, held, gesture)
	. = R
	if(!QDELETED(target) && (isnull(R) || (R.outcome & ACT_REFUSED) && R.reason == /datum/msg/op/not_available))
		switch(gesture)
			if(GESTURE_CLICK)
				if(held)
					held.resolve_attackby(target, actor)
			if(GESTURE_CTRL)
				actor.base_click_ctrl(target)
			if(GESTURE_ALT)
				actor.base_click_alt(target)
	am_settle()

/// A window button pressed in a window that stays open until the test ends (a question its button asks is answered against it).
/proc/ap_press(datum/unit_test/dq_atmos_m/pipes/T, mob/actor, datum/host, action, list/args)
	var/datum/tgui/ui = SStgui.get_open_ui(actor, host)
	if(!ui)
		ui = new(actor, host, "ApTest")
		ui.status = STATUS_INTERACTIVE
		ui.set_state(GLOB.tgui_always_state)
		SStgui.on_open(ui)
		LAZYADD(T.ap_windows, ui)
	var/datum/op_result/result = test_ui(actor, host, action, args)
	if(!result)
		result = host.tgui_act(action, args || list(), ui, ui.state())
	am_settle()
	return result

/// The click was refused (nothing ran, or what answered refused).
/proc/ap_refused(datum/op_result/R)
	return isnull(R) || (R.outcome & ACT_REFUSED)

// ---------------------------------------------------------------------------------------------------------------------
// Base
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_atmos_m/pipes
	abstract_type = /datum/unit_test/dq_atmos_m/pipes
	/// Windows ap_press() opened.
	var/list/ap_windows
	/// What pipe_line() built: taken down, pipes first, before the test's own sweep.
	var/list/ap_lines

/datum/unit_test/dq_atmos_m/pipes/Run()
	..()
	for(var/datum/tgui/ui as anything in ap_windows)
		if(!QDELETED(ui))
			qdel(ui)
	ap_windows = null

/// Takes down what pipe_line() built.
/datum/unit_test/dq_atmos_m/pipes/proc/take_down_lines()
	for(var/obj/machinery/atmospherics/pipe/P in ap_lines)
		if(!QDELETED(P))
			qdel(P)
	for(var/obj/machinery/atmospherics/M in ap_lines)
		if(!QDELETED(M))
			qdel(M)
	ap_lines = null
	sweep_pipe_items()

/// A pipe device of `type` on the room's tile (dx, dy), powered, its pipes looked for. `access` (a list) locks it to that access.
/datum/unit_test/dq_atmos_m/pipes/proc/pipe_device(type, dx = 3, dy = 1, list/access)
	var/obj/machinery/atmospherics/D = allocate(type, tile(dx, dy))
	D.set_grid_power(TRUE)
	D.set_broken_condition(FALSE)
	if(access)
		D.req_access = access.Copy()
	D.atmos_init()
	am_settle()
	return D

/// Clears what a wrench left on the room's floor.
/datum/unit_test/dq_atmos_m/pipes/proc/sweep_pipe_items()
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		for(var/obj/item/pipe/P in T)
			qdel(P)

// =====================================================================================================================
// The pressure pump
// =====================================================================================================================

/// The ctrl-click switches the pump for someone its access lets in, and only for them.
/datum/unit_test/dq_atmos_m/pipes/pump_ctrl_switch
/datum/unit_test/dq_atmos_m/pipes/pump_ctrl_switch/run_gate()
	var/obj/machinery/atmospherics/binary/pump/P = pipe_device(/obj/machinery/atmospherics/binary/pump, access = list(ACCESS_ATMOSPHERICS))
	var/mob/living/carbon/human/stranger = person(null, tile(2, 1))
	var/mob/living/carbon/human/tech = person(list(ACCESS_ATMOSPHERICS), tile(2, 2))
	ap_click(stranger, P, null, GESTURE_CTRL)
	TEST_ASSERT(!ap_pump_on(P), "a stranger's ctrl-click leaves it off")
	ap_click(tech, P, null, GESTURE_CTRL)
	TEST_ASSERT(ap_pump_on(P), "the technician's switches it on")
	ap_click(tech, P, null, GESTURE_CTRL)
	TEST_ASSERT(!ap_pump_on(P), "and off")

/// The alt-click sets the pump to its highest output, for someone its access lets in.
/datum/unit_test/dq_atmos_m/pipes/pump_alt_max
/datum/unit_test/dq_atmos_m/pipes/pump_alt_max/run_gate()
	var/obj/machinery/atmospherics/binary/pump/P = pipe_device(/obj/machinery/atmospherics/binary/pump, access = list(ACCESS_ATMOSPHERICS))
	var/mob/living/carbon/human/stranger = person(null, tile(2, 1))
	var/mob/living/carbon/human/tech = person(list(ACCESS_ATMOSPHERICS), tile(2, 2))
	var/before = ap_pump_target(P)
	ap_click(stranger, P, null, GESTURE_ALT)
	TEST_ASSERT_EQUAL(ap_pump_target(P), before, "a stranger's alt-click changes nothing")
	ap_click(tech, P, null, GESTURE_ALT)
	TEST_ASSERT_EQUAL(ap_pump_target(P), P.max_pressure_setting, "the technician's sets the highest output")

/// The window's buttons: the switch, and the target at its least and its most.
/datum/unit_test/dq_atmos_m/pipes/pump_window
/datum/unit_test/dq_atmos_m/pipes/pump_window/run_gate()
	var/obj/machinery/atmospherics/binary/pump/P = pipe_device(/obj/machinery/atmospherics/binary/pump)
	var/mob/living/carbon/human/H = person()
	ap_press(src, H, P, "power")
	TEST_ASSERT(ap_pump_on(P), "the power button switches it on")
	ap_press(src, H, P, "set_press", list("press" = "max"))
	TEST_ASSERT_EQUAL(ap_pump_target(P), P.max_pressure_setting, "max")
	ap_press(src, H, P, "set_press", list("press" = "min"))
	TEST_ASSERT_EQUAL(ap_pump_target(P), 0, "min")

/// The radio: power, the target, a toggle.
/datum/unit_test/dq_atmos_m/pipes/pump_radio
/datum/unit_test/dq_atmos_m/pipes/pump_radio/run_gate()
	var/obj/machinery/atmospherics/binary/pump/P = pipe_device(/obj/machinery/atmospherics/binary/pump)
	P.id = "ap_pump"
	ap_radio(P, "ap_pump", list("power" = "1"))
	TEST_ASSERT(ap_pump_on(P), "power 1 switches it on")
	ap_radio(P, "ap_pump", list("set_output_pressure" = "300"))
	TEST_ASSERT_EQUAL(ap_pump_target(P), 300, "the target is set")
	ap_radio(P, "ap_pump", list("power_toggle" = "1"))
	TEST_ASSERT(!ap_pump_on(P), "a toggle switches it off")
	ap_radio(P, "other", list("power" = "1"))
	TEST_ASSERT(!ap_pump_on(P), "another tag is ignored")

/// The wrench: a running pump is refused; a stopped one comes off as its pipe fitting.
/datum/unit_test/dq_atmos_m/pipes/pump_wrench
/datum/unit_test/dq_atmos_m/pipes/pump_wrench/run_gate()
	var/obj/machinery/atmospherics/binary/pump/on/P = pipe_device(/obj/machinery/atmospherics/binary/pump/on)
	var/mob/living/carbon/human/H = person()
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench)
	ap_click(H, P, W)
	TEST_ASSERT(!QDELETED(P), "a running pump is refused")
	P.set_use_power(USE_POWER_OFF)
	P.set_on(FALSE)
	ap_click(H, P, W)
	TEST_ASSERT(QDELETED(P), "a stopped one comes off")
	TEST_ASSERT_NOTNULL(locate(/obj/item/pipe) in tile(3, 1), "as its fitting")
	sweep_pipe_items()

// =====================================================================================================================
// The volumetric pump
// =====================================================================================================================

/// Ctrl-click switches it, alt-click sets its highest rate; both for someone its access lets in.
/datum/unit_test/dq_atmos_m/pipes/volume_pump_clicks
/datum/unit_test/dq_atmos_m/pipes/volume_pump_clicks/run_gate()
	var/obj/machinery/atmospherics/binary/volume_pump/P = pipe_device(/obj/machinery/atmospherics/binary/volume_pump, access = list(ACCESS_ATMOSPHERICS))
	var/mob/living/carbon/human/stranger = person(null, tile(2, 1))
	var/mob/living/carbon/human/tech = person(list(ACCESS_ATMOSPHERICS), tile(2, 2))
	ap_click(stranger, P, null, GESTURE_CTRL)
	TEST_ASSERT(!P.use_power, "a stranger's ctrl-click leaves it off")
	ap_click(stranger, P, null, GESTURE_ALT)
	TEST_ASSERT_EQUAL(P.transfer_rate, 20, "a stranger's alt-click leaves the rate")
	ap_click(tech, P, null, GESTURE_CTRL)
	TEST_ASSERT(P.use_power, "the technician's ctrl-click switches it on")
	ap_click(tech, P, null, GESTURE_ALT)
	TEST_ASSERT_EQUAL(P.transfer_rate, P.max_transfer_rate, "the technician's alt-click sets the highest rate")

/// The window: the switch and the rate; the multitool overclocks it and back; the wrench is refused while it runs.
/datum/unit_test/dq_atmos_m/pipes/volume_pump_window_and_tools
/datum/unit_test/dq_atmos_m/pipes/volume_pump_window_and_tools/run_gate()
	var/obj/machinery/atmospherics/binary/volume_pump/P = pipe_device(/obj/machinery/atmospherics/binary/volume_pump)
	var/mob/living/carbon/human/H = person()
	ap_press(src, H, P, "power")
	TEST_ASSERT(P.use_power, "the power button switches it on")
	ap_press(src, H, P, "set_press", list("press" = "max"))
	TEST_ASSERT_EQUAL(P.transfer_rate, P.max_transfer_rate, "max")
	ap_press(src, H, P, "set_press", list("press" = "min"))
	TEST_ASSERT_EQUAL(P.transfer_rate, 0, "min")
	var/obj/item/multitool/M = tool(/obj/item/multitool)
	ap_click(H, P, M)
	TEST_ASSERT(P.overclocked, "the multitool lifts its limiter")
	ap_click(H, P, M)
	TEST_ASSERT(!P.overclocked, "and puts it back")
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench)
	ap_click(H, P, W)
	TEST_ASSERT(!QDELETED(P), "a running pump is refused the wrench")
	P.set_use_power(USE_POWER_OFF)
	ap_click(H, P, W)
	TEST_ASSERT(QDELETED(P), "a stopped one comes off")
	sweep_pipe_items()

/// The radio: power and the rate.
/datum/unit_test/dq_atmos_m/pipes/volume_pump_radio
/datum/unit_test/dq_atmos_m/pipes/volume_pump_radio/run_gate()
	var/obj/machinery/atmospherics/binary/volume_pump/P = pipe_device(/obj/machinery/atmospherics/binary/volume_pump)
	P.id = "ap_vpump"
	ap_radio(P, "ap_vpump", list("power" = "1"))
	TEST_ASSERT(P.use_power, "power 1 switches it on")
	ap_radio(P, "ap_vpump", list("set_volume_rate" = "50"))
	TEST_ASSERT_EQUAL(P.transfer_rate, 50, "the rate is set")

// =====================================================================================================================
// The pressure regulator (passive gate)
// =====================================================================================================================

/// Its window: the valve, the regulation mode, the target and the flow limit.
/datum/unit_test/dq_atmos_m/pipes/passive_gate_window
/datum/unit_test/dq_atmos_m/pipes/passive_gate_window/run_gate()
	var/obj/machinery/atmospherics/binary/passive_gate/G = pipe_device(/obj/machinery/atmospherics/binary/passive_gate)
	var/mob/living/carbon/human/H = person()
	ap_press(src, H, G, "toggle_valve")
	TEST_ASSERT(G.unlocked, "the valve button opens it")
	ap_press(src, H, G, "regulate_mode", list("mode" = "input"))
	TEST_ASSERT_EQUAL(G.regulate_mode, 1, "input regulation")
	ap_press(src, H, G, "regulate_mode", list("mode" = "off"))
	TEST_ASSERT_EQUAL(G.regulate_mode, 0, "no regulation")
	ap_press(src, H, G, "set_press", list("press" = "max"))
	TEST_ASSERT_EQUAL(G.target_pressure, G.max_pressure_setting, "the target at its most")
	ap_press(src, H, G, "set_flow_rate", list("press" = "min"))
	TEST_ASSERT_EQUAL(G.set_flow_rate, 0, "the flow limit at its least")
	ap_press(src, H, G, "set_flow_rate", list("press" = "max"))
	TEST_ASSERT_EQUAL(G.set_flow_rate, G.air1.return_volume(), "and at its most, the input's volume")

/// Asked for a target, it takes the answer, clamped to its range.
/datum/unit_test/dq_atmos_m/pipes/passive_gate_asks_target
/datum/unit_test/dq_atmos_m/pipes/passive_gate_asks_target/run_gate()
	var/obj/machinery/atmospherics/binary/passive_gate/G = pipe_device(/obj/machinery/atmospherics/binary/passive_gate)
	var/mob/living/carbon/human/H = person()
	ap_press(src, H, G, "set_press", list("press" = "set"))
	am_answer(H, 250)
	TEST_ASSERT_EQUAL(G.target_pressure, 250, "the answer is the target")

/// The wrench: refused while its valve is open; closed, it comes off.
/datum/unit_test/dq_atmos_m/pipes/passive_gate_wrench
/datum/unit_test/dq_atmos_m/pipes/passive_gate_wrench/run_gate()
	var/obj/machinery/atmospherics/binary/passive_gate/on/G = pipe_device(/obj/machinery/atmospherics/binary/passive_gate/on)
	var/mob/living/carbon/human/H = person()
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench)
	ap_click(H, G, W)
	TEST_ASSERT(!QDELETED(G), "an open regulator is refused")
	G.set_unlocked(FALSE)
	ap_click(H, G, W)
	TEST_ASSERT(QDELETED(G), "a closed one comes off")
	sweep_pipe_items()

/// The radio: the valve, the target, the mode and the flow limit.
/datum/unit_test/dq_atmos_m/pipes/passive_gate_radio
/datum/unit_test/dq_atmos_m/pipes/passive_gate_radio/run_gate()
	var/obj/machinery/atmospherics/binary/passive_gate/G = pipe_device(/obj/machinery/atmospherics/binary/passive_gate)
	G.id = "ap_gate"
	ap_radio(G, "ap_gate", list("power" = "1", "set_target_pressure" = "400", "set_regulate_mode" = "1", "set_flow_rate" = "100"))
	TEST_ASSERT(G.unlocked, "opened")
	TEST_ASSERT_EQUAL(G.target_pressure, 400, "target")
	TEST_ASSERT_EQUAL(G.regulate_mode, 1, "mode")
	TEST_ASSERT_EQUAL(G.set_flow_rate, 100, "flow limit")

// =====================================================================================================================
// The valves
// =====================================================================================================================

/// A sealed line along the room's row `dy`: an end cap, a simple pipe, `middle` (facing east), a simple pipe, an end cap (dx 0 to 4); joined and
/// published to Rust. Returns the pipe, the middle and the pipe.
/datum/unit_test/dq_atmos_m/pipes/proc/pipe_line(middle, dy = 3, list/access)
	var/list/made = list()
	var/list/types = list(/obj/machinery/atmospherics/pipe/cap/visible, /obj/machinery/atmospherics/pipe/simple/visible, middle, /obj/machinery/atmospherics/pipe/simple/visible, /obj/machinery/atmospherics/pipe/cap/visible)
	for(var/i in 1 to 5)
		var/obj/machinery/atmospherics/M = allocate(types[i], tile(i - 1, dy))
		M.set_dir(i == 5 ? WEST : EAST)
		M.init_dir()
		M.set_grid_power(TRUE)
		M.set_broken_condition(FALSE)
		made += M
	var/list/inner = made.Copy(2, 5)
	if(access)
		var/obj/machinery/atmospherics/V = inner[2]
		V.req_access = access.Copy()
	for(var/obj/machinery/atmospherics/M as anything in made)
		M.atmos_init()
	dq_atmos_test_publish_rust_pipenets(made)
	LAZYADD(ap_lines, made)
	am_settle()
	return inner

/// A hand turns a manual valve's wheel: it opens, and turns back shut.
/datum/unit_test/dq_atmos_m/pipes/valve_hand
/datum/unit_test/dq_atmos_m/pipes/valve_hand/run_gate()
	var/list/line = pipe_line(/obj/machinery/atmospherics/valve)
	var/obj/machinery/atmospherics/valve/V = line[2]
	var/mob/living/carbon/human/H = person(null, tile(2, 2))
	ap_click(H, V)
	TEST_ASSERT(V.open, "the wheel opens it")
	ap_click(H, V)
	TEST_ASSERT(!V.open, "and shuts it")
	take_down_lines()


/// A digital valve turns for someone its access lets in; its radio opens, shuts and toggles it.
/datum/unit_test/dq_atmos_m/pipes/valve_digital
/datum/unit_test/dq_atmos_m/pipes/valve_digital/run_gate()
	var/list/line = pipe_line(/obj/machinery/atmospherics/valve/digital, access = list(ACCESS_ATMOSPHERICS))
	var/obj/machinery/atmospherics/valve/digital/V = line[2]
	var/mob/living/carbon/human/stranger = person(null, tile(2, 2))
	var/mob/living/carbon/human/tech = person(list(ACCESS_ATMOSPHERICS), tile(1, 2))
	ap_click(stranger, V)
	TEST_ASSERT(!V.open, "a stranger cannot turn it")
	ap_click(tech, V)
	TEST_ASSERT(V.open, "the technician opens it")
	V.id = "ap_valve"
	ap_radio(V, "ap_valve", list("command" = "valve_close"))
	TEST_ASSERT(!V.open, "the radio shuts it")
	ap_radio(V, "ap_valve", list("command" = "valve_toggle"))
	TEST_ASSERT(V.open, "and toggles it")
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench, tile(2, 2))
	ap_click(stranger, V, W)
	TEST_ASSERT(!QDELETED(V), "a stranger cannot wrench a digital valve off")
	take_down_lines()


/// An open valve joins its two sides: gas put on one side reaches the other.
/datum/unit_test/dq_atmos_m/pipes/valve_joins_sides
/datum/unit_test/dq_atmos_m/pipes/valve_joins_sides/run_gate()
	var/list/line = pipe_line(/obj/machinery/atmospherics/valve)
	var/obj/machinery/atmospherics/pipe/left = line[1]
	var/obj/machinery/atmospherics/valve/V = line[2]
	var/obj/machinery/atmospherics/pipe/right = line[3]
	var/datum/gas_mixture/left_air = left.return_air()
	var/datum/gas_mixture/right_air = right.return_air()
	left_air.adjust_gas(GAS_N2, 10)
	gas_touched(left_air)
	am_settle()
	TEST_ASSERT(right_air.total_moles() < 0.01, "shut, the far side stays empty")
	var/mob/living/carbon/human/H = person(null, tile(2, 2))
	ap_click(H, V)
	am_settle()
	right_air = right.return_air()
	TEST_ASSERT(right_air.total_moles() > 1, "open, the gas reaches it ([right_air.total_moles()])")
	take_down_lines()


/// The wrench takes a manual valve off.
/datum/unit_test/dq_atmos_m/pipes/valve_wrench
/datum/unit_test/dq_atmos_m/pipes/valve_wrench/run_gate()
	var/list/line = pipe_line(/obj/machinery/atmospherics/valve)
	var/obj/machinery/atmospherics/valve/V = line[2]
	var/mob/living/carbon/human/H = person(null, tile(2, 2))
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench, tile(2, 2))
	ap_click(H, V, W)
	TEST_ASSERT(QDELETED(V), "it comes off")
	take_down_lines()


/// A three-way valve's wheel moves it between straight and the side branch; a digital one asks for access.
/datum/unit_test/dq_atmos_m/pipes/tvalve_hand
/datum/unit_test/dq_atmos_m/pipes/tvalve_hand/run_gate()
	var/obj/machinery/atmospherics/tvalve/T = pipe_device(/obj/machinery/atmospherics/tvalve)
	var/obj/machinery/atmospherics/tvalve/digital/D = pipe_device(/obj/machinery/atmospherics/tvalve/digital, 1, 3, access = list(ACCESS_ATMOSPHERICS))
	var/mob/living/carbon/human/stranger = person(null, tile(2, 2))
	var/start = T.state
	ap_click(stranger, T)
	TEST_ASSERT(T.state != start, "the wheel moves it")
	var/dstart = D.state
	ap_click(stranger, D)
	TEST_ASSERT_EQUAL(D.state, dstart, "a stranger cannot move a digital one")
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench, tile(2, 2))
	ap_click(stranger, T, W)
	TEST_ASSERT(QDELETED(T), "the wrench takes it off")
	sweep_pipe_items()

/// The automatic shutoff valve: a hand switches its circuit; with the circuit off, an alt-click turns it by hand; with it on, the valve
/// shuts on a leak it can see and opens once it is sealed.
/datum/unit_test/dq_atmos_m/pipes/shutoff_valve
/datum/unit_test/dq_atmos_m/pipes/shutoff_valve/run_gate()
	var/list/line = pipe_line(/obj/machinery/atmospherics/valve/shutoff)
	var/obj/machinery/atmospherics/pipe/left = line[1]
	var/obj/machinery/atmospherics/valve/shutoff/V = line[2]
	TEST_ASSERT(V.open, "it starts open")
	left.damaged_leak = TRUE
	left.handle_leaking()
	am_settle()
	TEST_ASSERT(!V.open, "a leak beside it shuts it")
	left.damaged_leak = FALSE
	left.handle_leaking()
	am_settle()
	TEST_ASSERT(V.open, "sealed, it opens")
	var/mob/living/carbon/human/H = person(null, tile(2, 2))
	ap_click(H, V, null, GESTURE_ALT)
	TEST_ASSERT(V.open, "while the circuit is on, the hand cannot shut it")
	ap_click(H, V)
	TEST_ASSERT(!V.close_on_leaks, "a hand switches the circuit off")
	ap_click(H, V, null, GESTURE_ALT)
	TEST_ASSERT(!V.open, "and then an alt-click shuts it")
	ap_click(H, V, null, GESTURE_ALT)
	TEST_ASSERT(V.open, "and opens it")
	take_down_lines()

// =====================================================================================================================
// The filters and mixers
// =====================================================================================================================

/// A trinary filter's window: the switch, the rate (a number and "max") and the gas it takes out; its ctrl-click switch asks for access; the
/// wrench takes it off whether it runs or not.
/datum/unit_test/dq_atmos_m/pipes/trinary_filter
/datum/unit_test/dq_atmos_m/pipes/trinary_filter/run_gate()
	var/obj/machinery/atmospherics/trinary/atmos_filter/F = pipe_device(/obj/machinery/atmospherics/trinary/atmos_filter, access = list(ACCESS_ATMOSPHERICS))
	var/mob/living/carbon/human/stranger = person(null, tile(2, 1))
	var/mob/living/carbon/human/tech = person(list(ACCESS_ATMOSPHERICS), tile(2, 2))
	ap_press(src, tech, F, "rate", list("rate" = 50))
	TEST_ASSERT_EQUAL(F.set_flow_rate, 50, "a rate")
	ap_press(src, tech, F, "rate", list("rate" = "max"))
	TEST_ASSERT_EQUAL(F.set_flow_rate, F.air1.return_volume(), "the highest rate")
	ap_press(src, tech, F, "filter", list("filterset" = 1))
	TEST_ASSERT_EQUAL(F.filter_type, 1, "oxygen")
	var/was = F.use_power
	ap_click(stranger, F, null, GESTURE_CTRL)
	TEST_ASSERT_EQUAL(F.use_power, was, "a stranger's ctrl-click changes nothing")
	ap_click(tech, F, null, GESTURE_CTRL)
	TEST_ASSERT(F.use_power != was, "the technician's switches it")
	F.set_use_power(USE_POWER_IDLE)
	ap_click(tech, F, tool(/obj/item/tool/wrench, tile(2, 2)))
	TEST_ASSERT(QDELETED(F), "the wrench takes it off, running")
	sweep_pipe_items()

/// A trinary mixer's window: the switch, the rate and the two shares (each sets the other to the rest).
/datum/unit_test/dq_atmos_m/pipes/trinary_mixer
/datum/unit_test/dq_atmos_m/pipes/trinary_mixer/run_gate()
	var/obj/machinery/atmospherics/trinary/mixer/M = pipe_device(/obj/machinery/atmospherics/trinary/mixer)
	var/mob/living/carbon/human/H = person()
	ap_press(src, H, M, "pressure", list("pressure" = 100))
	TEST_ASSERT_EQUAL(M.set_flow_rate, 100, "a rate")
	ap_press(src, H, M, "node1", list("concentration" = 30))
	TEST_ASSERT(abs(M.node1_concentration - 0.3) < 0.001 && abs(M.node2_concentration - 0.7) < 0.001, "node 1 at 30%, node 2 the rest")
	ap_press(src, H, M, "node2", list("concentration" = 80))
	TEST_ASSERT(abs(M.node2_concentration - 0.8) < 0.001 && abs(M.node1_concentration - 0.2) < 0.001, "node 2 at 80%, node 1 the rest")
	var/was = M.use_power
	ap_press(src, H, M, "power")
	TEST_ASSERT(M.use_power != was, "the power button switches it")

/// An omni filter: the power button runs it; configuring stops it; the rate is asked for only while configuring; the ctrl-click switch.
/datum/unit_test/dq_atmos_m/pipes/omni_filter
/datum/unit_test/dq_atmos_m/pipes/omni_filter/run_gate()
	var/obj/machinery/atmospherics/omni/atmos_filter/F = pipe_device(/obj/machinery/atmospherics/omni/atmos_filter)
	var/mob/living/carbon/human/H = person()
	F.set_use_power(USE_POWER_OFF)
	ap_press(src, H, F, "power")
	TEST_ASSERT(F.use_power, "the power button runs it")
	ap_press(src, H, F, "configure")
	TEST_ASSERT(F.configuring && !F.use_power, "configuring stops it")
	ap_press(src, H, F, "set_flow_rate")
	am_answer(H, 120)
	TEST_ASSERT_EQUAL(F.set_flow_rate, 120, "the rate is asked for while configuring")
	ap_press(src, H, F, "configure")
	ap_click(H, F, null, GESTURE_CTRL)
	TEST_ASSERT(F.use_power, "the ctrl-click runs it")
	ap_click(H, F, tool(/obj/item/tool/wrench))
	TEST_ASSERT(QDELETED(F), "the wrench takes it off")
	sweep_pipe_items()

/// An omni mixer: the same switch and configuring, and the rate asked for while configuring.
/datum/unit_test/dq_atmos_m/pipes/omni_mixer
/datum/unit_test/dq_atmos_m/pipes/omni_mixer/run_gate()
	var/obj/machinery/atmospherics/omni/mixer/M = pipe_device(/obj/machinery/atmospherics/omni/mixer)
	var/mob/living/carbon/human/H = person()
	M.set_use_power(USE_POWER_OFF)
	ap_press(src, H, M, "power")
	TEST_ASSERT(M.use_power, "the power button runs it")
	ap_press(src, H, M, "configure")
	TEST_ASSERT(M.configuring && !M.use_power, "configuring stops it")
	ap_press(src, H, M, "set_flow_rate")
	am_answer(H, 90)
	TEST_ASSERT_EQUAL(M.set_flow_rate, 90, "the rate is asked for while configuring")
	ap_press(src, H, M, "configure")
	ap_click(H, M, null, GESTURE_CTRL)
	TEST_ASSERT(M.use_power, "the ctrl-click runs it")

// =====================================================================================================================
// The connector
// =====================================================================================================================

/// A canister on a connector shares its gas with the connector's pipe; the connector cannot be wrenched off while it holds one, and comes off
/// once it is let go.
/datum/unit_test/dq_atmos_m/pipes/connector_shares_gas
/datum/unit_test/dq_atmos_m/pipes/connector_shares_gas/run_gate()
	var/list/line = pipe_line(/obj/machinery/atmospherics/portables_connector)
	var/obj/machinery/atmospherics/portables_connector/port = line[2]
	var/obj/machinery/atmospherics/pipe/left = line[3] // the connector faces east: its one pipe
	var/obj/machinery/portable_atmospherics/canister/nitrogen/C = allocate(/obj/machinery/portable_atmospherics/canister/nitrogen, tile(2, 3))
	var/mob/living/carbon/human/H = person(null, tile(2, 2))
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench, tile(2, 2))
	if(!C.connected_port)
		ap_click(H, C, W)
	TEST_ASSERT_EQUAL(C.connected_port, port, "the canister is on the port")
	SSair.run_gas_frames(2)
	var/datum/gas_mixture/pipe_air = left.return_air()
	TEST_ASSERT(pipe_air.total_moles() > 1, "its gas reaches the pipe ([pipe_air.total_moles()])")
	ap_click(H, port, W)
	TEST_ASSERT(!QDELETED(port), "the port holding a canister cannot be wrenched off")
	ap_click(H, C, W)
	TEST_ASSERT(isnull(C.connected_port), "the canister is let go")
	var/canister_moles = C.air_contents.total_moles()
	TEST_ASSERT(canister_moles > 1, "and keeps its share ([canister_moles])")
	qdel(C)
	take_down_lines()

// =====================================================================================================================
// The outlet injector
// =====================================================================================================================

/// A hand switches the injector; the radio sets its power and rate; its multitool sets its tag and frequency; a ctrl-click on a running
/// injector with another rate puts the rate back to its default; the wrench takes it off.
/datum/unit_test/dq_atmos_m/pipes/injector_controls
/datum/unit_test/dq_atmos_m/pipes/injector_controls/run_gate()
	var/obj/machinery/atmospherics/unary/outlet_injector/I = pipe_device(/obj/machinery/atmospherics/unary/outlet_injector)
	var/mob/living/carbon/human/H = person()
	ap_click(H, I)
	TEST_ASSERT(I.use_power, "a hand switches it on")
	ap_click(H, I)
	TEST_ASSERT(!I.use_power, "and off")
	I.id = "ap_inj"
	ap_radio(I, "ap_inj", list("power" = "1", "set_volume_rate" = "30"))
	TEST_ASSERT(I.use_power, "the radio switches it on")
	TEST_ASSERT_EQUAL(I.volume_rate, 30, "and sets its rate")
	ap_click(H, I, null, GESTURE_CTRL)
	TEST_ASSERT_EQUAL(I.volume_rate, ATMOS_DEFAULT_VOLUME_PUMP + 500, "a ctrl-click puts the rate back")
	var/obj/item/multitool/M = tool(/obj/item/multitool)
	ap_click(H, I, M)
	am_answer(H, "ID Tag")
	am_answer(H, "ap_new_inj")
	TEST_ASSERT_EQUAL(I.id, "ap_new_inj", "the multitool sets its tag")
	ap_click(H, I, M)
	am_answer(H, "Frequency")
	am_answer(H, 1441)
	TEST_ASSERT_EQUAL(I.frequency, 1441, "and its frequency")
	ap_click(H, I, tool(/obj/item/tool/wrench))
	TEST_ASSERT(QDELETED(I), "the wrench takes it off")
	sweep_pipe_items()

/// A running injector puts its pipe's gas into the room.
/datum/unit_test/dq_atmos_m/pipes/injector_injects
/datum/unit_test/dq_atmos_m/pipes/injector_injects/run_gate()
	var/list/run = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(run, "no clear two-tile pipe run")
	var/turf/simulated/floor/T = run[1]
	var/turf/simulated/floor/pipe_turf = run[2]
	var/direction = get_dir(T, pipe_turf)
	dq_atmos_test_isolate_pair(T, pipe_turf)
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_snapshot_air(pipe_turf)
	am_set_air(T)
	am_set_air(pipe_turf)
	var/obj/machinery/atmospherics/unary/outlet_injector/I = allocate(/obj/machinery/atmospherics/unary/outlet_injector, T)
	I.set_dir(direction)
	I.init_dir()
	var/obj/machinery/atmospherics/pipe/cap/visible/P = allocate(/obj/machinery/atmospherics/pipe/cap/visible, pipe_turf)
	P.set_dir(REVERSE_DIR(direction))
	P.init_dir()
	I.atmos_init()
	P.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(I, P))
	I.set_grid_power(TRUE)
	I.set_broken_condition(FALSE)
	I.air_contents.adjust_gas(GAS_N2, 200)
	gas_touched(I.air_contents)
	var/before = T.return_air().total_moles()
	I.set_use_power(USE_POWER_IDLE)
	for(var/i in 1 to 5)
		ap_injector_tick(I)
	TEST_ASSERT(T.return_air().total_moles() > before + 1, "the room gains its gas: [before] -> [T.return_air().total_moles()]")
	qdel(P)
	qdel(I)
	am_set_air(T)
	am_set_air(pipe_turf)
	dq_atmos_test_restore_walls()

// =====================================================================================================================
// The heater and the freezer
// =====================================================================================================================

/// A unary device of `type` on a capped pipe in the room: returns it (its pipe is the cap on the tile east of it).
/datum/unit_test/dq_atmos_m/pipes/proc/capped_device(type, dx = 1, dy = 4)
	var/obj/machinery/atmospherics/unary/U = allocate(type, tile(dx, dy))
	U.set_dir(EAST)
	U.init_dir()
	var/obj/machinery/atmospherics/pipe/cap/visible/P = allocate(/obj/machinery/atmospherics/pipe/cap/visible, tile(dx + 1, dy))
	P.set_dir(WEST)
	P.init_dir()
	U.atmos_init()
	P.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(U, P))
	U.set_grid_power(TRUE)
	U.set_broken_condition(FALSE)
	LAZYADD(ap_lines, list(P, U))
	am_settle()
	return U

/// Switched on with cold gas in its loop, a heater heats it toward its thermostat; switched off, it stops.
/datum/unit_test/dq_atmos_m/pipes/heater_heats
/datum/unit_test/dq_atmos_m/pipes/heater_heats/run_gate()
	var/obj/machinery/atmospherics/unary/heater/U = capped_device(/obj/machinery/atmospherics/unary/heater)
	var/mob/living/carbon/human/H = person()
	U.air_contents.adjust_gas(GAS_N2, 50)
	heat_set(U.air_contents, 250, HEAT_SOURCE_OTHER)
	gas_touched(U.air_contents)
	ap_press(src, H, U, "setGasTemperature", list("temp" = 400))
	ap_press(src, H, U, "toggleStatus")
	TEST_ASSERT(U.use_power, "the button switches it on")
	for(var/i in 1 to 6)
		am_settle()
		SSair.run_gas_frames(1)
	TEST_ASSERT(U.air_contents.return_temperature() > 255, "it heats its loop ([U.air_contents.return_temperature()] K)")
	ap_press(src, H, U, "toggleStatus")
	am_settle()
	TEST_ASSERT(!U.pumping, "switched off, it stops")
	take_down_lines()

/// A freezer cools its loop toward its thermostat.
/datum/unit_test/dq_atmos_m/pipes/freezer_cools
/datum/unit_test/dq_atmos_m/pipes/freezer_cools/run_gate()
	var/obj/machinery/atmospherics/unary/freezer/U = capped_device(/obj/machinery/atmospherics/unary/freezer)
	var/mob/living/carbon/human/H = person()
	U.air_contents.adjust_gas(GAS_N2, 50)
	heat_set(U.air_contents, T20C, HEAT_SOURCE_OTHER)
	gas_touched(U.air_contents)
	ap_press(src, H, U, "setGasTemperature", list("temp" = 100))
	ap_press(src, H, U, "toggleStatus")
	for(var/i in 1 to 6)
		am_settle()
		SSair.run_gas_frames(1)
	TEST_ASSERT(U.air_contents.return_temperature() < T20C - 5, "it cools its loop ([U.air_contents.return_temperature()] K)")
	take_down_lines()

// =====================================================================================================================
// The pipes
// =====================================================================================================================

/// A welder seals a pipe's fatigue crack; a wrench takes a visible pipe off as its fitting.
/datum/unit_test/dq_atmos_m/pipes/pipe_weld_and_wrench
/datum/unit_test/dq_atmos_m/pipes/pipe_weld_and_wrench/run_gate()
	var/list/line = pipe_line(/obj/machinery/atmospherics/pipe/simple/visible)
	var/obj/machinery/atmospherics/pipe/P = line[2]
	var/mob/living/carbon/human/H = person(null, tile(2, 2))
	P.damaged_leak = TRUE
	P.handle_leaking()
	TEST_ASSERT(P.leaking, "a cracked pipe leaks")
	ap_click(H, P, welder(tile(2, 2)))
	TEST_ASSERT(!P.damaged_leak && !P.leaking, "the welder seals it")
	ap_click(H, P, tool(/obj/item/tool/wrench, tile(2, 2)))
	TEST_ASSERT(QDELETED(P), "the wrench takes it off")
	TEST_ASSERT_NOTNULL(locate(/obj/item/pipe) in tile(2, 3), "as its fitting")
	take_down_lines()

// =====================================================================================================================
// The meter
// =====================================================================================================================

/// The meter on a pipe: its needle follows the pipe's pressure; a screwdriver opens its panel, a multitool then sets its tag; a wrench takes it
/// off as its item.
/datum/unit_test/dq_atmos_m/pipes/meter
/datum/unit_test/dq_atmos_m/pipes/meter/run_gate()
	var/list/line = pipe_line(/obj/machinery/atmospherics/pipe/simple/visible)
	var/obj/machinery/atmospherics/pipe/P = line[2]
	var/obj/machinery/meter/M = allocate(/obj/machinery/meter, P.loc)
	M.set_grid_power(TRUE)
	M.set_broken_condition(FALSE)
	M.set_target(P)
	var/datum/gas_mixture/air = P.return_air()
	air.adjust_gas(GAS_N2, 2000)
	gas_touched(air)
	ap_meter_settle(M)
	TEST_ASSERT(M.icon_state != "meterX" && M.icon_state != "meter0", "the needle shows the pipe's pressure ([M.icon_state])")
	var/mob/living/carbon/human/H = person(null, tile(2, 2))
	ap_click(H, M, tool(/obj/item/tool/screwdriver, tile(2, 2)))
	TEST_ASSERT(M.open, "the screwdriver opens its panel")
	ap_click(H, M, tool(/obj/item/multitool, tile(2, 2)))
	am_answer(H, "ap_meter")
	TEST_ASSERT_EQUAL(M.id, "ap_meter", "the multitool sets its tag")
	ap_click(H, M, tool(/obj/item/tool/wrench, tile(2, 2)))
	TEST_ASSERT(QDELETED(M), "the wrench takes it off")
	TEST_ASSERT_NOTNULL(locate(/obj/item/pipe_meter) in P.loc, "as its item")
	for(var/obj/item/pipe_meter/I in P.loc)
		qdel(I)
	take_down_lines()

// =====================================================================================================================
// Pipe fittings
// =====================================================================================================================

/// A wrench fastens a pipe fitting into its pipe (joined to the pipe beside it), and a meter onto that pipe; a fitting where a pipe already runs
/// is refused.
/datum/unit_test/dq_atmos_m/pipes/fitting_fastens
/datum/unit_test/dq_atmos_m/pipes/fitting_fastens/run_gate()
	var/list/line = pipe_line(/obj/machinery/atmospherics/pipe/simple/visible)
	var/obj/machinery/atmospherics/pipe/right = line[3]
	var/mob/living/carbon/human/H = person(null, tile(4, 2))
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench, tile(4, 2))
	qdel(locate(/obj/machinery/atmospherics/pipe/cap) in tile(4, 3))
	am_settle()
	var/obj/item/pipe/F = new /obj/item/pipe/binary/bendable(tile(4, 3), /obj/machinery/atmospherics/pipe/simple/visible, EAST)
	F.setPipingLayer(PIPING_LAYER_REGULAR)
	var/datum/op_result/R = ap_click(H, F, W)
	TEST_ASSERT(QDELETED(F), "the fitting is fastened ([R?.outcome] [R?.key] [R?.reason])")
	var/obj/machinery/atmospherics/pipe/simple/visible/built = locate() in tile(4, 3)
	TEST_ASSERT_NOTNULL(built, "into its pipe")
	TEST_ASSERT(built.node1 == right || built.node2 == right, "joined to the pipe beside it")
	var/obj/item/pipe/second = new /obj/item/pipe/binary/bendable(tile(4, 3), /obj/machinery/atmospherics/pipe/simple/visible, EAST)
	second.setPipingLayer(PIPING_LAYER_REGULAR)
	ap_click(H, second, W)
	TEST_ASSERT(!QDELETED(second), "a fitting where a pipe already runs is refused")
	qdel(second)
	var/obj/item/pipe_meter/M = new(tile(4, 3))
	M.setAttachLayer(PIPING_LAYER_REGULAR)
	ap_click(H, M, W)
	TEST_ASSERT(QDELETED(M), "a meter item fastens onto the pipe")
	for(var/obj/machinery/meter/placed in tile(4, 3))
		qdel(placed)
	qdel(built)
	take_down_lines()

// =====================================================================================================================
// The algae farm
// =====================================================================================================================

/// Switched on with algae and carbon dioxide on its input, the farm turns the CO2 into oxygen on its output and graphite in its store; out of
/// CO2 it stops, and new CO2 starts it again.
/datum/unit_test/dq_atmos_m/pipes/algae_farm_converts
/datum/unit_test/dq_atmos_m/pipes/algae_farm_converts/run_gate()
	var/list/line = pipe_line(/obj/machinery/atmospherics/binary/algae_farm/filled)
	var/obj/machinery/atmospherics/binary/algae_farm/filled/F = line[2]
	var/mob/living/carbon/human/H = person()
	F.air1.adjust_gas(GAS_CO2, 5)
	gas_touched(F.air1)
	ap_press(src, H, F, "toggle")
	TEST_ASSERT_EQUAL(F.use_power, USE_POWER_ACTIVE, "the button switches its grow lights on")
	for(var/i in 1 to 3)
		ap_algae_tick(F)
	TEST_ASSERT(F.air2.get_moles(GAS_O2) > 0.5, "oxygen comes out ([F.air2.get_moles(GAS_O2)])")
	TEST_ASSERT(F.stored_material[MAT_GRAPHITE] > 0, "graphite is stored")
	var/algae = F.stored_material[MAT_ALGAE]
	F.air1.adjust_gas(GAS_CO2, -F.air1.get_moles(GAS_CO2))
	gas_touched(F.air1)
	for(var/i in 1 to 3)
		ap_algae_tick(F)
	TEST_ASSERT(F.ui_error, "out of CO2 it says so")
	var/algae_idle = F.stored_material[MAT_ALGAE]
	ap_algae_tick(F)
	TEST_ASSERT_EQUAL(F.stored_material[MAT_ALGAE], algae_idle, "and uses no algae")
	F.air1.adjust_gas(GAS_CO2, 5)
	gas_touched(F.air1)
	for(var/i in 1 to 3)
		ap_algae_tick(F)
	TEST_ASSERT(F.stored_material[MAT_ALGAE] < algae_idle, "new CO2 starts it again")
	take_down_lines()

// =====================================================================================================================
// The gas turbine
// =====================================================================================================================

/// Bolted down with a pressure head across it, a turbine spins up and its two sides draw together; unbolted, it stops.
/datum/unit_test/dq_atmos_m/pipes/turbine_spins
/datum/unit_test/dq_atmos_m/pipes/turbine_spins/run_gate()
	var/obj/machinery/atmospherics/pipeturbine/T = allocate(/obj/machinery/atmospherics/pipeturbine, tile(3, 3))
	var/mob/living/carbon/human/H = person(null, tile(2, 3))
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench, tile(2, 3))
	T.air_in.adjust_gas(GAS_N2, 200)
	heat_set(T.air_in, T20C, HEAT_SOURCE_OTHER)
	var/head = T.air_in.return_pressure() - T.air_out.return_pressure()
	ap_click(H, T, W)
	TEST_ASSERT(T.anchored, "the wrench bolts it down")
	for(var/i in 1 to 3)
		am_settle()
	TEST_ASSERT(T.kin_energy > 0, "the head spins it ([T.kin_energy])")
	var/after = T.air_in.return_pressure() - T.air_out.return_pressure()
	TEST_ASSERT(abs(after) < head * 0.1, "and draws its sides together ([head] kPa -> [after] kPa)")
	ap_click(H, T, W)
	TEST_ASSERT(!T.anchored, "the wrench frees it")

// =====================================================================================================================
// Heat-exchanging pipes
// =====================================================================================================================

/// A run of heat-exchanging pipes whose gas turns hot starts glowing (its sleeping glow watch wakes it), and settles once it shows its gas.
/datum/unit_test/dq_atmos_m/pipes/he_pipe_glows
/datum/unit_test/dq_atmos_m/pipes/he_pipe_glows/run_gate()
	var/list/made = list()
	for(var/i in 1 to 3)
		var/obj/machinery/atmospherics/pipe/simple/heat_exchanging/P = allocate(/obj/machinery/atmospherics/pipe/simple/heat_exchanging, tile(i, 3))
		P.set_dir(EAST)
		P.init_dir()
		made += P
	for(var/obj/machinery/atmospherics/M as anything in made)
		M.atmos_init()
	dq_atmos_test_publish_rust_pipenets(made)
	LAZYADD(ap_lines, made)
	am_settle()
	var/obj/machinery/atmospherics/pipe/simple/heat_exchanging/middle = made[2]
	TEST_ASSERT_NOTNULL(middle.parent, "the run is one pipeline")
	TEST_ASSERT(!middle.tending, "cool, it has nothing to do")
	var/datum/gas_mixture/air = middle.parent.air
	air.adjust_gas(GAS_N2, 20)
	heat_set(air, 1200, HEAT_SOURCE_OTHER)
	gas_touched(air)
	for(var/i in 1 to 60)
		SSair.run_gas_frames(1)
		native_system().drain()
		if(middle.icon_temperature > 500)
			break
		stoplag()
		am_settle()
	TEST_ASSERT(middle.icon_temperature > 500, "hot, it glows ([middle.icon_temperature] K)")
	take_down_lines()
