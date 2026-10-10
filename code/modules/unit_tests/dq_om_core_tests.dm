// Object-model core (doc/rewrite/object_model_core.md): one test per
// primitive, and one regression test per bug class the design removes.
// Every test runs on its own deterministic scheduler (scheduler_test_begin()).

// ---------------------------------------------------------------- fixtures

/datum/om_test_entity
	var/ticks = 0
	var/list/dts
	var/wakes = 0
	var/last_changes = 0
	var/deadlines = 0
	var/steps = 0
	var/starts = 0
	var/stops = 0
	var/events = 0
	var/list/log
	var/value = 1
	var/weight = 0
	var/enabled = TRUE
	var/crash_on_tick = FALSE
	var/native = 0
	/// Set by on_destroy(): how many om edges were still present then.
	var/edges_at_destroy = -1

/datum/om_test_entity/on_destroy(force)
	edges_at_destroy = length(om_rec?.edges)
	..()

/datum/om_test_entity/proc/inline_tick(dt)
	ticks++
	LAZYADD(dts, dt)

/datum/om_test_entity/proc/inline_react(changes)
	wakes++
	last_changes = changes

/datum/om_test_entity/decl_host

// ---------------------------------------------------------------- base

/datum/unit_test/om
	abstract_type = /datum/unit_test/om
	var/datum/time_scheduler/sched

/datum/unit_test/om/Run()
	rel_set(src, nameof(sched), scheduler_test_begin())
	var/list/made = list()
	try
		run_om(made)
	catch(var/exception/e)
		TEST_FAIL("runtime in om test: [e] ([e.file]:[e.line])")
	for(var/datum/D as anything in made)
		if(!QDELETED(D))
			qdel(D)
	scheduler_test_end()

/datum/unit_test/om/proc/run_om(list/made)
	return

/datum/unit_test/om/proc/entity(list/made, path = /datum/om_test_entity)
	var/datum/om_test_entity/E = new path
	made += E
	return E

// ---------------------------------------------------------------- A: scheduling

/datum/om_test_entity/var/list/log_targets

// ---------------------------------------------------------------- B: change tracking

// ---------------------------------------------------------------- C: derived

// ---------------------------------------------------------------- D: relations

// ---------------------------------------------------------------- G: events

// ---------------------------------------------------------------- H: checks

// ---------------------------------------------------------------- I: tasks

// ---------------------------------------------------------------- J: UI
// The window push and status wakes are the UI push system's (dq_ui_outputs_tests.dm).

// ---------------------------------------------------------------- K: helpers

/datum/unit_test/om/dt_helpers

/datum/unit_test/om/dt_helpers/run_om(list/made)
	var/one = approach(0, 10, 0.5, 2)
	var/two = approach(approach(0, 10, 0.5, 1), 10, 0.5, 1)
	TEST_ASSERT(abs(one - two) < 0.0001, "approach() is dt-exact")
	TEST_ASSERT(abs(decay(8, 1, 1) - 8 / NUM_E) < 0.0001, "decay()")
	TEST_ASSERT(!chance_over(0, 5), "chance_over() never fires at p = 0")
	TEST_ASSERT(chance_over(1, 0.1), "and always at p = 1")
	TEST_ASSERT_EQUAL(move_toward(0, 1, 2, 1), 1, "move_toward() clamps at the target")

// ---------------------------------------------------------------- tables
