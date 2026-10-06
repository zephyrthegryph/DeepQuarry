// The test driver (doc/rewrite/final_api.html, section 15 "Test driver"), as a test-build-only library.
//
// A fixture executes an input, answers a prompt, steps the kernel and reads what the contracts promise through these
// forms, and the E0 proofs use nothing else (section 19). Two kinds of form live here:
//
//   - Bookkeeping the driver owns outright, and which is real from E0: the roll counter behind chance(), the notice and
//     spill counters, the lane budgets, the log queue, the recorder and the "not implemented" ledger. The engines feed
//     them through the TEST_REC_* macros and TEST_ROLL / TEST_LANE_BUDGET (code/__defines/engine/test_hooks.dm).
//   - Forms that drive an engine: test_click, test_ui, test_menu, test_answer, test_drain, test_phase and test_time.
//     Each calls one E0 stub (code/engine/kernel/stubs.dm), which says what it needs and returns null until that engine
//     lands. Swapping the stub for the engine is the only change a driver form ever needs.
//
// Compiled under UNIT_TESTS only (and SPACEMAN_DMM, so DreamChecker sees it).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The driver's one piece of state: counters, budgets, the log queue and the active recording.
GLOBAL_DATUM_INIT(test_driver, /datum/test_driver, new)

/datum/test_driver
	/// "engine: what" for every stub a fixture hit since the last reset, in first-hit order, without repeats.
	var/list/pending
	/// The seed test_rng() set, or null.
	var/rng_seed
	/// Rolls drawn since the seed was set.
	var/rolls = 0
	/// lane -> microseconds, from test_budget().
	var/list/lane_budgets
	/// notice type -> delivered count, since the last reset.
	var/list/notice_counts
	/// notice type -> count of notices queued past ACT_MAX_DEPTH, since the last reset.
	var/list/notice_queued
	/// Marked passes that stopped at their budget since the last reset.
	var/spills = 0
	/// The log lines written since test_logs() last ran: /datum/test_log records.
	var/list/logs
	/// The rows test_record() started collecting (/datum/test_event), until test_recorded() returns them; null when not recording.
	var/list/recording
	/// The entities test_record() was given, in order: their deltas are kept and rows are compared by position among them.
	var/list/recorded_entities
	/// Rows the record refused past TEST_RECORD_MAX since test_record() started it.
	var/recording_dropped = 0

/// One log line, as test_logs() returns it: the op key chain, how it ended, where it came from, who and what, and the text.
/datum/test_log
	var/key
	var/outcome
	var/origin
	var/datum/actor
	var/datum/target
	var/text

// ---- The "not implemented" ledger ----

/// A stub reports that a fixture reached an engine piece that does not exist yet. `engine` is an ENGINE_E* name.
/proc/e0_pending(engine, what)
	var/entry = "[engine]: [what]"
	var/datum/test_driver/D = GLOB.test_driver
	if(!(entry in D.pending))
		LAZYADD(D.pending, entry)

/// TRUE when a fixture has reached a stub since the last reset.
/proc/e0_pending_any()
	return LAZYLEN(GLOB.test_driver.pending) > 0

/// The one failure message a proof gives while its engine is missing: "E1-E6 not implemented: <what>; <what>".
/proc/e0_pending_text()
	return "E1-E6 not implemented: [jointext(GLOB.test_driver.pending, "; ")]"

/// Fails the running proof with the "not implemented" message, once, and clears the ledger. Returns the Fail() result so a proof
/// writes `E0_GATE` and returns it.
/datum/unit_test/proc/e0_fail_pending(file, line)
	var/text = e0_pending_text()
	GLOB.test_driver.pending = null
	pending_engine = TRUE
	return Fail(text, file, line)

// ---- Reset ----

/// Back to a clean driver: no pending stubs, no seed, no budgets, no counters, no queued logs, no recording.
/proc/test_driver_reset()
	var/datum/test_driver/D = GLOB.test_driver
	D.pending = null
	D.rng_seed = null
	D.rolls = 0
	D.lane_budgets = null
	D.spills = 0
	D.notice_counts = null
	D.notice_queued = null
	D.logs = null
	D.recording = null
	D.recording_dropped = 0
	D.recorded_entities = null
	SSinput.reset_for_test()

/// Zeroes the notice and spill counters (and nothing else): "since the last reset".
/proc/test_counters_reset()
	var/datum/test_driver/D = GLOB.test_driver
	D.spills = 0
	D.notice_counts = null
	D.notice_queued = null

