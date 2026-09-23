// S4 wake and parity tests (doc/rewrite/reactor.md §2, §3, §5, §9): the retired SSobj,
// SSprocessing and SSfastprocess users woken by SSreactor. Each converted subscriber type
// wakes when its input changes and stays asleep while it is held steady (react_wake_test),
// and the time-scaled effects (cell recharge, gun recharge, status effect durations and
// ticks, declared continuous work) keep the rates the old fixed-period subsystems gave.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Records the deltas REACT_PROCESS hands process().
/datum/s4_process_probe
	var/list/deltas = list()
	var/kill_after = 0

/datum/s4_process_probe/process(delta)
	deltas += delta
	if(kill_after && length(deltas) >= kill_after)
		return PROCESS_KILL

/// REACT_PROCESS: idempotent, passes elapsed deciseconds, stops on PROCESS_KILL and on
/// REACT_PROCESS_STOP, and REACT_CLEAR drops it.
/datum/unit_test/dq_reactor_s4_process_bridge

/datum/unit_test/dq_reactor_s4_process_bridge/Run()
	var/datum/s4_process_probe/probe = allocate(/datum/s4_process_probe)
	REACT_PROCESS(probe, 2, "unit test")
	REACT_PROCESS(probe, 2, "unit test") // idempotent: one declaration
	TEST_ASSERT(REACT_PROCESSING(probe), "REACT_PROCESS did not mark the datum")
	TEST_ASSERT_EQUAL(length(SSreactor.continuous_by_id["[probe.reactor_id]"]), 1, "a second REACT_PROCESS added a second declaration")
	react_test_ticks(DS2TICKS(2 SECONDS))
	TEST_ASSERT(length(probe.deltas) >= 5, "the declaration ran [length(probe.deltas)] times in 2 s at a 2 ds period")
	var/total = 0
	for(var/delta in probe.deltas)
		total += delta
	// Every delta is the real elapsed time, so the sum tracks game time, not the call count.
	TEST_ASSERT(abs(total - length(probe.deltas) * 2) <= 2 * world.tick_lag + 0.01, "the deltas ([json_encode(probe.deltas)]) are not the elapsed deciseconds")
	REACT_PROCESS_STOP(probe)
	TEST_ASSERT(!REACT_PROCESSING(probe), "REACT_PROCESS_STOP left the flag")
	var/runs = length(probe.deltas)
	react_test_ticks(10)
	TEST_ASSERT_EQUAL(length(probe.deltas), runs, "a stopped declaration still ran")

	probe.kill_after = runs + 2
	REACT_PROCESS(probe, world.tick_lag, "unit test")
	react_test_ticks(10)
	TEST_ASSERT_EQUAL(length(probe.deltas), runs + 2, "PROCESS_KILL did not stop the declaration")
	TEST_ASSERT(!REACT_PROCESSING(probe), "PROCESS_KILL left the flag")

	probe.kill_after = 0
	REACT_PROCESS(probe, world.tick_lag, "unit test")
	REACT_CLEAR(probe)
	TEST_ASSERT(!REACT_PROCESSING(probe), "REACT_CLEAR left the process flag")

/// The continuous lane only touches due entries: a long-period declaration is bucketed at its
/// next run, not scanned every tick.
/datum/unit_test/dq_reactor_s4_continuous_buckets

/datum/unit_test/dq_reactor_s4_continuous_buckets/Run()
	var/datum/s4_process_probe/probe = allocate(/datum/s4_process_probe)
	REACT_PROCESS(probe, 10 SECONDS, "unit test")
	var/due_tick = SSreactor.tick_of(world.time + 10 SECONDS)
	var/list/bucket = SSreactor.continuous_due["[due_tick]"]
	TEST_ASSERT(length(bucket), "a 10 s declaration is not filed under its due tick [due_tick]")
	react_test_ticks(10)
	TEST_ASSERT_EQUAL(length(probe.deltas), 0, "a 10 s declaration ran early")
	REACT_PROCESS_STOP(probe)

