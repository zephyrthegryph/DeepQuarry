// Object-model pipelines (doc/rewrite/object_model_core.md §A.10): the core runner on test
// entities, and the machines ported onto it.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// --- Test entities, pipelines and stages ----------------------------------------------------

/datum/pipe_test_entity
	/// Read by the "on" fact (CHANGE_DATUM_A reports it) and the "lit" fact (no channel).
	var/on = TRUE
	var/lit = TRUE
	/// Stage names in the order they ran.
	var/list/log = list()
	/// Stage names that keep work (their idle() is FALSE).
	var/list/busy = list()
	var/abort_now = 0
	var/nested = 0
	/// test_throttle's wakes.
	var/list/wakes = list()

/datum/pipe_test_entity/deep
/datum/pipe_test_entity/deep/deeper
/datum/pipe_test_other

/// One decl for two unrelated types (multi-type decls).
/datum/om/decl/pipe_test
	of = list(/datum/pipe_test_entity, /datum/pipe_test_other)
	behaviours = list(/datum/om/pipeline/test, /datum/om/pipeline/test_reactive, /datum/om/behaviour/test_throttle)

/datum/om/pipeline/test
	name = "test pipeline"
	every = 1 SECONDS
	step_interval = 1
	max_catchup = 2
	stages = list(/datum/om/stage/test)
	frame_type = /datum/om/frame/test
	wake_all = CHANGE_EXPLICIT
	park_after = 2

/datum/om/frame/test
	facts = list(
		"on" = list(/datum/om/frame/test/proc/fact_on, CHANGE_DATUM_A),
		"lit" = list(/datum/om/frame/test/proc/fact_lit, 0),
	)
	var/computed = 0

/datum/om/frame/test/proc/fact_on()
	var/datum/pipe_test_entity/T = entity
	computed++
	return T.on

/datum/om/frame/test/proc/fact_lit()
	var/datum/pipe_test_entity/T = entity
	return T.lit

/datum/om/stage/test
	category = /datum/om/stage/test
	pipeline = /datum/om/pipeline/test
	of = /datum/pipe_test_entity

/datum/om/stage/test/perform(datum/pipe_test_entity/E, datum/om/frame/test/F)
	E.log += name

/datum/om/stage/test/idle(datum/pipe_test_entity/E)
	return !(name in E.busy)

/// Ordering: b runs after a despite its lower order; c runs before a despite its higher one.
/datum/om/stage/test/a
	name = "a"
	order = 20

/datum/om/stage/test/b
	name = "b"
	order = 10
	after = list(/datum/om/stage/test/a)

/datum/om/stage/test/c
	name = "c"
	order = 30
	before = list(/datum/om/stage/test/a)

/// run_if over facts: needs "on" (a channel reports it) and isn't blocked by it.
/datum/om/stage/test/d
	name = "d"
	order = 40
	wake_on = CHANGE_DATUM_A
	run_if = FACT("on")

/// Rewakes itself.
/datum/om/stage/test/e
	name = "e"
	order = 50

/datum/om/stage/test/e/rewake_delay(datum/pipe_test_entity/E)
	return 3 SECONDS

/// Aborts the frame when asked.
/datum/om/stage/test/f
	name = "f"
	order = 60

/datum/om/stage/test/f/perform(datum/pipe_test_entity/E, datum/om/frame/test/F)
	..()
	if(E.abort_now)
		F.abort(E.abort_now)

/// Runs a nested stage on demand (a second frame from the pool while this one is in use).
/datum/om/stage/test/g
	name = "g"
	order = 70

/datum/om/stage/test/g/perform(datum/pipe_test_entity/E, datum/om/frame/test/F)
	..()
	if(E.nested)
		E.nested = 0
		om_stage_run_now(E, /datum/om/stage/test/a)
		F.fact("on")

/// run_if on a fact no channel reports: a skip keeps it awake. And a general run_if (a check).
/datum/om/stage/test/h
	name = "h"
	order = 80
	run_if = ANY_OF(FACT("lit"), /datum/om/check/test_never)

/datum/om/check/test_never

/datum/om/check/test_never/why_not(datum/actor, datum/target)
	return "never"

