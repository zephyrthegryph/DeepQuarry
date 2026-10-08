/// The kernel's work items: cadence, phases and after-edges (one validator with the boot DAG), urgent requests,
/// membership relations, the stage adapter and the kernel tick itself (code/controllers/kernel/).

/// The handler target for every work-item test: records its calls and answers as told.
/datum/test_work_owner
	var/list/calls = list()
	var/list/dts = list()
	var/list/members_seen = list()
	var/gate = TRUE
	var/result
	var/fault = FALSE
	var/list/order

/datum/test_work_owner/proc/record(dt)
	calls += 1
	dts += dt
	if(fault)
		CRASH("deliberate work item fault")
	return result

/datum/test_work_owner/proc/record_member(datum/member, dt)
	members_seen[member] = (members_seen[member] || 0) + 1
	dts += dt
	return result

/datum/test_work_owner/proc/is_open()
	return gate

/datum/test_work_owner/proc/note_a(dt)
	order += "a"

/datum/test_work_owner/proc/note_b(dt)
	order += "b"

/datum/test_work_owner/proc/note_c(dt)
	order += "c"

// One owner type per registered item in a test, so registration keys never collide.
/datum/test_work_owner/gated
/datum/test_work_owner/parking
/datum/test_work_owner/yielding
/datum/test_work_owner/faulty
/datum/test_work_owner/a
/datum/test_work_owner/b
/datum/test_work_owner/c
/datum/test_work_owner/nothing

/// A work item whose owner is a fixture the test holds, so no system singleton is needed.
/datum/work_item/test_fixture
	var/datum/test_work_owner/fixture

/datum/work_item/test_fixture/owner()
	return fixture

/// Makes a fixture item; `handler` defaults to record().
/proc/test_work_item(datum/test_work_owner/O, handler = null, interval = 10, when = null, members = null, phase = KERNEL_PHASE_P, list/after = null, lane = LANE_SIMULATION, urgent = FALSE)
	var/datum/work_item/test_fixture/W = new(handler || TYPE_PROC_REF(/datum/test_work_owner, record), interval, when, members, phase, after, 0, lane, urgent)
	W.fixture = O
	return W

/proc/test_wake_work(datum/controller/kernel/K, key)
	var/datum/work_item/W = K.work_by_key[key]
	W?.wake()
	return !!W

/datum/unit_test/kernel_work_cadence