// --- Status effects ------------------------------------------------------------------------

/datum/status_effect/s4_test
	id = "s4_test"
	alert_type = null
	duration = 2 SECONDS
	tick_interval = 0.5 SECONDS
	var/ticks = 0
	var/seconds_ticked = 0

/datum/status_effect/s4_test/tick(seconds_between_ticks)
	ticks++
	seconds_ticked += seconds_between_ticks

/datum/status_effect/s4_test/permanent
	id = "s4_test_permanent"
	duration = STATUS_EFFECT_PERMANENT
	tick_interval = STATUS_EFFECT_NO_TICK

/// Status effects: expiry and ticks are timers (no poll), with the old rates.
/datum/unit_test/dq_reactor_s4_status_effect_timing

/datum/unit_test/dq_reactor_s4_status_effect_timing/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/start = world.time
	var/datum/status_effect/s4_test/effect = H.apply_status_effect(/datum/status_effect/s4_test)
	TEST_ASSERT_NOTNULL(effect, "the test status effect was not applied")
	TEST_ASSERT(!isnull(effect.react_timer), "a timed status effect has no timer")
	TEST_ASSERT_NULL(effect.react_sleep_violation(), "a fresh status effect fails its audit")
	TEST_ASSERT(!REACT_PROCESSING(effect), "a timed status effect is declared continuous")
	// Duration parity: it lasts 2 s to the tick.
	while(!QDELETED(effect) && world.time < start + 4 SECONDS)
		react_test_ticks(1)
	TEST_ASSERT(QDELETED(effect), "a 2 s status effect outlived 4 s")
	var/lasted = world.time - start
	TEST_ASSERT(lasted >= 2 SECONDS && lasted <= 2 SECONDS + 2 * world.tick_lag, "a 2 s status effect lasted [lasted] ds")
	// Tick parity: one tick per 0.5 s, each worth 0.5 s.
	TEST_ASSERT(effect.ticks >= 3 && effect.ticks <= 4, "a 0.5 s ticker ticked [effect.ticks] times in 2 s")
	TEST_ASSERT(abs(effect.seconds_ticked - effect.ticks * 0.5) < 0.001, "tick() was not given the tick length")

	// A permanent, non-ticking effect sleeps: no timer, no declaration, no wakes.
	var/datum/status_effect/s4_test/permanent/idle = H.apply_status_effect(/datum/status_effect/s4_test/permanent)
	TEST_ASSERT(isnull(idle.react_timer), "a permanent non-ticking effect has a timer")
	var/failure = react_wake_test(idle, CALLBACK(idle, TYPE_PROC_REF(/datum/status_effect, remove_duration), 0), 4)
	TEST_ASSERT(findtext(failure || "", "did not wake"), "a permanent non-ticking effect woke: [failure]")

/// Refreshing or shortening a status effect moves its timer.
/datum/unit_test/dq_reactor_s4_status_effect_wake

/datum/unit_test/dq_reactor_s4_status_effect_wake/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/status_effect/s4_test/effect = H.apply_status_effect(/datum/status_effect/s4_test)
	effect.tick_interval = STATUS_EFFECT_NO_TICK
	effect.duration = world.time + 1 MINUTE
	effect.schedule_next()
	var/failure = react_wake_test(effect, CALLBACK(src, PROC_REF(shorten), effect), 8)
	TEST_ASSERT(!failure, failure)
	TEST_ASSERT(QDELETED(effect), "shortening a status effect to now did not end it")

/// Shortens the effect to end one decisecond from now, the way refresh()/remove_duration() do.
/datum/unit_test/dq_reactor_s4_status_effect_wake/proc/shorten(datum/status_effect/effect)
	effect.duration = world.time + 1
	effect.schedule_next()

// --- Cells -------------------------------------------------------------------------------

/// Self-recharge: nothing during charge_delay, then charge_amount per 2 s as before, as a rate
/// model woken at display levels and at full.
/datum/unit_test/dq_reactor_s4_cell_recharge_parity

