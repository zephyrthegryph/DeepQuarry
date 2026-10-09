// Per-tick member sweeps (code/controllers/subsystems/tick_members.dm): a system's every(WORK_EVERY_TICK, ..., members = <the system>) steps each
// member once per kernel slot on the test clock (one per server tick in play), the status effect sweeps keep their 0.2 s and 1 s cadences, and a member
// that returns PROCESS_KILL, or is deleted, leaves the sweep.

/// A projectile that only counts its steps.
/obj/item/projectile/tick_probe
	var/steps = 0
	var/kill_after = 0

/obj/item/projectile/tick_probe/projectile_step()
	steps++
	if(kill_after && steps >= kill_after)
		return PROCESS_KILL

/// A status effect on each sweep: tick() is told the seconds its sweep stands for.
/datum/status_effect/cadence_probe
	id = "cadence_probe"
	duration = 60 SECONDS
	tick_interval = 1
	alert_type = null
	var/ticks = 0

/datum/status_effect/cadence_probe/tick(seconds_between_ticks)
	ticks++

/datum/status_effect/cadence_probe/fast
	id = "cadence_probe_fast"
	processing_speed = STATUS_EFFECT_FAST_PROCESS

/datum/status_effect/cadence_probe/normal
	id = "cadence_probe_normal"
	processing_speed = STATUS_EFFECT_NORMAL_PROCESS

/datum/status_effect/cadence_probe/priority
	id = "cadence_probe_priority"
	processing_speed = STATUS_EFFECT_PRIORITY

/datum/unit_test/dq_tick_members
	abstract_type = /datum/unit_test/dq_tick_members

/datum/unit_test/dq_tick_members/Run()
	test_driver_begin()
	run_members()
	test_driver_end()

/datum/unit_test/dq_tick_members/proc/run_members()
	return

/// A projectile is stepped once per slot while it is a member, and leaves when its step says so.
/datum/unit_test/dq_tick_members/projectile_steps_every_slot

/datum/unit_test/dq_tick_members/projectile_steps_every_slot/run_members()
	var/obj/item/projectile/tick_probe/P = allocate(/obj/item/projectile/tick_probe, run_loc_floor_bottom_left)
	TEST_ASSERT(!SSprojectile_steps.is_member(P), "a projectile that was not fired is not swept")
	SSprojectile_steps.kernel_join(P)
	test_time(10)
	TEST_ASSERT_EQUAL(P.steps, 10, "ten kernel slots step a projectile ten times, once per slot")
	P.kill_after = P.steps + 3
	test_time(10)
	TEST_ASSERT_EQUAL(P.steps, 13, "a step that returns PROCESS_KILL ends the membership")
	TEST_ASSERT(!SSprojectile_steps.is_member(P), "and the projectile left the sweep")

/// A deleted member leaves the sweep with no further step.
/datum/unit_test/dq_tick_members/deleted_member_leaves

/datum/unit_test/dq_tick_members/deleted_member_leaves/run_members()
	var/obj/item/projectile/tick_probe/P = new(run_loc_floor_bottom_left)
	SSprojectile_steps.kernel_join(P)
	test_time(2)
	TEST_ASSERT_EQUAL(P.steps, 2, "a member steps every slot")
	qdel(P)
	test_time(5)
	TEST_ASSERT(!SSprojectile_steps.is_member(P), "a deleted projectile left the sweep")
	TEST_ASSERT_EQUAL(P.steps, 2, "and was not stepped again")

/// The three status effect speeds keep their cadences: priority every slot, fast every 0.2 s, normal every second, each told its old step.
/datum/unit_test/dq_tick_members/status_effect_cadences

/datum/unit_test/dq_tick_members/status_effect_cadences/run_members()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/status_effect/cadence_probe/fast/fast = H.apply_status_effect(/datum/status_effect/cadence_probe/fast)
	var/datum/status_effect/cadence_probe/normal/normal = H.apply_status_effect(/datum/status_effect/cadence_probe/normal)
	var/datum/status_effect/cadence_probe/priority/priority = H.apply_status_effect(/datum/status_effect/cadence_probe/priority)
	TEST_ASSERT(SSstatus_fast.is_member(fast), "a fast effect joins the fast sweep")
	TEST_ASSERT(SSstatus_normal.is_member(normal), "a normal effect joins the normal sweep")
	TEST_ASSERT(SSstatus_priority.is_member(priority), "a priority effect joins the priority sweep")
	test_time(20)
	TEST_ASSERT_EQUAL(priority.ticks, 20, "a priority effect ticks every slot")
	TEST_ASSERT_EQUAL(fast.ticks, 10, "a fast effect ticks every 0.2 s")
	TEST_ASSERT_EQUAL(normal.ticks, 2, "a normal effect ticks every second")

/// A throw is swept while it flies and leaves when it lands.
/datum/unit_test/dq_tick_members/throw_is_swept_until_it_lands

/datum/unit_test/dq_tick_members/throw_is_swept_until_it_lands/run_members()
	var/obj/item/stack/rods/R = allocate(/obj/item/stack/rods, run_loc_floor_bottom_left)
	var/turf/target = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	R.throw_at(target, 2, 1)
	var/datum/thrownthing/TT = R.throwing
	TEST_ASSERT_NOTNULL(TT, "throw_at() made no thrownthing")
	TEST_ASSERT(SSthrow_steps.is_member(TT), "a throw joins the throw sweep")
	var/steps = 0
	while(!QDELETED(TT) && steps++ < 100)
		// world.time is frozen inside a test; a throw's pace is measured from its start_time, so age it one server tick per slot.
		TT.start_time -= world.tick_lag
		test_time(1)
	TEST_ASSERT(QDELETED(TT), "the throw never landed")
	TEST_ASSERT_NULL(R.throwing, "the landed item still points at its throw")
	TEST_ASSERT(!SSthrow_steps.is_member(TT), "a landed throw left the sweep")
