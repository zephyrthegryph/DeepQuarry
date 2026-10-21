// Power reaches machines through the framework (doc/rewrite/final_api.html sections 5, 7, 10): an area channel is tracked state, a machine's
// has_power reads it (generated deps), its on_change hook acts on the flip, its draw follows the stat, and work gated on operable parks while
// unpowered instead of polling. The APC itself is never polled: Rust reports it when what it shows crosses a band (ApcEvent::Report).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A machine whose periodic work is a capability every() gated on STAT_OPERABLE (started_work()), counting its steps.
/obj/machinery/dq_power_wake_probe
	use_power = USE_POWER_IDLE
	var/steps = 0

CAPABILITIES(/obj/machinery/dq_power_wake_probe)
	configure(uses_power(idle = 5, channel = EQUIP))
	powered() // goes dark unpowered: its look follows has_power
	started_work(step = PROC_REF(probe_step), interval = 1 SECOND, starts = TRUE)

/obj/machinery/dq_power_wake_probe/proc/probe_step(datum/act/timer/A)
	steps++

/// The probe's started_work activation.
/proc/dq_power_wake_activation(obj/machinery/dq_power_wake_probe/probe)
	return cap_activation(probe, CAP_STARTED_WORK, null)

/// The machines of one area, cut off and restored through the area's channels: each one's has_power and operable flip within one drain,
/// its look changes, and the probe's gated work parks (no step, no timer) while unpowered and runs again once power is back.
/datum/unit_test/dq_power_wakes_cut_and_restore

/datum/unit_test/dq_power_wakes_cut_and_restore/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	test_driver_begin()
	var/turf/T = get_turf(apc)
	var/area/A = apc.area
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, T)
	var/obj/machinery/alarm/alarm = allocate(/obj/machinery/alarm, T)
	var/obj/machinery/atmospherics/unary/vent_pump/vent = allocate(/obj/machinery/atmospherics/unary/vent_pump, T)
	var/obj/machinery/dq_power_wake_probe/probe = allocate(/obj/machinery/dq_power_wake_probe, T)
	var/list/machines = list(door, alarm, vent, probe)
	A.set_channels(TRUE, TRUE, TRUE)
	test_drain()
	refresh_flush()
	test_time(3 SECONDS)
	for(var/obj/machinery/M as anything in machines)
		TEST_ASSERT(stat_value(M, STAT_HAS_POWER) && M.operable(), "[M.type] is powered and operable before the cut: [dq_power_door_state(door)]")
	TEST_ASSERT(probe.steps > 0, "the probe's gated work runs while powered")
	var/list/looks = list()
	for(var/obj/machinery/M as anything in machines)
		looks[M] = M.rx?.look_key

	// The cut: one write of the area's channels; nothing walks the area.
	A.set_channels(FALSE, FALSE, FALSE)
	test_drain()
	for(var/obj/machinery/M as anything in machines)
		TEST_ASSERT(!stat_value(M, STAT_HAS_POWER), "[M.type]'s has_power flipped within one drain of the cut")
		TEST_ASSERT(!M.operable(), "[M.type] is not operable unpowered")
		TEST_ASSERT(M.power_lost(), "[M.type] acted on the flip (power_change() through its on_change hook)")
	refresh_flush()
	TEST_ASSERT(probe.rx?.look_key != looks[probe], "the probe redrew dark")
	TEST_ASSERT(alarm.rx?.look_key != looks[alarm], "the air alarm redrew dark")
	var/parks_before = GLOB.every_activation_parks
	test_time(2 SECONDS) // the probe's next interval comes due once, finds its gate false and parks
	var/datum/activation/work = dq_power_wake_activation(probe)
	TEST_ASSERT(length(work?.every_parked), "the probe's gated work parked behind its false gate")
	TEST_ASSERT(GLOB.every_activation_parks > parks_before, "the park was counted")
	var/steps_unpowered = probe.steps
	var/parks_unpowered = GLOB.every_activation_parks
	var/runs_unpowered = GLOB.every_activation_runs
	test_time(20 SECONDS)
	TEST_ASSERT_EQUAL(probe.steps, steps_unpowered, "no step while unpowered")
	TEST_ASSERT_EQUAL(GLOB.every_activation_parks, parks_unpowered, "a parked every() holds no timer: it is not re-checked while unpowered")
	TEST_NOTICE(src, "activation every() runs on the whole map over 20 unpowered seconds: [GLOB.every_activation_runs - runs_unpowered]")

	// Restore: the reverse, and the parked work wakes by itself.
	A.set_channels(TRUE, TRUE, TRUE)
	test_drain()
	for(var/obj/machinery/M as anything in machines)
		TEST_ASSERT(stat_value(M, STAT_HAS_POWER) && M.operable(), "[M.type] is powered and operable again within one drain of the restore")
		TEST_ASSERT(!M.power_lost(), "[M.type] acted on the restore")
	TEST_ASSERT(!length(work?.every_parked), "the probe's work woke on the restore")
	refresh_flush()
	TEST_ASSERT_EQUAL(probe.rx?.look_key, looks[probe], "the probe redrew lit")
	TEST_ASSERT_EQUAL(alarm.rx?.look_key, looks[alarm], "the air alarm redrew lit")
	test_time(3 SECONDS)
	TEST_ASSERT(probe.steps > steps_unpowered, "the probe's work runs again")
	apc.apply_area_power()
	test_drain()
	test_driver_end()

