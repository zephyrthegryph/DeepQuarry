// Framework robustness, ownership API and request/stat fixes (doc/rewrite/framework_gaps.md: D1-D4, C2, C3, A1-A5, B2, E1-E4).
// Each test fails on the code before its fix.

// ---------------------------------------------------------------- fixtures

/// An action whose instead hook runtimes: the leak D1 describes.
ACTION(lanea_boom, notice = /datum/notice/lanea_boomed)

/obj/lanea_fixture
	name = "lane a fixture"
	anchored = TRUE
	/// Runs of the instead hook (it runtimes every time).
	var/booms = 0
	/// The type-level every() gate throws while TRUE; the first every() counts runs in `ticks`.
	var/gate_throws = FALSE
	var/ticks = 0
	/// The interval proc of the second every() throws while TRUE, and records whether it got a real timer context.
	var/gap_throws = FALSE
	var/gap_context_ok = FALSE
	var/gap_runs = 0
	var/armed = FALSE
	var/fired = 0
	var/heard = 0

TRACKED(/obj/lanea_fixture, armed)
TRACKED(/obj/lanea_fixture, gate_throws)

CAPABILITIES(/obj/lanea_fixture)
	extend(/datum/act/lanea_boom, instead(then(PROC_REF(boom))))
	every(5 SECONDS, then(PROC_REF(tick)), when = PROC_REF(gate))
	every(PROC_REF(next_gap), then(PROC_REF(gap_tick)))
	on_change(nameof(armed), ANY, then(PROC_REF(armed_changed)))
	on_notice(/datum/notice/lanea_boomed, then(PROC_REF(heard_boom)))

/obj/lanea_fixture/proc/boom(datum/act/A)
	booms++
	CRASH("lane a deliberate runtime in an instead hook")

/obj/lanea_fixture/proc/gate(datum/act/A)
	if(gate_throws)
		CRASH("lane a deliberate runtime in an every() gate")
	return TRUE

/obj/lanea_fixture/proc/tick(datum/act/timer/A)
	ticks++

/obj/lanea_fixture/proc/next_gap(datum/act/timer/A)
	gap_context_ok = !!(A && A.holder == src)
	if(gap_throws)
		CRASH("lane a deliberate runtime in an every() interval")
	return 1 SECOND

/obj/lanea_fixture/proc/gap_tick(datum/act/timer/A)
	gap_runs++

/obj/lanea_fixture/proc/armed_changed(datum/act/A)
	fired++

/obj/lanea_fixture/proc/heard_boom(datum/act/A)
	heard++

/// Begins the runtiming action: the caller wraps it in safe_call().
/proc/lanea_try_boom(obj/lanea_fixture/F)
	var/datum/act/lanea_boom/A = ACT_TRY(F, lanea_boom)
	if(A)
		act_cancel(A)

/datum/unit_test/dq_lane_a
	abstract_type = /datum/unit_test/dq_lane_a
	var/runtimes_at_start = 0

/// A clean driver, the depth reports and the caught faults captured: the engine reports a handler's fault with dq_report_caught() (a logged runtime a
/// test run fails on) and these tests cause some on purpose.
/datum/unit_test/dq_lane_a/Run()
	runtimes_at_start = GLOB.total_runtimes
	test_driver_begin()
	GLOB.act_report_capture = list()
	set_global("dq_caught_capture", list())
	run_lane_a()
	set_global("dq_caught_capture", null)
	GLOB.act_report_capture = null
	GLOB.total_runtimes = runtimes_at_start
	test_driver_end()

/datum/unit_test/dq_lane_a/proc/run_lane_a()
	return

// ---------------------------------------------------------------- D1: act_depth leak

/datum/unit_test/dq_lane_a/runtimes_in_hooks_do_not_leak_depth

/datum/unit_test/dq_lane_a/runtimes_in_hooks_do_not_leak_depth/run_lane_a()
	var/obj/lanea_fixture/F = allocate(/obj/lanea_fixture)
	var/too_deep_before = GLOB.act_too_deep
	for(var/i in 1 to ACT_MAX_DEPTH + 3)
		var/datum/result/R = safe_call(GLOBAL_PROC_REF(lanea_try_boom), F)
		TEST_ASSERT(!R.ok, "the hook's runtime reaches the caller (attempt [i])")
	TEST_ASSERT_EQUAL(F.booms, ACT_MAX_DEPTH + 3, "every attempt reached the hook: none was refused as too deeply nested")
	TEST_ASSERT_EQUAL(GLOB.act_too_deep, too_deep_before, "no action was refused for depth")
	TEST_ASSERT_EQUAL(GLOB.act_depth, 0, "the depth is back to zero")
	TEST_ASSERT_EQUAL(length(GLOB.act_chain), 0, "and the chain is empty")

