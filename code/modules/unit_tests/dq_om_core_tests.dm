// Object-model core (doc/rewrite/object_model_core.md): one test per
// primitive, and one regression test per bug class the design removes.
// Every test runs on its own deterministic scheduler (om_test_begin()).

// ---------------------------------------------------------------- fixtures

/datum/om_test_entity
	var/ticks = 0
	var/list/dts = list()
	var/wakes = 0
	var/last_changes = 0
	var/deadlines = 0
	var/steps = 0
	var/starts = 0
	var/stops = 0
	var/events = 0
	var/list/log = list()
	var/value = 1
	var/weight = 0
	var/enabled = TRUE
	var/crash_on_tick = FALSE
	var/native = 0
	var/ui_pushes = 0
	/// Set by Destroy(): how many om edges were still present then.
	var/edges_at_destroy = -1

/datum/om_test_entity/Destroy()
	edges_at_destroy = length(om_rec?.edges)
	return ..()

/datum/om_test_entity/om_ui_push()
	ui_pushes++

/datum/om_test_entity/proc/inline_tick(dt)
	ticks++
	dts += dt

/datum/om_test_entity/proc/inline_react(changes)
	wakes++
	last_changes = changes

/datum/om_test_entity/decl_host

/datum/om/behaviour/test
	abstract_type = /datum/om/behaviour/test

/datum/om/behaviour/test/tick(datum/om_test_entity/E, dt)
	E.ticks++
	E.dts += dt
	E.log += "[type]"
	if(E.crash_on_tick)
		CRASH("deliberate test runtime")

/datum/om/behaviour/test/on_wake(datum/om_test_entity/E, changes)
	E.wakes++
	E.last_changes |= changes

/datum/om/behaviour/test/on_deadline(datum/om_test_entity/E)
	E.deadlines++

/datum/om/behaviour/test/on_step(datum/om_test_entity/E)
	E.steps++

/datum/om/behaviour/test/on_start(datum/om_test_entity/E)
	E.starts++

/datum/om/behaviour/test/on_stop(datum/om_test_entity/E)
	E.stops++

/datum/om/behaviour/test/on_native(datum/om_test_entity/E, bits)
	E.native |= bits

/datum/om/behaviour/test/every_second
	every = 1 SECONDS

/datum/om/behaviour/test/every_second_b
	every = 1 SECONDS
	order_after = list(/datum/om/behaviour/test/every_second)

/datum/om/behaviour/test/background
	every = 1 SECONDS
	lane = LANE_BACKGROUND

/datum/om/behaviour/test/presentation
	every = 1 SECONDS
	lane = LANE_PRESENTATION

/datum/om/behaviour/test/waker
	wake_on = CHANGE_DATUM_A | CHANGE_DATUM_B

/datum/om/behaviour/test/bad_returns
	every = 1 SECONDS

/datum/om/behaviour/test/bad_returns/tick(datum/om_test_entity/E, dt)
	E.ticks++
	return list("not", "a", "schedule")

/datum/om/behaviour/test/bad_returns/on_wake(datum/om_test_entity/E, changes)
	E.wakes++
	return -1

/datum/om/behaviour/test/clocked
	every = 1 SECONDS
	clock = CLOCK_BIO

/datum/om/behaviour/test/substeps
	every = 1 SECONDS
	max_dt = 0.25

/datum/om/behaviour/test/stepped
	every = 1 SECONDS
	step_interval = 0.2
	max_catchup = 20

/datum/om/behaviour/test/relevant
	every = 1 SECONDS
	relevance = list(OM_SLEEP, 5 SECONDS, 2 SECONDS, 1)

/datum/om/behaviour/test/gated
	every = 1 SECONDS
	requires = list(/datum/om/check/test_enabled)

/datum/om/behaviour/test/related_waker
	wake_on_related = list(/datum/om/relation/test_link = CHANGE_DATUM_A | CHANGE_RELATION_ADDED | CHANGE_RELATION_REMOVED)

/datum/om/behaviour/test/two_hop
	wake_on_related = list(list(/datum/om/relation/test_link, /datum/om/relation/test_link, CHANGE_DATUM_B))

/datum/om/behaviour/test/derived_watcher
	wake_on = CHANGE_DATUM_D

/datum/om/behaviour/test/holder
	every = 1 SECONDS
	holds = TRUE

/datum/om/behaviour/test/holder/tick(datum/om_test_entity/E, dt)
	E.ticks++
	if(E.enabled)
		om_hold(E, EFFECT_STUNNED, E)

/datum/om/behaviour/test/handler
	handles = list(/datum/om/event/test)

/datum/om/behaviour/test/native_watcher
	wake_on_native = 1

/datum/om/behaviour/test/deadline_only

/datum/om/behaviour/test/deadline_clocked
	clock = CLOCK_BIO

/datum/om/check/test_enabled
	depends_on = CHANGE_DATUM_B

/datum/om/check/test_enabled/why_not(datum/om_test_entity/actor, datum/target)
	if(!istype(actor) || !actor.enabled)
		return "disabled"

/datum/om/relation/test_link
	name = "test link"

/datum/om/relation/test_member
	name = "test member"
	source_single = TRUE

/datum/om/relation/test_single_refuse
	name = "test seat"
	target_single = TRUE
	conflict = OM_REL_REFUSE

/datum/om/relation/test_contributing
	name = "test armour"
	contributes = list(EFFECT_ARMOR_MELEE = FROM_VAR("weight"))
	grants_occupant = list(GRANT_ABILITY = "test_ability")
	active_if = /datum/om/check/test_enabled

/datum/om/relation/test_hooked
	name = "test hooked"

/datum/om/relation/test_hooked/on_unlink(datum/om_test_entity/source, datum/om_test_entity/target, datum/om/edge/edge)
	source.log += "unlink:[!isnull(source)]:[!isnull(target)]:[QDELETED(source)]"
	target.log += "unlink:[!isnull(source)]:[!isnull(target)]"

/datum/om/event/test
	var/payload

/datum/om/event/test/dispatch(datum/om/behaviour/B, datum/E)
	return B.on_test_event(E, src)

/datum/om/behaviour/proc/on_test_event(datum/E, datum/om/event/test/event)
	return

/datum/om/behaviour/test/handler/on_test_event(datum/om_test_entity/E, datum/om/event/test/event)
	E.events++
	E.log += "event:[event.type]:[event.payload]"
	if(event.payload == "reenter")
		var/datum/om/event/test/sub/inner = new
		inner.payload = "inner"
		om_emit(E, inner)
		E.log += "after inner emit"
	if(event.payload == "crash")
		CRASH("deliberate handler runtime")