/// A variant for deeper entity types: resolved by inheritance depth.
/datum/om/stage/test/a/deep
	name = "a deep"
	of = /datum/pipe_test_entity/deep

/datum/om/stage/test/a/deep/deeper
	name = "a deeper"
	of = /datum/pipe_test_entity/deep/deeper

/// A reactive pipeline (no cadence): stages run when woken; one is throttled.
/datum/om/pipeline/test_reactive
	name = "test reactive"
	lane = LANE_PRESENTATION
	stages = list(/datum/om/stage/test_reactive)
	wake_all = CHANGE_EXPLICIT

/datum/om/stage/test_reactive
	category = /datum/om/stage/test_reactive
	pipeline = /datum/om/pipeline/test_reactive
	of = /datum/pipe_test_entity

/datum/om/stage/test_reactive/show
	name = "show"
	wake_on = CHANGE_DATUM_C
	min_interval = 1 SECONDS

/datum/om/stage/test_reactive/show/perform(datum/pipe_test_entity/E, datum/om/frame/F)
	E.log += "show"
	return STAGE_IDLE

/// A behaviour with min_interval: wakes coalesce and arrive by deadline.
/datum/om/behaviour/test_throttle
	name = "test throttle"
	wake_on = CHANGE_DATUM_B | CHANGE_DATUM_D
	min_interval = 1 SECONDS

/datum/om/behaviour/test_throttle/on_wake(datum/pipe_test_entity/E, changes)
	E.wakes += "wake:[changes]"

/proc/pipe_test_new(path = /datum/pipe_test_entity)
	var/datum/pipe_test_entity/E = new path
	om_start(E)
	return E

/proc/pipe_test_state(datum/E)
	return om_pipe_state(E, /datum/om/pipeline/test)

// --- Runner --------------------------------------------------------------------------------

/datum/unit_test/om_pipeline
	abstract_type = /datum/unit_test/om_pipeline
	var/datum/om/scheduler/sched

/datum/unit_test/om_pipeline/Run()
	sched = om_test_begin()
	try
		run_pipeline()
	catch(var/exception/e)
		TEST_FAIL("runtime in pipeline test: [e] ([e.file]:[e.line])")
	om_test_end()

/datum/unit_test/om_pipeline/proc/run_pipeline()
	return

/// Stages run in the order after/before and `order` give, compiled at boot, with every stage
/// awake at first; run_if skips a stage whose fact fails.
/datum/unit_test/om_pipeline/order_and_run_if

/datum/unit_test/om_pipeline/order_and_run_if/run_pipeline()
	var/datum/pipe_test_entity/E = pipe_test_new()
	om_run_frame_now(E, /datum/om/pipeline/test)
	TEST_ASSERT_EQUAL(jointext(E.log, ","), "c,a,b,d,e,f,g,h", "stage order")
	E.log.Cut()
	var/datum/om/pipe/S = pipe_test_state(E)
	om_pipe_set_all(S, FALSE)
	E.on = FALSE
	E.lit = FALSE
	E.busy = list("h")
	om_run_frame_now(E, /datum/om/pipeline/test)
	TEST_ASSERT(!("d" in E.log), "a failing fact skips the stage")
	TEST_ASSERT(!("h" in E.log), "a failing general run_if skips the stage")
	TEST_ASSERT(om_stage_idle(E, /datum/om/pipeline/test, /datum/om/stage/test/d), "skipped for a fact its wake_on reports, it idles")
	TEST_ASSERT(!om_stage_idle(E, /datum/om/pipeline/test, /datum/om/stage/test/h), "skipped for a fact no channel reports, it stays awake")
	E.on = TRUE
	om_changed(E, CHANGE_DATUM_A)
	sched.run_pass(1e9)
	TEST_ASSERT(!om_stage_idle(E, /datum/om/pipeline/test, /datum/om/stage/test/d), "the fact's channel wakes it")

/// Facts are computed once per frame, on first use.
/datum/unit_test/om_pipeline/facts_are_cached