/datum/unit_test/dq_lane_a/kernel_backstop_resets_a_leaked_depth

/datum/unit_test/dq_lane_a/kernel_backstop_resets_a_leaked_depth/run_lane_a()
	TEST_ASSERT(!act_backstop_reset(), "nothing leaked: nothing reset")
	GLOB.act_depth = 5
	GLOB.act_chain += "leaked"
	var/before = GLOB.act_backstops
	TEST_ASSERT(act_backstop_reset(), "a leaked depth is reset")
	TEST_ASSERT_EQUAL(GLOB.act_depth, 0, "to zero")
	TEST_ASSERT_EQUAL(length(GLOB.act_chain), 0, "with the chain cleared")
	TEST_ASSERT_EQUAL(GLOB.act_backstops, before + 1, "and counted")

// ---------------------------------------------------------------- C2, C3: every()

/datum/unit_test/dq_lane_a/every_survives_a_throwing_gate_and_interval

/datum/unit_test/dq_lane_a/every_survives_a_throwing_gate_and_interval/run_lane_a()
	var/obj/lanea_fixture/F = allocate(/obj/lanea_fixture)
	TEST_ASSERT(F.gap_context_ok, "an interval proc is handed a real timer context whose holder is the instance, not null")
	test_time(30 SECONDS)
	TEST_ASSERT(F.ticks > 0, "the gated every() runs")
	TEST_ASSERT(F.gap_runs > 0, "the every() with an interval proc runs")
	F.set_gate_throws(TRUE)
	F.gap_throws = TRUE
	test_time(30 SECONDS)
	F.set_gate_throws(FALSE)
	F.gap_throws = FALSE
	var/ticks_then = F.ticks
	var/gaps_then = F.gap_runs
	test_time(30 SECONDS)
	TEST_ASSERT(length(GLOB.dq_caught_capture) >= 2, "the faults were reported, not swallowed: [json_encode(GLOB.dq_caught_capture)]")
	TEST_ASSERT(F.ticks > ticks_then, "the every() whose gate threw runs again once the gate holds: one fault did not end it")
	TEST_ASSERT(F.gap_runs > gaps_then, "the every() whose interval proc threw runs again too")

// ---------------------------------------------------------------- D2, D4: drains

/datum/unit_test/dq_lane_a/late_drain_clears_its_flag_when_a_delivery_throws

/datum/unit_test/dq_lane_a/late_drain_clears_its_flag_when_a_delivery_throws/run_lane_a()
	var/obj/lanea_fixture/F = allocate(/obj/lanea_fixture)
	var/datum/notice/lanea_boomed/good = take(/datum/notice/lanea_boomed)
	// A poisoned row (no notice), then a good one behind it.
	GLOB.notice_late_queue += list(list(F, null, ACT_COMMITTED, "poisoned"))
	GLOB.notice_late_queue += list(list(F, good, ACT_COMMITTED, "good"))
	notice_drain_late()
	TEST_ASSERT(!GLOB.notice_draining_late, "the draining flag is clear again")
	TEST_ASSERT_EQUAL(length(GLOB.notice_late_queue), 0, "the queue is empty")
	TEST_ASSERT_EQUAL(length(GLOB.dq_caught_capture), 1, "the poisoned delivery was reported")
	TEST_ASSERT_EQUAL(F.heard, 1, "the good notice behind the poisoned one was still delivered")
	// The flag being clear means the next drain point works.
	var/datum/notice/lanea_boomed/later = take(/datum/notice/lanea_boomed)
	GLOB.notice_late_queue += list(list(F, later, ACT_COMMITTED, "later"))
	act_drain_point()
	TEST_ASSERT_EQUAL(F.heard, 2, "and a later late notice drains")

/datum/unit_test/dq_lane_a/change_drain_survives_a_throwing_condition