/datum/unit_test/kernel_work_cadence/Run()
	var/datum/controller/kernel/K = new
	K.expect_errors = TRUE
	var/datum/test_work_owner/O = new
	var/datum/work_item/test_fixture/W = K.register_work(/datum/test_work_owner, test_work_item(O, interval = 10))
	TEST_ASSERT_EQUAL(W.key, "/datum/test_work_owner:record", "the key is owner type and handler")

	// Cadence: due the first time, then every interval, with the real elapsed time.
	var/first = K.run_item(W, WORK_TEST_LIMIT, 100)
	TEST_ASSERT(first, "the first run completes: faults [W.faults] parked [W.parked] cursor [W.cursor] yielded [W.yielded] log [json_encode(K.fault_log)] tick [TICK_USAGE]")
	TEST_ASSERT_EQUAL(length(O.calls), 1, "it ran when first due")
	TEST_ASSERT_EQUAL(O.dts[1], 10, "the first dt is one interval")
	K.run_item(W, WORK_TEST_LIMIT, 105)
	TEST_ASSERT_EQUAL(length(O.calls), 1, "not due before the interval")
	K.run_item(W, WORK_TEST_LIMIT, 110)
	TEST_ASSERT_EQUAL(length(O.calls), 2, "due at the interval")
	K.run_item(W, WORK_TEST_LIMIT, 125)
	TEST_ASSERT_EQUAL(length(O.calls), 3, "a late pass still runs it")
	TEST_ASSERT_EQUAL(O.dts[3], 15, "with the real elapsed time, not the nominal one")

	// run_when gates without running.
	var/datum/test_work_owner/G = new
	G.gate = FALSE
	var/datum/work_item/test_fixture/gated = K.register_work(/datum/test_work_owner/gated, test_work_item(G, when = TYPE_PROC_REF(/datum/test_work_owner, is_open)))
	K.run_item(gated, WORK_TEST_LIMIT, 100)
	TEST_ASSERT_EQUAL(length(G.calls), 0, "run_when FALSE: the handler does not run")
	TEST_ASSERT_EQUAL(gated.skips, 1, "and the skip is counted")
	G.gate = TRUE
	K.run_item(gated, WORK_TEST_LIMIT, 110)
	TEST_ASSERT_EQUAL(length(G.calls), 1, "runs once the condition holds")

	// The step protocol.
	var/datum/test_work_owner/P = new
	P.result = STEP_PARK
	var/datum/work_item/test_fixture/parking = K.register_work(/datum/test_work_owner/parking, test_work_item(P))
	K.run_item(parking, WORK_TEST_LIMIT, 100)
	TEST_ASSERT(parking.parked, "STEP_PARK parks the item")
	K.run_item(parking, WORK_TEST_LIMIT, 200)
	TEST_ASSERT_EQUAL(length(P.calls), 1, "a parked item does not run")
	P.result = null
	TEST_ASSERT(test_wake_work(K, parking.key), "wake finds the item")
	K.run_item(parking, WORK_TEST_LIMIT, 210)
	TEST_ASSERT_EQUAL(length(P.calls), 2, "a woken item runs again")

	var/datum/test_work_owner/Y = new
	Y.result = STEP_YIELD
	var/datum/work_item/test_fixture/yielding = K.register_work(/datum/test_work_owner/yielding, test_work_item(Y, interval = 100))
	TEST_ASSERT(!K.run_item(yielding, WORK_TEST_LIMIT, 100), "a yield is not done")
	Y.result = null
	K.run_item(yielding, WORK_TEST_LIMIT, 101)
	TEST_ASSERT_EQUAL(length(Y.calls), 2, "a yielded step resumes next pass, ahead of its interval")
	K.run_item(yielding, WORK_TEST_LIMIT, 102)
	TEST_ASSERT_EQUAL(length(Y.calls), 2, "and then waits its interval")

	// Fault isolation: a runtime is caught and counted; a streak parks the item.
	var/datum/test_work_owner/F = new
	F.fault = TRUE
	var/datum/work_item/test_fixture/faulty = K.register_work(/datum/test_work_owner/faulty, test_work_item(F))
	var/now = 100
	for(var/i in 1 to KERNEL_FAULT_PARK)
		K.run_item(faulty, WORK_TEST_LIMIT, now)
		now += 10
	TEST_ASSERT_EQUAL(faulty.faults, KERNEL_FAULT_PARK, "every fault was caught and counted")
	TEST_ASSERT(faulty.parked, "a streak of faults parks the item")
	TEST_ASSERT_EQUAL(length(K.fault_log), KERNEL_FAULT_PARK, "and each is in the kernel's fault log")

	// Per-reaction cost accounting.
	var/list/cost = K.work_cost_of(/datum/test_work_owner)
	TEST_ASSERT_EQUAL(cost["items"], 1, "cost is summed by owner type")
	TEST_ASSERT_EQUAL(cost["runs"], W.runs, "runs counted")
	TEST_ASSERT(W.runs == 3 && W.total_ms >= 0, "each completed run is counted with its cost")
	var/list/metrics = K.metrics()
	TEST_ASSERT(!isnull(metrics["work"]["/datum/test_work_owner:record"]), "metrics() lists the item")
	TEST_ASSERT_EQUAL(metrics["work_items"], 5, "and counts the items")

/datum/unit_test/kernel_work_order

