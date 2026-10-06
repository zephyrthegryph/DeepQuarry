// Behaviour tests for the atmospherics machines a player meets in a room: the air alarm, the vent pump and the scrubber it drives, the
// portable canister and the remote atmospherics control console. They pin what a player, a silicon or the radio can observe (clicks, window
// buttons, questions answered, radio commands, time, the gas in the room), so the same file passes before and after the machines move to the
// final forms (doc/rewrite/conversion_guide.md section 2).
//
// Rules the tests keep:
//   - Input goes through clicks (am_click), window buttons (am_press), answers (am_answer), radio packets (am_radio) and time (am_settle / the
//     adapters below that make a machine's own periodic work happen); never an op key.
//   - State is read through the adapter block below (the only place that names today's accessors) and plain vars.
//   - A test that pins a bug says so ("BUG:") and is flipped, with a line in doc/rewrite/intended_changes.md, in the commit that fixes it.

// The air alarm's modes, as the window and the wires send them.
#define AM_MODE_SCRUBBING 1
#define AM_MODE_REPLACEMENT 2
#define AM_MODE_PANIC 3
#define AM_MODE_CYCLE 4
#define AM_MODE_FILL 5
#define AM_MODE_OFF 6

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: today's accessors, wrapped. After the conversion only these bodies change.
// ---------------------------------------------------------------------------------------------------------------------

/// The alarm's interface lock is engaged.
/proc/am_alarm_locked(obj/machinery/alarm/A)
	return !!lock_locked(A)

/// Engages or releases the alarm's interface lock (a test fixture's starting state).
/proc/am_alarm_set_locked(obj/machinery/alarm/A, on)
	cap_key_set(A, LOCK_LOCKED, !!on, null)

/// The alarm's maintenance panel is open.
/proc/am_alarm_panel_open(obj/machinery/alarm/A)
	return !!panel_open(A)

/// The alarm's thermostat is working the room: 0 idle, 1 cooling, 2 heating.
/proc/am_alarm_regulating(obj/machinery/alarm/A)
	return A.regulating_temperature

/// One threshold row of the alarm (red min, yellow min, yellow max, red max).
/proc/am_alarm_tlv(obj/machinery/alarm/A, env)
	var/list/row = A.TLV[env]
	return row?.Copy()

/// The alarm's own periodic work happens once (its scan of the room and its thermostat), as one machine service interval does: only the area's
/// working main alarm scans.
/proc/am_alarm_tick(obj/machinery/alarm/A)
	A.scan_room(null)
	test_drain()
	vg_heat_net_advance(MACHINE_SERVICE_INTERVAL / (1 SECONDS)) // its heat pump works over the interval

/// The area elects `A` its main alarm (the one that scans and drives the room's devices).
/proc/am_alarm_make_main(obj/machinery/alarm/A)
	rel_set(A.alarm_area_ref(), nameof(/area::main_air_alarm), A)
	A.alarm_area_ref().air_alarms_refresh()

/// The vent's or scrubber's radio and area registration come up, as the pipe network's init does for a placed device.
/proc/am_device_online(obj/machinery/atmospherics/unary/D)
	D.atmos_init()

/// The area numbers its devices from one again (a fresh area).
/proc/am_area_reset_numbers(area/A)
	A.air_device_serials = null

/// The device is welded shut.
/proc/am_device_welded(obj/machinery/atmospherics/unary/D)
	return !!is_welded(D)

/// Welds the device shut or frees it (a test fixture's starting state).
/proc/am_device_set_welded(obj/machinery/atmospherics/unary/D, on)
	set_welded(D, on)

/// The device's radio tag.
/proc/am_device_tag(obj/machinery/atmospherics/unary/D)
	var/obj/machinery/atmospherics/unary/vent_pump/V = D
	if(istype(V))
		return V.id_tag
	var/obj/machinery/atmospherics/unary/vent_scrubber/S = D
	return S.id_tag

/// The device's radio frequency.
/proc/am_device_frequency(obj/machinery/atmospherics/unary/D)
	var/obj/machinery/atmospherics/unary/vent_pump/V = D
	if(istype(V))
		return V.frequency
	var/obj/machinery/atmospherics/unary/vent_scrubber/S = D
	return S.frequency

/// The canister steps once: what one machine service interval of its own work does (the valve's release, the gauge).
/proc/am_canister_tick(obj/machinery/portable_atmospherics/canister/C)
	C.canister_step(null)

/// The canister can be relabelled now (its window's can_relabel).
/proc/am_canister_relabelable(obj/machinery/portable_atmospherics/canister/C)
	return !!C.can_relabel(null)

/// A cyborg pulse-pressurizes its jetpack `J` from canister `C`.
/proc/am_jetpack_refill(mob/living/silicon/robot/R, obj/machinery/portable_atmospherics/canister/C, obj/item/tank/jetpack/J)
	R.next_click = 0
	test_click(R, C, J)

/// The number of entries in the canister's release log.
/proc/am_canister_log_entries(obj/machinery/portable_atmospherics/canister/C)
	return length(C.release_log)

/// Presses `action` on `alarm`'s window as it is shown by the remote atmospherics console `console` (a tgui module) to `user`. The window the
/// console opens is used only while it lets `user` work it.
/proc/am_remote_press(mob/user, datum/tgui_module/atmos_control/console, obj/machinery/alarm/alarm, action, list/args)
	var/datum/air_alarm_remote/panel = new(console, alarm)
	. = hc_ui(user, panel, action, args)
	qdel(panel)

/// A remote atmospherics console's module, with `access` as its own req_one_access (the console's access).
/proc/am_remote_console(list/access)
	return new /datum/tgui_module/atmos_control(null, null, access)

/// The console's screen was emagged.
/proc/am_remote_console_emag(datum/tgui_module/atmos_control/console)
	console.emagged = TRUE

// ---------------------------------------------------------------------------------------------------------------------
// Input and time
// ---------------------------------------------------------------------------------------------------------------------

/// A click by `actor` on `target` with `held` in the active hand (the click a client sends), and the time for it to play out.
/proc/am_click(mob/living/actor, atom/target, obj/item/held, gesture = GESTURE_CLICK)
	if(held && actor.get_active_hand() != held)
		if(actor.get_active_hand())
			actor.drop_item()
		actor.put_in_active_hand(held)
	else if(!held && actor.get_active_hand())
		actor.drop_item()
	actor.next_click = 0
	var/datum/op_result/result = test_click(actor, target, held, gesture)
	. = result
	if(held && gesture == GESTURE_CLICK && !QDELETED(target) && (isnull(result) || istype(target, /obj/machinery/portable_atmospherics) && (result.outcome & ACT_REFUSED) && result.reason == /datum/msg/op/not_available))
		// A type still on the legacy item handlers: the attack chain a client's click reaches once no op answers.
		held.resolve_attackby(target, actor)
	am_settle()

/// A window button, and the time for it to play out.
/proc/am_press(mob/actor, datum/host, action, list/args)
	. = hc_ui(actor, host, action, args)
	am_settle()

/// Answers the question `actor` was asked. A test mob has no client, so a question that re-checks the asker's window state as it is answered is
/// answered as a player whose window is open would answer it.
/proc/am_answer(mob/actor, value)
	var/datum/request/open = SSrequests.open_for(actor)
	if(open)
		open.usable_state = null
	. = p2cl_answer(actor, value)
	am_settle()

/// Time for a click, a button, an answer or a radio exchange to play out: longer than any tool's wait or a device's status reply.
/proc/am_settle()
	test_time(10 SECONDS)

/// A radio command packet to the device tagged `tag`, as an air alarm or a control console sends it.
/proc/am_radio(obj/machinery/atmospherics/unary/D, list/command)
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO
	signal.data = command.Copy()
	signal.data["tag"] = am_device_tag(D)
	signal.data["sigtype"] = "command"
	D.receive_signal(signal, TRANSMISSION_RADIO, am_device_frequency(D))
	qdel(signal)
	am_settle()

/// The thermal energy of `T`'s air, J.
/proc/am_air_energy(turf/T)
	var/datum/gas_mixture/air = T.return_air()
	return air.heat_capacity() * air.return_temperature()

/// `T`'s air: oxygen and nitrogen at the given partial pressures (kPa) and temperature, nothing else.
/proc/am_set_air(turf/T, o2_kpa = 21.28, n2_kpa = 80.04, temperature = T20C, list/extra)
	var/datum/gas_mixture/air = T.return_air()
	air.clear()
	heat_set(air, temperature, HEAT_SOURCE_OTHER)
	var/per_kpa = air.return_volume() / (R_IDEAL_GAS_EQUATION * temperature)
	if(o2_kpa)
		air.set_moles(/datum/gas/oxygen, o2_kpa * per_kpa)
	if(n2_kpa)
		air.set_moles(/datum/gas/nitrogen, n2_kpa * per_kpa)
	for(var/gas in extra)
		air.set_moles(gas, extra[gas])
	heat_set(air, temperature, HEAT_SOURCE_OTHER)

