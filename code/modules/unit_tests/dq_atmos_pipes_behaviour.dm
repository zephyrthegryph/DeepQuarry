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

/datum/unit_test/dq_atmos_m/pipes/Run()
	..()
	for(var/datum/tgui/ui as anything in ap_windows)
		if(!QDELETED(ui))
			qdel(ui)
	ap_windows = null

/// A pipe device of `type` on the room's tile (dx, dy), powered, its pipes looked for. `access` (a list) locks it to that access.
/datum/unit_test/dq_atmos_m/pipes/proc/pipe_device(type, dx = 3, dy = 1, list/access)
	var/obj/machinery/atmospherics/D = allocate(type, tile(dx, dy))
	D.stat_remove(NOPOWER | BROKEN)
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
	sweep_pipe_items()
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