/// A clean driver and the kernel on its injected clock: the first thing a fixture that makes time pass calls, before it
/// builds its entities (they join the test scheduler that is current when they are created).
/proc/test_driver_begin()
	test_driver_reset()
	kernel_test_begin()

/// The kernel back on the real clock, and a clean driver.
/proc/test_driver_end()
	kernel_test_end()
	test_driver_reset()
	GLOB.e0_night_service?.set_night(FALSE) // the night system of proof 8 is a lazy global: the next test finds it by day

// ---- Input forms (drive E2's resolver through E6's inbox) ----

/// Sends a click through the input inbox with origin ORIGIN_CLICK and resolves it as a player's click would. Returns the
/// /datum/op_result of the op that ran (outcome null while it waits), or null when nothing resolved.
/proc/test_click(mob/actor, atom/target, obj/item/held, gesture = GESTURE_CLICK)
	return inbox_click(actor, target, held, gesture, ORIGIN_CLICK)

/// Drags `dragged` onto `over` as a player's drag would (origin ORIGIN_CLICK, gesture GESTURE_DRAG): the dragged atom, an item or a mob, is the held one.
/proc/test_drag(mob/actor, atom/dragged, atom/over)
	return inbox_drag(actor, dragged, over)

/// Presses a window button as a player would (origin ORIGIN_UI): the args cross the schema boundary, the op's ui_act()
/// binding matches, and the result comes back.
/proc/test_ui(mob/actor, window, action, list/args)
	return inbox_ui(actor, window, action, args)

/// Picks the op named `op_key` from the context menu of `target`, as a player's pick would: origin ORIGIN_MENU, the actor's held
/// item, the same gates as a click. The only form that takes the menu path. Its contents are read with action_options().
/proc/test_menu(mob/actor, atom/target, op_key)
	return inbox_menu(actor, target, op_key, actor?.held_for_ops())

/// Answers the actor's open request with a value, or ends it with an outcome (REQ_CANCELLED, REQ_TIMED_OUT) when
/// `outcome` is given: a REQ_* constant is a small number a value could equal, so the outcome has its own argument.
/// Returns the /datum/op_result of the op that was waiting, now advanced.
/proc/test_answer(mob/actor, value, outcome = REQ_ANSWERED)
	return request_answer(actor, value, outcome)

/// Every prompt request opened since test_prompts_reset(), in order (null: not recording).
GLOBAL_VAR(test_prompts)

/// Starts recording the prompts the test causes (GLOB.test_prompts).
/proc/test_prompts_reset()
	GLOB.test_prompts = list()

/// Answers prompt `P` with `answer` (or cancels it): null when the answer went through, else why not (the refusal, "no answer" for a cancel,
/// or the re-check that dropped it, such as "no admin rights").
/proc/test_prompt_answer(datum/prompt/P, answer, cancel = FALSE)
	if(!istype(P) || !P.is_open())
		return "that question is closed"
	if(cancel)
		request_end(P, REQ_CANCELLED, null)
		return "no answer"
	var/why = request_submit(P, answer)
	if(why)
		return why
	if(P.outcome != REQ_ANSWERED)
		return P.last_error || "cancelled"
	return null

// ---- Kernel forms (E6) ----

/// Runs a drain point now.
/proc/test_drain()
	kernel_drain_now()

/// Runs one kernel phase (KERNEL_PHASE_K .. KERNEL_PHASE_G, and KERNEL_PHASE_S) to completion. A fixture steps phases
/// itself and waits real ticks only with wait_ticks().
/proc/test_phase(phase)
	kernel_phase_run(phase)

/// Advances the kernel clock by `t` deciseconds, running every phase and drain that falls due in between, so timers,
/// every(), waits and request timeouts fire.
/proc/test_time(t)
	kernel_time_advance(t)

// ---- Bookkeeping the driver owns ----

/// Seeds the generator chance() and prob() draw from, and zeroes the roll counter.
/proc/test_rng(seed)
	var/datum/test_driver/D = GLOB.test_driver
	D.rng_seed = seed
	D.rolls = 0
	rand_seed(seed)

/// The number of rolls made since the seed was set.
/proc/test_rolls()
	return GLOB.test_driver.rolls

/// The roll behind chance(p): counted, and drawn from the generator test_rng() seeded. TRUE when it succeeds.
/proc/test_roll(percent)
	var/datum/test_driver/D = GLOB.test_driver
	D.rolls++
	return prob(percent)