// ---------------------------------------------------------------------------------------------------------------------
// Base: the kernel on its injected clock around the test, the room's air and the area's device lists put back after.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_atmos_m
	abstract_type = /datum/unit_test/dq_atmos_m
	/// The area's lists as the test found them.
	var/list/area_saved

/datum/unit_test/dq_atmos_m/Run()
	test_driver_begin()
	p2cl_capture_prompts()
	var/area/room = get_area(run_loc_floor_bottom_left)
	area_saved = list(
		"names" = LAZYCOPY(room.air_vent_names), "info" = LAZYCOPY(room.air_vent_info),
		"snames" = LAZYCOPY(room.air_scrub_names), "sinfo" = LAZYCOPY(room.air_scrub_info),
		"atmosalm" = room.atmosalm)
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		dq_atmos_test_snapshot_air(T)
	run_gate()
	room.air_vent_names = area_saved["names"]
	room.air_vent_info = area_saved["info"]
	room.air_scrub_names = area_saved["snames"]
	room.air_scrub_info = area_saved["sinfo"]
	if(room.atmosalm != area_saved["atmosalm"])
		room.atmosalert(area_saved["atmosalm"], null)
	test_driver_end()

/datum/unit_test/dq_atmos_m/proc/run_gate()
	return

/// A turf of the room, `dx` and `dy` from its bottom-left corner.
/datum/unit_test/dq_atmos_m/proc/tile(dx, dy)
	return locate(run_loc_floor_bottom_left.x + dx, run_loc_floor_bottom_left.y + dy, run_loc_floor_bottom_left.z)

/// A person wearing an ID with `access` (none when null), awake for the whole test.
/datum/unit_test/dq_atmos_m/proc/person(list/access, turf/where)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, where || tile(2, 1))
	H.enable_godmode()
	var/mob/controller = allocate(/mob/living/simple_mob/e0_fixture, tile(0, 4))
	rel_set(H, nameof(H.teleop), controller)
	if(access)
		H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
		H.equip_to_slot(id_card(access, H.loc), SLOT_ID_ID)
	return H

/// An ID card with `access`.
/datum/unit_test/dq_atmos_m/proc/id_card(list/access, turf/where)
	var/obj/item/card/id/card = allocate(/obj/item/card/id, where || tile(2, 1))
	card.access = access || list()
	card.registered_name = "Atmos Tester"
	return card

/// A fast tool of `type`.
/datum/unit_test/dq_atmos_m/proc/tool(type, turf/where)
	var/obj/item/T = allocate(type, where || tile(2, 1))
	T.toolspeed = 0
	return T

/// A lit, fuelled welder.
/datum/unit_test/dq_atmos_m/proc/welder(turf/where)
	var/obj/item/weldingtool/W = tool(/obj/item/weldingtool, where)
	W.reagents.add_reagent(REAGENT_ID_FUEL, W.max_fuel)
	W.setWelding(TRUE)
	return W

/// A powered air alarm of `type` on the room's tile (dx, dy), its area's main alarm when `main`.
/datum/unit_test/dq_atmos_m/proc/alarm(type = /obj/machinery/alarm, dx = 1, dy = 1, main = TRUE)
	var/obj/machinery/alarm/A = allocate(type, tile(dx, dy))
	A.set_grid_power(TRUE)
	A.set_broken_condition(FALSE)
	if(main)
		am_alarm_make_main(A)
	return A

/// A powered vent pump or scrubber of `type` on the room's tile (dx, dy), its radio up and registered with the area.
/datum/unit_test/dq_atmos_m/proc/device(type, dx = 3, dy = 1)
	var/obj/machinery/atmospherics/unary/D = allocate(type, tile(dx, dy))
	D.set_grid_power(TRUE)
	D.set_broken_condition(FALSE)
	am_device_online(D)
	am_settle()
	return D

/// An empty tank.
/datum/unit_test/dq_atmos_m/proc/empty_tank(turf/where)
	var/obj/item/tank/oxygen/T = allocate(/obj/item/tank/oxygen, where || tile(2, 1))
	T.air_contents.clear()
	return T

// =====================================================================================================================
// The air alarm: its window and its lock
// =====================================================================================================================

/// The mode button changes the mode of every alarm in the area and commands the area's devices: panic siphons with the scrubbers and stops the
/// vents, scrubbing puts the scrubbers back to filtering CO2 and the vents to their default pressure.
/datum/unit_test/dq_atmos_m/alarm_mode_drives_the_area
/datum/unit_test/dq_atmos_m/alarm_mode_drives_the_area/run_gate()
	var/obj/machinery/alarm/A = alarm()
	var/obj/machinery/alarm/B = alarm(dx = 3, dy = 3, main = FALSE)
	var/obj/machinery/atmospherics/unary/vent_pump/V = device(/obj/machinery/atmospherics/unary/vent_pump/on, 3, 1)
	var/obj/machinery/atmospherics/unary/vent_scrubber/S = device(/obj/machinery/atmospherics/unary/vent_scrubber/on, 1, 3)
	am_alarm_set_locked(A, FALSE)
	var/mob/living/carbon/human/H = person()
	am_press(H, A, "mode", list("mode" = AM_MODE_PANIC))
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_PANIC, "the mode button sets the alarm's mode")
	TEST_ASSERT_EQUAL(B.mode, AM_MODE_PANIC, "and every alarm of the area follows")
	TEST_ASSERT(S.panic, "panic siphons with the scrubbers")
	TEST_ASSERT(!S.scrubbing, "which stop filtering")
	TEST_ASSERT(S.use_power, "and stay on")
	TEST_ASSERT(!V.use_power, "the vents stop")
	V.set_external_pressure_bound(50)
	V.set_pressure_checks(0)
	am_press(H, A, "mode", list("mode" = AM_MODE_SCRUBBING))
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_SCRUBBING, "back to scrubbing")
	TEST_ASSERT(!S.panic, "the scrubbers stop siphoning")
	TEST_ASSERT(S.scrubbing, "and filter again")
	TEST_ASSERT(GAS_CO2 in S.scrubbing_gas, "CO2 among what they filter")
	TEST_ASSERT(V.use_power, "the vents run again")
	TEST_ASSERT_EQUAL(V.external_pressure_bound, V.external_pressure_bound_default, "at their default pressure")
	TEST_ASSERT_EQUAL(V.pressure_checks, V.pressure_checks_default, "with their default checks")
	am_press(H, A, "mode", list("mode" = AM_MODE_OFF))
	TEST_ASSERT(!S.use_power && !V.use_power, "off: every device stops")
	am_press(H, A, "mode", list("mode" = AM_MODE_FILL))
	TEST_ASSERT(!S.use_power && V.use_power, "fill: the vents run and the scrubbers stop")
	am_press(H, A, "mode", list("mode" = AM_MODE_REPLACEMENT))
	TEST_ASSERT(S.panic && S.use_power && V.use_power, "replacement: the scrubbers siphon while the vents run")

/// A locked alarm refuses a person's controls (but not the thermostat or the remote setting); unlocked, they work. The lock button itself is a
/// silicon's: a person pressing it changes nothing.
/datum/unit_test/dq_atmos_m/alarm_lock_gates_the_controls
/datum/unit_test/dq_atmos_m/alarm_lock_gates_the_controls/run_gate()
	var/obj/machinery/alarm/A = alarm()
	var/mob/living/carbon/human/H = person()
	am_alarm_set_locked(A, TRUE)
	am_press(H, A, "mode", list("mode" = AM_MODE_PANIC))
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_SCRUBBING, "a locked alarm refuses the mode")
	am_press(H, A, "rcon", list("rcon" = RCON_YES))
	TEST_ASSERT_EQUAL(A.rcon_setting, RCON_YES, "the remote setting is not behind the lock")
	am_press(H, A, "lock")
	TEST_ASSERT(am_alarm_locked(A), "a person's lock button does nothing")
	am_alarm_set_locked(A, FALSE)
	am_press(H, A, "lock")
	TEST_ASSERT(!am_alarm_locked(A), "nor does it lock it")
	am_press(H, A, "mode", list("mode" = AM_MODE_PANIC))
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_PANIC, "unlocked, the mode changes")
	var/list/data = hc_data(A, H)
	TEST_ASSERT_EQUAL(data["locked"], FALSE, "the window shows the lock")
	TEST_ASSERT(islist(data["vents"]) && islist(data["scrubbers"]) && islist(data["thresholds"]), "an unlocked window lists the devices and thresholds")
	am_alarm_set_locked(A, TRUE)
	data = hc_data(A, H)
	TEST_ASSERT(isnull(data["vents"]) && isnull(data["thresholds"]), "a locked one does not, to a person")