/datum/unit_test/dq_lane_a/change_drain_survives_a_throwing_condition/run_lane_a()
	var/obj/lanea_fixture/F = allocate(/obj/lanea_fixture)
	var/list/index = change_index_of(F)
	TEST_ASSERT(islist(index) && length(index["armed"]), "the fixture's on_change is indexed")
	var/datum/hook/good = index["armed"][1]
	// A hook whose when-condition throws (an entry with no arguments), marked before the good one.
	var/datum/hook/bad = new
	bad.kind = good.kind
	bad.entry = good.entry
	bad.serial = ++GLOB.hook_serial
	bad.whens = list(new /datum/entry)
	F.set_armed(TRUE)
	var/list/marked = list()
	marked[bad] = TRUE
	for(var/datum/hook/H as anything in GLOB.hook_change_pending[F])
		marked[H] = TRUE
	GLOB.hook_change_pending[F] = marked
	hooks_drain_changes()
	TEST_ASSERT_EQUAL(length(GLOB.dq_caught_capture), 1, "the throwing condition was reported")
	TEST_ASSERT_EQUAL(F.fired, 1, "the hook behind the throwing one still ran")
	TEST_ASSERT_EQUAL(length(GLOB.hook_change_pending), 0, "nothing is stranded in the pending list")
	TEST_ASSERT_EQUAL(GLOB.act_depth, 0, "the depth is back to zero")
	qdel(bad)

// ---------------------------------------------------------------- A: ownership API

/// A part an owner holds.
/datum/lanea_part

/obj/lanea_owner
	name = "lane a owner"
	anchored = TRUE
	/// Declared `= list()`: an eager list.
	var/list/eager = list()
	/// Declared null: a lazy list.
	var/list/lazy
	var/datum/lanea_part/part

CAPABILITIES(/obj/lanea_owner)
	owns_many(nameof(eager))
	owns_many(nameof(lazy))

/obj/lanea_owner/ownership()
	. = ..()
	. += owns(nameof(part), starts = /datum/lanea_part)

/// A subtype that starts without the occupant its ancestor makes.
/obj/lanea_owner/bare

/obj/lanea_owner/bare/ownership()
	. = ..()
	. += no_starts(nameof(part))

/datum/unit_test/dq_lane_a_own
	abstract_type = /datum/unit_test/dq_lane_a_own

/datum/unit_test/dq_lane_a_own/proc/part()
	return allocate(/datum/lanea_part)

/datum/unit_test/dq_lane_a_own/rel_take_without_a_member_takes_nothing

/datum/unit_test/dq_lane_a_own/rel_take_without_a_member_takes_nothing/Run()
	var/obj/lanea_owner/O = allocate(/obj/lanea_owner)
	var/datum/lanea_part/a = part()
	var/datum/lanea_part/b = part()
	rel_add(O, nameof(O.eager), a)
	rel_add(O, nameof(O.eager), b)
	var/null_member
	TEST_ASSERT_NULL(rel_take(O, nameof(O.eager), null_member), "a null member is no member: nothing is taken")
	TEST_ASSERT_NULL(rel_take(O, nameof(O.eager)), "no member and no key on a list var takes nothing")
	TEST_ASSERT_EQUAL(length(O.eager), 2, "both members are still there")
	TEST_ASSERT_EQUAL(rel_take(O, nameof(O.eager), a), a, "a member is taken by name")
	TEST_ASSERT_EQUAL(length(O.eager), 1, "and only it")
	var/list/rest = rel_take_all(O, nameof(O.eager))
	TEST_ASSERT_EQUAL(length(rest), 1, "rel_take_all takes what is left")
	TEST_ASSERT_EQUAL(rest[1], b, "the other one")

/datum/unit_test/dq_lane_a_own/rel_take_all_always_returns_a_list