/// Sets a lane's budget for the next drain points, in microseconds of tick time (the unit of section 2). In test builds each
/// stat evaluation is charged TEST_EVAL_COST instead of reading the clock, so a budget of 200 lets 20 evaluations through
/// per drain and a spill happens in the same place on every run.
/proc/test_budget(lane, units)
	var/datum/test_driver/D = GLOB.test_driver
	LAZYSET(D.lane_budgets, "[lane]", units)

/// The budget test_budget() set for `lane`, or null.
/proc/test_lane_budget(lane)
	return LAZYACCESS(GLOB.test_driver.lane_budgets, "[lane]")

/// The notices of `type` (and its subtypes) delivered since the last reset.
/proc/test_notice_count(type)
	var/datum/test_driver/D = GLOB.test_driver
	. = 0
	for(var/delivered in D.notice_counts)
		if(ispath(text2path(delivered), type))
			. += D.notice_counts[delivered]

/// The notices of `type` (and its subtypes) queued past ACT_MAX_DEPTH since the last reset.
/proc/test_notice_queued_count(type)
	var/datum/test_driver/D = GLOB.test_driver
	. = 0
	for(var/queued in D.notice_queued)
		if(ispath(text2path(queued), type))
			. += D.notice_queued[queued]

/// The drain spills since the last reset: marked passes that stopped at their budget.
/proc/test_spill_count()
	return GLOB.test_driver.spills

/// Returns and clears the log lines written since the last call, each a /datum/test_log.
/proc/test_logs()
	var/datum/test_driver/D = GLOB.test_driver
	. = D.logs || list()
	D.logs = null

// ---- The seams the engines call (the TEST_REC_* macros; the recorder's own are in recorder.dm) ----

/proc/test_rec_notice(notice_type, outcome, queued)
	var/datum/test_driver/D = GLOB.test_driver
	if(queued)
		LAZYSET(D.notice_queued, "[notice_type]", LAZYACCESS(D.notice_queued, "[notice_type]") + 1)
	else
		LAZYSET(D.notice_counts, "[notice_type]", LAZYACCESS(D.notice_counts, "[notice_type]") + 1)
	test_rec_event(queued ? TEST_EVENT_NOTICE_QUEUED : TEST_EVENT_NOTICE, null, notice_type, null, outcome)

/proc/test_rec_spill(key_chain)
	GLOB.test_driver.spills++
	test_rec_event(TEST_EVENT_SPILL, null, key_chain, null, null)

/proc/test_rec_log(key, outcome, origin, datum/actor, datum/target, text)
	var/datum/test_driver/D = GLOB.test_driver
	var/datum/test_log/line = new
	line.key = key
	line.outcome = outcome
	line.origin = origin
	line.actor = actor // ALLOW(ownership): a test-only record the test reads and drops
	line.target = target // ALLOW(ownership): a test-only record the test reads and drops
	line.text = text
	LAZYADD(D.logs, line) // ALLOW(ownership): the test-only log queue the test reads and clears
	test_rec_event(TEST_EVENT_LOG, actor, key, outcome, text)

#endif

/// TRUE when an op driven through the dispatcher (perform_op(), op_ui_act(), test_click(), test_menu(), test_ui()) committed.
/proc/test_op_committed(datum/op_result/R)
	return R?.outcome == ACT_COMMITTED

/// Calls an op handler directly, as the engine would: x(datum/act/op/A, args...) with the actor, the holder (also the target) and the held item set.
/// For a test of what the handler itself does; a click is test_click().
/proc/test_op_handler(datum/holder, proc_name, mob/actor, obj/item/held = null, ...)
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	A.target = holder
	A.actor = actor
	A.held = held
	var/list/call_args = list(A) // ALLOW(handlers): the list lives for this one call and the act is released right after it
	if(length(args) > 4)
		call_args += args.Copy(5)
	. = call(holder, proc_name)(arglist(call_args))
	A.release()

/// Calls a request handler directly: x(datum/act/request/A) for a request that `answerer` answered with `value` (a prompt of `kind`, answered as given).
/proc/test_request_handler(datum/holder, proc_name, mob/answerer, value, kind = /datum/prompt/choice)
	var/datum/request/R = new kind
	R.answerer = answerer // ALLOW(ownership): a throwaway request record for one direct handler call, discarded at the end of the proc
	R.value = value
	var/datum/act/request/A = take(/datum/act/request)
	A.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	A.request = R // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	A.answer = R // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	. = call(holder, proc_name)(A)
	A.release()
	qdel(R) // ALLOW(lifecycle): the throwaway request record of this test call was never owned by anything