/// An AI works a locked alarm; with its AI control wire cut it does not.
/datum/unit_test/dq_atmos_m/alarm_ai_works_it_locked
/datum/unit_test/dq_atmos_m/alarm_ai_works_it_locked/run_gate()
	var/obj/machinery/alarm/A = alarm()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, tile(0, 0), null, null, null, TRUE)
	am_alarm_set_locked(A, TRUE)
	am_press(AI, A, "mode", list("mode" = AM_MODE_PANIC))
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_PANIC, "the AI changes the mode of a locked alarm")
	am_press(AI, A, "lock")
	TEST_ASSERT(!am_alarm_locked(A), "and works its lock button")
	var/datum/wires_test_adapter/W = wires_test(A)
	W.cut(WIRE_AI_CONTROL)
	am_press(AI, A, "mode", list("mode" = AM_MODE_SCRUBBING))
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_PANIC, "with AI control cut, the AI is refused")

/// An ID with atmospherics access swiped on the alarm toggles its lock; an ID without it does not, nor does any other thing, nor does an ID on
/// a broken alarm. An alt-click by someone wearing the access toggles it too.
/datum/unit_test/dq_atmos_m/alarm_id_swipe_toggles_the_lock
/datum/unit_test/dq_atmos_m/alarm_id_swipe_toggles_the_lock/run_gate()
	var/obj/machinery/alarm/A = alarm()
	am_alarm_set_locked(A, TRUE)
	var/mob/living/carbon/human/H = person()
	var/obj/item/card/id/good = id_card(list(ACCESS_ATMOSPHERICS))
	var/obj/item/card/id/bad = id_card(list(ACCESS_MAINT_TUNNELS))
	am_click(H, A, bad)
	TEST_ASSERT(am_alarm_locked(A), "an ID without access does not unlock it")
	am_click(H, A, good)
	TEST_ASSERT(!am_alarm_locked(A), "an ID with atmospherics access unlocks it")
	am_click(H, A, good)
	TEST_ASSERT(am_alarm_locked(A), "and locks it again")
	var/obj/item/paper/P = allocate(/obj/item/paper, tile(2, 1))
	am_click(H, A, P)
	TEST_ASSERT(am_alarm_locked(A), "a sheet of paper does nothing to the lock")
	var/mob/living/carbon/human/wearer = person(list(ACCESS_ATMOSPHERICS), tile(2, 2))
	am_click(wearer, A, null, GESTURE_ALT)
	TEST_ASSERT(!am_alarm_locked(A), "an alt-click by someone wearing the access toggles it")
	A.set_broken_condition(TRUE)
	am_click(H, A, good)
	TEST_ASSERT(!am_alarm_locked(A), "a broken alarm's lock does not move")

/// The ID scanner wire cut locks the alarm and keeps swipes from working.
/datum/unit_test/dq_atmos_m/alarm_idscan_wire
/datum/unit_test/dq_atmos_m/alarm_idscan_wire/run_gate()
	var/obj/machinery/alarm/A = alarm()
	am_alarm_set_locked(A, FALSE)
	var/datum/wires_test_adapter/W = wires_test(A)
	W.cut(WIRE_IDSCAN)
	TEST_ASSERT(am_alarm_locked(A), "the ID wire cut locks it")
	var/mob/living/carbon/human/H = person()
	am_click(H, A, id_card(list(ACCESS_ATMOSPHERICS)))
	TEST_ASSERT(am_alarm_locked(A), "and a swipe no longer unlocks it")

/// The syphon wire: cut, the room panics; pulsed, scrubbing and panic swap. The alarm wire raises the area's atmospherics alarm (cut) and
/// clears it (pulsed).
/datum/unit_test/dq_atmos_m/alarm_syphon_and_alarm_wires
/datum/unit_test/dq_atmos_m/alarm_syphon_and_alarm_wires/run_gate()
	var/obj/machinery/alarm/A = alarm()
	var/datum/wires_test_adapter/W = wires_test(A)
	W.pulse(WIRE_SYPHON)
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_PANIC, "pulsing the syphon wire from scrubbing panics")
	W.pulse(WIRE_SYPHON)
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_SCRUBBING, "and back")
	A.set_mode(AM_MODE_FILL)
	W.pulse(WIRE_SYPHON)
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_SCRUBBING, "from any other mode it scrubs")
	W.cut(WIRE_SYPHON)
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_PANIC, "cutting it panics the room")
	var/area/room = get_area(A)
	W.cut(WIRE_AALARM)
	TEST_ASSERT_EQUAL(room.atmosalm, 2, "the alarm wire cut raises the area's alarm")
	W.cut(WIRE_AALARM)
	TEST_ASSERT_EQUAL(room.atmosalm, 2, "mending it raises it too")
	W.pulse(WIRE_AALARM)
	TEST_ASSERT_EQUAL(room.atmosalm, 0, "pulsing it clears it")

/// The thermostat question is bounded by the temperature thresholds; the answer sets every alarm of the area.
/datum/unit_test/dq_atmos_m/alarm_thermostat_sets_the_area
/datum/unit_test/dq_atmos_m/alarm_thermostat_sets_the_area/run_gate()
	var/obj/machinery/alarm/A = alarm()
	var/obj/machinery/alarm/B = alarm(dx = 3, dy = 3, main = FALSE)
	var/mob/living/carbon/human/H = person()
	am_alarm_set_locked(A, TRUE)
	am_press(H, A, "temperature")
	am_answer(H, 25)
	TEST_ASSERT_EQUAL(A.target_temperature, T0C + 25, "the answer sets the thermostat, locked or not")
	TEST_ASSERT_EQUAL(B.target_temperature, T0C + 25, "of every alarm of the area")

/// A threshold edit is asked, applied when answered (negative: off, -1), kept consistent with the other three of its row, and copied to every
/// alarm of the area; the other alarms' own table is untouched until then.
/datum/unit_test/dq_atmos_m/alarm_threshold_edit
/datum/unit_test/dq_atmos_m/alarm_threshold_edit/run_gate()
	var/obj/machinery/alarm/A = alarm()
	var/obj/machinery/alarm/B = alarm(dx = 3, dy = 3, main = FALSE)
	var/obj/machinery/alarm/other = new(null) // in nullspace: no area, its own table
	var/mob/living/carbon/human/H = person()
	am_alarm_set_locked(A, FALSE)
	var/list/before = am_alarm_tlv(A, "pressure")
	am_press(H, A, "threshold", list("env" = "pressure", "var" = 1))
	TEST_ASSERT_EQUAL(json_encode(am_alarm_tlv(A, "pressure")), json_encode(before), "nothing changes before the answer")
	am_answer(H, 200)
	TEST_ASSERT_EQUAL(json_encode(am_alarm_tlv(A, "pressure")), json_encode(list(200, 200, 200, 200)), "a red minimum above the rest raises the rest")
	TEST_ASSERT_EQUAL(json_encode(am_alarm_tlv(B, "pressure")), json_encode(list(200, 200, 200, 200)), "every alarm of the area takes the edited band")
	TEST_ASSERT_EQUAL(json_encode(am_alarm_tlv(other, "pressure")), json_encode(before), "another alarm's table is untouched")
	qdel(other)
	am_press(H, A, "threshold", list("env" = GAS_CO2, "var" = 4))
	am_answer(H, -5)
	var/list/co2 = am_alarm_tlv(A, GAS_CO2)
	TEST_ASSERT_EQUAL(co2[4], -1, "a negative answer turns the threshold off")

/// The server room's alarm: its access and its thermostat.
/datum/unit_test/dq_atmos_m/alarm_server_subtype
/datum/unit_test/dq_atmos_m/alarm_server_subtype/run_gate()
	var/obj/machinery/alarm/server/A = alarm(/obj/machinery/alarm/server)
	TEST_ASSERT_EQUAL(json_encode(A.req_access), json_encode(list(ACCESS_RD, ACCESS_ATMOSPHERICS, ACCESS_ENGINE_EQUIP)), "the server alarm's access")
	TEST_ASSERT_EQUAL(A.target_temperature, 90, "and its thermostat")
	TEST_ASSERT_EQUAL(json_encode(am_alarm_tlv(A, "temperature")), json_encode(list(20, 40, 140, 160)), "and its temperature thresholds")

// =====================================================================================================================
// The air alarm: the room
// =====================================================================================================================

/// The alarm reads the room: phoron past its threshold raises the danger to red and the area's alarm with it; clean air clears both. A monitor
/// alarm reads the room but raises no area alarm.
/datum/unit_test/dq_atmos_m/alarm_danger_and_area_alert
/datum/unit_test/dq_atmos_m/alarm_danger_and_area_alert/run_gate()
	var/turf/T = tile(1, 1)
	am_set_air(T)
	var/obj/machinery/alarm/A = alarm()
	var/area/room = get_area(A)
	am_alarm_tick(A)
	TEST_ASSERT_EQUAL(A.danger_level, 0, "standard air is safe")
	am_set_air(T, extra = list(/datum/gas/plasma = 5))
	am_alarm_tick(A)
	TEST_ASSERT_EQUAL(A.danger_level, 2, "phoron is red")
	TEST_ASSERT_EQUAL(room.atmosalm, 2, "and raises the area's alarm")
	var/list/data = hc_data(A, person())
	var/phoron_level
	for(var/list/row in data["environment_data"])
		if(row["name"] == GAS_PHORON)
			phoron_level = row["danger_level"]
	TEST_ASSERT_EQUAL(phoron_level, 2, "the window marks the phoron row red")
	am_set_air(T)
	am_alarm_tick(A)
	TEST_ASSERT_EQUAL(A.danger_level, 0, "clean air is safe again")
	TEST_ASSERT_EQUAL(room.atmosalm, 0, "and clears the area's alarm")
	qdel(A)
	var/obj/machinery/alarm/monitor/M = alarm(/obj/machinery/alarm/monitor)
	am_set_air(T, extra = list(/datum/gas/plasma = 5))
	am_alarm_tick(M)
	TEST_ASSERT_EQUAL(M.danger_level, 2, "a monitor reads the danger")
	TEST_ASSERT_EQUAL(room.atmosalm, 0, "but raises no area alarm")
	am_set_air(T)

