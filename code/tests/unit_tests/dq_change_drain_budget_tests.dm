// The on_change drain and the late-notice drain share the simulation lane's budget with the stat drain: a cascade that does not fit is carried, in
// order, to the next drain point, and every change is delivered exactly once (code/engine/actions/change.dm, notices.dm).

/obj/drainb_node
	name = "drain budget node"
	anchored = TRUE
	/// Order of this node among the allocated ones; the hook appends it to GLOB.drainb_order when it runs.
	var/serial = 0
	var/armed = FALSE
	var/heard = 0

GLOBAL_LIST_EMPTY(drainb_order)

CAPABILITIES(/obj/drainb_node)
	on_change(nameof(armed), ANY, then(PROC_REF(armed_changed)))
	on_notice(/datum/notice/lanea_boomed, then(PROC_REF(heard_boom)))

/obj/drainb_node/proc/armed_changed(datum/act/A)
	heard++
	GLOB.drainb_order += serial

/obj/drainb_node/proc/heard_boom(datum/act/A)
	heard++
	GLOB.drainb_order += serial

/datum/unit_test/dq_change_drain_budget
	abstract_type = /datum/unit_test/dq_change_drain_budget

/// Allocates `count` nodes numbered in order.
/datum/unit_test/dq_change_drain_budget/proc/make_nodes(count)
	var/list/nodes = list()
	for(var/i in 1 to count)
		var/obj/drainb_node/N = allocate(/obj/drainb_node)
		N.serial = i
		nodes += N
	// Whatever other machines the test world left marked is delivered first, so the budget below is spent on the nodes alone.
	var/flush = 0
	while(GLOB.hook_change_pending && flush++ < 50)
		hooks_drain_changes()
	GLOB.drainb_order = list()
	return nodes

/// The serials of the holders marked now, in the order the drain takes them.
/datum/unit_test/dq_change_drain_budget/proc/pending_order()
	var/list/order = list()
	for(var/handle in GLOB.hook_change_pending)
		var/obj/drainb_node/N = handle_get(handle)
		if(istype(N))
			order += N.serial
	return order

/datum/unit_test/dq_change_drain_budget/on_change_cascade_spreads_over_drains_in_order/Run()
	var/list/nodes = make_nodes(10)
	for(var/obj/drainb_node/N as anything in nodes)
		N.set_armed(TRUE)
	var/list/expect = pending_order()
	TEST_ASSERT_EQUAL(length(expect), 10, "every node is marked before the drain: [json_encode(expect)]")
	test_budget(LANE_SIMULATION, 3 * TEST_EVAL_COST)
	hooks_drain_changes()
	TEST_ASSERT_EQUAL(length(GLOB.drainb_order), 3, "the first drain ran only what the budget allows")
	TEST_ASSERT(GLOB.hook_change_pending, "the rest is still marked")
	// A change marked while the rest waits: a node that already ran again, and one still waiting (one mark, not two).
	var/obj/drainb_node/again = nodes[expect[1]]
	again.set_armed(FALSE)
	var/obj/drainb_node/waiting = nodes[expect[10]]
	waiting.set_armed(FALSE)
	var/drains = 1
	while(GLOB.hook_change_pending && drains < 20)
		hooks_drain_changes()
		drains++
	test_budget(LANE_SIMULATION, null)
	TEST_ASSERT(drains > 3, "the cascade took several drains: [drains]")
	TEST_ASSERT(!GLOB.hook_change_pending, "nothing is left marked")
	TEST_ASSERT_EQUAL(json_encode(GLOB.drainb_order.Copy(1, 4)), json_encode(expect.Copy(1, 4)), "the first drain took the head of the marks")
	// Each node ran once; the one that changed again ran a second time; the one flipped back before it ran saw no change (its value is read when it
	// runs), so it did not run at all.
	for(var/serial in expect)
		var/ran = 0
		for(var/entry in GLOB.drainb_order)
			if(entry == serial)
				ran++
		var/want = (serial == waiting.serial) ? 0 : ((serial == again.serial) ? 2 : 1)
		TEST_ASSERT_EQUAL(ran, want, "node [serial] delivered [want] time(s): [json_encode(GLOB.drainb_order)]")

/datum/unit_test/dq_change_drain_budget/kernel_drain_point_resumes_the_carried_hooks/Run()
	var/list/nodes = make_nodes(8)
	for(var/obj/drainb_node/N as anything in nodes)
		N.set_armed(TRUE)
	var/list/expect = pending_order()
	test_budget(LANE_SIMULATION, 2 * TEST_EVAL_COST)
	stat_tick_begin()
	stat_drain_point()
	TEST_ASSERT(length(GLOB.drainb_order) < 8, "one tick's drain points did not run the whole cascade")
	TEST_ASSERT(length(GLOB.drainb_order) >= 1, "but made progress")
	var/ticks = 1
	while(GLOB.hook_change_pending && ticks < 20)
		stat_tick_begin()
		stat_drain_point()
		ticks++
	test_budget(LANE_SIMULATION, null)
	TEST_ASSERT(ticks > 1, "the rest resumed on later ticks")
	TEST_ASSERT_EQUAL(json_encode(GLOB.drainb_order), json_encode(expect), "every change delivered once, in order")

/datum/unit_test/dq_change_drain_budget/late_notices_carry_in_order/Run()
	var/list/nodes = make_nodes(7)
	for(var/obj/drainb_node/N as anything in nodes)
		var/datum/notice/lanea_boomed/queued = take(/datum/notice/lanea_boomed)
		GLOB.notice_late_queue += list(list(N, queued, ACT_COMMITTED, "budget test"))
	test_budget(LANE_SIMULATION, 2 * TEST_EVAL_COST)
	notice_drain_late()
	TEST_ASSERT_EQUAL(length(GLOB.drainb_order), 2, "the first drain delivered what the budget allows")
	TEST_ASSERT_EQUAL(length(GLOB.notice_late_queue), 5, "the rest is still queued")
	TEST_ASSERT(!GLOB.notice_draining_late, "the draining flag is clear")
	var/drains = 1
	while(length(GLOB.notice_late_queue) && drains < 20)
		notice_drain_late()
		drains++
	test_budget(LANE_SIMULATION, null)
	TEST_ASSERT_EQUAL(json_encode(GLOB.drainb_order), json_encode(list(1, 2, 3, 4, 5, 6, 7)), "every late notice delivered once, in the order queued")

/datum/unit_test/dq_change_drain_budget/carried_hook_of_a_deleted_holder_is_dropped/Run()
	var/list/nodes = make_nodes(4)
	for(var/obj/drainb_node/N as anything in nodes)
		N.set_armed(TRUE)
	var/list/expect = pending_order()
	test_budget(LANE_SIMULATION, TEST_EVAL_COST)
	hooks_drain_changes()
	var/obj/drainb_node/doomed = nodes[expect[2]]
	expect -= doomed.serial
	qdel(doomed)
	var/drains = 0
	while(GLOB.hook_change_pending && drains++ < 20)
		hooks_drain_changes()
	test_budget(LANE_SIMULATION, null)
	TEST_ASSERT(!GLOB.hook_change_pending, "nothing stranded")
	TEST_ASSERT_EQUAL(json_encode(GLOB.drainb_order), json_encode(expect), "the deleted holder's carried hook did not run; the others did, once")
