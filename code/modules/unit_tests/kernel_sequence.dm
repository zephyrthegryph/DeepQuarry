/// Kernel sequences (code/controllers/kernel/sequence*.dm): the semantics of the pipeline runner's tests
/// (dq_om_pipeline_tests.dm) on a test sequence, plus the Life order lock and on_change(at_most =).

// ---------------------------------------------------------------- fixtures

/// A test entity. Every step logs its name when it runs and has work while its name is in `busy`.
/datum/seq_test_entity
	/// Read by the "on" condition (its read "on" wakes the steps it blocks).
	var/on = TRUE
	/// Read by the "lit" condition (no read: nothing announces it).
	var/lit = TRUE
	/// The "heat" step has work while it is above 0 (read "heat", a TRACKED var).
	var/heat = 0
	var/admitted = TRUE
	var/abort_now = FALSE
	var/nested = FALSE
	/// The "on" condition's evaluations.
	var/on_reads = 0
	var/plan_key
	var/list/log = list()
	var/list/busy = list()

TRACKED_BRIDGED(/datum/seq_test_entity, heat, CHANGE_DATUM_B)

/datum/seq_test_entity/seq_plan_key()
	return plan_key

/// Overrides a step: the sequence's variants are plain overriding.
/datum/seq_test_entity/deep
/// Declares a cycle and an edge to nothing.
/datum/seq_test_entity/cyclic

/datum/seq_test_entity/proc/test_steps()
	return list(
		seq_step(PROC_REF(sb), after = "T_FIRST", should_run = PROC_REF(sb_busy)),
		seq_step(PROC_REF(sa), after = list("T_FIRST", "sb"), should_run = PROC_REF(sa_busy)),
		seq_step(PROC_REF(sc), after = "T_FIRST", should_run = PROC_REF(sc_busy)),
		seq_step(PROC_REF(sd), after = "T_FIRST", when = "on", should_run = PROC_REF(sd_busy)),
		seq_step(PROC_REF(se), after = "T_FIRST", should_run = PROC_REF(se_busy), rewake = 3 SECONDS),
		seq_step(PROC_REF(sf), after = "T_FIRST", should_run = PROC_REF(sf_busy)),
		seq_step(PROC_REF(sg), after = "T_FIRST", should_run = PROC_REF(sg_busy)),
		seq_step(PROC_REF(sh), after = "T_FIRST", when = "lit", should_run = PROC_REF(sh_busy)),
		seq_step(PROC_REF(sn), after = "T_FIRST", when = "!on", should_run = PROC_REF(sn_busy)),
		seq_step(PROC_REF(so), after = "T_FIRST", when = "on", should_run = PROC_REF(so_busy)),
		seq_step(PROC_REF(heat), after = "T_FIRST", reads = nameof(heat), should_run = PROC_REF(heat_hot), woken_by = "set_heat()"),
		seq_step(PROC_REF(chan), after = "T_FIRST", reads = CHANGE_DATUM_C, should_run = PROC_REF(chan_busy)),
		seq_step(PROC_REF(tail), after = "T_LAST", should_run = PROC_REF(tail_busy)),
	)

/datum/seq_test_entity/cyclic/test_steps()
	. = ..()
	. += seq_step(PROC_REF(cx), after = list("T_FIRST", "cy"))
	. += seq_step(PROC_REF(cy), after = list("T_FIRST", "cx", "nothing"))

// One step body and one should_run per name.
#define SEQ_TEST_STEP(NAME) /datum/seq_test_entity/proc/##NAME(datum/seq_frame/test/F) { log += #NAME; }; /datum/seq_test_entity/proc/##NAME##_busy() { return (#NAME in busy); }
SEQ_TEST_STEP(sa)
SEQ_TEST_STEP(sb)
SEQ_TEST_STEP(sc)
SEQ_TEST_STEP(sd)
SEQ_TEST_STEP(se)
SEQ_TEST_STEP(sh)
SEQ_TEST_STEP(sn)
SEQ_TEST_STEP(so)
SEQ_TEST_STEP(chan)
SEQ_TEST_STEP(tail)
SEQ_TEST_STEP(cx)
SEQ_TEST_STEP(cy)
#undef SEQ_TEST_STEP

/datum/seq_test_entity/deep/sa(datum/seq_frame/test/F)
	log += "sa deep"

/// Stops the frame when asked.
/datum/seq_test_entity/proc/sf(datum/seq_frame/test/F)
	log += "sf"
	if(abort_now)
		return F.abort()

/datum/seq_test_entity/proc/sf_busy()
	return ("sf" in busy)