/datum/om/event/test/sub

/datum/om/event/test/other

/datum/om/event/before/test_veto
	var/reenter = FALSE

/datum/om/event/before/test_veto/dispatch(datum/om/behaviour/B, datum/om_test_entity/E)
	if(!istype(B, /datum/om/behaviour/test/veto_handler))
		return null
	E.events++
	if(reenter)
		var/datum/om/event/before/test_veto/again = new
		return om_emit(E, again)
	return E.enabled ? null : EVENT_VETO

/datum/om/behaviour/test/veto_handler
	handles = list(/datum/om/event/before/test_veto)

/datum/om/derived/test_double
	name = "test_double"
	inputs = CHANGE_DATUM_A
	channel = CHANGE_DATUM_D

/datum/om/derived/test_double/compute(datum/om_test_entity/E)
	return E.value * 2

/datum/om/derived/test_quad
	name = "test_quad"
	derived_inputs = list("test_double")
	channel = CHANGE_DATUM_C

/datum/om/derived/test_quad/compute(datum/om_test_entity/E)
	return om_derived(E, "test_double") * 2

/datum/om/derived/test_cycle_a
	name = "test_cycle_a"
	derived_inputs = list("test_cycle_b")
	channel = CHANGE_DATUM_A
	registry_skip = TRUE

/datum/om/derived/test_cycle_b
	name = "test_cycle_b"
	derived_inputs = list("test_cycle_a")
	channel = CHANGE_DATUM_B
	registry_skip = TRUE

/datum/om/behaviour/test/cycle_a
	order_after = list(/datum/om/behaviour/test/cycle_b)
	registry_skip = TRUE

/datum/om/behaviour/test/cycle_b
	order_after = list(/datum/om/behaviour/test/cycle_a)
	registry_skip = TRUE

/datum/om/service/test_observer
	wake_on_any = list(/datum/om_test_entity = CHANGE_DATUM_C)
	var/calls = 0
	var/last_bits = 0

/datum/om/service/test_observer/on_changes(datum/E, bits)
	calls++
	last_bits = bits

/datum/om/bundle/test_inner
	ticks = list(/datum/om_test_entity/proc/inline_tick = list("every" = 1 SECONDS))
	checks = list("test_enabled_named" = /datum/om/check/test_enabled)

/datum/om/bundle/test_outer
	include = list(/datum/om/bundle/test_inner)
	reacts = list(/datum/om_test_entity/proc/inline_react = CHANGE_DATUM_A)
	derived = list(
		DERIVE_SUM("test_weight_sum", /datum/om/relation/test_member, FROM_VAR("weight"), CHANGE_DATUM_B),
		DERIVE_MAX("test_weight_max", /datum/om/relation/test_member, FROM_VAR("weight"), 0),
		DERIVE_COUNT("test_member_count", /datum/om/relation/test_member, 0),
		DERIVE("test_enabled_derived", "test_enabled_named", CHANGE_DATUM_C),
	)
	tasks = list(
		"test_task" = list("duration" = 2 SECONDS, "claims" = TRUE, "requires" = list(/datum/om/check/test_enabled), "interrupted_by" = list(/datum/om/event/test/other)),
	)

/datum/om/decl/test_host
	of = /datum/om_test_entity/decl_host
	include = list(/datum/om/bundle/test_outer)
	self_grants = list(GRANT_TRAIT = "test_trait")

/datum/om/decl/test_bad
	registry_skip = TRUE
	of = /datum/om_test_entity
	include = list(/datum/om/bundle/test_bad_cycle_a)
	ticks = list(/datum/om_test_entity/proc/inline_tick = list("evry" = 1 SECONDS))
	reacts = list(/datum/om_test_entity/proc/inline_react = 0)
	effects = list("test_bad_effect" = list("combine" = 99, "colour" = "red"))
	derived = list(list("derive" = "median", "name" = "test_bad_derived"))

/datum/om/bundle/test_bad_cycle_a
	registry_skip = TRUE
	include = list(/datum/om/bundle/test_bad_cycle_b)

/datum/om/bundle/test_bad_cycle_b
	registry_skip = TRUE
	include = list(/datum/om/bundle/test_bad_cycle_a)

// ---------------------------------------------------------------- base

/datum/unit_test/om
	abstract_type = /datum/unit_test/om
	var/datum/om/scheduler/sched

/datum/unit_test/om/Run()
	sched = om_test_begin()
	var/list/made = list()
	try
		run_om(made)
	catch(var/exception/e)
		TEST_FAIL("runtime in om test: [e] ([e.file]:[e.line])")
	for(var/datum/D as anything in made)
		if(!QDELETED(D))
			qdel(D)
	om_test_end()

/datum/unit_test/om/proc/run_om(list/made)
	return

/datum/unit_test/om/proc/entity(list/made, path = /datum/om_test_entity)
	var/datum/om_test_entity/E = new path
	made += E
	return E

// ---------------------------------------------------------------- A: scheduling

/datum/unit_test/om/cadence_runs_with_dt

/datum/unit_test/om/cadence_runs_with_dt/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/every_second)
	scheduler_advance(5)
	TEST_ASSERT(E.ticks >= 4 && E.ticks <= 5, "expected 4-5 ticks in 5 s, got [E.ticks]")
	for(var/dt in E.dts.Copy(2))
		TEST_ASSERT(abs(dt - 1) < 0.01, "dt should be 1 s, got [dt]")
	TEST_ASSERT_EQUAL(E.starts, 1, "on_start once")
	om_detach(E, /datum/om/behaviour/test/every_second)
	TEST_ASSERT_EQUAL(E.stops, 1, "on_stop once")
	var/before = E.ticks
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(E.ticks, before, "a detached behaviour does not run")

/// Regression: skipped cadence slots on skipped ticks.
/datum/unit_test/om/regression_no_skipped_slots

/datum/unit_test/om/regression_no_skipped_slots/run_om(list/made)
	var/list/entities = list()
	for(var/i in 1 to 10)
		var/datum/om_test_entity/E = entity(made)
		entities += E
		om_attach(E, /datum/om/behaviour/test/every_second)
	scheduler_advance(1)
	sched.jump(3)
	sched.run(1e9)
	for(var/datum/om_test_entity/E as anything in entities)
		TEST_ASSERT(E.ticks >= 1, "an entity was skipped after a 3 s gap")
		var/total = 0
		for(var/dt in E.dts)
			total += dt
		TEST_ASSERT(abs(total - 4) < 0.15, "dt must carry the real elapsed time: [total] s of 4 s")