/datum/unit_test/om_pipeline/facts_are_cached/run_pipeline()
	var/datum/pipe_test_entity/E = pipe_test_new()
	var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/test)
	var/datum/om/frame/test/F = P.frame_acquire(sched, E, 1)
	F.fact("on")
	F.fact("on")
	TEST_ASSERT(F.facts_pass(1, 0), "facts_pass reads the cached value")
	TEST_ASSERT_EQUAL(F.computed, 1, "a fact is computed once per frame")
	F.forget("on")
	F.fact("on")
	TEST_ASSERT_EQUAL(F.computed, 2, "forget() recomputes it")
	F.set_fact("on", FALSE)
	TEST_ASSERT(!F.fact("on"), "set_fact() sets it for the rest of the frame")
	P.frame_release(sched, F)

/// Idle stages are skipped; an entity with every stage idle parks after park_after frames in a
/// row; a stage wake unparks it and wakes every stage.
/datum/unit_test/om_pipeline/idle_park_unpark

/datum/unit_test/om_pipeline/idle_park_unpark/run_pipeline()
	var/datum/pipe_test_entity/E = pipe_test_new()
	var/datum/om/pipe/S = pipe_test_state(E)
	E.busy = list("a")
	om_run_frame_now(E, /datum/om/pipeline/test)
	TEST_ASSERT_EQUAL(S.asleep, S.plan.n - 1, "every stage but the busy one idles")
	E.log.Cut()
	om_run_frame_now(E, /datum/om/pipeline/test)
	TEST_ASSERT_EQUAL(jointext(E.log, ","), "a", "idle stages are skipped")
	TEST_ASSERT_EQUAL(S.idle_frames, 0, "a frame with a busy stage isn't idle")
	E.busy.Cut()
	om_run_frame_now(E, /datum/om/pipeline/test)
	TEST_ASSERT_EQUAL(S.idle_frames, 1, "all idle: one idle frame")
	TEST_ASSERT(!S.parked, "one idle frame doesn't park (hysteresis)")
	om_run_frame_now(E, /datum/om/pipeline/test)
	TEST_ASSERT(S.parked, "two in a row park it")
	var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/test)
	om_cancel_all_after(E, P)
	TEST_ASSERT(E in P.parked_on(sched), "listed as parked")
	var/before = S.frames
	scheduler_advance(5)
	TEST_ASSERT_EQUAL(S.frames, before, "a parked entity runs no frames")
	om_changed(E, CHANGE_EXPLICIT)
	sched.run_pass(1e9)
	TEST_ASSERT(!S.parked, "a wake unparks it")
	TEST_ASSERT(!S.asleep, "whole")
	TEST_ASSERT(!(E in P.parked_on(sched)), "and it leaves the parked list")
	scheduler_advance(2)
	TEST_ASSERT(S.frames > before, "back on the ring")

/// A stage's rewake is a core deadline keyed by (entity, pipeline, stage); it wakes that stage
/// only, and a parked entity comes back for it.
/datum/unit_test/om_pipeline/rewake

/datum/unit_test/om_pipeline/rewake/run_pipeline()
	var/datum/pipe_test_entity/E = pipe_test_new()
	var/datum/om/pipe/S = pipe_test_state(E)
	// The reactive pipeline runs its stages once on start; get that out of the log.
	sched.run_pass(1e9)
	var/datum/om/stage/T = om_registry().stage_by_type[/datum/om/stage/test/e]
	om_run_frame_now(E, /datum/om/pipeline/test)
	om_run_frame_now(E, /datum/om/pipeline/test)
	TEST_ASSERT(S.parked, "parked")
	TEST_ASSERT(om_deadline_pending(E, /datum/om/pipeline/test, OM_DL_STAGE - 1 + T.pos), "e's rewake is pending")
	E.log.Cut()
	var/waited = 0
	var/unparked_at = 0
	while(!length(E.log) && waited < 60)
		sched.manual_time += 1
		sched.run_pass(1e9)
		waited++
		if(!unparked_at && !S.parked)
			unparked_at = waited
	TEST_ASSERT(unparked_at || length(E.log), "the rewake unparked it")
	TEST_ASSERT(waited >= 30, "not before its delay ([waited])")
	TEST_ASSERT_EQUAL(jointext(E.log, ","), "e", "only e ran")
	TEST_ASSERT(S.parked, "and, a rewake counting as one idle frame already, it parked again at once")

/// F.abort(OM_ABORT_FRAME) stops the frame and idles nothing; OM_ABORT_REST keeps the idles made.
/datum/unit_test/om_pipeline/abort