/datum/unit_test/dq_lane_a_own/rel_take_all_always_returns_a_list/Run()
	var/obj/lanea_owner/O = allocate(/obj/lanea_owner)
	TEST_ASSERT_NULL(O.lazy, "the lazy list starts unset")
	var/list/none = rel_take_all(O, nameof(O.lazy))
	TEST_ASSERT(islist(none), "an unset lazy list gives a list, not null")
	TEST_ASSERT_EQUAL(length(none), 0, "an empty one")
	var/list/none_eager = rel_take_all(O, nameof(O.eager))
	TEST_ASSERT(islist(none_eager), "an empty eager list gives a list")
	var/datum/lanea_part/a = part()
	rel_add(O, nameof(O.lazy), a)
	var/list/all = rel_take_all(O, nameof(O.lazy))
	TEST_ASSERT_EQUAL(length(all), 1, "a lazy list with a member gives it")
	TEST_ASSERT(isnull(O.lazy), "and goes back to null")

/datum/unit_test/dq_lane_a_own/taking_the_last_member_keeps_an_eager_list

/datum/unit_test/dq_lane_a_own/taking_the_last_member_keeps_an_eager_list/Run()
	var/obj/lanea_owner/O = allocate(/obj/lanea_owner)
	var/datum/lanea_part/a = part()
	rel_add(O, nameof(O.eager), a)
	rel_take(O, nameof(O.eager), a)
	TEST_ASSERT(islist(O.eager), "an eager list stays a list when its last member is taken singly")
	var/datum/lanea_part/b = part()
	rel_add(O, nameof(O.lazy), b)
	rel_take(O, nameof(O.lazy), b)
	TEST_ASSERT(isnull(O.lazy), "a lazy one goes back to null")

/datum/unit_test/dq_lane_a_own/rel_clear_forwards_its_policy

/datum/unit_test/dq_lane_a_own/rel_clear_forwards_its_policy/Run()
	var/obj/lanea_owner/O = allocate(/obj/lanea_owner)
	var/datum/lanea_part/kept = part()
	rel_add(O, nameof(O.eager), kept)
	rel_clear(O, nameof(O.eager), OWN_KEEP)
	TEST_ASSERT(!QDELETED(kept), "OWN_KEEP over the declared delete leaves the member alive")
	var/datum/lanea_part/gone = part()
	rel_add(O, nameof(O.eager), gone)
	rel_clear(O, nameof(O.eager))
	TEST_ASSERT(QDELETED(gone), "no policy: the declaration decides, and it deletes")

/datum/unit_test/dq_lane_a_own/a_subtype_cancels_an_inherited_start

/datum/unit_test/dq_lane_a_own/a_subtype_cancels_an_inherited_start/Run()
	var/obj/lanea_owner/O = allocate(/obj/lanea_owner)
	TEST_ASSERT_NOTNULL(O.part, "the ancestor makes its starting occupant")
	var/obj/lanea_owner/bare/B = allocate(/obj/lanea_owner/bare)
	TEST_ASSERT_NULL(B.part, "the subtype that declares no_starts starts empty")
	var/datum/lanea_part/p = part()
	rel_set(B, nameof(B.part), p)
	TEST_ASSERT_EQUAL(B.part, p, "the inherited declaration still owns the var")
	var/obj/vehicle/bike/built/frame = allocate(/obj/vehicle/bike/built)
	TEST_ASSERT_NULL(frame.cell, "a built bike frame starts without a cell")
	var/obj/vehicle/bike/whole = allocate(/obj/vehicle/bike)
	TEST_ASSERT_NOTNULL(whole.cell, "a factory bike keeps its cell")

// ---------------------------------------------------------------- B2: holds

/datum/unit_test/dq_e3/hold_then_override_from_one_source_is_one_row

/datum/unit_test/dq_e3/hold_then_override_from_one_source_is_one_row/run_e3()
	var/obj/e3_rules/R = allocate(/obj/e3_rules)
	var/obj/e3_source/A = source()
	hold(R, STAT_E3_SUM, 3, A)
	TEST_ASSERT(hold_override(R, STAT_E3_SUM, 100, A), "the same source overrides what it held")
	var/rows = 0
	for(var/list/row as anything in R.rx.stats.holds)
		if(row[H_SOURCE] == A)
			rows++
	TEST_ASSERT_EQUAL(rows, 1, "one row for the (stat, source), not two")
	TEST_ASSERT_EQUAL(R.e3_sum, 100, "the override reads")
	release(R, STAT_E3_SUM, A)
	TEST_ASSERT_EQUAL(R.e3_sum, 0, "one release leaves nothing of the source behind")
	TEST_ASSERT(!held_by_source(R, STAT_E3_SUM, A), "the source holds nothing")