/// Regression: one lane starving the others and the deadlines.
/datum/unit_test/om/regression_lanes_do_not_starve

/datum/unit_test/om/regression_lanes_do_not_starve/run_om(list/made)
	sched.harness_caps = list(3, 3, 3, 3, 3)
	sched.harness_deadline_cap = 3
	var/list/crowd = list()
	for(var/i in 1 to 200)
		var/datum/om_test_entity/E = entity(made)
		crowd += E
		om_attach(E, /datum/om/behaviour/test/every_second)
	var/datum/om_test_entity/P = entity(made)
	om_attach(P, /datum/om/behaviour/test/presentation)
	var/datum/om_test_entity/D = entity(made)
	om_after(D, 5, /datum/om/behaviour/test/deadline_only)
	scheduler_advance(2)
	TEST_ASSERT(P.ticks >= 1, "presentation lane starved by the simulation lane")
	TEST_ASSERT_EQUAL(D.deadlines, 1, "deadline starved by the lanes")
	var/list/S = sched.stat_for(om_registry().behaviour(/datum/om/behaviour/test/every_second).id)
	TEST_ASSERT(S[OM_STAT_DEFERRALS] > 0, "the crowded lane should have deferred")
	sched.harness_caps = null
	sched.harness_deadline_cap = 0
	scheduler_advance(2)
	for(var/datum/om_test_entity/E as anything in crowd)
		TEST_ASSERT(E.ticks >= 1, "deferred work never ran")

/// Regression: a wake must not run the cadence work.
/datum/unit_test/om/regression_wake_is_not_tick

/datum/unit_test/om/regression_wake_is_not_tick/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/waker)
	om_changed(E, CHANGE_DATUM_A)
	om_changed(E, CHANGE_DATUM_B)
	om_changed(E, CHANGE_DATUM_C)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(E.wakes, 1, "changes in one tick coalesce into one on_wake")
	TEST_ASSERT_EQUAL(E.last_changes, CHANGE_DATUM_A | CHANGE_DATUM_B, "on_wake gets the union of watched bits")
	TEST_ASSERT_EQUAL(E.ticks, 0, "a wake never calls tick()")
	om_wake(E, /datum/om/behaviour/test/waker)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(E.wakes, 2, "om_wake() queues an on_wake")
	TEST_ASSERT(E.last_changes & CHANGE_EXPLICIT, "explicit wakes carry CHANGE_EXPLICIT")

/// Regression: hook return values are ignored; runtimes don't kill behaviours or other entities.
/datum/unit_test/om/regression_returns_and_runtimes

/datum/unit_test/om/regression_returns_and_runtimes/run_om(list/made)
	sched.expect_errors = TRUE
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/bad_returns)
	scheduler_advance(3)
	TEST_ASSERT(E.ticks >= 2, "odd return values stopped the behaviour ([E.ticks] ticks)")
	var/datum/om_test_entity/bad = entity(made)
	bad.crash_on_tick = TRUE
	var/datum/om_test_entity/good = entity(made)
	om_attach(bad, /datum/om/behaviour/test/every_second)
	om_attach(good, /datum/om/behaviour/test/every_second)
	scheduler_advance(3)
	TEST_ASSERT(good.ticks >= 2, "a runtime in one entity stopped the others")
	TEST_ASSERT(bad.ticks >= 2, "a runtime removed the entity from its ring")
	TEST_ASSERT(length(sched.errors) >= 2, "runtimes are recorded")

/datum/unit_test/om/order_after_runs_in_order

/datum/unit_test/om/order_after_runs_in_order/run_om(list/made)
	var/datum/om/registry/reg = om_registry()
	var/datum/om/behaviour/A = reg.behaviour(/datum/om/behaviour/test/every_second)
	var/datum/om/behaviour/B = reg.behaviour(/datum/om/behaviour/test/every_second_b)
	TEST_ASSERT(A.id < B.id, "order_after compiles into id order")
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/every_second_b)
	om_attach(E, /datum/om/behaviour/test/every_second)
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(length(E.log), 2, "both behaviours ran once in the same slot")
	TEST_ASSERT_EQUAL(E.log[1], "[/datum/om/behaviour/test/every_second]", "the earlier behaviour runs first")

/datum/unit_test/om/order_cycle_is_boot_error

/datum/unit_test/om/order_cycle_is_boot_error/run_om(list/made)
	var/datum/om/registry/reg = new
	reg.quiet = TRUE
	reg.include_skipped = TRUE
	reg.build()
	var/found_behaviour = FALSE
	var/found_derived = FALSE
	for(var/msg in reg.errors)
		if(findtext(msg, "order_after cycle"))
			found_behaviour = TRUE
		if(findtext(msg, "derived input cycle"))
			found_derived = TRUE
	TEST_ASSERT(found_behaviour, "an order_after cycle must be a boot error")
	TEST_ASSERT(found_derived, "a derived input cycle must be a boot error")

/datum/unit_test/om/clock_scales_dt_and_zero_sleeps

/datum/unit_test/om/clock_scales_dt_and_zero_sleeps/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/source = entity(made)
	om_attach(E, /datum/om/behaviour/test/clocked)
	om_hold(E, EFFECT_CLOCK_BIO_MULT, source, 2)
	TEST_ASSERT_EQUAL(om_clock_rate_of(E, CLOCK_BIO), 2, "multiplier applies")
	scheduler_advance(3)
	TEST_ASSERT(length(E.dts) >= 2, "clocked behaviour ran")
	var/last_dt = E.dts[length(E.dts)]
	TEST_ASSERT(abs(last_dt - 2) < 0.01, "dt is scaled by the clock rate: [last_dt]")
	om_hold(E, EFFECT_CLOCK_BIO_INHIBIT, source, 1)
	TEST_ASSERT_EQUAL(om_clock_rate_of(E, CLOCK_BIO), 0, "full inhibition stops the clock")
	var/before = E.ticks
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(E.ticks, before, "a zero-rate clock sleeps cadence work")
	qdel(source)
	TEST_ASSERT_EQUAL(om_clock_rate_of(E, CLOCK_BIO), 1, "deleting the source restores the rate")
	scheduler_advance(2)
	TEST_ASSERT(E.ticks > before, "cadence resumes")