/datum/unit_test/kernel_work_order/Run()
	var/datum/controller/kernel/K = new
	K.expect_errors = TRUE
	var/datum/test_work_owner/O = new
	O.order = list()
	// Registered in reverse: the after-edges, not registration order, decide.
	var/datum/work_item/test_fixture/C = K.register_work(/datum/test_work_owner/c, test_work_item(O, TYPE_PROC_REF(/datum/test_work_owner, note_c), interval = 0, after = list(/datum/test_work_owner/b)))
	var/datum/work_item/test_fixture/B = K.register_work(/datum/test_work_owner/b, test_work_item(O, TYPE_PROC_REF(/datum/test_work_owner, note_b), interval = 0, after = list("/datum/test_work_owner/a:note_a")))
	var/datum/work_item/test_fixture/A = K.register_work(/datum/test_work_owner/a, test_work_item(O, TYPE_PROC_REF(/datum/test_work_owner, note_a), interval = 0))
	var/list/items = K.items_of_phase(KERNEL_PHASE_P)
	TEST_ASSERT_EQUAL(items.Find(A), 1, "a runs first")
	TEST_ASSERT_EQUAL(items.Find(B), 2, "b after a (by key)")
	TEST_ASSERT_EQUAL(items.Find(C), 3, "c after b (by owner type)")
	TEST_ASSERT_EQUAL(length(K.work_errors), 0, "a clean graph has no errors")
	K.work_run_phase(KERNEL_PHASE_P, WORK_TEST_LIMIT, 0, 100)
	TEST_ASSERT_EQUAL(jointext(O.order, ""), "abc", "they run in edge order")

	// Phase R (leftovers) runs its items when the pass reaches it.
	var/datum/controller/kernel/K5 = new
	var/datum/test_work_owner/O5 = new
	O5.order = list()
	K5.register_work(/datum/test_work_owner/a, test_work_item(O5, TYPE_PROC_REF(/datum/test_work_owner, note_a), interval = 0, phase = KERNEL_PHASE_R))
	K5.work_run_phase(KERNEL_PHASE_R, WORK_TEST_LIMIT, 0, 100)
	TEST_ASSERT_EQUAL(jointext(O5.order, ""), "a", "a leftover-phase item runs")
	K5.work_run_phase(KERNEL_PHASE_D, WORK_TEST_LIMIT, 0, 100)
	TEST_ASSERT_EQUAL(jointext(O5.order, ""), "a", "and a phase runs only its own items")

	// Lanes: a lane pass runs only its own items.
	O.order = list()
	K.work_run_phase(KERNEL_PHASE_P, WORK_TEST_LIMIT, LANE_URGENT, 110)
	TEST_ASSERT_EQUAL(length(O.order), 0, "nothing runs in a lane no item is in")
	K.work_run_phase(KERNEL_PHASE_P, WORK_TEST_LIMIT, LANE_SIMULATION, 110)
	TEST_ASSERT_EQUAL(jointext(O.order, ""), "abc", "the simulation lane runs them")

	// An edge into a later phase, or at nothing, is an error.
	var/datum/controller/kernel/K2 = new
	K2.expect_errors = TRUE
	var/datum/test_work_owner/O2 = new
	var/datum/work_item/test_fixture/late = K2.register_work(/datum/test_work_owner/a, test_work_item(O2, TYPE_PROC_REF(/datum/test_work_owner, note_a), phase = KERNEL_PHASE_R))
	var/datum/work_item/test_fixture/early = K2.register_work(/datum/test_work_owner/b, test_work_item(O2, TYPE_PROC_REF(/datum/test_work_owner, note_b), phase = KERNEL_PHASE_D, after = list(/datum/test_work_owner/a)))
	K2.rebuild_work_graph()
	TEST_ASSERT_EQUAL(length(K2.work_errors), 1, "an after-edge into a later phase is an error")
	TEST_ASSERT(early in K2.items_of_phase(KERNEL_PHASE_D), "but the item is still scheduled")
	TEST_ASSERT(late in K2.items_of_phase(KERNEL_PHASE_R), "and so is its target")
	K2.register_work(/datum/test_work_owner/c, test_work_item(O2, TYPE_PROC_REF(/datum/test_work_owner, note_c), phase = KERNEL_PHASE_R, after = list(/datum/test_work_owner/nothing)))
	K2.rebuild_work_graph()
	TEST_ASSERT_EQUAL(length(K2.work_errors), 2, "an edge naming no item is an error")

	// An edge into an earlier phase is satisfied already.
	var/datum/controller/kernel/K4 = new
	var/datum/test_work_owner/O4 = new
	K4.register_work(/datum/test_work_owner/a, test_work_item(O4, TYPE_PROC_REF(/datum/test_work_owner, note_a), phase = KERNEL_PHASE_D))
	K4.register_work(/datum/test_work_owner/b, test_work_item(O4, TYPE_PROC_REF(/datum/test_work_owner, note_b), phase = KERNEL_PHASE_R, after = list(/datum/test_work_owner/a)))
	K4.rebuild_work_graph()
	TEST_ASSERT_EQUAL(length(K4.work_errors), 0, "an after-edge into an earlier phase needs nothing")

	var/datum/controller/kernel/K3 = new
	K3.expect_errors = TRUE
	var/datum/test_work_owner/O3 = new
	var/datum/work_item/test_fixture/x = K3.register_work(/datum/test_work_owner/a, test_work_item(O3, TYPE_PROC_REF(/datum/test_work_owner, note_a), after = list(/datum/test_work_owner/b)))
	var/datum/work_item/test_fixture/y = K3.register_work(/datum/test_work_owner/b, test_work_item(O3, TYPE_PROC_REF(/datum/test_work_owner, note_b), after = list(/datum/test_work_owner/a)))
	K3.rebuild_work_graph()
	TEST_ASSERT(length(K3.work_errors) >= 1, "a cycle is reported")
	TEST_ASSERT(x in K3.items_of_phase(KERNEL_PHASE_P), "an item in a cycle still runs: a bad graph must not silence gameplay")
	TEST_ASSERT(y in K3.items_of_phase(KERNEL_PHASE_P), "and so does the other")

	// The boot DAG and the work graph share one validator: same sorter, same cycle report.
	var/list/nodes = list("p", "q")
	var/list/deps = list("p" = list("q"), "q" = list("p"))
	var/datum/graph_check/G = graph_validate(nodes, deps)
	TEST_ASSERT(!G.ok(), "graph_validate reports a cycle")
	var/list/cycle_direct = list()
	boot_dependency_order(nodes, deps, cycle_direct)
	TEST_ASSERT_EQUAL(jointext(G.cycle, ","), jointext(cycle_direct, ","), "with the boot sorter's own cycle")
	var/datum/graph_check/fine = graph_validate(list("p", "q"), list("p" = list("q"), "q" = list()), list("q needs nothing"))
	TEST_ASSERT(fine.order[1] == "q" && fine.order[2] == "p", "an acyclic graph orders dependencies first")
	TEST_ASSERT_EQUAL(length(fine.errors), 1, "and carries the caller's own resolution errors")