/datum/unit_test/dq_reactor_s4_cell_recharge_parity/Run()
	var/obj/item/cell/C = allocate(/obj/item/cell, test_floor())
	C.maxcharge = 10000
	C.self_recharge = TRUE
	C.charge_amount = 100
	C.charge_delay = 1 SECOND
	C.charge = 5000
	C.last_use = world.time
	C.schedule_self_recharge()
	TEST_ASSERT(!isnull(C.recharge_timer), "a used self-recharging cell has no delay timer")
	TEST_ASSERT_NULL(C.react_sleep_violation(), "a recharging cell fails its audit")
	var/used_at = world.time
	react_test_ticks(DS2TICKS(0.5 SECONDS))
	TEST_ASSERT_EQUAL(C.percent(), 50, "the cell recharged during its charge_delay")
	while(world.time < used_at + 1 SECOND + 10 SECONDS)
		react_test_ticks(1)
	// 10 s of recharge at 100 per 2 s is 500 (the old poll gave 5 steps of 100, +- one step).
	var/gained = C.percent() * C.maxcharge / 100 - 5000
	TEST_ASSERT(abs(gained - 500) <= 100, "10 s of self-recharge gave [gained], not 500")
	// A use restarts the delay.
	C.last_use = world.time
	C.schedule_self_recharge()
	TEST_ASSERT(isnull(C.charge_model), "a use kept the recharge model running through the delay")
	TEST_ASSERT(!isnull(C.recharge_timer), "a use did not re-arm the delay")

/// A full self-recharging cell sleeps; a use wakes it.
/datum/unit_test/dq_reactor_s4_cell_wake

/datum/unit_test/dq_reactor_s4_cell_wake/Run()
	var/obj/item/cell/C = allocate(/obj/item/cell, test_floor())
	C.self_recharge = TRUE
	C.charge_delay = 1 // a use arms a one-decisecond delay timer
	C.charge = C.maxcharge
	C.schedule_self_recharge()
	TEST_ASSERT(isnull(C.recharge_timer) && isnull(C.charge_model), "a full cell is recharging")
	var/failure = react_wake_test(C, CALLBACK(src, PROC_REF(drain), C), 6)
	TEST_ASSERT(!failure, failure)

/// A use: half the charge gone, the delay restarted.
/datum/unit_test/dq_reactor_s4_cell_wake/proc/drain(obj/item/cell/C)
	C.charge = C.maxcharge / 2
	C.last_use = world.time
	C.schedule_self_recharge()

// --- Energy guns --------------------------------------------------------------------------

/// A self-recharging gun gains 20% per recharge_time periods of 2 s after charge_delay.
/datum/unit_test/dq_reactor_s4_energy_gun_recharge_parity

/datum/unit_test/dq_reactor_s4_energy_gun_recharge_parity/Run()
	var/obj/item/gun/energy/G = allocate(/obj/item/gun/energy/laser, test_floor())
	G.self_recharge = TRUE
	if(!G.power_supply)
		G.power_supply = new /obj/item/cell/device/weapon(G)
	G.recharge_time = 1
	G.charge_delay = 1 SECOND
	G.power_supply.charge = 0
	G.last_shot = world.time
	G.schedule_recharge()
	TEST_ASSERT(!isnull(G.recharge_timer), "an empty self-recharging gun has no recharge timer")
	TEST_ASSERT_NULL(G.react_sleep_violation(), "a recharging gun fails its audit")
	var/start = world.time
	while(world.time < start + 1 SECOND + 2 SECONDS - world.tick_lag)
		react_test_ticks(1)
	TEST_ASSERT_EQUAL(G.power_supply.charge, 0, "the gun recharged before charge_delay plus one period")
	react_test_ticks(3)
	TEST_ASSERT(abs(G.power_supply.charge - G.power_supply.maxcharge * 0.2) < 1, "one recharge step gave [G.power_supply.charge] of [G.power_supply.maxcharge]")
	react_test_ticks(DS2TICKS(2 SECONDS) + 1)
	TEST_ASSERT(abs(G.power_supply.charge - G.power_supply.maxcharge * 0.4) < 1, "the second step did not follow one period later ([G.power_supply.charge])")