/// Runs another step on demand inside the frame (a second frame from the pool while this one is in use).
/datum/seq_test_entity/proc/sg(datum/seq_frame/test/F)
	log += "sg"
	if(nested)
		nested = FALSE
		run_step_now(src, "sa", /datum/sequence/test)
		F.cond("on")

/datum/seq_test_entity/proc/sg_busy()
	return ("sg" in busy)

/datum/seq_test_entity/proc/heat(datum/seq_frame/test/F)
	log += "heat"

/datum/seq_test_entity/proc/heat_hot()
	return heat > 0

/// A contributor of the entity's own (seq_extra_add()): its step runs on it with (entity, frame).
/datum/seq_test_contributor
	var/calls = 0

/datum/seq_test_contributor/proc/test_steps()
	return list(seq_step(PROC_REF(helper), after = "T_FIRST"))

/datum/seq_test_contributor/proc/helper(datum/seq_test_entity/E, datum/seq_frame/test/F)
	calls++
	E.log += "helper"

/datum/seq_frame/test

/datum/seq_frame/test/proc/cond_on()
	var/datum/seq_test_entity/E = entity
	E.on_reads++
	return E.on

/datum/seq_frame/test/proc/cond_lit()
	var/datum/seq_test_entity/E = entity
	return E.lit

/// The test sequence: a 1 s fixed step, catch-up of 2, parking after 2 idle frames. The live kernel does not sweep
/// it: a test drives its own kernel and item (seq_test_kernel()) or runs frames directly.
/datum/sequence/test
	name = "test sequence"
	interval = 1 SECONDS
	step = 1
	max_catchup = 2
	park_after = 2
	wake_all = CHANGE_EXPLICIT
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	table_proc = TYPE_PROC_REF(/datum/seq_test_entity, test_steps)
	frame_type = /datum/seq_frame/test
	autoregister = FALSE
	admit_guard = TRUE

/datum/sequence/test/anchors()
	return list(seq_anchor("T_FIRST"), seq_anchor("T_LAST", after = "T_FIRST"))

/datum/sequence/test/conditions()
	return list(
		seq_condition("on", TYPE_PROC_REF(/datum/seq_frame/test, cond_on), "on"),
		seq_condition("lit", TYPE_PROC_REF(/datum/seq_frame/test, cond_lit)),
	)

/datum/sequence/test/admit(datum/seq_test_entity/E)
	return E.admitted

/// Out of the sweep below RELEVANCE_NEAR.
/datum/sequence/test/relevance
	name = "test sequence (relevance)"
	min_relevance = RELEVANCE_NEAR

/// Game run level only (the dormant test).
/datum/sequence/test/game_only
	name = "test sequence (game only)"
	runlevels = RUNLEVEL_GAME

/// Every frame profiled.
/datum/sequence/test/profiled
	name = "test sequence (profiled)"
	profile_stride = 1

/// A kernel of the test's own with a fresh sweep item for `path` (its run level set to game; the sweep not spread
/// unless `spread`, so every member runs on every due pass). Returns list(K, W).
/proc/seq_test_kernel(path, spread = FALSE)
	var/datum/controller/kernel/K = new
	var/datum/sequence/S = sequence_def(path)
	var/datum/work_item/sequence/W = new(S)
	W.test_runlevel = RUNLEVEL_GAME
	W.spread = spread
	S.work = W
	K.register_work(path, W)
	return list(K, W)

/// An atom whose capability contributes a step.
/obj/seq_test_atom
	name = "sequence test atom"
	var/list/log = list()

/obj/seq_test_atom/capabilities()
	. = ..()
	. += cap_seq_test()

/obj/seq_test_atom/proc/test_steps()
	return list(seq_step(PROC_REF(own_step), after = "T_FIRST"))

/obj/seq_test_atom/proc/own_step(datum/seq_frame/test/F)
	log += "own"

/datum/capability/seq_test

/proc/cap_seq_test()
	return new /datum/capability/seq_test

/datum/capability/seq_test/proc/test_steps()
	return list(seq_step(PROC_REF(cap_step), after = "T_FIRST"))

/datum/capability/seq_test/proc/cap_step(obj/seq_test_atom/A, datum/seq_frame/test/F)
	A.log += "cap"

#define SEQ_TEST /datum/sequence/test
/// Every step, in the order the table runs them (anchors dropped; "sn" is gated off while "on" holds).
#define SEQ_TEST_ORDER "chan,heat,sb,sa,sc,sd,se,sf,sg,sh,so,tail"

// ---------------------------------------------------------------- order and tables

/// Steps run in `after` order, then by key; anchors are barriers; one table per type key; overriding replaces
/// variants; a cycle and an edge to nothing are reported, and the steps still run.
/datum/unit_test/kernel_sequence_order