/datum/unit_test/om/clocked_deadline_tracks_rate

/datum/unit_test/om/clocked_deadline_tracks_rate/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/source = entity(made)
	om_hold(E, EFFECT_CLOCK_BIO_MULT, source, 0.5)
	om_after(E, 2 SECONDS, /datum/om/behaviour/test/deadline_clocked)
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(E.deadlines, 0, "half speed: not yet")
	om_hold(E, EFFECT_CLOCK_BIO_MULT, source, 4)
	// 0.5 s of local time elapsed; 1.5 s left at 4x = 0.375 s real.
	scheduler_advance(0.5)
	TEST_ASSERT_EQUAL(E.deadlines, 1, "a rate increase re-inserts the deadline earlier")

/datum/unit_test/om/substeps_and_fixed_steps

/datum/unit_test/om/substeps_and_fixed_steps/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/substeps)
	scheduler_advance(1)
	sched.jump(1.5)
	sched.run(1e9)
	for(var/dt in E.dts)
		TEST_ASSERT(dt <= 0.25 + 0.001, "max_dt splits large dt into substeps: [dt]")
	var/datum/om_test_entity/S = entity(made)
	om_attach(S, /datum/om/behaviour/test/stepped)
	scheduler_advance(3)
	TEST_ASSERT(S.steps >= 9 && S.steps <= 15, "fixed steps follow elapsed time: [S.steps] steps in 3 s")

/datum/unit_test/om/relevance_moves_rings

/datum/unit_test/om/relevance_moves_rings/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/viewer = entity(made)
	om_attach(E, /datum/om/behaviour/test/relevant)
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(E.ticks, 0, "RELEVANCE_NONE sleeps this behaviour")
	om_observe(E, viewer, RELEVANCE_WATCHED)
	TEST_ASSERT_EQUAL(om_relevance(E), RELEVANCE_WATCHED, "relevance derives from observers")
	scheduler_advance(1)
	TEST_ASSERT(E.ticks >= 5, "WATCHED runs every decisecond: [E.ticks]")
	qdel(viewer)
	TEST_ASSERT_EQUAL(om_relevance(E), RELEVANCE_NONE, "observer gone, relevance drops")
	var/before = E.ticks
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(E.ticks, before, "back to sleep")

/datum/unit_test/om/requires_gates_membership

/datum/unit_test/om/requires_gates_membership/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	E.enabled = FALSE
	om_attach(E, /datum/om/behaviour/test/gated)
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(E.ticks, 0, "failing requires keeps it off the roster")
	TEST_ASSERT_EQUAL(E.starts, 0, "not started")
	E.enabled = TRUE
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(E.ticks, 0, "requires are only re-checked when their channel changes")
	om_changed(E, CHANGE_DATUM_B)
	scheduler_advance(2)
	TEST_ASSERT(E.ticks >= 1, "channel change re-evaluates requires")
	TEST_ASSERT_EQUAL(E.starts, 1, "on_start on joining")
	E.enabled = FALSE
	om_changed(E, CHANGE_DATUM_B)
	TEST_ASSERT_EQUAL(E.stops, 1, "on_stop on leaving")

/datum/unit_test/om/deadlines_replace_and_cancel

/datum/unit_test/om/deadlines_replace_and_cancel/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	om_after(E, 5, /datum/om/behaviour/test/deadline_only)
	om_after(E, 10, /datum/om/behaviour/test/deadline_only)
	scheduler_advance(0.7)
	TEST_ASSERT_EQUAL(E.deadlines, 0, "calling after() again replaces the deadline")
	scheduler_advance(0.5)
	TEST_ASSERT_EQUAL(E.deadlines, 1, "the replacement fires once")
	om_after(E, 5, /datum/om/behaviour/test/deadline_only)
	om_cancel_after(E, /datum/om/behaviour/test/deadline_only)
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(E.deadlines, 1, "cancelled deadlines never fire")
	var/datum/om_test_entity/doomed = entity(made)
	om_after(doomed, 5, /datum/om/behaviour/test/deadline_only)
	qdel(doomed)
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(doomed.deadlines, 0, "a deleted entity's deadline is skipped")
	om_after(E, 200 SECONDS, /datum/om/behaviour/test/deadline_only)
	scheduler_advance(201)
	TEST_ASSERT_EQUAL(E.deadlines, 2, "deadlines beyond one wheel turn still fire")

/// Regression: DM timers must not cost an FFI call (or a datum) per operation.
/datum/unit_test/om/regression_no_ffi_per_deadline

/datum/unit_test/om/regression_no_ffi_per_deadline/run_om(list/made)
	var/list/entities = list()
	for(var/i in 1 to 50)
		entities += entity(made)
	var/ffi_before = global.vars["__verdigris_ffi_calls"]
	for(var/datum/om_test_entity/E as anything in entities)
		om_after(E, 3, /datum/om/behaviour/test/deadline_only)
	scheduler_advance(0.5)
	TEST_ASSERT_EQUAL(global.vars["__verdigris_ffi_calls"], ffi_before, "deadlines crossed into Rust")
	for(var/datum/om_test_entity/E as anything in entities)
		TEST_ASSERT_EQUAL(E.deadlines, 1, "every deadline fired")

/datum/unit_test/om/native_delivery

/datum/unit_test/om/native_delivery/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/native_watcher)
	TEST_ASSERT_EQUAL(E.om_rec.native_bits, 1, "native interest registered")
	om_native_deliver(E, 3)
	TEST_ASSERT_EQUAL(E.native, 1, "on_native gets the declared bits")

/datum/unit_test/om/diagnostics_snapshot

/datum/unit_test/om/diagnostics_snapshot/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/every_second)
	scheduler_advance(2)
	var/list/snapshot = om_diagnostics(sched)
	var/list/types = snapshot["types"]
	var/list/row = types[om_registry().behaviour(/datum/om/behaviour/test/every_second).name]
	TEST_ASSERT_NOTNULL(row, "per-type counters exist")
	TEST_ASSERT(row["runs"] >= 1, "runs counted")
	TEST_ASSERT_EQUAL(row["population"], 1, "ring population reported")

// ---------------------------------------------------------------- B: change tracking

/datum/unit_test/om/listen_mask_short_circuits