/// A pressure drop into the red is a breach: the alarm turns the room's devices off. A no-breach alarm does not; nor does one already siphoning.
/datum/unit_test/dq_atmos_m/alarm_breach_detection
/datum/unit_test/dq_atmos_m/alarm_breach_detection/run_gate()
	var/turf/T = tile(1, 1)
	am_set_air(T)
	var/obj/machinery/alarm/A = alarm()
	am_alarm_tick(A)
	am_set_air(T, 10, 30)
	am_alarm_tick(A)
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_OFF, "a breach turns the room off")
	qdel(A)
	am_set_air(T)
	var/obj/machinery/alarm/nobreach/N = alarm(/obj/machinery/alarm/nobreach)
	am_alarm_tick(N)
	am_set_air(T, 10, 30)
	am_alarm_tick(N)
	TEST_ASSERT_EQUAL(N.mode, AM_MODE_SCRUBBING, "a no-breach alarm keeps its mode")
	qdel(N)
	am_set_air(T)
	var/obj/machinery/alarm/P = alarm()
	am_alarm_tick(P)
	P.set_mode(AM_MODE_PANIC)
	am_set_air(T, 10, 30)
	am_alarm_tick(P)
	TEST_ASSERT_EQUAL(P.mode, AM_MODE_PANIC, "a panicking room is not a breach")
	am_set_air(T)

/// Cycle mode siphons the room and, once it is nearly empty, fills it again.
/datum/unit_test/dq_atmos_m/alarm_cycle_turns_to_fill
/datum/unit_test/dq_atmos_m/alarm_cycle_turns_to_fill/run_gate()
	var/turf/T = tile(1, 1)
	am_set_air(T)
	var/obj/machinery/alarm/A = alarm()
	A.set_mode(AM_MODE_CYCLE)
	am_alarm_tick(A)
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_CYCLE, "a full room keeps cycling")
	am_set_air(T, 1, 2)
	am_alarm_tick(A)
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_FILL, "a nearly empty one is filled")
	am_set_air(T)

/// The thermostat heats a cold room at its rated 1000 J per service interval, cools a hot one at the same rate, and stops within half a degree
/// of the target; it does nothing in a near vacuum.
/datum/unit_test/dq_atmos_m/alarm_thermostat_heats_and_cools
/datum/unit_test/dq_atmos_m/alarm_thermostat_heats_and_cools/run_gate()
	var/turf/T = tile(1, 1)
	dq_atmos_test_isolate_pair(T, T)
	var/obj/machinery/alarm/A = alarm()
	A.target_temperature = T20C
	am_set_air(T, temperature = T20C - 10)
	var/before = am_air_energy(T)
	for(var/i in 1 to 3)
		am_alarm_tick(A)
	TEST_ASSERT_EQUAL(am_alarm_regulating(A), 2, "a cold room is heated")
	var/gained = am_air_energy(T) - before
	TEST_ASSERT(abs(gained - 3000) < 150, "at 1000 J per interval: [gained] J in three")
	am_set_air(T, temperature = T20C + 20)
	before = am_air_energy(T)
	for(var/i in 1 to 3)
		am_alarm_tick(A)
	TEST_ASSERT(am_alarm_regulating(A), "still regulating, now cooling the hot room")
	var/lost = before - am_air_energy(T)
	TEST_ASSERT(abs(lost - 3000) < 150, "at the same rate: [lost] J in three")
	am_set_air(T, temperature = T20C + 0.3)
	am_alarm_tick(A)
	TEST_ASSERT_EQUAL(am_alarm_regulating(A), 0, "within half a degree it stops")
	am_set_air(T, 0.1, 0.2, T20C - 10)
	am_alarm_tick(A)
	am_alarm_tick(A)
	TEST_ASSERT_EQUAL(am_alarm_regulating(A), 0, "a near vacuum is left alone")
	am_set_air(T)
	dq_atmos_test_restore_walls()

/// The Sif wilderness alarm judges oxygen by its own band: 18 kPa of oxygen (fine for Sif) reads safe.
/datum/unit_test/dq_atmos_m/alarm_sif_oxygen_band
/datum/unit_test/dq_atmos_m/alarm_sif_oxygen_band/run_gate()
	var/turf/T = tile(1, 1)
	am_set_air(T, 18, 83)
	var/obj/machinery/alarm/sifwilderness/A = alarm(/obj/machinery/alarm/sifwilderness)
	am_alarm_tick(A)
	TEST_ASSERT_EQUAL(A.danger_level, 0, "Sif's own oxygen band is read")
	TEST_ASSERT_EQUAL(json_encode(am_alarm_tlv(A, GAS_O2)), json_encode(list(16, 17, 135, 140)), "Sif's oxygen band applies")
	am_set_air(T)

/// The area elects one main alarm; when it goes another one takes over.
/datum/unit_test/dq_atmos_m/alarm_area_election
/datum/unit_test/dq_atmos_m/alarm_area_election/run_gate()
	var/obj/machinery/alarm/A = alarm()
	var/obj/machinery/alarm/B = alarm(dx = 3, dy = 3, main = FALSE)
	var/area/room = get_area(A)
	TEST_ASSERT_EQUAL(room.main_air_alarm, A, "the area has its main alarm")
	qdel(A)
	TEST_ASSERT_EQUAL(room.main_air_alarm, B, "when it goes the other alarm takes over")

// =====================================================================================================================
// The vent pump and the scrubber: radio, status, names
// =====================================================================================================================

/// A vent pump answers its radio commands.
/datum/unit_test/dq_atmos_m/vent_radio_commands
/datum/unit_test/dq_atmos_m/vent_radio_commands/run_gate()
	var/obj/machinery/atmospherics/unary/vent_pump/V = device(/obj/machinery/atmospherics/unary/vent_pump)
	am_radio(V, list("power" = "1"))
	TEST_ASSERT(V.use_power, "power on")
	am_radio(V, list("power_toggle" = 1))
	TEST_ASSERT(!V.use_power, "power toggled off")
	am_radio(V, list("checks" = "3"))
	TEST_ASSERT_EQUAL(V.pressure_checks, 3, "checks set")
	am_radio(V, list("checks" = "default"))
	TEST_ASSERT_EQUAL(V.pressure_checks, V.pressure_checks_default, "checks back to default")
	am_radio(V, list("checks_toggle" = 1))
	TEST_ASSERT_EQUAL(V.pressure_checks, 0, "checks toggled off")
	am_radio(V, list("checks_toggle" = 1))
	TEST_ASSERT_EQUAL(V.pressure_checks, 3, "and to both")
	am_radio(V, list("direction" = "0"))
	TEST_ASSERT_EQUAL(V.pump_direction, 0, "siphoning")
	am_radio(V, list("set_external_pressure" = "50"))
	TEST_ASSERT_EQUAL(V.external_pressure_bound, 50, "external bound set")
	am_radio(V, list("adjust_external_pressure" = "10"))
	TEST_ASSERT_EQUAL(V.external_pressure_bound, 60, "external bound adjusted")
	am_radio(V, list("set_external_pressure" = "999999"))
	TEST_ASSERT_EQUAL(V.external_pressure_bound, ONE_ATMOSPHERE * 50, "clamped to fifty atmospheres")
	am_radio(V, list("set_external_pressure" = "default"))
	TEST_ASSERT_EQUAL(V.external_pressure_bound, V.external_pressure_bound_default, "external bound to default")
	am_radio(V, list("set_internal_pressure" = "300"))
	TEST_ASSERT_EQUAL(V.internal_pressure_bound, 300, "internal bound set")
	am_radio(V, list("adjust_internal_pressure" = "-50"))
	TEST_ASSERT_EQUAL(V.internal_pressure_bound, 250, "internal bound adjusted")
	am_radio(V, list("reset_internal_pressure" = 1))
	TEST_ASSERT_EQUAL(V.internal_pressure_bound, 0, "internal bound reset")
	am_radio(V, list("set_external_pressure" = "40"))
	am_radio(V, list("reset_external_pressure" = 1))
	TEST_ASSERT_EQUAL(V.external_pressure_bound, ONE_ATMOSPHERE, "external bound reset")
	am_radio(V, list("purge" = 1))
	TEST_ASSERT(!(V.pressure_checks & 1) && V.pump_direction == 0, "purge: no external check, siphoning")
	am_radio(V, list("stabalize" = 1))
	TEST_ASSERT((V.pressure_checks & 1) && V.pump_direction == 1, "stabilize: the external check, releasing")
	am_radio(V, list("init" = "Renamed Vent"))
	TEST_ASSERT_EQUAL(V.name, "Renamed Vent", "init names it")
	V.set_broken_condition(TRUE)
	am_radio(V, list("power" = "1"))
	TEST_ASSERT(!V.use_power, "a broken vent ignores the radio")