/datum/unit_test/kernel_sequence_order/Run()
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	var/datum/seq_state/S = seq_start(E, SEQ_TEST)
	TEST_ASSERT_NOTNULL(S, "started")
	TEST_ASSERT_EQUAL(seq_start(E, SEQ_TEST), S, "starting twice is the same state")
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT_EQUAL(jointext(E.log, ","), SEQ_TEST_ORDER, "sb before sa (an edge beats the key), T_LAST's tail last (a barrier)")
	TEST_ASSERT_EQUAL(jointext(S.table.order, ","), "T_FIRST,chan,heat,sb,sa,sc,sd,se,sf,sg,sh,sn,so,T_LAST,tail", "the anchors are in the order, sn is in the table")
	TEST_ASSERT_EQUAL(length(S.table.errors), 0, "a clean table has no errors")

	var/datum/seq_test_entity/twin = allocate(/datum/seq_test_entity)
	var/datum/seq_state/twin_state = seq_start(twin, SEQ_TEST)
	TEST_ASSERT_EQUAL(twin_state.table, S.table, "one table per type key")
	var/datum/seq_test_entity/wide = allocate(/datum/seq_test_entity)
	wide.plan_key = "wide"
	var/datum/seq_state/wide_state = seq_start(wide, SEQ_TEST)
	TEST_ASSERT_NOTEQUAL(wide_state.table, S.table, "seq_plan_key() is part of the key")

	var/datum/seq_test_entity/deep/D = allocate(/datum/seq_test_entity/deep)
	seq_start(D, SEQ_TEST)
	seq_run_frame_now(D, SEQ_TEST)
	TEST_ASSERT(("sa deep" in D.log) && !("sa" in D.log), "a subtype's override runs in the step's place: [jointext(D.log, ",")]")

	var/datum/sequence/def = sequence_def(SEQ_TEST)
	def.expect_errors = TRUE
	var/datum/seq_test_entity/cyclic/C = allocate(/datum/seq_test_entity/cyclic)
	var/datum/seq_state/cyclic_state = seq_start(C, SEQ_TEST)
	def.expect_errors = FALSE
	TEST_ASSERT(length(cyclic_state.table.errors) >= 1, "a cycle is reported (graph_validate)")
	TEST_ASSERT(("nothing" in cyclic_state.table.unresolved), "an edge to a key the table lacks is recorded")
	seq_run_frame_now(C, SEQ_TEST)
	TEST_ASSERT(("cx" in C.log) && ("cy" in C.log), "steps in a cycle still run: a bad table must not silence the entity")

// ---------------------------------------------------------------- sleep and wake

/// A step sleeps when its should_run() is FALSE after it ran. publish_change() of a key wakes the steps that read
/// it, changed() of a channel the steps that read that, a wake_all channel every step. The sequence's reads
/// are READERS on the type, so a TRACKED setter publishes them.
/datum/unit_test/kernel_sequence_sleep_wake

/datum/unit_test/kernel_sequence_sleep_wake/Run()
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	var/datum/seq_state/S = seq_start(E, SEQ_TEST)
	E.busy = list("sa")
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT_EQUAL(S.asleep, S.table.n - 1, "every step but the busy one sleeps")
	E.log.Cut()
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT_EQUAL(jointext(E.log, ","), "sa", "sleeping steps are skipped")

	TEST_ASSERT(READERS(E, "heat"), "a step's read is a reader on the type")
	TEST_ASSERT(READERS(E, "on"), "and so is a condition's read")
	TEST_ASSERT(!READERS(E, "lit"), "a condition without reads reads nothing")
	E.heat = 5
	publish_change(E, "heat")
	TEST_ASSERT(!seq_step_asleep(E, SEQ_TEST, "heat"), "publishing a key wakes the step that reads it")
	TEST_ASSERT(seq_step_asleep(E, SEQ_TEST, "sc"), "and only that one")
	E.log.Cut()
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT_EQUAL(jointext(E.log, ","), "heat,sa", "the woken step runs")
	TEST_ASSERT(!seq_step_asleep(E, SEQ_TEST, "heat"), "and stays awake while it has work")
	E.set_heat(0)
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT(seq_step_asleep(E, SEQ_TEST, "heat"), "with no work left it sleeps")

	changed(E, CHANGE_DATUM_C)
	TEST_ASSERT(!seq_step_asleep(E, SEQ_TEST, "chan"), "changed() of a channel wakes the step that reads it")
	TEST_ASSERT(seq_step_asleep(E, SEQ_TEST, "heat"), "and not the others")
	E.set_heat(2)
	TEST_ASSERT(!seq_step_asleep(E, SEQ_TEST, "heat"), "a TRACKED setter publishes the read (READERS)")
	E.heat = 0
	E.log.Cut()
	seq_run_frame_now(E, SEQ_TEST)
	changed(E, CHANGE_EXPLICIT)
	TEST_ASSERT_EQUAL(S.asleep, 0, "a wake_all channel wakes every step")

