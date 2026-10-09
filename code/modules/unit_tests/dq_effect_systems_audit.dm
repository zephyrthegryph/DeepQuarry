// Fire-and-forget effect systems (an explosion, a smoke spread) are thrown away after start(): nothing holds them but their own timers. They declare
// a lifetime (expire()), so the ownership audit sees a system on its way out, not one dropped with a record and timers still holding it, and they
// delete themselves once the smoke they owe is out.

/// Starts the systems without keeping a reference to either (a caller that does is not a dropped one).
/datum/unit_test/proc/dq_start_effect_systems(turf/T)
	var/datum/effect/system/explosion/boom = new
	boom.set_up(T)
	boom.start()
	var/datum/effect/effect/system/smoke_spread/smoke = new
	smoke.set_up(5, 0, T, null)
	smoke.start()

/datum/unit_test/dq_effect_systems_leave_nothing_for_own_audit

/datum/unit_test/dq_effect_systems_leave_nothing_for_own_audit/Run()
	test_driver_begin()
	dq_start_effect_systems(run_loc_floor_bottom_left)
	for(var/line in own_audit(quiet = TRUE))
		TEST_ASSERT(!(findtext(line, "dropped with a rec") && (findtext(line, "effect/system/explosion") || findtext(line, "effect/system/smoke_spread"))), "the audit found a dropped effect system: [line]")
	test_time(30 SECONDS)
	var/list/left_over = list()
	for(var/datum/effect/system/explosion/boom)
		if(!QDELETED(boom))
			left_over += "[boom.type] expire pending [after_pending(boom, "lifecycle_lifetime_timer")]"
	for(var/datum/effect/effect/system/smoke_spread/smoke)
		if(!QDELETED(smoke))
			left_over += "[smoke.type] expire pending [after_pending(smoke, "lifecycle_lifetime_timer")] total_smoke [smoke.total_smoke]"
	TEST_ASSERT(!length(left_over), "the systems deleted themselves once their smoke was out: [jointext(left_over, "; ")]")
	for(var/line in own_audit(quiet = TRUE))
		TEST_ASSERT(!findtext(line, "dropped with a rec"), "nothing is left for the audit: [line]")