/// The APC is not polled: Rust's ApcTick reports a channel change (a manual override written straight into Rust here), the frame's outbox
/// delivers it, the area's channel follows and the machine on it flips. A settled APC is reported nothing.
/datum/unit_test/dq_power_wakes_apc_report

/datum/unit_test/dq_power_wakes_apc_report/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	TEST_ASSERT(apc.vg_entity, "the APC is bound to the power domain")
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, get_turf(apc))
	for(var/i in 1 to 3)
		dq_power_test_step()
	test_drain()
	TEST_ASSERT(apc.area.power_environ, "the APC powers its area's environment channel: [dq_power_door_state(door)]; rust channels [apc.get_channels(0)]/[apc.get_channels(1)]/[apc.get_channels(2)] reported [apc.get_reported()] heard [apc.power_event_count]")
	TEST_ASSERT(!door.power_lost(), "the airlock has power")

	// Settled: Rust reports nothing, whatever steps run.
	var/heard = apc.power_event_count
	var/charge = apc.get_charge()
	for(var/i in 1 to 5)
		dq_power_test_step()
	if(round(apc.get_charge() * 100 / max(apc.cell.maxcharge, 1)) == round(charge * 100 / max(apc.cell.maxcharge, 1)))
		TEST_ASSERT_EQUAL(apc.power_event_count, heard, "a settled APC is reported nothing")

	// Rust turns the environment channel off: the report brings it to DM and the airlock goes dark.
	native_write(apc, NATIVE_APC_CHANNELS, POWERCHAN_OFF, POWER_CHANNEL_ENVIRON)
	dq_power_test_step()
	test_drain()
	TEST_ASSERT_EQUAL(apc.environ, POWERCHAN_OFF, "the report set the APC's environment channel")
	TEST_ASSERT(!apc.area.power_environ, "the area's environment channel followed the report")
	TEST_ASSERT(door.power_lost(), "the airlock lost power from the report: [dq_power_door_state(door)]")

	// And back.
	native_write(apc, NATIVE_APC_CHANNELS, POWERCHAN_ON_AUTO, POWER_CHANNEL_ENVIRON)
	dq_power_test_step()
	test_drain()
	TEST_ASSERT(apc.area.power_environ, "the environment channel is back")
	TEST_ASSERT(!door.power_lost(), "the airlock has power again: [dq_power_door_state(door)]")

#endif