/// A scrubber answers its radio commands: power, panic, scrubbing and the gases it filters.
/datum/unit_test/dq_atmos_m/scrubber_radio_commands
/datum/unit_test/dq_atmos_m/scrubber_radio_commands/run_gate()
	var/obj/machinery/atmospherics/unary/vent_scrubber/S = device(/obj/machinery/atmospherics/unary/vent_scrubber)
	am_radio(S, list("power" = "1"))
	TEST_ASSERT(S.use_power, "power on")
	am_radio(S, list("panic_siphon" = "1"))
	TEST_ASSERT(S.panic && !S.scrubbing, "panic siphons")
	am_radio(S, list("scrubbing" = "1"))
	TEST_ASSERT(S.scrubbing && !S.panic, "scrubbing ends the panic")
	am_radio(S, list("toggle_panic_siphon" = 1))
	TEST_ASSERT(S.panic && !S.scrubbing, "the panic toggle")
	am_radio(S, list("toggle_scrubbing" = 1))
	TEST_ASSERT(S.scrubbing && !S.panic, "the scrubbing toggle")
	am_radio(S, list("o2_scrub" = "1"))
	TEST_ASSERT(GAS_O2 in S.scrubbing_gas, "filters oxygen")
	am_radio(S, list("co2_scrub" = "0"))
	TEST_ASSERT(!(GAS_CO2 in S.scrubbing_gas), "stops filtering CO2")
	am_radio(S, list("toggle_n2_scrub" = 1))
	TEST_ASSERT(GAS_N2 in S.scrubbing_gas, "the nitrogen toggle")
	am_radio(S, list("tox_scrub" = "0"))
	TEST_ASSERT(!(GAS_PHORON in S.scrubbing_gas), "phoron off")
	am_radio(S, list("n2o_scrub" = "1", "fuel_scrub" = "1", "ch4_scrub" = "0"))
	TEST_ASSERT((GAS_N2O in S.scrubbing_gas) && (GAS_VOLATILE_FUEL in S.scrubbing_gas) && !(GAS_CH4 in S.scrubbing_gas), "several at once")
	var/obj/machinery/atmospherics/unary/vent_scrubber/other = device(/obj/machinery/atmospherics/unary/vent_scrubber, 1, 3)
	TEST_ASSERT_EQUAL(json_encode(other.scrubbing_gas), json_encode(list(GAS_CO2, GAS_PHORON, GAS_CH4)), "another scrubber keeps the default gases")
	am_radio(S, list("power_toggle" = 1))
	TEST_ASSERT(!S.use_power, "power toggled off")

/// A scrubber told panic_siphon = 0 (a number, as the air alarm's window sends it) stops siphoning.
/datum/unit_test/dq_atmos_m/scrubber_panic_off
/datum/unit_test/dq_atmos_m/scrubber_panic_off/run_gate()
	var/obj/machinery/atmospherics/unary/vent_scrubber/S = device(/obj/machinery/atmospherics/unary/vent_scrubber/on)
	am_radio(S, list("panic_siphon" = 1))
	TEST_ASSERT(S.panic, "panicking")
	am_radio(S, list("panic_siphon" = 0))
	TEST_ASSERT(!S.panic && S.scrubbing, "panic_siphon 0 ends the panic")
	am_radio(S, list("panic_siphon" = 1))
	var/obj/machinery/alarm/A = alarm()
	am_alarm_set_locked(A, FALSE)
	am_press(person(), A, "panic_siphon", list("id_tag" = am_device_tag(S), "val" = 0))
	TEST_ASSERT(!S.panic, "the alarm window's panic switch turns it off")

/// The devices report to the area: a vent and a scrubber register under their tags with numbered names, their status follows a command, and
/// the alarm's window lists them.
/datum/unit_test/dq_atmos_m/devices_report_to_the_area
/datum/unit_test/dq_atmos_m/devices_report_to_the_area/run_gate()
	var/obj/machinery/alarm/A = alarm()
	am_alarm_set_locked(A, FALSE)
	var/area/room = get_area(A)
	room.air_vent_names = null
	room.air_vent_info = null
	room.air_scrub_names = null
	room.air_scrub_info = null
	am_area_reset_numbers(room)
	var/obj/machinery/atmospherics/unary/vent_pump/V = device(/obj/machinery/atmospherics/unary/vent_pump)
	var/obj/machinery/atmospherics/unary/vent_scrubber/S = device(/obj/machinery/atmospherics/unary/vent_scrubber, 1, 3)
	TEST_ASSERT_EQUAL(LAZYACCESS(room.air_vent_names, am_device_tag(V)), "[room.name] Vent Pump #1", "the vent is registered and numbered")
	TEST_ASSERT_EQUAL(V.name, "[room.name] Vent Pump #1", "and named so")
	TEST_ASSERT_EQUAL(LAZYACCESS(room.air_scrub_names, am_device_tag(S)), "[room.name] Air Scrubber #1", "the scrubber too")
	am_radio(V, list("power" = "1"))
	var/list/info = LAZYACCESS(room.air_vent_info, am_device_tag(V))
	TEST_ASSERT_EQUAL(info?["power"], V.use_power, "the vent's status follows a command")
	var/list/data = hc_data(A, person())
	var/found
	for(var/list/row in data["vents"])
		if(row["id_tag"] == am_device_tag(V))
			found = row
	TEST_ASSERT_NOTNULL(found, "the alarm's window lists the vent")
	TEST_ASSERT_EQUAL(found?["power"], V.use_power, "with its power")
	found = null
	for(var/list/row in data["scrubbers"])
		if(row["id_tag"] == am_device_tag(S))
			found = row
	TEST_ASSERT_NOTNULL(found, "and the scrubber")

/// A vent's number is never reused: a vent placed after another one went takes a new number.
/datum/unit_test/dq_atmos_m/device_names_collide
/datum/unit_test/dq_atmos_m/device_names_collide/run_gate()
	var/area/room = get_area(tile(1, 1))
	room.air_vent_names = null
	room.air_vent_info = null
	var/obj/machinery/atmospherics/unary/vent_pump/first = device(/obj/machinery/atmospherics/unary/vent_pump, 1, 1)
	var/obj/machinery/atmospherics/unary/vent_pump/second = device(/obj/machinery/atmospherics/unary/vent_pump, 3, 1)
	TEST_ASSERT_NOTEQUAL(first.name, second.name, "two vents, two names")
	qdel(first)
	var/obj/machinery/atmospherics/unary/vent_pump/third = device(/obj/machinery/atmospherics/unary/vent_pump, 1, 3)
	TEST_ASSERT_NOTEQUAL(third.name, second.name, "the third vent takes a number of its own")

/// The multitool sets a vent's tag (the area follows it to the new tag), its frequency and its direction.
/datum/unit_test/dq_atmos_m/vent_multitool_settings
/datum/unit_test/dq_atmos_m/vent_multitool_settings/run_gate()
	var/area/room = get_area(tile(1, 1))
	var/obj/machinery/atmospherics/unary/vent_pump/V = device(/obj/machinery/atmospherics/unary/vent_pump)
	var/mob/living/carbon/human/H = person()
	var/obj/item/multitool/M = tool(/obj/item/multitool)
	var/old_tag = am_device_tag(V)
	var/datum/op_result/R = am_click(H, V, M)
	TEST_ASSERT(SSrequests.open_for(H), "the multitool asks what to set ([R?.outcome] [R?.key] [R?.reason])")
	am_answer(H, "ID Tag")
	am_answer(H, "am_new_tag")
	TEST_ASSERT_EQUAL(am_device_tag(V), "am_new_tag", "the tag is set")
	TEST_ASSERT(!LAZYACCESS(room.air_vent_names, old_tag), "the old tag is gone from the area")
	TEST_ASSERT_EQUAL(LAZYACCESS(room.air_vent_names, "am_new_tag"), V.name, "the new tag carries the vent's name")
	var/direction = V.pump_direction
	am_click(H, V, M)
	am_answer(H, "Direction")
	TEST_ASSERT_NOTEQUAL(V.pump_direction, direction, "the direction is flipped")
	am_click(H, V, M)
	am_answer(H, "Frequency")
	am_answer(H, 1441)
	TEST_ASSERT_EQUAL(am_device_frequency(V), 1441, "the frequency is set")