/// A woken step is asked should_run() before it runs: FALSE sends it back to sleep without running; TRUE runs it.
/datum/unit_test/kernel_sequence_precheck

/datum/unit_test/kernel_sequence_precheck/Run()
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	var/datum/seq_state/S = seq_start(E, SEQ_TEST)
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT_EQUAL(S.asleep, S.table.n, "with nothing to do every step sleeps")
	publish_change(E, "heat")
	TEST_ASSERT(!seq_step_asleep(E, SEQ_TEST, "heat"), "a publish wakes it")
	E.log.Cut()
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT_EQUAL(length(E.log), 0, "its should_run() is FALSE: it did not run")
	TEST_ASSERT(seq_step_asleep(E, SEQ_TEST, "heat"), "and went back to sleep")
	TEST_ASSERT_NULL(S.woken, "no woken bits are left")
	E.heat = 3
	publish_change(E, "heat")
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT_EQUAL(jointext(E.log, ","), "heat", "a woken step with work runs")

/// Conditions gate steps, evaluated lazily and once per frame. A step blocked by a condition whose reads wake it
/// sleeps and wakes on the read; one blocked by a condition with no reads stays awake (while it has work).
/datum/unit_test/kernel_sequence_conditions

/datum/unit_test/kernel_sequence_conditions/Run()
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	seq_start(E, SEQ_TEST)
	E.busy = list("sd", "so", "sn", "sh")
	E.on = FALSE
	E.lit = FALSE
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT_EQUAL(E.on_reads, 1, "two steps gated on one condition: evaluated once in the frame")
	TEST_ASSERT(!("sd" in E.log) && !("so" in E.log), "a failing condition skips its steps")
	TEST_ASSERT(("sn" in E.log), "a negated condition runs its step while it is false")
	TEST_ASSERT(seq_step_asleep(E, SEQ_TEST, "sd"), "blocked by a condition whose read wakes it: it sleeps")
	TEST_ASSERT(!seq_step_asleep(E, SEQ_TEST, "sh"), "blocked by a condition nothing announces: it stays awake")
	E.busy -= "sh"
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT(seq_step_asleep(E, SEQ_TEST, "sh"), "blocked with no work left: it sleeps")
	E.on_reads = 0
	E.log.Cut()
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT(E.on_reads <= 1, "evaluated only when a step asks")
	E.on = TRUE
	publish_change(E, "on")
	TEST_ASSERT(!seq_step_asleep(E, SEQ_TEST, "sd") && !seq_step_asleep(E, SEQ_TEST, "so"), "the condition's read wakes the steps it blocked")
	E.log.Cut()
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT(("sd" in E.log) && ("so" in E.log), "and they run")
	TEST_ASSERT(seq_step_asleep(E, SEQ_TEST, "sn"), "the negated one is blocked now")

	// The frame API: cached per frame, forget() evaluates again.
	var/datum/seq_frame/test/F = take(/datum/seq_frame/test)
	F.seq = sequence_def(SEQ_TEST)
	F.entity = E
	E.on_reads = 0
	F.cond("on")
	F.cond("on")
	TEST_ASSERT_EQUAL(E.on_reads, 1, "cond() is computed once per frame")
	F.forget("on")
	F.cond("on")
	TEST_ASSERT_EQUAL(E.on_reads, 2, "forget() computes it again")
	F.release()

/// STEP_ABORT (F.abort()) stops the frame and nothing sleeps that frame; admit() FALSE runs no frame.
/datum/unit_test/kernel_sequence_abort

/datum/unit_test/kernel_sequence_abort/Run()
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	var/datum/seq_state/S = seq_start(E, SEQ_TEST)
	E.abort_now = TRUE
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT(("sf" in E.log) && !("sg" in E.log), "an aborted frame stops after the aborting step: [jointext(E.log, ",")]")
	TEST_ASSERT_EQUAL(S.asleep, 0, "and nothing sleeps that frame (the steps before it went back to awake)")
	TEST_ASSERT_EQUAL(S.idle_frames, 0, "and it is no idle frame")
	E.abort_now = FALSE
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT_EQUAL(S.asleep, S.table.n, "the next frame runs to the end")

	var/list/pair = seq_test_kernel(SEQ_TEST)
	var/datum/controller/kernel/K = pair[1]
	var/datum/work_item/sequence/W = pair[2]
	var/datum/seq_test_entity/G = allocate(/datum/seq_test_entity)
	var/datum/seq_state/GS = seq_start(G, SEQ_TEST)
	G.admitted = FALSE
	K.run_item(W, WORK_TEST_LIMIT, 100)
	TEST_ASSERT_EQUAL(GS.frames, 0, "admit() FALSE: no frame")
	G.admitted = TRUE
	K.run_item(W, WORK_TEST_LIMIT, 110)
	TEST_ASSERT_EQUAL(GS.frames, 1, "admitted: its frame runs")
	TEST_ASSERT(GS.acc < 1, "the refused interval was spent, not saved up ([GS.acc])")