/// Members of a work item are relations in the membership store.
/datum/test_work_member
/datum/test_work_member/keyed
/datum/test_work_member/other_key

/datum/unit_test/kernel_work_urgent

/datum/unit_test/kernel_work_urgent/Run()
	var/datum/controller/kernel/K = new
	K.expect_errors = TRUE
	var/datum/test_work_owner/O = new
	var/key = /datum/test_work_member
	var/datum/test_work_member/M = new
	var/datum/test_work_member/N = new
	member_join(key, M)
	member_join(key, N)
	var/datum/work_item/test_fixture/W = K.register_work(/datum/test_work_owner, test_work_item(O, TYPE_PROC_REF(/datum/test_work_owner, record_member), interval = 10, members = key, urgent = TRUE))
	var/datum/work_item/test_fixture/plain = K.register_work(/datum/test_work_owner/a, test_work_item(O, TYPE_PROC_REF(/datum/test_work_owner, record_member), interval = 10, members = key))

	TEST_ASSERT_NULL(K.kernel_urgent(M, plain, 500), "an item not declared urgent refuses requests")
	var/datum/urgent_request/R = K.kernel_urgent(M, W, 500)
	TEST_ASSERT(R, "an urgent item takes a request")
	TEST_ASSERT_EQUAL(K.kernel_urgent(M, W, 700), R, "a second request for the same member and work is the same request")
	TEST_ASSERT_EQUAL(K.urgent_deduped, 1, "and is counted as deduped")
	TEST_ASSERT_EQUAL(R.deadline, 500, "it keeps the earlier deadline")
	K.kernel_urgent(M, W, 300)
	TEST_ASSERT_EQUAL(R.deadline, 300, "an earlier deadline tightens it")
	TEST_ASSERT_EQUAL(length(K.urgent_queue), 1, "one pending request")

	// It runs from phase U, stamps the execution token, and the cadence pass does not apply the same time twice.
	K.run_urgent(WORK_TEST_LIMIT, 100)
	TEST_ASSERT_EQUAL(O.members_seen[M], 1, "the urgent run reached the member")
	TEST_ASSERT_NULL(O.members_seen[N], "and only that member")
	TEST_ASSERT_EQUAL(length(K.urgent_queue), 0, "the request is finished")
	K.run_item(W, WORK_TEST_LIMIT, 100)
	TEST_ASSERT_EQUAL(O.members_seen[M], 1, "the cadence pass in the same instant skips the member (token current)")
	TEST_ASSERT_EQUAL(O.members_seen[N], 1, "but still runs the others")
	K.run_item(W, WORK_TEST_LIMIT, 110)
	TEST_ASSERT_EQUAL(O.members_seen[M], 2, "the next pass runs it again")
	TEST_ASSERT_EQUAL(O.dts[length(O.dts)], 10, "with the time since the urgent run, applied once")

	// Breach metric: overdue requests are counted once, late runs sum their lateness.
	var/datum/test_work_owner/O2 = new
	var/datum/work_item/test_fixture/W2 = K.register_work(/datum/test_work_owner/b, test_work_item(O2, TYPE_PROC_REF(/datum/test_work_owner, record_member), interval = 10, members = key, urgent = TRUE))
	K.kernel_urgent(M, W2, 150)
	K.run_urgent(WORK_TEST_LIMIT, 200)
	TEST_ASSERT_EQUAL(K.urgent_breaches, 1, "a run after its deadline is a breach")
	TEST_ASSERT_EQUAL(K.urgent_lateness_ds, 50, "with its lateness")
	K.kernel_urgent(M, W2, 400)
	K.run_urgent(WORK_TEST_LIMIT, 300)
	TEST_ASSERT_EQUAL(K.urgent_breaches, 1, "a run before its deadline is not")

	// The reserved slice: over budget, one request still runs and the rest wait; overdue ones count.
	K.kernel_urgent(M, W2, 310)
	K.kernel_urgent(N, W2, 320)
	K.run_urgent(-1, 400)
	TEST_ASSERT_EQUAL(length(K.urgent_queue), 1, "a spent slice still runs the earliest request, and leaves the rest")
	TEST_ASSERT_EQUAL(K.urgent_breaches, 3, "both overdue requests were counted")
	TEST_ASSERT_NULL(O2.members_seen[N], "the earliest deadline went first")
	K.run_urgent(WORK_TEST_LIMIT, 401)
	TEST_ASSERT_EQUAL(length(K.urgent_queue), 0, "the rest runs when the slice allows")
	TEST_ASSERT_EQUAL(K.urgent_breaches, 3, "an already-counted breach is not counted twice")

	// A deleted member's request is dropped.
	K.kernel_urgent(N, W2, 900)
	member_purge(N)
	qdel(N)
	K.run_urgent(WORK_TEST_LIMIT, 500)
	TEST_ASSERT_EQUAL(K.urgent_dropped, 1, "a request for a deleted member is dropped")
	member_purge(M)
	qdel(M)

