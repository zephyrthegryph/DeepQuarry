/// The input inbox (code/engine/kernel/inbox.dm; doc/rewrite/final_api.html section 2): an input resolves in place with
/// budget, queues without it, drains in arrival order and round-robin across clients, coalesces and drops past the cap, and
/// drops a stale target with the gate's reason.

/// Where the probes record what resolved, in order.
GLOBAL_LIST_EMPTY(inbox_probe_log)

/// A fixture input: resolves by writing its id into the log. `lane` is the client it stands for.
/datum/input_event/probe
	driven = TRUE
	var/id
	var/lane
	var/coalesce
	var/datum/thing
	var/faulty = FALSE

/datum/input_event/probe/lane_key()
	return lane

/datum/input_event/probe/coalesce_key()
	return coalesce

/datum/input_event/probe/subject()
	return thing

/datum/input_event/probe/resolve()
	if(faulty)
		CRASH("deliberate inbox probe fault")
	GLOB.inbox_probe_log += id
	return null

/// A probe in `lane`.
/proc/inbox_probe(id, lane, coalesce = null, datum/thing = null, faulty = FALSE)
	var/datum/input_event/probe/P = new
	P.id = id
	P.lane = lane
	P.coalesce = coalesce
	P.thing = thing
	P.faulty = faulty
	return P

/datum/unit_test/kernel_inbox_in_place_and_queue

/datum/unit_test/kernel_inbox_in_place_and_queue/Run()
	test_driver_begin()
	GLOB.inbox_probe_log = list()
	var/lane = "client_a"
	SSinput.room_override = TRUE
	TEST_ASSERT(input_submit(inbox_probe("A", lane)), "with room the input resolves on the spot")
	TEST_ASSERT_EQUAL(jointext(GLOB.inbox_probe_log, ""), "A", "and it ran before the call returned")
	SSinput.room_override = FALSE
	TEST_ASSERT(!input_submit(inbox_probe("B", lane)), "without room it queues")
	TEST_ASSERT(!input_submit(inbox_probe("C", lane)), "and so does the next")
	TEST_ASSERT_EQUAL(length(SSinput.waiting(lane)), 2, "two waiting")
	// Room again: an input behind a queue still waits its turn, so arrival order holds.
	SSinput.room_override = TRUE
	TEST_ASSERT(!input_submit(inbox_probe("D", lane)), "an input behind a waiting one does not jump the queue")
	TEST_ASSERT_EQUAL(length(SSinput.waiting(lane)), 3, "three waiting")
	TEST_ASSERT_EQUAL(jointext(GLOB.inbox_probe_log, ""), "A", "nothing ran yet")
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(jointext(GLOB.inbox_probe_log, ""), "ABCD", "phase K drains in arrival order")
	TEST_ASSERT_EQUAL(length(SSinput.waiting(lane)), 0, "and empties the inbox")
	TEST_ASSERT_EQUAL(SSinput.queued_total(), 0, "nothing left anywhere")
	test_driver_end()

/datum/unit_test/kernel_inbox_round_robin

/datum/unit_test/kernel_inbox_round_robin/Run()
	test_driver_begin()
	GLOB.inbox_probe_log = list()
	SSinput.room_override = FALSE
	for(var/i in 1 to 3)
		input_submit(inbox_probe("x[i]", "client_x"))
	for(var/i in 1 to 3)
		input_submit(inbox_probe("y[i]", "client_y"))
	input_submit(inbox_probe("z1", "client_z"))
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(jointext(GLOB.inbox_probe_log, ","), "x1,y1,z1,x2,y2,x3,y3", "clients are served round-robin, each in its own arrival order")
	test_driver_end()

/datum/unit_test/kernel_inbox_coalesce_and_cap