/// A full gun sleeps; draining its cell and arming wakes it at its step.
/datum/unit_test/dq_reactor_s4_energy_gun_wake

/datum/unit_test/dq_reactor_s4_energy_gun_wake/Run()
	var/obj/item/gun/energy/G = allocate(/obj/item/gun/energy/laser, test_floor())
	G.self_recharge = TRUE
	if(!G.power_supply)
		G.power_supply = new /obj/item/cell/device/weapon(G)
	G.recharge_time = 0
	G.charge_delay = 0
	G.power_supply.charge = G.power_supply.maxcharge
	G.schedule_recharge()
	TEST_ASSERT(isnull(G.recharge_timer), "a full gun has a recharge timer")
	var/failure = react_wake_test(G, CALLBACK(src, PROC_REF(drain_and_arm), G), 6)
	TEST_ASSERT(!failure, failure)

/datum/unit_test/dq_reactor_s4_energy_gun_wake/proc/drain_and_arm(obj/item/gun/energy/G)
	G.power_supply.charge = 0
	G.schedule_recharge()

// --- Material service ----------------------------------------------------------------------

/// A material assembly's advance is one REACT_AT (SSmaterial_services is gone): idle, it
/// sleeps; an environment change wakes it.
/datum/unit_test/dq_reactor_s4_material_service_wake

/datum/unit_test/dq_reactor_s4_material_service_wake/Run()
	var/obj/machinery/portable_atmospherics/canister/can = allocate(/obj/machinery/portable_atmospherics/canister, test_floor())
	can.material_custom_assembly = TRUE // a stable ordinary canister would retire its service
	var/datum/material_service/service = can.enable_material_service()
	TEST_ASSERT_NOTNULL(service, "the canister has no material service")
	react_test_ticks(DS2TICKS(2 SECONDS)) // the admission advance
	service.timer = REACT_REARM(service, service.timer, null)
	service.active = FALSE
	var/failure = react_wake_test(service, CALLBACK(service, TYPE_PROC_REF(/datum/material_service, environment_changed)), 6)
	TEST_ASSERT(!failure, failure)

/// The assembly's thermal state is its heat body, with a watch on its stress levels.
/datum/unit_test/dq_reactor_s4_material_service_heat_body

/datum/unit_test/dq_reactor_s4_material_service_heat_body/Run()
	var/obj/item/cell/C = allocate(/obj/item/cell, test_floor())
	var/datum/material_service/service = C.material_service
	TEST_ASSERT_NOTNULL(service, "a cell has no material service")
	service.update_heat_watch()
	TEST_ASSERT_NOTNULL(C.heat_body, "the service keeps no heat body")
	TEST_ASSERT(length(service.heat_watch_levels), "the service watches no stress levels")
	TEST_ASSERT(!isnull(service.heat_watch), "the service registered no heat watch")
	var/before = service.current_temperature()
	service.add_heat(service.thermal_mass() * 100)
	vg_heat_debug_run_frames(1)
	TEST_ASSERT(service.current_temperature() > before + 50, "heat added to the service did not reach its body ([before] -> [service.current_temperature()] K)")

// --- Talking atoms -------------------------------------------------------------------------

/// A talking atom sleeps until it has heard words, then sets one sampled REACT_AT.
/datum/unit_test/dq_reactor_s4_talking_atom

/datum/unit_test/dq_reactor_s4_talking_atom/Run()
	var/obj/item/stack/rods/holder = allocate(/obj/item/stack/rods, test_floor())
	var/datum/talking_atom/talker = new(holder)
	TEST_ASSERT(isnull(talker.talk_timer), "a talking atom with nothing heard has a timer")
	talker.heard_words["hello"] = list("world")
	talker.schedule_talk()
	TEST_ASSERT(!isnull(talker.talk_timer), "a talking atom with words has no talk timer")
	qdel(talker)

#endif