// ---------------------------------------------------------------- E1, E2: requests

/datum/unit_test/dq_lane_a_requests_owner_death

/datum/unit_test/dq_lane_a_requests_owner_death/Run()
	test_driver_begin()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	var/datum/e6_probe_owner/doomed = new
	var/datum/request/R = open_request(doomed, /datum/prompt/e6_probe, TYPE_PROC_REF(/datum/e6_probe_owner, done), answerer = actor, timeout = 60 SECONDS)
	TEST_ASSERT(R.is_open(), "the prompt is open")
	TEST_ASSERT_NOTNULL(SSrequests.open_for(actor), "the actor has a question to answer")
	qdel(doomed)
	TEST_ASSERT(!R.is_open(), "the owner's deletion ended the request without waiting for the sweep")
	TEST_ASSERT_EQUAL(R.outcome, REQ_CANCELLED, "cancelled")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "the actor has nothing left to answer")
	TEST_ASSERT_NULL(test_answer(actor, 1), "a late answer finds nothing")
	test_driver_end()

/datum/unit_test/dq_lane_a_requests_default_timeout

/datum/unit_test/dq_lane_a_requests_default_timeout/Run()
	test_driver_begin()
	var/datum/e6_probe_owner/owner = allocate(/datum/e6_probe_owner)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	var/datum/request/R = open_request(owner, /datum/prompt/e6_probe, TYPE_PROC_REF(/datum/e6_probe_owner, done), answerer = actor)
	TEST_ASSERT_EQUAL(R.timeout, REQUEST_DEFAULT_TIMEOUT, "no timeout given: the default")
	test_time(REQUEST_DEFAULT_TIMEOUT + 1 SECOND)
	TEST_ASSERT_EQUAL(R.outcome, REQ_TIMED_OUT, "it times out instead of pinning its owner")
	var/datum/request/open_forever = open_request(owner, /datum/prompt/e6_probe, TYPE_PROC_REF(/datum/e6_probe_owner, done), answerer = actor, timeout = REQUEST_NO_TIMEOUT)
	test_time(REQUEST_DEFAULT_TIMEOUT * 2)
	TEST_ASSERT(open_forever.is_open(), "REQUEST_NO_TIMEOUT is the explicit opt-out")
	test_answer(actor, 1)
	test_driver_end()

// ---------------------------------------------------------------- E3, E4: services

/datum/lanea_runechat_probe
	var/list/order = list()

/datum/lanea_runechat_probe/proc/finish(n)
	order += n

/datum/unit_test/dq_lane_a_runechat_oldest_first

/datum/unit_test/dq_lane_a_runechat_oldest_first/Run()
	var/datum/lanea_runechat_probe/probe = new
	var/list/first = om_callable(probe, TYPE_PROC_REF(/datum/lanea_runechat_probe, finish), 1)
	var/list/second = om_callable(probe, TYPE_PROC_REF(/datum/lanea_runechat_probe, finish), 2)
	var/list/third = om_callable(probe, TYPE_PROC_REF(/datum/lanea_runechat_probe, finish), 3)
	SSrunechat.enqueue(first)
	SSrunechat.enqueue(second)
	SSrunechat.enqueue(third)
	SSrunechat.dequeue(second)
	SSrunechat.enqueue(second)
	var/result = SSrunechat.deliver_messages(0)
	for(var/i in 1 to 20)
		if(result != STEP_YIELD)
			break
		result = SSrunechat.deliver_messages(0)
	TEST_ASSERT_EQUAL(jointext(probe.order, ","), "1,3,2", "messages arrive in the order they were queued (the dequeued one re-queued last)")
	qdel(probe)

/datum/unit_test/dq_lane_a_vis_overlay_sweep_skips_a_deleted_overlay

/datum/unit_test/dq_lane_a_vis_overlay_sweep_skips_a_deleted_overlay/Run()
	// The sweep's snapshot holds an entry whose overlay was deleted meanwhile (the reference reads null).
	SSvis_overlays.vars["currentrun"] = list("lane_a_gone" = null)
	SSvis_overlays.vars["resuming"] = TRUE
	TEST_ASSERT_EQUAL(SSvis_overlays.expire_overlays(0), STEP_DONE, "the sweep skips the empty entry instead of runtiming")