/datum/unit_test/kernel_inbox_coalesce_and_cap/Run()
	test_driver_begin()
	GLOB.inbox_probe_log = list()
	SSinput.room_override = FALSE
	var/lane = "client_a"
	var/coalesced_before = SSinput.coalesced
	input_submit(inbox_probe("held1", lane, "move"))
	input_submit(inbox_probe("say1", lane))
	input_submit(inbox_probe("held2", lane, "move"))
	TEST_ASSERT_EQUAL(length(SSinput.waiting(lane)), 2, "a repeated held key keeps only the latest")
	TEST_ASSERT_EQUAL(SSinput.coalesced - coalesced_before, 1, "and counts it")
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(jointext(GLOB.inbox_probe_log, ","), "say1,held2", "the latest copy sits at the latest position")

	// The cap: past INPUT_CLIENT_MAX the oldest coalescible input goes.
	GLOB.inbox_probe_log = list()
	var/dropped_before = SSinput.dropped_cap
	for(var/i in 1 to INPUT_CLIENT_MAX + 5)
		input_submit(inbox_probe("k[i]", lane, "key[i]"))
	TEST_ASSERT_EQUAL(length(SSinput.waiting(lane)), INPUT_CLIENT_MAX, "the inbox is bounded")
	TEST_ASSERT_EQUAL(SSinput.dropped_cap - dropped_before, 5, "five were dropped and counted")
	var/datum/input_event/probe/oldest = SSinput.waiting(lane)[1]
	TEST_ASSERT_EQUAL(oldest.id, "k6", "the oldest five were the ones dropped")
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(length(GLOB.inbox_probe_log), INPUT_CLIENT_MAX, "what stayed resolved")

	// An input that cannot coalesce is never dropped: not even past the cap.
	GLOB.inbox_probe_log = list()
	var/other = "client_b"
	for(var/i in 1 to INPUT_CLIENT_MAX + 10)
		input_submit(inbox_probe("n[i]", other))
	TEST_ASSERT_EQUAL(length(SSinput.waiting(other)), INPUT_CLIENT_MAX + 10, "say, Topic and admin inputs are never dropped")
	var/dropped_mid = SSinput.dropped_cap
	input_submit(inbox_probe("late", other, "late_key"))
	TEST_ASSERT_EQUAL(SSinput.dropped_cap - dropped_mid, 1, "a droppable input arriving at an inbox full of undroppable ones is the one shed")
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(length(GLOB.inbox_probe_log), INPUT_CLIENT_MAX + 10, "every one of them resolved")
	test_driver_end()

/datum/unit_test/kernel_inbox_stale_target

/datum/unit_test/kernel_inbox_stale_target/Run()
	test_driver_begin()
	GLOB.inbox_probe_log = list()
	SSinput.room_override = FALSE
	var/obj/item/pen/target = allocate(/obj/item/pen)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	var/datum/input_event/probe/stale = inbox_probe("stale", "client_a", null, target)
	stale.actor = actor
	input_submit(stale)
	input_submit(inbox_probe("fresh", "client_a"))
	qdel(target)
	wait_ticks(2)
	TEST_ASSERT(QDELETED(target), "the target is gone before the drain")
	test_record(actor)
	test_phase(KERNEL_PHASE_K)
	var/list/rows = test_recorded()
	TEST_ASSERT_EQUAL(jointext(GLOB.inbox_probe_log, ","), "fresh", "the input on the vanished target did not run; the next one did")
	TEST_ASSERT_EQUAL(test_events_count(rows, TEST_EVENT_OUTCOME), 1, "the drop is recorded once")
	var/datum/test_event/row = rows[1]
	TEST_ASSERT_EQUAL(row.to_value, ACT_REFUSED, "as a refusal")
	TEST_ASSERT_EQUAL(row.from_value, /datum/msg/input/stale_target, "with the gate's reason")
	test_driver_end()

/datum/unit_test/kernel_inbox_fault_isolated

/datum/unit_test/kernel_inbox_fault_isolated/Run()
	test_driver_begin()
	GLOB.inbox_probe_log = list()
	SSinput.room_override = FALSE
	var/datum/controller/kernel/K = kernel()
	set_var(K, "expect_errors", TRUE)
	var/faults_before = SSinput.faults
	input_submit(inbox_probe("bad", "client_a", null, null, TRUE))
	input_submit(inbox_probe("good", "client_a"))
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(SSinput.faults - faults_before, 1, "an input that runtimes is counted")
	TEST_ASSERT_EQUAL(jointext(GLOB.inbox_probe_log, ","), "good", "and the drain goes on to the next input")
	test_driver_end()

/// The driver's input forms enter the inbox as typed events; the resolver behind them is E2's, and says so until it lands.
/datum/unit_test/kernel_inbox_driver_forms

/datum/unit_test/kernel_inbox_driver_forms/Run()
	test_driver_begin()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	var/obj/item/pen/target = allocate(/obj/item/pen)
	SSinput.room_override = FALSE
	test_click(actor, target, null)
	test_ui(actor, target, "toggle", list())
	test_menu(actor, target, "x.y")
	TEST_ASSERT_EQUAL(length(SSinput.waiting(actor)), 3, "a click, a window action and a menu pick are three inputs of one actor")
	var/datum/input_event/click/clicked = SSinput.waiting(actor)[1]
	TEST_ASSERT_EQUAL(clicked.origin, ORIGIN_CLICK, "a click comes in as ORIGIN_CLICK")
	var/datum/input_event/ui_act/pressed = SSinput.waiting(actor)[2]
	TEST_ASSERT_EQUAL(pressed.origin, ORIGIN_UI, "a window action as ORIGIN_UI")
	var/datum/input_event/menu/picked = SSinput.waiting(actor)[3]
	TEST_ASSERT_EQUAL(picked.origin, ORIGIN_MENU, "a menu pick as ORIGIN_MENU")
	TEST_ASSERT_EQUAL(picked.op_key, "x.y", "carrying the op key")
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT(e0_pending_any(), "the resolver behind the inbox (E2) reports that it is not there yet")
	TEST_ASSERT_EQUAL(length(SSinput.waiting(actor)), 0, "and the inbox is drained")
	test_driver_end()