/datum/unit_test/om/listen_mask_short_circuits/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	TEST_ASSERT_EQUAL(E.om_listen, 0, "nothing listens before joining")
	om_attach(E, /datum/om/behaviour/test/waker)
	TEST_ASSERT(E.om_listen & CHANGE_DATUM_A, "attachments add their interest")
	TEST_ASSERT(!(E.om_listen & CHANGE_DATUM_D), "unrelated bits stay out")
	om_detach(E, /datum/om/behaviour/test/waker)
	TEST_ASSERT(!(E.om_listen & CHANGE_DATUM_A), "detaching removes it")

/datum/unit_test/om/relation_forwarding

/datum/unit_test/om/relation_forwarding/run_om(list/made)
	var/datum/om_test_entity/A = entity(made)
	var/datum/om_test_entity/B = entity(made)
	var/datum/om_test_entity/C = entity(made)
	om_attach(A, /datum/om/behaviour/test/related_waker)
	om_link(A, B, /datum/om/relation/test_link)
	scheduler_advance(0.1)
	TEST_ASSERT(A.last_changes & CHANGE_RELATION_ADDED, "RELATION_ADDED wakes")
	A.last_changes = 0
	om_changed(B, CHANGE_DATUM_A)
	scheduler_advance(0.1)
	TEST_ASSERT(A.last_changes & CHANGE_RELATED, "a related entity's change is forwarded")
	// Two hops: A -> B -> C.
	om_attach(A, /datum/om/behaviour/test/two_hop)
	om_link(B, C, /datum/om/relation/test_link)
	scheduler_advance(0.1)
	A.wakes = 0
	om_changed(C, CHANGE_DATUM_B)
	scheduler_advance(0.1)
	TEST_ASSERT(A.wakes >= 1, "multi-hop forwarding")
	om_unlink(B, C, /datum/om/relation/test_link)
	scheduler_advance(0.1)
	A.wakes = 0
	om_changed(C, CHANGE_DATUM_B)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(A.wakes, 0, "unlinking an intermediate hop rebuilds the path")

/datum/unit_test/om/watch_and_service

/datum/unit_test/om/watch_and_service/run_om(list/made)
	var/datum/om_test_entity/owner = entity(made)
	var/datum/om_test_entity/target = entity(made)
	om_attach(owner, /datum/om/behaviour/test/waker)
	om_watch(owner, target, CHANGE_DATUM_D, /datum/om/behaviour/test/waker)
	om_changed(target, CHANGE_DATUM_D)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(owner.wakes, 1, "watch wakes its owner")
	qdel(target)
	TEST_ASSERT(!length(owner.om_rec.watching), "the watch dies with its target")
	var/datum/om/service/test_observer/S
	for(var/datum/om/service/candidate as anything in om_registry().services)
		if(istype(candidate, /datum/om/service/test_observer))
			S = candidate
	var/datum/om_test_entity/watched = entity(made)
	om_rec_of(watched)
	var/calls = S.calls
	om_changed(watched, CHANGE_DATUM_C)
	om_changed(watched, CHANGE_DATUM_C)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(S.calls, calls + 1, "global observers get one call per tick")

/datum/unit_test/om/bulk_coalesces

/datum/unit_test/om/bulk_coalesces/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/waker)
	om_attach(E, /datum/om/behaviour/test/handler)
	om_bulk_begin()
	om_changed(E, CHANGE_DATUM_A)
	om_changed(E, CHANGE_DATUM_B)
	TEST_ASSERT_EQUAL(E.om_rec.att_pend[1] | E.om_rec.att_pend[2], 0, "nothing dispatched inside bulk")
	var/datum/om/event/test/skipped = new
	skipped.skip_in_bulk = TRUE
	om_emit(E, skipped)
	om_bulk_end()
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(E.wakes, 1, "one wake after bulk_end")
	TEST_ASSERT_EQUAL(E.last_changes, CHANGE_DATUM_A | CHANGE_DATUM_B, "with the union of bits")
	TEST_ASSERT_EQUAL(E.events, 0, "skip_in_bulk events are dropped in bulk")

// ---------------------------------------------------------------- C: derived

/datum/unit_test/om/derived_lazy_eager_and_chained

/datum/unit_test/om/derived_lazy_eager_and_chained/run_om(list/made)
	var/datum/om/registry/reg = om_registry()
	var/datum/om/derived/D2 = reg.derived_def("test_double")
	var/datum/om/derived/D4 = reg.derived_def("test_quad")
	TEST_ASSERT(D2.order < D4.order, "derived inputs are ordered first")
	var/datum/om_test_entity/E = entity(made)
	E.value = 3
	TEST_ASSERT_EQUAL(om_derived(E, "test_quad"), 12, "derived of derived")
	E.value = 5
	om_changed(E, CHANGE_DATUM_A)
	TEST_ASSERT_EQUAL(om_derived(E, "test_quad"), 20, "dirtiness cascades lazily")
	TEST_ASSERT_EQUAL(om_derived(E, /datum/om/derived/test_double), 10, "readable by type too")
	om_attach(E, /datum/om/behaviour/test/derived_watcher)
	E.value = 7
	om_changed(E, CHANGE_DATUM_A)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(E.wakes, 1, "an observed derived value is eager and raises its channel")
	E.value = 7
	om_changed(E, CHANGE_DATUM_A)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(E.wakes, 1, "no channel when the value did not change")

/datum/unit_test/om/aggregates_delta_and_rescan

/datum/unit_test/om/aggregates_delta_and_rescan/run_om(list/made)
	var/datum/om_test_entity/holder = entity(made)
	var/list/members = list()
	TEST_ASSERT_EQUAL(om_derived(holder, "test_weight_sum"), 0, "empty sum")
	for(var/w in list(1, 2, 3))
		var/datum/om_test_entity/M = entity(made)
		M.weight = w
		members += M
		om_link(M, holder, /datum/om/relation/test_member)
	TEST_ASSERT_EQUAL(om_derived(holder, "test_weight_sum"), 6, "sum")
	TEST_ASSERT_EQUAL(om_derived(holder, "test_weight_max"), 3, "max")
	TEST_ASSERT_EQUAL(om_derived(holder, "test_member_count"), 3, "count")
	var/datum/om_test_entity/first = members[1]
	first.weight = 10
	om_changed(first, CHANGE_DATUM_A)
	// FROM_VAR readers have no channel of their own; declare member_inputs to track.
	om_unlink(first, holder, /datum/om/relation/test_member)
	TEST_ASSERT_EQUAL(om_derived(holder, "test_weight_sum"), 5, "member left: O(1) delta from the cached contribution")
	var/datum/om_test_entity/heaviest = members[3]
	qdel(heaviest)
	TEST_ASSERT_EQUAL(om_derived(holder, "test_weight_max"), 2, "the extreme left: rescan")
	TEST_ASSERT_EQUAL(om_derived(holder, "test_member_count"), 1, "deleting a member unlinks it")