// ---------------------------------------------------------------- parking and relevance

/// A member whose steps all sleep for park_after frames leaves the sweep; a parked member runs no frames; a wake
/// brings it back. A member below min_relevance is out of the sweep; relevance brings it back unless it is parked.
/datum/unit_test/kernel_sequence_parking

/datum/unit_test/kernel_sequence_parking/Run()
	var/list/pair = seq_test_kernel(SEQ_TEST)
	var/datum/controller/kernel/K = pair[1]
	var/datum/work_item/sequence/W = pair[2]
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	var/datum/seq_state/S = seq_start(E, SEQ_TEST)
	TEST_ASSERT(member_is(SEQ_TEST, E), "a started member is in the sweep")
	E.busy = list("sa")
	K.run_item(W, WORK_TEST_LIMIT, 100)
	TEST_ASSERT_EQUAL(S.frames, 1, "the sweep ran its frame")
	E.busy.Cut()
	K.run_item(W, WORK_TEST_LIMIT, 110)
	TEST_ASSERT_EQUAL(S.idle_frames, 1, "every step asleep: one idle frame")
	TEST_ASSERT(!S.parked, "one idle frame doesn't park (hysteresis)")
	K.run_item(W, WORK_TEST_LIMIT, 120)
	TEST_ASSERT(S.parked, "two in a row park it")
	TEST_ASSERT(!member_is(SEQ_TEST, E), "out of the sweep")
	TEST_ASSERT((E in members_of(sequence_def(SEQ_TEST).parked_key)), "and in the parked list")
	var/before = S.frames
	for(var/now in list(130, 140, 150, 160))
		K.run_item(W, WORK_TEST_LIMIT, now)
	TEST_ASSERT_EQUAL(S.frames, before, "a parked member runs no frames")
	E.heat = 1
	publish_change(E, "heat")
	TEST_ASSERT(!S.parked, "a wake unparks it")
	TEST_ASSERT(member_is(SEQ_TEST, E), "back in the sweep")
	TEST_ASSERT(!(E in members_of(sequence_def(SEQ_TEST).parked_key)), "and off the parked list")
	K.run_item(W, WORK_TEST_LIMIT, 170)
	TEST_ASSERT_EQUAL(S.frames, before + 1, "one frame on return (its token went when it left: no catch-up)")

	var/datum/seq_test_entity/R = allocate(/datum/seq_test_entity)
	var/datum/seq_state/RS = seq_start(R, /datum/sequence/test/relevance)
	TEST_ASSERT(!RS.relevant && !member_is(/datum/sequence/test/relevance, R), "below min_relevance: out of the sweep")
	om_observe(R, src, RELEVANCE_NEAR)
	TEST_ASSERT(RS.relevant && member_is(/datum/sequence/test/relevance, R), "relevance brings it into the sweep (CHANGE_RELEVANCE)")
	om_unobserve(R, src)
	TEST_ASSERT(!member_is(/datum/sequence/test/relevance, R), "and losing it takes it out")
	R.busy.Cut()
	seq_run_frame_now(R, /datum/sequence/test/relevance)
	seq_run_frame_now(R, /datum/sequence/test/relevance)
	TEST_ASSERT(RS.parked, "it parks while irrelevant too")
	om_observe(R, src, RELEVANCE_NEAR)
	TEST_ASSERT(!member_is(/datum/sequence/test/relevance, R), "relevant but parked: still out of the sweep")
	seq_wake(R, /datum/sequence/test/relevance)
	TEST_ASSERT(member_is(/datum/sequence/test/relevance, R), "a wake of a relevant parked member rejoins")
	om_unobserve(R, src)

	qdel(E)
	TEST_ASSERT(!member_is(SEQ_TEST, E), "a destroyed member leaves the sweep")
	TEST_ASSERT_NULL(E.seq_states, "and its state goes")

/// A step's rewake is a due time on the member's one rewake timer (after(), keyed by entity and sequence): it wakes that step only, and a
/// parked member comes back for it and parks again at once when it sleeps again.
/datum/unit_test/kernel_sequence_rewake