/// A vent moved off the air alarms' frequency no longer hears them.
/datum/unit_test/dq_atmos_m/vent_off_frequency_ignores_the_alarm
/datum/unit_test/dq_atmos_m/vent_off_frequency_ignores_the_alarm/run_gate()
	var/obj/machinery/alarm/A = alarm()
	am_alarm_set_locked(A, FALSE)
	var/obj/machinery/atmospherics/unary/vent_pump/V = device(/obj/machinery/atmospherics/unary/vent_pump/on)
	var/mob/living/carbon/human/H = person()
	var/obj/item/multitool/M = tool(/obj/item/multitool)
	am_click(H, V, M)
	am_answer(H, "Frequency")
	am_answer(H, 1441)
	am_press(H, A, "mode", list("mode" = AM_MODE_OFF))
	TEST_ASSERT(V.use_power, "the alarm's command did not reach it")

/// Welding: a lit welder welds a vent or a scrubber shut and frees it again.
/datum/unit_test/dq_atmos_m/devices_weld
/datum/unit_test/dq_atmos_m/devices_weld/run_gate()
	var/obj/machinery/atmospherics/unary/vent_pump/V = device(/obj/machinery/atmospherics/unary/vent_pump)
	var/obj/machinery/atmospherics/unary/vent_scrubber/S = device(/obj/machinery/atmospherics/unary/vent_scrubber, 1, 1)
	var/mob/living/carbon/human/H = person()
	var/obj/item/weldingtool/W = welder()
	var/datum/op_result/R = am_click(H, V, W)
	TEST_ASSERT(am_device_welded(V), "the vent is welded shut ([R?.outcome] [R?.key] [R?.reason] [json_encode(GLOB.dq_tool_last_use)])")
	am_click(H, V, W)
	TEST_ASSERT(!am_device_welded(V), "and freed")
	am_click(H, S, W)
	TEST_ASSERT(am_device_welded(S), "the scrubber is welded shut")

/// The wrench: a running or welded device is refused; a stopped one comes off.
/datum/unit_test/dq_atmos_m/devices_wrench
/datum/unit_test/dq_atmos_m/devices_wrench/run_gate()
	var/obj/machinery/atmospherics/unary/vent_pump/V = device(/obj/machinery/atmospherics/unary/vent_pump/on)
	var/mob/living/carbon/human/H = person()
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench)
	am_click(H, V, W)
	TEST_ASSERT(!QDELETED(V), "a running vent is refused")
	var/obj/machinery/atmospherics/unary/vent_scrubber/S = device(/obj/machinery/atmospherics/unary/vent_scrubber, 1, 1)
	am_device_set_welded(S, TRUE)
	am_click(H, S, W)
	TEST_ASSERT(!QDELETED(S), "a welded scrubber is refused")
	V.set_use_power(USE_POWER_OFF)
	am_device_set_welded(V, TRUE)
	am_click(H, V, W)
	TEST_ASSERT(!QDELETED(V), "a welded vent is refused, as a welded scrubber is")
	am_device_set_welded(V, FALSE)
	am_click(H, V, W)
	TEST_ASSERT(QDELETED(V), "a stopped, unwelded vent comes off")
	am_device_set_welded(S, FALSE)
	am_click(H, S, W)
	TEST_ASSERT(QDELETED(S), "a stopped, unwelded scrubber comes off")
	for(var/obj/item/pipe/P in tile(1, 1))
		qdel(P)
	for(var/obj/item/pipe/P in tile(3, 1))
		qdel(P)

/// A ctrl-click does not switch a vent or a scrubber (the air alarm drives them).
/datum/unit_test/dq_atmos_m/devices_ignore_ctrl_click
/datum/unit_test/dq_atmos_m/devices_ignore_ctrl_click/run_gate()
	var/obj/machinery/atmospherics/unary/vent_pump/V = device(/obj/machinery/atmospherics/unary/vent_pump/on)
	var/obj/machinery/atmospherics/unary/vent_scrubber/S = device(/obj/machinery/atmospherics/unary/vent_scrubber/on, 1, 1)
	var/mob/living/carbon/human/H = person(list(ACCESS_ATMOSPHERICS))
	am_click(H, V, null, GESTURE_CTRL)
	am_click(H, S, null, GESTURE_CTRL)
	TEST_ASSERT(V.use_power && S.use_power, "both still run")

// =====================================================================================================================
// The remote atmospherics console
// =====================================================================================================================

/// A remote console works an alarm for whoever its access lets in, past the alarm's own lock; someone without access works it only while the
/// alarm allows remote control (always, or in an emergency on auto), or when the console is emagged.
/datum/unit_test/dq_atmos_m/remote_console_access
/datum/unit_test/dq_atmos_m/remote_console_access/run_gate()
	var/obj/machinery/alarm/A = alarm()
	am_alarm_set_locked(A, TRUE)
	A.rcon_setting = RCON_NO
	var/datum/tgui_module/atmos_control/console = am_remote_console(list(ACCESS_ATMOSPHERICS))
	var/mob/living/carbon/human/tech = person(list(ACCESS_ATMOSPHERICS))
	var/mob/living/carbon/human/visitor = person(null, tile(2, 2))
	am_remote_press(visitor, console, A, "mode", list("mode" = AM_MODE_PANIC))
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_SCRUBBING, "no access, no remote control: refused")
	am_remote_press(tech, console, A, "mode", list("mode" = AM_MODE_PANIC))
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_PANIC, "the console's access works the locked alarm")
	A.rcon_setting = RCON_YES
	am_remote_press(visitor, console, A, "mode", list("mode" = AM_MODE_FILL))
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_FILL, "remote control always on lets anyone in")
	A.rcon_setting = RCON_AUTO
	am_remote_press(visitor, console, A, "mode", list("mode" = AM_MODE_SCRUBBING))
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_FILL, "on auto without an emergency: refused")
	var/area/room = get_area(A)
	room.atmosalert(2, A)
	am_remote_press(visitor, console, A, "mode", list("mode" = AM_MODE_SCRUBBING))
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_SCRUBBING, "on auto in an emergency: let in")
	room.atmosalert(0, A)
	A.rcon_setting = RCON_NO
	am_remote_console_emag(console)
	am_remote_press(visitor, console, A, "mode", list("mode" = AM_MODE_PANIC))
	TEST_ASSERT_EQUAL(A.mode, AM_MODE_PANIC, "an emagged console lets anyone in")
	qdel(console)

// =====================================================================================================================
// The canister
// =====================================================================================================================

/// The presets: each starts at 45 atmospheres of its gas at 20 C (air is a mix, the airlock canister holds three atmospheres, the engine set-up
/// ones double). The chilled oxygen canister holds one load, chilled to 80 K.
/datum/unit_test/dq_atmos_m/canister_presets
/datum/unit_test/dq_atmos_m/canister_presets/run_gate()
	var/turf/T = tile(3, 1)
	var/list/presets = list(
		/obj/machinery/portable_atmospherics/canister/oxygen = /datum/gas/oxygen,
		/obj/machinery/portable_atmospherics/canister/nitrogen = /datum/gas/nitrogen,
		/obj/machinery/portable_atmospherics/canister/phoron = /datum/gas/plasma,
		/obj/machinery/portable_atmospherics/canister/carbon_dioxide = /datum/gas/carbon_dioxide,
		/obj/machinery/portable_atmospherics/canister/nitrous_oxide = /datum/gas/nitrous_oxide,
		/obj/machinery/portable_atmospherics/canister/methane = /datum/gas/methane,
	)
	var/full = (45 * ONE_ATMOSPHERE) * 1000 / (R_IDEAL_GAS_EQUATION * T20C)
	for(var/path in presets)
		var/obj/machinery/portable_atmospherics/canister/C = allocate(path, T)
		TEST_ASSERT(abs(C.air_contents.get_moles(presets[path]) - full) < 0.5, "[path]: a full load of its gas")
		TEST_ASSERT(abs(C.air_contents.total_moles() - full) < 0.5, "[path]: and nothing else")
		TEST_ASSERT(abs(C.air_contents.return_temperature() - T20C) < 0.1, "[path]: at 20 C")
		qdel(C)
	var/obj/machinery/portable_atmospherics/canister/air/air = allocate(/obj/machinery/portable_atmospherics/canister/air, T)
	TEST_ASSERT(abs(air.air_contents.get_moles(/datum/gas/oxygen) - O2STANDARD * full) < 0.5, "air: its oxygen share")
	TEST_ASSERT(abs(air.air_contents.get_moles(/datum/gas/nitrogen) - N2STANDARD * full) < 0.5, "air: its nitrogen share")
	qdel(air)
	var/obj/machinery/portable_atmospherics/canister/air/airlock/airlock = allocate(/obj/machinery/portable_atmospherics/canister/air/airlock, T)
	TEST_ASSERT(abs(airlock.air_contents.return_pressure() - 3 * ONE_ATMOSPHERE) < 1, "the airlock canister holds three atmospheres")
	qdel(airlock)
	var/list/doubled = list(
		/obj/machinery/portable_atmospherics/canister/nitrogen/engine_setup = /datum/gas/nitrogen,
		/obj/machinery/portable_atmospherics/canister/carbon_dioxide/engine_setup = /datum/gas/carbon_dioxide,
		/obj/machinery/portable_atmospherics/canister/phoron/engine_setup = /datum/gas/plasma,
	)
	for(var/path in doubled)
		var/obj/machinery/portable_atmospherics/canister/C = allocate(path, T)
		TEST_ASSERT(abs(C.air_contents.get_moles(doubled[path]) - 2 * full) < 1, "[path]: a double load")
		qdel(C)
	var/obj/machinery/portable_atmospherics/canister/empty/E = allocate(/obj/machinery/portable_atmospherics/canister/empty, T)
	TEST_ASSERT(E.air_contents.total_moles() < 0.01, "an empty canister is empty")
	qdel(E)
	var/obj/machinery/portable_atmospherics/canister/oxygen/prechilled/P = allocate(/obj/machinery/portable_atmospherics/canister/oxygen/prechilled, T)
	TEST_ASSERT(abs(P.air_contents.return_temperature() - 80) < 0.1, "the chilled canister is at 80 K")
	TEST_ASSERT(abs(P.air_contents.get_moles(/datum/gas/oxygen) - full) < 1, "and holds one load")
	qdel(P)