// ---------------------------------------------------------------- D: relations

/datum/unit_test/om/relations_cardinality_and_queries

/datum/unit_test/om/relations_cardinality_and_queries/run_om(list/made)
	var/datum/om_test_entity/item = entity(made)
	var/datum/om_test_entity/box1 = entity(made)
	var/datum/om_test_entity/box2 = entity(made)
	om_link(item, box1, /datum/om/relation/test_member)
	om_link(item, box2, /datum/om/relation/test_member)
	TEST_ASSERT_EQUAL(om_relation_of(item, /datum/om/relation/test_member), box2, "source_single replaces")
	TEST_ASSERT_EQUAL(length(om_related_to(box1, /datum/om/relation/test_member)), 0, "old edge gone from both ends")
	var/datum/om_test_entity/seat = entity(made)
	var/datum/om_test_entity/first = entity(made)
	var/datum/om_test_entity/second = entity(made)
	TEST_ASSERT(!istext(om_link(first, seat, /datum/om/relation/test_single_refuse)), "first claim works")
	var/reason = om_link(second, seat, /datum/om/relation/test_single_refuse)
	TEST_ASSERT(istext(reason), "refused with a reason")

/// Regression: relation hooks never see a null end, and deletion unlinks before Destroy().
/datum/unit_test/om/regression_relation_hooks_non_null

/datum/unit_test/om/regression_relation_hooks_non_null/run_om(list/made)
	var/datum/om_test_entity/A = entity(made)
	var/datum/om_test_entity/B = entity(made)
	om_link(A, B, /datum/om/relation/test_hooked)
	qdel(A)
	TEST_ASSERT_EQUAL(A.log.len, 1, "on_unlink ran on delete")
	TEST_ASSERT_EQUAL(A.log[1], "unlink:1:1:1", "both ends non-null, deleting end QDELETED")
	TEST_ASSERT_EQUAL(A.edges_at_destroy, 0, "edges are gone before Destroy() (lifecycle phase 4 precedes phase 7)")
	TEST_ASSERT_EQUAL(length(om_related(B, /datum/om/relation/test_hooked)), 0, "other end cleaned")

/datum/unit_test/om/relation_contributions_active_if

/datum/unit_test/om/relation_contributions_active_if/run_om(list/made)
	var/datum/om_test_entity/armour = entity(made)
	var/datum/om_test_entity/wearer = entity(made)
	armour.weight = 4
	om_link(armour, wearer, /datum/om/relation/test_contributing)
	TEST_ASSERT_EQUAL(om_value_of(wearer, EFFECT_ARMOR_MELEE), 4, "contributes a FROM_VAR value to the target")
	TEST_ASSERT(om_has_grant(armour, GRANT_ABILITY, "test_ability"), "grants_occupant go to the source")
	armour.enabled = FALSE
	om_changed(armour, CHANGE_DATUM_B)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(om_value_of(wearer, EFFECT_ARMOR_MELEE), 0, "active_if failing releases")
	armour.enabled = TRUE
	om_changed(armour, CHANGE_DATUM_B)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(om_value_of(wearer, EFFECT_ARMOR_MELEE), 4, "active_if passing re-applies")
	om_unlink(armour, wearer, /datum/om/relation/test_contributing)
	TEST_ASSERT_EQUAL(om_value_of(wearer, EFFECT_ARMOR_MELEE), 0, "unlinking releases")
	TEST_ASSERT(!om_has_grant(armour, GRANT_ABILITY, "test_ability"), "and revokes")

// ---------------------------------------------------------------- E: contributions

/datum/unit_test/om/effects_timed_stacking_composites

/datum/unit_test/om/effects_timed_stacking_composites/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/src_a = entity(made)
	var/datum/om_test_entity/src_b = entity(made)
	TEST_ASSERT(om_value_of(E, EFFECT_CAN_MOVE), "composite default")
	om_apply(E, EFFECT_STUNNED, src_a, 1 SECONDS)
	TEST_ASSERT(om_has(E, EFFECT_STUNNED), "applied")
	TEST_ASSERT(!om_value_of(E, EFFECT_CAN_MOVE), "EFFECT_CAN_MOVE = NOT(ANY(stunned, ...))")
	om_apply(E, EFFECT_STUNNED, src_a, 3 SECONDS)
	scheduler_advance(2)
	TEST_ASSERT(om_has(E, EFFECT_STUNNED), "STACKING_MAX keeps the longer expiry")
	scheduler_advance(1.5)
	TEST_ASSERT(!om_has(E, EFFECT_STUNNED), "expired through the deadline wheel")
	TEST_ASSERT(om_value_of(E, EFFECT_CAN_MOVE), "composite follows its parts")
	om_hold(E, EFFECT_SLOWED, src_a, 2)
	om_hold(E, EFFECT_SLOWED, src_b, 3)
	TEST_ASSERT_EQUAL(om_value_of(E, EFFECT_SLOWED), 5, "COMBINE_SUM")
	om_release(E, EFFECT_SLOWED, src_a)
	TEST_ASSERT_EQUAL(om_value_of(E, EFFECT_SLOWED), 3, "release")
	om_hold(E, EFFECT_MOVE_SPEED, src_a, 0.5)
	om_hold(E, EFFECT_MOVE_SPEED, src_b, 0.5)
	TEST_ASSERT_EQUAL(om_value_of(E, EFFECT_MOVE_SPEED), 0.25, "COMBINE_MULTIPLY")

/// Regression: overrides never outlive their source.
/datum/unit_test/om/regression_no_stuck_overrides