/datum/unit_test/om_pipeline/abort/run_pipeline()
	var/datum/pipe_test_entity/E = pipe_test_new()
	var/datum/om/pipe/S = pipe_test_state(E)
	E.abort_now = OM_ABORT_FRAME
	om_run_frame_now(E, /datum/om/pipeline/test)
	TEST_ASSERT(!("g" in E.log), "an aborted frame stops after the aborting stage")
	TEST_ASSERT(!S.asleep, "and idles nothing")
	E.abort_now = OM_ABORT_REST
	om_run_frame_now(E, /datum/om/pipeline/test)
	TEST_ASSERT(S.asleep >= 5, "OM_ABORT_REST keeps the idles already made ([S.asleep])")
	TEST_ASSERT(!om_stage_idle(E, /datum/om/pipeline/test, /datum/om/stage/test/g), "the stages after it didn't run")

/// Catch-up: a fixed-step pipeline runs at most max_catchup frames per pass after a gap.
/datum/unit_test/om_pipeline/catch_up

/datum/unit_test/om_pipeline/catch_up/run_pipeline()
	var/datum/pipe_test_entity/E = pipe_test_new()
	var/datum/om/pipe/S = pipe_test_state(E)
	E.busy = list("a")
	scheduler_advance(2)
	var/before = S.frames
	sched.jump(20)
	sched.run_pass(1e9)
	TEST_ASSERT(S.frames - before >= 1 && S.frames - before <= 2, "catch-up bounded at max_catchup, ran [S.frames - before]")

/// Variants resolve by inheritance depth, once per entity type (the plan), not by path length.
/datum/unit_test/om_pipeline/variants_by_depth

/datum/unit_test/om_pipeline/variants_by_depth/run_pipeline()
	var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/test)
	TEST_ASSERT_EQUAL(P.resolve(/datum/om/stage/test/a, /datum/pipe_test_entity)?.type, /datum/om/stage/test/a, "the root serves the base type")
	TEST_ASSERT_EQUAL(P.resolve(/datum/om/stage/test/a, /datum/pipe_test_entity/deep)?.type, /datum/om/stage/test/a/deep, "the deeper variant wins")
	TEST_ASSERT_EQUAL(P.resolve(/datum/om/stage/test/a, /datum/pipe_test_entity/deep/deeper)?.type, /datum/om/stage/test/a/deep/deeper, "the deepest variant wins")
	var/datum/pipe_test_entity/E = pipe_test_new(/datum/pipe_test_entity/deep/deeper)
	om_run_frame_now(E, /datum/om/pipeline/test)
	TEST_ASSERT("a deeper" in E.log, "an entity runs its variant")
	var/datum/pipe_test_entity/other = pipe_test_new(/datum/pipe_test_entity/deep/deeper)
	TEST_ASSERT_EQUAL(pipe_test_state(E).plan, pipe_test_state(other).plan, "one plan per entity type")

/// Stages never sleep, so frames are pooled with no scratch state: a stage that runs another stage
/// on demand gets a second frame, and its own frame is intact afterwards.
/datum/unit_test/om_pipeline/nested_frames

/datum/unit_test/om_pipeline/nested_frames/run_pipeline()
	var/datum/pipe_test_entity/E = pipe_test_new()
	E.nested = 1
	om_run_frame_now(E, /datum/om/pipeline/test)
	TEST_ASSERT_EQUAL(jointext(E.log, ","), "c,a,b,d,e,f,g,a,h", "the nested run ran inside g, and the frame went on")
	var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/test)
	TEST_ASSERT_EQUAL(length(sched.frame_pools[P.pipe_idx]), 2, "both frames went back to the pool")

/// Multi-type decls: one decl's rows apply to every type it lists.
/datum/unit_test/om_pipeline/multi_type_decl

/datum/unit_test/om_pipeline/multi_type_decl/run_pipeline()
	var/datum/om/registry/reg = om_registry()
	TEST_ASSERT(reg.decl_typecache[/datum/pipe_test_other], "every listed type is in the decl cache")
	TEST_ASSERT(reg.behaviour(/datum/om/pipeline/test) in reg.type_table(/datum/pipe_test_other).behaviours, "the second type gets the rows")
	TEST_ASSERT(reg.behaviour(/datum/om/pipeline/test) in reg.type_table(/datum/pipe_test_entity/deep).behaviours, "subtypes of the first too")