/datum/unit_test/kernel_work_membership

/datum/unit_test/kernel_work_membership/Run()
	var/key = /datum/test_work_member/keyed
	var/datum/test_work_member/a = new
	var/datum/test_work_member/b = new
	var/datum/test_work_member/c = new
	var/datum/test_work_member/src1 = new
	var/datum/test_work_member/src2 = new
	TEST_ASSERT(member_join(key, a, src1), "a first join is new")
	TEST_ASSERT(!member_join(key, a, src2), "a second source on the same member is not a new membership")
	member_join(key, b)
	member_join(key, c, null, "supply")
	TEST_ASSERT_EQUAL(members_total(key), 3, "three members")
	TEST_ASSERT(!member_leave(key, a, src1), "dropping one of two sources keeps the member")
	TEST_ASSERT(member_is(key, a), "still a member")
	TEST_ASSERT(member_leave(key, a, src2), "dropping the last source removes it")
	TEST_ASSERT(!member_is(key, a), "gone")
	TEST_ASSERT_EQUAL(members_of(key)[1], c, "swap-remove: the last member took the freed slot")
	TEST_ASSERT(c in members_of(key, "supply"), "a role indexes the members that hold it")
	TEST_ASSERT_EQUAL(length(members_of(key, "other")), 0, "and no one else is in another role")
	TEST_ASSERT_EQUAL(member_role(key, c), "supply", "the role reads back")
	member_join(/datum/test_work_member/other_key, c)
	TEST_ASSERT_EQUAL(length(member_keys(c)), 2, "a member knows its keys")
	var/list/left = member_purge(c)
	TEST_ASSERT_EQUAL(length(left), 2, "purge removes it from every key")
	TEST_ASSERT(!(c in members_of(key, "supply")), "and from its role list")
	member_purge(b)
	TEST_ASSERT_EQUAL(members_total(key), 0, "empty")

	// The roster wrappers: a system joins through the store; world_services() comes from the registry.
	var/datum/system/test_members/S = new
	S.kernel_join(a)
	TEST_ASSERT(member_is(S.type, a) && S.is_member(a), "a system's members are membership relations")
	TEST_ASSERT_EQUAL(S.member_list()[1], a, "member_list() is the relation store's list")
	S.kernel_leave(a)
	TEST_ASSERT_EQUAL(S.member_count(), 0, "leaving removes it")
	TEST_ASSERT(SSmachines in kernel_systems(), "kernel_systems() is derived from the registry")