/datum/unit_test/kernel_sequence_rewake/Run()
	var/datum/om/scheduler/sched = om_test_begin()
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	var/datum/seq_state/S = seq_start(E, SEQ_TEST)
	seq_run_frame_now(E, SEQ_TEST)
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT(S.parked, "parked")
	TEST_ASSERT(seq_rewake_pending(E, SEQ_TEST, "se"), "se's rewake is pending")
	TEST_ASSERT(rx_ledger_has(E, RELK_TIMER, "seq:[S.seq.idx]:rewake"), "on the member's one rewake timer, a TIMER relation")
	E.log.Cut()
	var/waited = 0
	while(S.parked && waited < 60)
		sched.manual_time += 1
		sched.run_pass(1e9)
		waited++
	TEST_ASSERT(!S.parked, "the rewake unparked it")
	TEST_ASSERT(waited >= 30, "not before its delay ([waited])")
	TEST_ASSERT_EQUAL(S.asleep, S.table.n - 1, "only se woke")
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT_EQUAL(jointext(E.log, ","), "se", "only se ran: a rewake runs the step (no should_run() pre-check)")
	TEST_ASSERT(S.parked, "and, a rewake counting as one idle frame already, it parked again as soon as se slept")
	seq_stop(E, SEQ_TEST)
	TEST_ASSERT(!seq_rewake_pending(E, SEQ_TEST, "se"), "stopping cancels the rewakes")
	om_test_end()

// ---------------------------------------------------------------- time

/// A fixed-step sequence runs at most max_catchup frames per sweep after a gap; a sweep is spread over the interval
/// (each member keeps its phase); outside its run levels nothing runs, and resuming is no catch-up.
/datum/unit_test/kernel_sequence_catch_up

/datum/unit_test/kernel_sequence_catch_up/Run()
	var/list/pair = seq_test_kernel(SEQ_TEST)
	var/datum/controller/kernel/K = pair[1]
	var/datum/work_item/sequence/W = pair[2]
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	var/datum/seq_state/S = seq_start(E, SEQ_TEST)
	E.busy = list("sa")
	K.run_item(W, WORK_TEST_LIMIT, 100)
	K.run_item(W, WORK_TEST_LIMIT, 110)
	TEST_ASSERT_EQUAL(S.frames, 2, "one frame per interval")
	var/breaches = S.seq.breaches
	K.run_item(W, WORK_TEST_LIMIT, 310)
	TEST_ASSERT_EQUAL(S.frames, 4, "twenty frames due: max_catchup (2) run")
	TEST_ASSERT_EQUAL(S.seq.breaches, breaches + 1, "and the dropped time is a breach")
	seq_stop(E, SEQ_TEST)

	// Spread: a member keeps its phase; the sweep takes the share of the interval that has passed.
	var/datum/work_item/sequence/plain = new(sequence_def(SEQ_TEST))
	TEST_ASSERT(plain.spread, "a sequence slower than the tick spreads its sweep")
	var/list/spread_pair = seq_test_kernel(SEQ_TEST, TRUE)
	var/datum/controller/kernel/K2 = spread_pair[1]
	var/datum/work_item/sequence/W2 = spread_pair[2]
	var/list/crowd = list()
	for(var/i in 1 to 10)
		var/datum/seq_test_entity/member = allocate(/datum/seq_test_entity)
		member.busy = list("sa")
		seq_start(member, SEQ_TEST)
		crowd += member
	var/lag = max(world.tick_lag, 0.1)
	var/passes = round((1 SECONDS) / lag)
	K2.run_item(W2, WORK_TEST_LIMIT, 1000)
	var/first_pass = seq_frames(crowd, SEQ_TEST)
	TEST_ASSERT(first_pass >= 1 && first_pass < 10, "the first pass takes a share of the members ([first_pass] of 10)")
	for(var/k in 1 to passes - 1)
		K2.run_item(W2, WORK_TEST_LIMIT, 1000 + k * lag)
	TEST_ASSERT_EQUAL(seq_frames(crowd, SEQ_TEST), 10, "one interval of passes runs every member once")
	for(var/datum/seq_test_entity/member as anything in crowd)
		seq_stop(member, SEQ_TEST)

	// Run levels: dormant outside them, no catch-up when they resume.
	var/list/game_pair = seq_test_kernel(/datum/sequence/test/game_only)
	var/datum/controller/kernel/K3 = game_pair[1]
	var/datum/work_item/sequence/W3 = game_pair[2]
	var/datum/seq_test_entity/G = allocate(/datum/seq_test_entity)
	var/datum/seq_state/GS = seq_start(G, /datum/sequence/test/game_only)
	G.busy = list("sa")
	K3.run_item(W3, WORK_TEST_LIMIT, 100)
	W3.test_runlevel = RUNLEVEL_LOBBY
	for(var/lobby_now in list(110, 120, 130, 140))
		K3.run_item(W3, WORK_TEST_LIMIT, lobby_now)
	TEST_ASSERT_EQUAL(GS.frames, 1, "nothing runs outside the run levels")
	W3.test_runlevel = RUNLEVEL_GAME
	K3.run_item(W3, WORK_TEST_LIMIT, 150)
	TEST_ASSERT_EQUAL(GS.frames, 2, "resuming is not a catch-up")