// --- min_interval ------------------------------------------------------------------------

/// A min_interval behaviour: the first wake runs at once, the rest coalesce into one wake by
/// deadline when the interval ends.
/datum/unit_test/om_pipeline/behaviour_throttle

/datum/unit_test/om_pipeline/behaviour_throttle/run_pipeline()
	var/datum/pipe_test_entity/E = pipe_test_new()
	om_changed(E, CHANGE_DATUM_B)
	sched.run_pass(1e9)
	TEST_ASSERT_EQUAL(length(E.wakes), 1, "the first wake runs at once")
	for(var/i in 1 to 4)
		scheduler_advance(0.1)
		om_changed(E, CHANGE_DATUM_B | (i == 4 ? CHANGE_DATUM_D : 0))
		sched.run_pass(1e9)
	TEST_ASSERT_EQUAL(length(E.wakes), 1, "wakes inside the interval wait")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(length(E.wakes), 2, "and arrive once when it ends: [jointext(E.wakes, ",")]")
	TEST_ASSERT(findtext(E.wakes[2], "wake:[CHANGE_DATUM_B | CHANGE_DATUM_D]"), "with the union of their bits: [E.wakes[2]]")

/// A reactive pipeline runs its stages when woken; a stage's min_interval defers it by rewake.
/datum/unit_test/om_pipeline/stage_throttle

/datum/unit_test/om_pipeline/stage_throttle/run_pipeline()
	var/datum/pipe_test_entity/E = pipe_test_new()
	sched.run_pass(1e9)
	E.log.Cut()
	om_changed(E, CHANGE_DATUM_C)
	sched.run_pass(1e9)
	TEST_ASSERT_EQUAL(E.log.Find("show"), 0, "the pass on start ran it already; within its interval it waits")
	scheduler_advance(1.1)
	TEST_ASSERT(E.log.Find("show"), "and runs by rewake when the interval ends")
	scheduler_advance(1.1)
	E.log.Cut()
	om_changed(E, CHANGE_DATUM_C)
	sched.run_pass(1e9)
	TEST_ASSERT(E.log.Find("show"), "after the interval a wake runs at once")

// --- Runlevels ------------------------------------------------------------------------

/// A behaviour's rings don't run outside its runlevels, and resume without catch-up.
/datum/unit_test/om_pipeline/runlevels_dormant

/datum/unit_test/om_pipeline/runlevels_dormant/run_pipeline()
	var/mob/observer/dead/life_test/G = allocate(/mob/observer/dead/life_test)
	scheduler_advance(OBSERVER_UPKEEP_INTERVAL / 10 * 2)
	var/before = G.upkeeps
	sched.runlevel = RUNLEVEL_LOBBY
	scheduler_advance(OBSERVER_UPKEEP_INTERVAL / 10 * 3)
	TEST_ASSERT_EQUAL(G.upkeeps, before, "nothing runs outside the behaviour's runlevels")
	sched.runlevel = RUNLEVEL_GAME
	sched.run_pass(1e9)
	TEST_ASSERT_EQUAL(G.upkeeps, before, "resuming is not a catch-up")
	scheduler_advance(OBSERVER_UPKEEP_INTERVAL / 10 * 2)
	TEST_ASSERT(G.upkeeps > before, "it runs again in its runlevel")

// --- Machines ------------------------------------------------------------------------

/// A recharger charges on the machine pipeline while it has work, idles and parks when the cell is
/// full, and wakes when a cell goes in; it never joins SSmachines' roster.
/datum/unit_test/om_pipeline/recharger_idles