/// The room filler empties its nitrous oxide into the room as it is placed.
/datum/unit_test/dq_atmos_m/canister_roomfiller
/datum/unit_test/dq_atmos_m/canister_roomfiller/run_gate()
	var/turf/T = tile(3, 1)
	am_set_air(T)
	var/obj/machinery/portable_atmospherics/canister/nitrous_oxide/roomfiller/C = allocate(/obj/machinery/portable_atmospherics/canister/nitrous_oxide/roomfiller, T)
	TEST_ASSERT(T.return_air().get_moles(/datum/gas/nitrous_oxide) > 9 * 4000 - 1, "the room gets the nitrous oxide")
	TEST_ASSERT(C.air_contents.total_moles() < 0.01, "the canister is left empty")
	am_set_air(T)

/// The valve releases into the room up to the release pressure, at most the release flow per interval; into a held tank instead when there is
/// one. Closing it stops the release.
/datum/unit_test/dq_atmos_m/canister_valve_releases
/datum/unit_test/dq_atmos_m/canister_valve_releases/run_gate()
	var/turf/T = tile(3, 1)
	am_set_air(T)
	var/obj/machinery/portable_atmospherics/canister/oxygen/C = allocate(/obj/machinery/portable_atmospherics/canister/oxygen, T)
	var/mob/living/carbon/human/H = person()
	am_press(H, C, "pressure", list("pressure" = 200))
	TEST_ASSERT_EQUAL(C.release_pressure, 200, "the release pressure is set")
	am_press(H, C, "valve")
	TEST_ASSERT(C.valve_open, "the valve is open")
	am_canister_tick(C)
	TEST_ASSERT(abs(T.return_air().return_pressure() - 200) < 5, "the room is brought to the release pressure: [T.return_air().return_pressure()]")
	am_press(H, C, "pressure", list("pressure" = 1000))
	am_set_air(T)
	var/total = C.air_contents.total_moles()
	am_canister_tick(C)
	var/moved = total - C.air_contents.total_moles()
	var/cap = (C.release_flow_rate / C.air_contents.return_volume()) * total
	TEST_ASSERT(abs(moved - cap) < cap * 0.01, "at most the release flow per interval: [moved] of [cap]")
	am_set_air(T)
	am_press(H, C, "valve")
	TEST_ASSERT(!C.valve_open, "closed")
	total = C.air_contents.total_moles()
	am_canister_tick(C)
	TEST_ASSERT(abs(total - C.air_contents.total_moles()) < 0.01, "a closed valve releases nothing")
	var/obj/item/tank/oxygen/tank = empty_tank()
	am_click(H, C, tank)
	TEST_ASSERT_EQUAL(C.holding, tank, "the tank goes in")
	am_press(H, C, "pressure", list("pressure" = 500))
	am_press(H, C, "valve")
	var/room_before = T.return_air().total_moles()
	am_canister_tick(C)
	TEST_ASSERT(abs(tank.air_contents.return_pressure() - 500) < 5, "the tank is filled to the release pressure")
	TEST_ASSERT(abs(T.return_air().total_moles() - room_before) < 0.01, "and nothing goes to the room")
	am_press(H, C, "eject")
	TEST_ASSERT(isnull(C.holding), "eject takes the tank out")
	TEST_ASSERT_EQUAL(tank.loc, T, "onto the floor")
	TEST_ASSERT(!C.valve_open, "and closes the valve")
	am_set_air(T)

/// The release log records who opened and closed the valve.
/datum/unit_test/dq_atmos_m/canister_release_log
/datum/unit_test/dq_atmos_m/canister_release_log/run_gate()
	var/turf/T = tile(3, 1)
	am_set_air(T)
	var/obj/machinery/portable_atmospherics/canister/C = allocate(/obj/machinery/portable_atmospherics/canister/empty, T)
	var/mob/living/carbon/human/H = person()
	am_press(H, C, "valve")
	am_press(H, C, "valve")
	TEST_ASSERT_EQUAL(am_canister_log_entries(C), 2, "two entries")

/// A tank goes in by hand; a second one does not replace it; a wrecked canister takes none.
/datum/unit_test/dq_atmos_m/canister_tank_slot
/datum/unit_test/dq_atmos_m/canister_tank_slot/run_gate()
	var/obj/machinery/portable_atmospherics/canister/C = allocate(/obj/machinery/portable_atmospherics/canister/empty, tile(3, 1))
	var/mob/living/carbon/human/H = person()
	var/obj/item/tank/oxygen/first = empty_tank()
	var/obj/item/tank/oxygen/second = empty_tank()
	am_click(H, C, first)
	TEST_ASSERT_EQUAL(C.holding, first, "the first tank goes in")
	am_click(H, C, second)
	TEST_ASSERT_EQUAL(C.holding, first, "a second does not replace it")
	am_press(H, C, "eject")
	C.atom_destruction(BRUTE)
	am_click(H, C, second)
	TEST_ASSERT(isnull(C.holding), "a wrecked canister takes no tank")

/// A canister can be relabelled while it is empty: an empty one can, a full preset cannot, and draining or filling one changes that.
/datum/unit_test/dq_atmos_m/canister_relabel_while_empty
/datum/unit_test/dq_atmos_m/canister_relabel_while_empty/run_gate()
	var/turf/T = tile(3, 1)
	var/obj/machinery/portable_atmospherics/canister/oxygen/full = allocate(/obj/machinery/portable_atmospherics/canister/oxygen, T)
	var/obj/machinery/portable_atmospherics/canister/empty/E = allocate(/obj/machinery/portable_atmospherics/canister/empty, T)
	am_canister_tick(full)
	am_canister_tick(E)
	TEST_ASSERT(!am_canister_relabelable(full), "a full preset cannot be relabelled")
	TEST_ASSERT(am_canister_relabelable(E), "an empty one can")
	full.air_contents.clear()
	E.air_contents.adjust_gas(/datum/gas/nitrogen, 500)
	am_canister_tick(full)
	am_canister_tick(E)
	TEST_ASSERT(am_canister_relabelable(full), "drained, the preset can")
	TEST_ASSERT(!am_canister_relabelable(E), "filled, the empty one cannot")
	var/mob/living/carbon/human/H = person()
	am_press(H, full, "relabel")
	am_answer(H, "\[N2\]")
	TEST_ASSERT_EQUAL(full.canister_color, "red", "the label paints it")
	TEST_ASSERT_EQUAL(full.name, "Canister: \[N2\]", "and names it")

/// A pressure liner goes into a drained canister from two sheets; a pressurized canister or a single sheet is refused.
/datum/unit_test/dq_atmos_m/canister_liner
/datum/unit_test/dq_atmos_m/canister_liner/run_gate()
	var/obj/machinery/portable_atmospherics/canister/oxygen/full = allocate(/obj/machinery/portable_atmospherics/canister/oxygen, tile(3, 1))
	var/obj/machinery/portable_atmospherics/canister/E = allocate(/obj/machinery/portable_atmospherics/canister/empty, tile(1, 1))
	var/mob/living/carbon/human/H = person()
	var/obj/item/stack/material/steel/one = allocate(/obj/item/stack/material/steel, tile(2, 1), 1)
	am_click(H, E, one)
	TEST_ASSERT(isnull(E.pressure_liner_material_id), "one sheet is not enough")
	var/obj/item/stack/material/steel/sheets = allocate(/obj/item/stack/material/steel, tile(2, 2), 5)
	am_click(H, full, sheets)
	TEST_ASSERT(isnull(full.pressure_liner_material_id), "a pressurized canister is refused")
	am_click(H, E, sheets)
	TEST_ASSERT_NOTNULL(E.pressure_liner_material_id, "a drained one takes the liner")
	TEST_ASSERT_EQUAL(sheets.get_amount(), 3, "for two sheets")