// ---------------------------------------------------------------- on demand

/// run_step_now() runs one step with a scratch frame and leaves its sleep bit alone; a step that runs another step
/// inside its frame gets a second frame from the pool, and its own frame goes on.
/datum/unit_test/kernel_sequence_run_step_now

/datum/unit_test/kernel_sequence_run_step_now/Run()
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	var/datum/seq_state/S = seq_start(E, SEQ_TEST)
	seq_run_frame_now(E, SEQ_TEST)
	E.log.Cut()
	run_step_now(E, "sa")
	TEST_ASSERT_EQUAL(jointext(E.log, ","), "sa", "it ran (the sequence found by the key)")
	TEST_ASSERT(seq_step_asleep(E, SEQ_TEST, "sa"), "and its sleep bit is unchanged")
	TEST_ASSERT_NULL(run_step_now(E, "no_such_step"), "an unknown step runs nothing")
	var/datum/seq_test_entity/N = allocate(/datum/seq_test_entity)
	var/datum/seq_state/NS = seq_start(N, SEQ_TEST)
	N.nested = TRUE
	seq_run_frame_now(N, SEQ_TEST)
	TEST_ASSERT_EQUAL(jointext(N.log, ","), "chan,heat,sb,sa,sc,sd,se,sf,sg,sa,sh,so,tail", "the nested run ran inside sg, and the frame went on")
	TEST_ASSERT(!NS.running && !S.running, "the frames closed")

// ---------------------------------------------------------------- contributions

/// A contributor of the entity's own and a capability of its type add steps that run on them with (entity, frame).
/datum/unit_test/kernel_sequence_contributions

/datum/unit_test/kernel_sequence_contributions/Run()
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	var/datum/seq_state/S = seq_start(E, SEQ_TEST)
	var/datum/seq_test_contributor/C = new
	TEST_ASSERT(seq_extra_add(E, SEQ_TEST, C), "added")
	TEST_ASSERT(!seq_extra_add(E, SEQ_TEST, new /datum/seq_test_contributor), "one contributor per type")
	TEST_ASSERT(S.table.pos_of["/datum/seq_test_contributor:helper"], "its step is keyed by its type: [jointext(S.table.order, ",")]")
	seq_run_frame_now(E, SEQ_TEST)
	TEST_ASSERT_EQUAL(C.calls, 1, "its step ran on it")
	TEST_ASSERT(("helper" in E.log), "with the entity")
	TEST_ASSERT(seq_extra_remove(E, SEQ_TEST, C), "removed")
	TEST_ASSERT_NULL(S.table.pos_of["/datum/seq_test_contributor:helper"], "and its step with it")

	var/obj/seq_test_atom/A = allocate(/obj/seq_test_atom)
	var/datum/seq_state/AS = seq_start(A, SEQ_TEST)
	TEST_ASSERT(AS.table.pos_of["/datum/capability/seq_test:cap_step"], "a capability of the type contributes its step: [jointext(AS.table.order, ",")]")
	seq_run_frame_now(A, SEQ_TEST)
	TEST_ASSERT(("cap" in A.log) && ("own" in A.log), "both ran: [jointext(A.log, ",")]")

// ---------------------------------------------------------------- the audit

/// A sleeping step whose should_run() holds, with its conditions passing and no rewake pending, is a missed wake:
/// logged with the key that changed without a publish (test builds snapshot the reads), and woken.
/datum/unit_test/kernel_sequence_audit

