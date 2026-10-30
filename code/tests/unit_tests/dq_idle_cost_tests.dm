// Idle-cost fixes (doc/rewrite/server_bench_20261027.md): periodic work that fired in lockstep, a log line per charging flip, and material services that
// resampled a steady assembly every interval.

/// The first delay of a type-level every() is spread over the interval: instances armed on one tick no longer all run on one tick.
/datum/unit_test/dq_every_first_run_is_phased

/datum/unit_test/dq_every_first_run_is_phased/Run()
	var/interval = 10 SECONDS
	var/lowest = INFINITY
	var/highest = 0
	var/list/seen = list()
	for(var/i in 1 to 64)
		var/delay = type_every_phase(interval)
		TEST_ASSERT(delay >= 1 TICKS && delay <= interval, "the first run falls within one interval (got [delay])")
		TEST_ASSERT(delay >= interval * TYPE_EVERY_PHASE_FLOOR - 1 TICKS, "the first run is no earlier than the floor share of the interval (got [delay])")
		lowest = min(lowest, delay)
		highest = max(highest, delay)
		seen["[delay]"] = TRUE
	TEST_ASSERT(lowest < interval * 0.45, "some first runs start early in the interval (lowest [lowest])")
	TEST_ASSERT(highest > interval * 0.9, "some first runs start late in the interval (highest [highest])")
	TEST_ASSERT(length(seen) > 30, "64 holders do not share a handful of start ticks ([length(seen)] distinct)")
	TEST_ASSERT_EQUAL(type_every_phase(TYPE_EVERY_PHASE_MIN - 1 TICKS), TYPE_EVERY_PHASE_MIN - 1 TICKS, "a short interval is left exactly as written")

/// A charging-only APC report is logged once per interval and counted; a channel change is always logged.
/datum/unit_test/dq_apc_report_log_folds_charging_flips

/datum/unit_test/dq_apc_report_log_folds_charging_flips/Run()
	var/obj/machinery/power/apc/A = allocate(/obj/machinery/power/apc, run_loc_floor_bottom_left)
	var/eq = A.equipment
	var/li = A.lighting
	var/en = A.environ
	var/status = A.main_status
	A.report_log_skipped = 0
	COOLDOWN_RESET(A, report_log_cooldown)
	var/charging = !A.charging
	A.on_apc_report(eq, li, en, charging, A.power_alarm_raised, status, 0)
	TEST_ASSERT(COOLDOWN_STARTED(A, report_log_cooldown), "the first charging report is logged and starts the interval")
	TEST_ASSERT_EQUAL(A.report_log_skipped, 0, "nothing was folded yet")
	A.on_apc_report(eq, li, en, !charging, A.power_alarm_raised, status, 0)
	A.on_apc_report(eq, li, en, charging, A.power_alarm_raised, status, 0)
	TEST_ASSERT_EQUAL(A.report_log_skipped, 2, "charging flips inside the interval are counted, not written")
	var/new_status = status == APC_EXTERNAL_POWER_GOOD ? APC_EXTERNAL_POWER_NOENERGY : APC_EXTERNAL_POWER_GOOD
	A.on_apc_report(eq, li, en, charging, A.power_alarm_raised, new_status, 0)
	TEST_ASSERT_EQUAL(A.report_log_skipped, 0, "a status change is always written, and the count restarts")
	A.on_apc_report(eq, li, en, !charging, A.power_alarm_raised, new_status, 0)
	TEST_ASSERT_EQUAL(A.report_log_skipped, 1, "the interval restarted with that line")
	A.on_apc_report(eq, li, en, A.charging, A.power_alarm_raised, status, 0)
	COOLDOWN_RESET(A, report_log_cooldown)
	if(A.terminal)
		qdel(A.terminal)
	if(A.cell)
		qdel(A.cell)

/// A service stays awake for heat that moves its assembly, not for a gap to the air: a cell 290 K off a vacuum sink whose link moves nothing sleeps.
/datum/unit_test/dq_material_service_sleeps_when_heat_does_not_move_it

/datum/unit_test/dq_material_service_sleeps_when_heat_does_not_move_it/Run()
	var/turf/simulated/floor/T = gas_level_test_room()
	var/obj/item/cell/high/C = new(T)
	var/datum/material_service/service = material_service_of(C)
	TEST_ASSERT_NOTNULL(service, "a cell has a material service")
	var/datum/gas_mixture/ambient = T.return_air()
	service.last_environment_temperature = service.temperature()
	TEST_ASSERT(!service.refresh_heat_links(ambient), "an assembly whose temperature did not move since the last sample holds no flowing heat, whatever its air's temperature")
	service.last_environment_temperature = service.temperature() + 5 * MATERIAL_THERMAL_RESOLUTION
	TEST_ASSERT(service.refresh_heat_links(ambient), "an assembly whose temperature moved since the last sample is still taking heat")
	cancel_after(service, "material_service")
	service.timer = FALSE
	qdel(C)
