// A door in an area whose APC has a charged cell has power (the playtest's unpowered arrival doors on Southern Cross).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// What the grid looks like from `door`, for a failure message.
/proc/dq_power_door_state(obj/machinery/door/door)
	var/area/A = get_area(door)
	var/obj/machinery/power/apc/apc = A?.apc
	var/area/served = door.power_area
	var/text = "[door.type] at [door.x],[door.y],[door.z] in [A?.type]: power_area [served?.type], channel [power_of(door).channel]"
	text += "; area requires [A?.requires_power] equip/light/environ [A?.power_equip]/[A?.power_light]/[A?.power_environ]"
	if(apc)
		text += "; apc operating [apc.operating] supplying [apc.supplying] shorted [apc.shorted] grid_check [apc.grid_check]"
		text += " channels [apc.equipment]/[apc.lighting]/[apc.environ] cell [apc.cell?.charge]/[apc.cell?.maxcharge] area [apc.area?.type]"
	else
		text += "; no apc"
	text += "; has_power [stat_value(door, STAT_HAS_POWER)] power_lost [door.power_lost()]"
	return text

/// An airlock put down in the area of a working APC has power once the APC has run a few power steps.
/datum/unit_test/dq_power_airlock_in_apc_area

/datum/unit_test/dq_power_airlock_in_apc_area/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, get_turf(apc))
	for(var/i in 1 to 5)
		dq_power_test_step()
	refresh_flush()
	TEST_ASSERT(apc.area.powered(ENVIRON), "the APC powers its area's environment channel: [dq_power_door_state(door)]")
	TEST_ASSERT(!door.power_lost(), "an airlock in the APC's area has power: [dq_power_door_state(door)]")

/// On the map as loaded (Southern Cross with --full-map): every airlock whose area's APC holds a charged cell has power.
/datum/unit_test/dq_power_mapped_airlocks_powered

/datum/unit_test/dq_power_mapped_airlocks_powered/Run()
	for(var/i in 1 to 5)
		dq_power_test_step()
	refresh_flush()
	var/checked = 0
	var/list/dark = list()
	for(var/obj/machinery/door/airlock/door in world)
		var/area/A = get_area(door)
		var/obj/machinery/power/apc/apc = A?.apc
		if(!A?.requires_power || A.always_unpowered || !apc?.cell || apc.cell.charge <= 0 || !apc.operating)
			continue
		checked++
		if(door.power_lost())
			dark += dq_power_door_state(door)
	TEST_ASSERT(checked, "the map has airlocks in APC-powered areas")
	TEST_ASSERT(!length(dark), "[length(dark)] of [checked] airlocks in areas with a charged APC have no power; first: [jointext(dark.Copy(1, min(length(dark), 5) + 1), " || ")]")

/// A machine with a polling every() behind a proc gate (the form fire alarms, diffusers, disposals and heaters use), counting its draws.
/obj/machinery/dq_idle_redraw_probe
	use_power = USE_POWER_IDLE
	var/draws = 0
	var/steps = 0

CAPABILITIES(/obj/machinery/dq_idle_redraw_probe)
	configure(uses_power(idle = 5, channel = EQUIP))
	every(1 SECOND, then(PROC_REF(probe_step)), when = PROC_REF(probe_gate))

/// The polling gate: a proc, so the every() keeps firing while it is false.
/obj/machinery/dq_idle_redraw_probe/proc/probe_gate(datum/act/A)
	return operable()

/obj/machinery/dq_idle_redraw_probe/proc/probe_step(datum/act/timer/A)
	steps++

/obj/machinery/dq_idle_redraw_probe/draw(datum/look/look)
	..()
	draws++

/// An unpowered area's idle machines and floor do not redraw on every interval: a polling every() whose gate is false skips its run, and a
/// skipped run changed nothing (the timer fire used to redraw the holder each time: the unpowered Southern Cross redrew its machines all round).
/datum/unit_test/dq_power_idle_unpowered_no_redraw

/datum/unit_test/dq_power_idle_unpowered_no_redraw/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	test_driver_begin()
	var/turf/T = get_turf(apc)
	var/obj/machinery/dq_idle_redraw_probe/probe = allocate(/obj/machinery/dq_idle_redraw_probe, T)
	var/area/A = apc.area
	A.set_channels(FALSE, FALSE, FALSE)
	test_drain()
	test_time(2 SECONDS)
	TEST_ASSERT(probe.power_lost(), "the probe is unpowered once its area's channels are off")
	var/draws_before = probe.draws
	var/turf_key = T.rx?.look_key
	var/drained_before = GLOB.refresh_bench_drained
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(probe.steps, 0, "the gated every() never ran its step while unpowered")
	TEST_ASSERT_EQUAL(probe.draws, draws_before, "an unpowered idle machine is not redrawn on its polling interval ([probe.draws - draws_before] redraws in 10 s)")
	TEST_ASSERT_EQUAL(T.rx?.look_key, turf_key, "the floor under it keeps its look")
	TEST_NOTICE(src, "refreshes drained over 10 idle seconds: [GLOB.refresh_bench_drained - drained_before]")
	A.set_channels(TRUE, TRUE, TRUE)
	test_drain()
	test_time(2 SECONDS)
	TEST_ASSERT(probe.steps > 0, "powered again, the every() runs")
	apc.apply_area_power()
	test_driver_end()

#endif