/datum/unit_test/kernel_sequence_audit/Run()
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	var/datum/seq_state/S = seq_start(E, SEQ_TEST)
	seq_run_frame_now(E, SEQ_TEST)
	var/datum/sequence/def = sequence_def(SEQ_TEST)
	TEST_ASSERT_NULL(def.missed_wake(E), "all asleep with nothing to do: no miss")
	E.busy = list("se")
	TEST_ASSERT_NULL(def.missed_wake(E), "a step whose rewake is pending is not a miss")
	E.busy = list("sd")
	E.on = FALSE
	TEST_ASSERT_NULL(def.missed_wake(E), "a step its conditions block is not a miss")
	E.busy.Cut()
	E.on = TRUE
	E.heat = 7 // a raw write: nothing publishes "heat"
	var/datum/seq_step/missed = def.missed_wake(E)
	TEST_ASSERT_EQUAL(missed?.key, "heat", "the step whose read changed without a publish is the miss")
	var/list/found = seq_audit(expected = TRUE)
	var/message
	for(var/line in found)
		if(findtext(line, "[E.type]"))
			message = line
	TEST_ASSERT_NOTNULL(message, "the audit reported it: [json_encode(found)]")
	TEST_ASSERT(findtext(message, "MOB_HIBERNATE_AUDIT: MISSED WAKE"), "with the missed-wake log line: [message]")
	TEST_ASSERT(findtext(message, "Changed without a publish: heat"), "naming the key the snapshot diff found: [message]")
	TEST_ASSERT(findtext(message, "set_heat()"), "and what should have woken it: [message]")
	TEST_ASSERT(!seq_step_asleep(E, SEQ_TEST, "heat"), "and the audit woke it")
	TEST_ASSERT(S.seq.missed >= 1, "counted")

// ---------------------------------------------------------------- metrics

/// Profiled frames time every step into its cost slot; the sweep item's metrics carry them to the kernel's.
/datum/unit_test/kernel_sequence_metrics

/datum/unit_test/kernel_sequence_metrics/Run()
	var/list/pair = seq_test_kernel(/datum/sequence/test/profiled)
	var/datum/controller/kernel/K = pair[1]
	var/datum/work_item/sequence/W = pair[2]
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	seq_start(E, /datum/sequence/test/profiled)
	E.busy = list("sa")
	K.run_item(W, WORK_TEST_LIMIT, 100)
	K.run_item(W, WORK_TEST_LIMIT, 110)
	var/datum/sequence/def = sequence_def(/datum/sequence/test/profiled)
	var/slot = def.slot_of["sa"]
	TEST_ASSERT(slot, "the step has a cost slot")
	TEST_ASSERT_EQUAL(def.step_calls[slot], 2, "each profiled frame counted its run (stride 1)")
	TEST_ASSERT_EQUAL(def.step_calls[def.slot_of["sb"]], 1, "a step that slept after the first frame ran once")
	var/list/metrics = K.metrics()
	var/list/item = metrics["work"][W.key]
	TEST_ASSERT_NOTNULL(item, "the kernel lists the sweep item")
	TEST_ASSERT_NOTNULL(item["sequence"]["steps"]["sa"], "with the per-step slots")
	TEST_ASSERT_EQUAL(item["sequence"]["frames"], def.frames, "and the frame count")

// ---------------------------------------------------------------- Life's order

// ---------------------------------------------------------------- on_change(at_most =)

/// A reaction fixture whose on_change is coalesced to once a second.
/datum/seq_rx_fixture
	var/level = 0
	var/mode = 0
	var/list/heard = list()

TRACKED(/datum/seq_rx_fixture, level)

/datum/seq_rx_fixture/reactions()
	. = ..()
	. += on_change(list(nameof(level), nameof(mode)), PROC_REF(on_level), at_most = 1 SECONDS)

/datum/seq_rx_fixture/proc/on_level(list/keys)
	heard += list(keys.Copy())

/// on_change(at_most = N): the first change delivers at the drain; changes within N of a delivery are held and
/// delivered once, with every key they named, when the window ends.
/datum/unit_test/kernel_sequence_at_most

/datum/unit_test/kernel_sequence_at_most/Run()
	om_test_begin()
	var/datum/seq_rx_fixture/F = allocate(/datum/seq_rx_fixture)
	F.set_level(1)
	rx_drain()
	TEST_ASSERT_EQUAL(length(F.heard), 1, "the first change is delivered at once")
	scheduler_advance(0.2)
	F.set_level(2)
	publish_change(F, nameof(F.mode))
	rx_drain()
	TEST_ASSERT_EQUAL(length(F.heard), 1, "inside the window it is held")
	scheduler_advance(0.5)
	rx_drain()
	TEST_ASSERT_EQUAL(length(F.heard), 1, "still held")
	scheduler_advance(0.5)
	rx_drain()
	TEST_ASSERT_EQUAL(length(F.heard), 2, "delivered once when the window ends")
	var/list/keys = F.heard[2]
	TEST_ASSERT(("level" in keys) && ("mode" in keys), "with every key it held: [json_encode(keys)]")
	F.set_level(3)
	rx_drain()
	TEST_ASSERT_EQUAL(length(F.heard), 2, "the delivery opened a new window")
	scheduler_advance(1.1)
	rx_drain()
	TEST_ASSERT_EQUAL(length(F.heard), 3, "which ends in turn")
	om_test_end()

#undef SEQ_TEST_ORDER
#undef SEQ_TEST