/// The welder takes a drained canister apart into ten sheets of steel; a pressurized one is refused.
/datum/unit_test/dq_atmos_m/canister_welder
/datum/unit_test/dq_atmos_m/canister_welder/run_gate()
	var/turf/T = tile(3, 1)
	var/obj/machinery/portable_atmospherics/canister/oxygen/full = allocate(/obj/machinery/portable_atmospherics/canister/oxygen, T)
	var/mob/living/carbon/human/H = person()
	var/obj/item/weldingtool/W = welder()
	am_click(H, full, W)
	TEST_ASSERT(!QDELETED(full), "a pressurized canister is refused")
	var/obj/machinery/portable_atmospherics/canister/E = allocate(/obj/machinery/portable_atmospherics/canister/empty, tile(1, 1))
	am_click(H, E, W)
	TEST_ASSERT(QDELETED(E), "a drained one comes apart")
	var/sheets = 0
	for(var/obj/item/stack/material/steel/S in tile(1, 1))
		sheets += S.get_amount()
		qdel(S)
	TEST_ASSERT_EQUAL(sheets, 10, "into ten sheets")

/// The wrench connects a canister to the port under it and disconnects it again; connected, it is anchored.
/datum/unit_test/dq_atmos_m/canister_port
/datum/unit_test/dq_atmos_m/canister_port/run_gate()
	var/turf/T = tile(3, 1)
	var/obj/machinery/atmospherics/portables_connector/port = allocate(/obj/machinery/atmospherics/portables_connector, T)
	var/obj/machinery/portable_atmospherics/canister/E = allocate(/obj/machinery/portable_atmospherics/canister/empty, tile(1, 1))
	var/mob/living/carbon/human/H = person()
	var/obj/item/tool/wrench/W = tool(/obj/item/tool/wrench)
	E.forceMove(T)
	am_click(H, E, W)
	TEST_ASSERT_EQUAL(E.connected_port, port, "the wrench connects it")
	TEST_ASSERT(E.anchored, "and anchors it")
	am_click(H, E, W)
	TEST_ASSERT(isnull(E.connected_port), "and disconnects it")
	TEST_ASSERT(!E.anchored, "freeing it")

/// A canister struck with a weapon is damaged; a tank or an analyzer used on it is not a blow. Wrecked, it dumps its gas into the room, drops its
/// tank and stops blocking the way.
/datum/unit_test/dq_atmos_m/canister_struck_and_wrecked
/datum/unit_test/dq_atmos_m/canister_struck_and_wrecked/run_gate()
	var/turf/T = tile(3, 1)
	am_set_air(T)
	var/obj/machinery/portable_atmospherics/canister/oxygen/C = allocate(/obj/machinery/portable_atmospherics/canister/oxygen, T)
	var/mob/living/carbon/human/H = person()
	var/obj/item/analyzer/scanner = allocate(/obj/item/analyzer, tile(2, 1))
	var/start = C.get_integrity()
	am_click(H, C, scanner)
	TEST_ASSERT_EQUAL(C.get_integrity(), start, "an analyzer is no blow")
	var/obj/item/tank/oxygen/tank = empty_tank()
	am_click(H, C, tank)
	TEST_ASSERT_EQUAL(C.get_integrity(), start, "nor a tank (it goes in)")
	var/obj/item/material/twohanded/fireaxe/axe = allocate(/obj/item/material/twohanded/fireaxe, tile(2, 1))
	H.set_combat_mode(TRUE)
	am_click(H, C, axe)
	TEST_ASSERT(C.get_integrity() < start, "an axe is")
	var/gas = C.air_contents.total_moles()
	var/room = T.return_air().total_moles()
	C.atom_destruction(BRUTE)
	TEST_ASSERT(C.destroyed, "wrecked")
	TEST_ASSERT(!C.density, "it no longer blocks the way")
	TEST_ASSERT(!C.air_contents || C.air_contents.total_moles() < gas * 0.01, "its gas has left it ([room] + [gas] -> [T.return_air().total_moles()])")
	TEST_ASSERT(T.return_air().total_moles() > room + gas * 0.99, "into the room")
	TEST_ASSERT(isnull(C.holding), "it no longer holds its tank")
	for(var/turf/near in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		own_turf_contents(near)
	am_set_air(T)

/// A cyborg pulse-pressurizes its jetpack from a canister: half the pressure difference, up to ten atmospheres in the jetpack.
/datum/unit_test/dq_atmos_m/canister_jetpack_refill
/datum/unit_test/dq_atmos_m/canister_jetpack_refill/run_gate()
	var/obj/machinery/portable_atmospherics/canister/oxygen/C = allocate(/obj/machinery/portable_atmospherics/canister/oxygen, tile(3, 1))
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, tile(2, 1))
	R.enable_godmode()
	if(!R.module)
		rel_set(R, nameof(R.module), new /obj/item/robot_module/robot/standard(R))
	var/obj/item/tank/jetpack/carbondioxide/J = new(R.module)
	rel_add(R.module, nameof(R.module.modules), J)
	R.activate_module(J)
	R.select_module(R.module_slot_of(J))
	J.air_contents.clear()
	var/canister_pressure = C.air_contents.return_pressure()
	am_jetpack_refill(R, C, J)
	am_settle()
	var/expected = min(10 * ONE_ATMOSPHERE, canister_pressure / 2)
	TEST_ASSERT(abs(J.air_contents.return_pressure() - expected) < expected * 0.02, "the jetpack holds [J.air_contents.return_pressure()] kPa, expected [expected]")

// =====================================================================================================================
// The vent pump's flow
// =====================================================================================================================

/// The atmospherics siphon (internal check only, a 2000 kPa ceiling on its pipe) stops siphoning into a pipe already above its ceiling.
/datum/unit_test/dq_atmos_m/vent_internal_check
/datum/unit_test/dq_atmos_m/vent_internal_check/run_gate()
	var/list/run = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(run, "no clear two-tile pipe run")
	var/turf/simulated/floor/T = run[1]
	var/turf/simulated/floor/pipe_turf = run[2]
	var/direction = get_dir(T, pipe_turf)
	dq_atmos_test_isolate_pair(T, pipe_turf)
	// The two tiles share their air: both start with the same, or the room's moles drift by mixing with whatever an earlier test left on the
	// pipe's tile (the run is found anywhere on the map, outside the room the base snapshots).
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_snapshot_air(pipe_turf)
	am_set_air(T)
	am_set_air(pipe_turf)
	var/obj/machinery/atmospherics/unary/vent_pump/siphon/on/atmos/V = allocate(/obj/machinery/atmospherics/unary/vent_pump/siphon/on/atmos, T)
	V.dir = direction
	V.initialize_directions = direction
	var/obj/machinery/atmospherics/pipe/simple/P = allocate(/obj/machinery/atmospherics/pipe/simple, pipe_turf)
	P.dir = direction | REVERSE_DIR(direction)
	P.initialize_directions = P.dir
	V.atmos_init()
	P.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(V, P))
	V.set_grid_power(TRUE)
	V.set_broken_condition(FALSE)
	V.air_contents.adjust_gas(/datum/gas/nitrogen, 3000 * V.air_contents.return_volume() / (R_IDEAL_GAS_EQUATION * T20C))
	heat_set(V.air_contents, T20C, HEAT_SOURCE_OTHER)
	V.push_to_rust()
	var/before = T.return_air().total_moles()
	for(var/i in 1 to 5)
		SSair.rust_step_pipe_devices()
		SSair.run_gas_frames(1)
	TEST_ASSERT(abs(T.return_air().total_moles() - before) < 1, "the siphon leaves the room alone: [before] -> [T.return_air().total_moles()]")
	V.air_contents.clear()
	V.air_contents.adjust_gas(/datum/gas/nitrogen, 1000 * V.air_contents.return_volume() / (R_IDEAL_GAS_EQUATION * T20C))
	heat_set(V.air_contents, T20C, HEAT_SOURCE_OTHER)
	am_set_air(T)
	before = T.return_air().total_moles()
	for(var/i in 1 to 5)
		SSair.rust_step_pipe_devices()
		SSair.run_gas_frames(1)
	TEST_ASSERT(T.return_air().total_moles() < before - 1, "below its ceiling it siphons the room")
	am_set_air(T)
	dq_atmos_test_restore_walls()

#undef AM_MODE_SCRUBBING
#undef AM_MODE_REPLACEMENT
#undef AM_MODE_PANIC
#undef AM_MODE_CYCLE
#undef AM_MODE_FILL
#undef AM_MODE_OFF

/// Every air alarm's declarations compile clean: each requirement carries a reason (the threshold button's once did not, a runtime at boot).
/datum/unit_test/dq_atmos_alarm_declarations_clean/Run()
	for(var/path in typesof(/obj/machinery/alarm))
		var/datum/type_table/T = table_of_type(path)
		TEST_ASSERT(T, "[path] has a table")
		TEST_ASSERT(!length(T.errors), "[path] declares clean: [jointext(T.errors || list(), "; ")]")