/datum/unit_test/om/regression_no_stuck_overrides/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/source = entity(made)
	om_hold(E, EFFECT_PARALYZED, source)
	om_grant(E, GRANT_LANGUAGE, "test_language", source)
	TEST_ASSERT(om_has(E, EFFECT_PARALYZED), "held")
	qdel(source)
	TEST_ASSERT(!om_has(E, EFFECT_PARALYZED), "a hold dies with its source")
	TEST_ASSERT(!om_has_grant(E, GRANT_LANGUAGE, "test_language"), "so does a grant")
	// Holds made from a hook last only while the hook keeps making them.
	var/datum/om_test_entity/H = entity(made)
	om_attach(H, /datum/om/behaviour/test/holder)
	scheduler_advance(1.5)
	TEST_ASSERT(om_has(H, EFFECT_STUNNED), "hook hold made")
	H.enabled = FALSE
	scheduler_advance(1.5)
	TEST_ASSERT(!om_has(H, EFFECT_STUNNED), "not re-held: released on return")
	H.enabled = TRUE
	scheduler_advance(1.5)
	TEST_ASSERT(om_has(H, EFFECT_STUNNED), "held again")
	om_detach(H, /datum/om/behaviour/test/holder)
	TEST_ASSERT(!om_has(H, EFFECT_STUNNED), "stopping the behaviour releases its holds")

/datum/unit_test/om/grants_vocabulary

/datum/unit_test/om/grants_vocabulary/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/source = entity(made)
	om_grant(E, GRANT_ABILITY, "jump", source)
	om_grant(E, GRANT_VERB, "wave", source)
	TEST_ASSERT(om_has_grant(E, GRANT_ABILITY, "jump"), "granted")
	TEST_ASSERT_EQUAL(length(om_grants_from(E, source)), 2, "grants_from lists a source's grants")
	om_revoke(E, GRANT_ABILITY, "jump", source)
	TEST_ASSERT(!om_has_grant(E, GRANT_ABILITY, "jump"), "revoked")
	var/datum/om_test_entity/host = entity(made, /datum/om_test_entity/decl_host)
	om_start(host)
	TEST_ASSERT(om_has_grant(host, GRANT_TRAIT, "test_trait"), "decl self_grants")

// ---------------------------------------------------------------- F: rates

/datum/unit_test/om/rates_thresholds

/datum/unit_test/om/rates_thresholds/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/waker)
	var/datum/om/rate/R = om_rate_new(E, "charge", 0, 2, CHANGE_DATUM_A, list(10))
	TEST_ASSERT_EQUAL(R.time_until(10), 50, "time_until in deciseconds")
	scheduler_advance(4)
	TEST_ASSERT_EQUAL(E.wakes, 0, "no crossing yet")
	TEST_ASSERT(abs(R.now() - 8) < 0.01, "value at time")
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(E.wakes, 1, "crossing publishes the channel once")
	R.set_rate(-4)
	TEST_ASSERT(abs(R.now() - 11) < 0.25, "set_rate settles first")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(E.wakes, 2, "crossing back down")
	var/list/stream = om_ui_rate(R)
	TEST_ASSERT_EQUAL(stream["rate"], -4, "rate streaming helper")

// ---------------------------------------------------------------- G: events

/// Regression: subtype events reach handlers of the parent type.
/datum/unit_test/om/regression_subtype_events

/datum/unit_test/om/regression_subtype_events/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/handler)
	om_emit(E, new /datum/om/event/test/sub)
	TEST_ASSERT_EQUAL(E.events, 1, "a subtype event was missed (exact-type lookup)")

/// Regression: re-entrant events are queued, never silently dropped; veto re-entry errors loudly.
/datum/unit_test/om/regression_reentrant_events

/datum/unit_test/om/regression_reentrant_events/run_om(list/made)
	sched.expect_errors = TRUE
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/handler)
	var/datum/om/event/test/outer = new
	outer.payload = "reenter"
	om_emit(E, outer)
	TEST_ASSERT_EQUAL(E.events, 2, "the inner event was dropped")
	TEST_ASSERT_EQUAL(E.log[2], "after inner emit", "the inner event is queued, not nested")
	TEST_ASSERT_EQUAL(E.log[3], "event:[/datum/om/event/test/sub]:inner", "and delivered right after")
	om_attach(E, /datum/om/behaviour/test/veto_handler)
	E.enabled = FALSE
	TEST_ASSERT_EQUAL(om_emit(E, new /datum/om/event/before/test_veto), EVENT_VETO, "veto")
	E.enabled = TRUE
	TEST_ASSERT_NULL(om_emit(E, new /datum/om/event/before/test_veto), "no veto")
	var/errors = length(sched.errors)
	var/datum/om/event/before/test_veto/again = new
	again.reenter = TRUE
	TEST_ASSERT_EQUAL(om_emit(E, again), EVENT_VETO, "re-entrant veto event is refused")
	TEST_ASSERT(length(sched.errors) > errors, "and reported")

/// Regression: a runtime can't leave draining or transaction flags set.
/datum/unit_test/om/regression_flags_cannot_stick

/datum/unit_test/om/regression_flags_cannot_stick/run_om(list/made)
	sched.expect_errors = TRUE
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/handler)
	var/datum/om/event/test/bad = new
	bad.payload = "crash"
	om_emit(E, bad)
	TEST_ASSERT_EQUAL(sched.emit_depth, 0, "emit depth reset after a handler runtime")
	om_emit(E, new /datum/om/event/test)
	TEST_ASSERT_EQUAL(E.events, 2, "later events still deliver")
	E.crash_on_tick = TRUE
	om_attach(E, /datum/om/behaviour/test/every_second)
	scheduler_advance(1.5)
	TEST_ASSERT(!sched.dl_processing, "deadline flag reset")
	TEST_ASSERT_NULL(sched.ctx_rec, "hook context reset")
	TEST_ASSERT_EQUAL(sched.bulk_depth, 0, "bulk depth untouched")

// ---------------------------------------------------------------- H: checks

/datum/unit_test/om/checks_combinators_and_cache

/datum/unit_test/om/checks_combinators_and_cache/run_om(list/made)
	var/datum/om/check/a = om_check_get(CHECK(/datum/om/check/in_range, 3))
	var/datum/om/check/b = om_check_get(list(/datum/om/check/in_range = 3))
	TEST_ASSERT(a && a == b, "parameterised checks are cached by value")
	TEST_ASSERT(a != om_check_get(CHECK(/datum/om/check/in_range, 4)), "different parameter, different instance")
	var/datum/om/check/combo = om_check_get(ALL_OF(/datum/om/check/test_enabled, NOT_OF(/datum/om/check/has_effect)))
	TEST_ASSERT(combo.depends_on & CHANGE_DATUM_B, "depends_on is the union of parts")
	TEST_ASSERT(combo.depends_on & CHANGE_EFFECTS, "including nested parts")
	var/datum/om_test_entity/E = entity(made)
	TEST_ASSERT(om_can(ANY_OF(/datum/om/check/test_enabled, /datum/om/check/target_exists), E, null), "ANY_OF")
	E.enabled = FALSE
	TEST_ASSERT_EQUAL(om_why_not(/datum/om/check/test_enabled, E, null), "disabled", "why_not gives the reason")
	TEST_ASSERT(om_can(NOT_OF(/datum/om/check/test_enabled), E, null), "NOT_OF")
	TEST_ASSERT(om_can(CHECK(/datum/om/check/var_below, list("weight", 5)), E, null), "library check with list param")
	TEST_ASSERT(om_can("test_enabled_named", E, null) == FALSE, "named checks from bundles")