/datum/unit_test/om_pipeline/recharger_idles/run_pipeline()
	var/obj/machinery/recharger/R = allocate(/obj/machinery/recharger)
	TEST_ASSERT(om_attached(R, /datum/om/pipeline/machine), "a recharger runs the machine pipeline")
	TEST_ASSERT(!(R in SSmachines.processing_machines), "and doesn't poll")
	R.stat &= ~(NOPOWER | BROKEN)
	var/datum/om/pipe/S = om_pipe_state(R, /datum/om/pipeline/machine, TRUE)
	for(var/i in 1 to 3)
		om_run_frame_now(R, /datum/om/pipeline/machine)
	TEST_ASSERT(S.parked, "an empty recharger parks")
	var/obj/item/cell/C = new /obj/item/cell/high(R)
	C.charge = C.maxcharge - C.maxcharge / 100
	R.charging = C
	om_changed(R, CHANGE_MACHINE_OCCUPANT)
	sched.run_pass(1e9)
	TEST_ASSERT(!S.parked, "inserting something wakes it")
	var/frames = 0
	while(!C.fully_charged() && frames < 50)
		om_run_frame_now(R, /datum/om/pipeline/machine)
		frames++
	TEST_ASSERT(C.fully_charged(), "it charges the cell")
	TEST_ASSERT_EQUAL(R.use_power, USE_POWER_ACTIVE, "drawing active power while charging")
	for(var/i in 1 to 3)
		om_run_frame_now(R, /datum/om/pipeline/machine)
	TEST_ASSERT_EQUAL(R.use_power, USE_POWER_IDLE, "idle power once charged")
	TEST_ASSERT(S.parked, "a settled recharger parks")
	R.stat |= NOPOWER
	om_changed(R, CHANGE_MACHINE_POWER)
	sched.run_pass(1e9)
	TEST_ASSERT(!S.parked, "losing power wakes it (power_change raises CHANGE_MACHINE_POWER)")
	R.stat &= ~NOPOWER
	R.charging = null
	qdel(C)

/// An APC and an SMES settle and park on the machine pipeline; an APC power failure ends by the
/// power stage's rewake; the APC icon updates at most every APC_UPDATE_ICON_COOLDOWN.
/datum/unit_test/om_pipeline/apc_and_smes_park

/datum/unit_test/om_pipeline/apc_and_smes_park/run_pipeline()
	om_test_end()
	var/obj/machinery/power/apc/A = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(A, "the test map has no working APC")
	if(!A)
		return
	TEST_ASSERT(om_attached(A, /datum/om/pipeline/machine), "an APC runs the machine pipeline")
	TEST_ASSERT(!(A in SSmachines.processing_machines), "and doesn't poll")
	var/datum/om/pipe/S = om_pipe_state(A, /datum/om/pipeline/machine, TRUE)
	for(var/i in 1 to 3)
		om_run_frame_now(A, /datum/om/pipeline/machine)
	TEST_ASSERT(S.parked, "a settled APC parks")
	A.energy_fail(1)
	TEST_ASSERT(A.failure_until > world.time, "the failure is on")
	A.om_rec.sched.run_pass(1e9)
	om_run_frame_now(A, /datum/om/pipeline/machine)
	var/datum/om/stage/T = om_registry().stage_by_type[/datum/om/stage/machine/power/apc]
	TEST_ASSERT(om_deadline_pending(A, /datum/om/pipeline/machine, OM_DL_STAGE - 1 + T.pos), "the power stage ends the failure by rewake, no timer")
	A.failure_until = world.time
	A.failure_timer = 0
	om_run_frame_now(A, /datum/om/pipeline/machine)
	A.update()
	var/obj/machinery/power/smes/M
	for(var/obj/machinery/power/smes/candidate as anything in REGISTRY_MEMBERS(REGISTRY_SMES))
		if(!(candidate.stat & BROKEN) && !istype(candidate, /obj/machinery/power/smes/buildable/hybrid) && !istype(candidate, /obj/machinery/power/smes/batteryrack))
			M = candidate
			break
	if(!M)
		TEST_NOTICE(src, "no SMES on the test map; checked the APC only")
		sched = om_test_begin()
		return
	TEST_ASSERT(!(M in SSmachines.processing_machines), "an SMES doesn't poll")
	var/datum/om/pipe/MS = om_pipe_state(M, /datum/om/pipeline/machine, TRUE)
	M.set_output(M.output_level)
	for(var/i in 1 to 3)
		om_run_frame_now(M, /datum/om/pipeline/machine)
	TEST_ASSERT(MS.parked, "a settled SMES parks")
	sched = om_test_begin()

#endif