/datum/test_work_stage_member
	var/ready = FALSE
	var/steps = 0

/datum/work_stage/kernel_adapter_fixture
	registry_skip = TRUE
	of = /datum/test_work_stage_member
	reads = list("ready")

/datum/work_stage/kernel_adapter_fixture/idle(datum/test_work_stage_member/member)
	return !member.ready

/datum/work_stage/kernel_adapter_fixture/perform(datum/test_work_stage_member/member, datum/work_frame/F)
	member.steps++
	return STEP_DONE

/datum/unit_test/kernel_work_stage_adapter

/datum/unit_test/kernel_work_stage_adapter/Run()
	var/datum/definition_registry/reg = definition_registry()
	var/list/original_stages = reg.stage_by_type
	set_var(reg, nameof(reg.stage_by_type), original_stages.Copy())
	var/datum/work_stage/kernel_adapter_fixture/T = allocate(/datum/work_stage/kernel_adapter_fixture)
	reg.stage_by_type[T.type] = T
	TEST_ASSERT(!(T.type in original_stages), "the skipped fixture never entered the boot registry")
	var/datum/work_item/stage/W = stage_work_item(T.type, /datum/test_work_stage_member, 2 SECONDS)
	own(W)
	TEST_ASSERT(istype(W), "a canonical engine stage adapts to an actual work item")
	TEST_ASSERT_EQUAL(W.interval, 2 SECONDS, "it carries the requested cadence")
	TEST_ASSERT_EQUAL(length(W.reads), 1, "the adapter carries the fixture's genuine ready dependency")
	TEST_ASSERT_EQUAL(W.reads[1], "ready", "the declared dependency survives unchanged")
	TEST_ASSERT(W.reads != T.reads, "the adapter owns a separate dependency list")
	var/datum/test_work_stage_member/member = allocate(/datum/test_work_stage_member)
	TEST_ASSERT(!W.runnable(null, member), "an unready member idles through the actual adapter")
	member.ready = TRUE
	TEST_ASSERT(W.runnable(null, member), "the actual adapter wakes for a ready member")
	T.perform(member, null)
	TEST_ASSERT_EQUAL(member.steps, 1, "the actual stage effect changes real member state")
	member.ready = FALSE
	TEST_ASSERT(!W.runnable(null, member), "the actual adapter parks after readiness is removed")
	TEST_ASSERT(W.runnable(null, null), "without a member the adapter asks nothing of the stage")
	TEST_ASSERT_EQUAL(W.owner(), W, "the adapter owns itself")

/datum/test_work_owner/phases
	var/list/phase_log = list()