// ---------------------------------------------------------------- I: tasks

/datum/unit_test/om/tasks_complete_claim_interrupt

/datum/unit_test/om/tasks_complete_claim_interrupt/run_om(list/made)
	var/datum/om_test_entity/actor = entity(made)
	var/datum/om_test_entity/other = entity(made)
	var/datum/om_test_entity/target = entity(made)
	var/datum/om/task/T = om_task_start(actor, "test_task", target)
	TEST_ASSERT(istype(T), "task started: [T]")
	TEST_ASSERT(istext(om_task_start(other, "test_task", target)), "claim gives exclusivity with a reason")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(T.state, OM_TASK_RUNNING, "still running")
	scheduler_advance(1.2)
	TEST_ASSERT_EQUAL(T.state, OM_TASK_DONE, "completed by its deadline")
	var/datum/om/task/T2 = om_task_start(other, "test_task", target)
	TEST_ASSERT(istype(T2), "claim released on completion")
	other.enabled = FALSE
	om_changed(other, CHANGE_DATUM_B)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(T2.state, OM_TASK_CANCELLED, "requires failing cancels")
	var/datum/om/task/T3 = om_task_start(actor, "test_task", target)
	om_emit(actor, new /datum/om/event/test/other)
	TEST_ASSERT_EQUAL(T3.state, OM_TASK_CANCELLED, "interrupted_by cancels")
	var/datum/om/task/T4 = om_task_start(actor, "test_task", target)
	qdel(target)
	TEST_ASSERT_EQUAL(T4.state, OM_TASK_CANCELLED, "deleting the target cancels")

/// Regression: waits must have a timeout.
/datum/unit_test/om/regression_await_needs_timeout

/datum/unit_test/om/regression_await_needs_timeout/run_om(list/made)
	var/caught = FALSE
	try
		om_await(null, null)
	catch
		caught = TRUE
	TEST_ASSERT(caught, "om_await() without a timeout must fail")

// ---------------------------------------------------------------- J: UI

/datum/unit_test/om/ui_bind_coalesces_and_throttles

/datum/unit_test/om/ui_bind_coalesces_and_throttles/run_om(list/made)
	var/datum/om_test_entity/session = entity(made)
	var/datum/om_test_entity/target = entity(made)
	om_ui_bind(session, target, CHANGE_DATUM_A)
	TEST_ASSERT_EQUAL(om_relevance(target), RELEVANCE_WATCHED, "binding raises relevance to WATCHED")
	om_changed(target, CHANGE_DATUM_A)
	om_changed(target, CHANGE_DATUM_A)
	om_changed(target, CHANGE_DATUM_A)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(session.ui_pushes, 1, "changes coalesce into one push")
	om_changed(target, CHANGE_DATUM_A)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(session.ui_pushes, 1, "throttled")
	scheduler_advance(0.3)
	TEST_ASSERT_EQUAL(session.ui_pushes, 2, "the throttled change is pushed later")
	om_ui_unbind(session, target)
	TEST_ASSERT_EQUAL(om_relevance(target), RELEVANCE_NONE, "unbinding drops relevance")

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

/datum/unit_test/om/decl_tables_and_bundles

/datum/unit_test/om/decl_tables_and_bundles/run_om(list/made)
	TEST_ASSERT(om_type_has_decl(/datum/om_test_entity/decl_host), "decl typecache")
	TEST_ASSERT(!om_type_has_decl(/datum/om_test_entity), "only the declared family")
	var/datum/om_test_entity/E = entity(made, /datum/om_test_entity/decl_host)
	om_start(E)
	scheduler_advance(2)
	TEST_ASSERT(E.ticks >= 1, "a tick row from a nested bundle calls the entity's proc")
	om_changed(E, CHANGE_DATUM_A)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(E.wakes, 1, "a reacts row calls the entity's proc")
	TEST_ASSERT_EQUAL(om_derived(E, "test_enabled_derived"), TRUE, "DERIVE() over a named check")

/datum/unit_test/om/table_errors_surface_at_boot

/datum/unit_test/om/table_errors_surface_at_boot/run_om(list/made)
	var/datum/om/registry/reg = new
	reg.quiet = TRUE
	reg.include_skipped = TRUE
	reg.only_bundles = list(/datum/om/decl/test_bad)
	reg.build()
	var/list/wanted = list("include cycle", "unknown key evry", "non-zero channel mask", "bad combine", "unknown key colour", "unknown kind median")
	for(var/needle in wanted)
		var/found = FALSE
		for(var/msg in reg.errors)
			if(findtext(msg, needle))
				found = TRUE
				break
		TEST_ASSERT(found, "expected a boot error containing '[needle]'; got: [jointext(reg.errors, " | ")]")
	TEST_ASSERT(!length(om_registry().errors), "the live registry has no errors: [jointext(om_registry().errors, " | ")]")

/// Regression: per-type config is never mutated per entity.
/datum/unit_test/om/regression_defs_are_immutable

/datum/unit_test/om/regression_defs_are_immutable/run_om(list/made)
	var/datum/om/behaviour/B = om_registry().behaviour(/datum/om/behaviour/test/relevant)
	var/list/before = B.compiled_intervals.Copy()
	var/list/relevance_before = B.relevance.Copy()
	var/datum/om_test_entity/A = entity(made)
	var/datum/om_test_entity/C = entity(made)
	var/datum/om_test_entity/viewer = entity(made)
	om_attach(A, B)
	om_attach(C, B)
	om_observe(A, viewer, RELEVANCE_WATCHED)
	scheduler_advance(1)
	TEST_ASSERT(A.ticks > 0 && C.ticks == 0, "per-entity relevance, not per-type")
	for(var/i in 1 to 4)
		TEST_ASSERT_EQUAL(B.compiled_intervals[i], before[i], "compiled intervals unchanged")
		TEST_ASSERT_EQUAL(B.relevance[i], relevance_before[i], "declaration unchanged")