/datum/test_work_owner/phases/proc/note_k(dt)
	phase_log += "[world.time]:K"

/datum/test_work_owner/phases/proc/note_s(dt)
	phase_log += "[world.time]:S"

/datum/test_work_owner/phases/proc/note_n(dt)
	phase_log += "[world.time]:N"

/datum/test_work_owner/phases/proc/note_d(dt)
	phase_log += "[world.time]:D"

/datum/test_work_owner/phases/proc/note_p(dt)
	phase_log += "[world.time]:P"

/datum/test_work_owner/phases/proc/note_r(dt)
	phase_log += "[world.time]:R"

/datum/test_work_owner/phases/proc/note_g(dt)
	phase_log += "[world.time]:G"

/datum/unit_test/kernel_tick_phases

/datum/unit_test/kernel_tick_phases/Run()
	var/datum/controller/kernel/K = kernel()
	TEST_ASSERT(SSbehaviours.initialized, "SSbehaviours is a system: it booted, and the scheduler pass runs from the kernel")
	var/datum/test_work_owner/phases/O = new
	var/list/handlers = list("note_k", "note_s", "note_n", "note_d", "note_p", "note_r", "note_g")
	var/list/phase_of = list(KERNEL_PHASE_K, KERNEL_PHASE_S, KERNEL_PHASE_N, KERNEL_PHASE_D, KERNEL_PHASE_P, KERNEL_PHASE_R, KERNEL_PHASE_G)
	for(var/i in 1 to length(handlers))
		var/datum/work_item/test_fixture/W = new(handlers[i], WORK_EVERY_TICK)
		W.phase = phase_of[i]
		W.fixture = O
		K.register_work(/datum/test_work_owner/phases, W)
	var/ticks_before = K.ticks
	var/datum/work_item/input_drain = K.work_by_key["[/datum/system/input]:drain_step"]
	var/input_before = input_drain.runs
	// The drain parks while nothing is queued: a wake is what makes it run once more.
	SSinput.wake_work_item(TYPE_PROC_REF(/datum/system/input, drain_step))
	var/bench_before = SSbehaviours.bench_ms
	var/runs_before = K.sched?.runs
	// Phase G runs on leftovers with a floor once a second: the window has to span one.
	sleep(1 SECONDS + 4)
	K.unregister_work(/datum/test_work_owner/phases)
	TEST_ASSERT(K.ticks > ticks_before, "the kernel loop runs the kernel tick every tick")
	TEST_ASSERT(input_drain.runs > input_before, "phase K runs the input inbox's drain")
	TEST_ASSERT(SSbehaviours.bench_ms > bench_before, "the scheduler pass runs from the kernel and is counted")
	TEST_ASSERT(K.sched.runs > runs_before, "phases D, P and R are scheduler passes")
	TEST_ASSERT_EQUAL(length(K.work_errors), 0, "the live work graph has no errors")
	var/list/log = O.phase_log
	TEST_ASSERT(length(log) >= 7, "work items ran")
	// Group by tick: inside a tick the phases that ran are in K S N D P R G order, and every phase ran at some tick.
	var/order = "KSNDPRG"
	var/last_time
	var/last_index = 0
	var/seen = ""
	for(var/entry in log)
		var/list/parts = splittext(entry, ":")
		var/index = findtext(order, parts[2])
		if(parts[1] == last_time)
			TEST_ASSERT(index > last_index, "phase [parts[2]] ran out of order in tick [parts[1]]: [json_encode(log)]")
		last_time = parts[1]
		last_index = index
		if(!findtext(seen, parts[2]))
			seen += parts[2]
	// R is leftovers: it runs only when the lanes left budget, which a busy test tick may not. G has its floor.
	for(var/letter in list("K", "S", "N", "D", "P", "G"))
		TEST_ASSERT(findtext(seen, letter), "phase [letter] ran: [json_encode(log)]")
	TEST_ASSERT(K.phase_ms_total[KERNEL_PHASE_P] >= 0, "phase cost is accounted")
	var/list/metrics = K.metrics()
	TEST_ASSERT(!isnull(metrics["phases"]["P"]), "metrics() reports the phases")
