/// Latency classes, overrun shedding and the kernel click queue (code/controllers/kernel/latency.dm).
/// Uses private /datum/kernel_latency instances so the live one (and the scheduler) are untouched.

/datum/system/test_latency_l3
	abstract_type = /datum/system/test_latency_l3
	latency_class = LATENCY_L3

/datum/unit_test/kernel_latency

/datum/unit_test/kernel_latency/Run()
	TEST_ASSERT_EQUAL(kernel_lane_class(LANE_URGENT), LATENCY_L1, "urgent is a deadline lane")
	TEST_ASSERT_EQUAL(kernel_lane_class(LANE_SIMULATION), LATENCY_L2, "simulation defers")
	TEST_ASSERT_EQUAL(kernel_lane_class(LANE_DERIVED), LATENCY_L2, "derived defers")
	TEST_ASSERT_EQUAL(kernel_lane_class(LANE_PRESENTATION), LATENCY_L3, "presentation sheds")
	TEST_ASSERT_EQUAL(kernel_lane_class(LANE_BACKGROUND), LATENCY_L3, "background sheds")
	var/datum/kernel_latency/live = kernel_latency()
	TEST_ASSERT(!live.enabled, "test builds leave live shedding off")

	var/datum/kernel_latency/L = new
	L.enabled = TRUE
	TEST_ASSERT(L.admit(LATENCY_L3), "nothing is shed while calm")

	// A streak of overruns starts shedding; a lone overrun does not.
	L.note_tick(120)
	L.note_tick(90)
	TEST_ASSERT(!L.shedding, "an isolated overrun does not shed")
	for(var/i in 1 to KERNEL_SHED_STREAK)
		L.note_tick(130)
	TEST_ASSERT(L.shedding, "[KERNEL_SHED_STREAK] overruns in a row start shedding")
	TEST_ASSERT_EQUAL(L.shed_events, 1, "one shed event")

	// L0-L2 always run; L3 is refused except for the once-a-second floor.
	L.floor_pass["k"] = world.time
	TEST_ASSERT(L.admit(LATENCY_L0) && L.admit(LATENCY_L1) && L.admit(LATENCY_L2), "L0-L2 are never shed")
	TEST_ASSERT(!L.admit(LATENCY_L3, "k"), "L3 is shed under overrun")
	TEST_ASSERT(L.sheds_lane(LANE_PRESENTATION) && L.sheds_lane(LANE_BACKGROUND), "the L3 lanes are shed")
	TEST_ASSERT(!L.sheds_lane(LANE_SIMULATION) && !L.sheds_lane(LANE_URGENT), "the deadline and defer lanes are not")
	TEST_ASSERT_EQUAL(L.shed_by_class[LATENCY_L3 + 1], 1, "the refusal is counted against L3")
	L.floor_pass["k"] = world.time - KERNEL_SHED_FLOOR
	TEST_ASSERT(L.admit(LATENCY_L3, "k"), "L3 gets its floor pass after a second")
	TEST_ASSERT(!L.admit(LATENCY_L3, "k"), "and only one")
	TEST_ASSERT(L.admit(LATENCY_L3, "other"), "a different L3 key has its own floor and is not starved by the first")
	TEST_ASSERT(!L.admit(LATENCY_L3, "other"), "which is also one a second")
	var/datum/system/test_latency_l3/S = new
	L.floor_pass[S.type] = world.time
	TEST_ASSERT(!L.admit(S.latency_class, S.type), "a system's class and type are what gate it")

	// Shedding ends after enough calm ticks.
	for(var/i in 1 to KERNEL_SHED_RECOVER - 1)
		L.note_tick(50)
	TEST_ASSERT(L.shedding, "still shedding one calm tick early")
	L.note_tick(50)
	TEST_ASSERT(!L.shedding, "shedding ends after [KERNEL_SHED_RECOVER] calm ticks")
	L.enabled = FALSE
	for(var/i in 1 to KERNEL_SHED_STREAK)
		L.note_tick(200)
	TEST_ASSERT(L.admit(LATENCY_L3), "a disabled kernel never sheds")

	// Input latency: a histogram in ticks, read in one pass.
	var/datum/kernel_latency/I = new
	for(var/i in 1 to 90)
		I.record_input(0)
	for(var/i in 1 to 9)
		I.record_input(1)
	I.record_input(5)
	TEST_ASSERT_EQUAL(I.input_percentile(50), 0, "p50 is on arrival")
	TEST_ASSERT_EQUAL(I.input_percentile(95), 1, "p95 waited a tick")
	TEST_ASSERT_EQUAL(I.input_percentile(100), 5, "the worst waited five ticks")
	I.record_input(999)
	TEST_ASSERT_EQUAL(I.input_percentile(100), KERNEL_LATENCY_BINS - 1, "slower clicks land in the last bin")

	// The click queue: bounded, drops the oldest, and drops a click whose target is gone.
	var/datum/kernel_latency/Q = new
	Q.enabled = TRUE
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/atom/target = allocate(/obj/item/pen)
	TEST_ASSERT(!Q.should_queue_click(H), "a clientless mob is never queued")
	for(var/i in 1 to KERNEL_CLICK_QUEUE_MAX + 3)
		Q.enqueue_click(H, target, null, null, "")
	TEST_ASSERT_EQUAL(length(Q.click_queue), KERNEL_CLICK_QUEUE_MAX, "the queue is bounded")
	TEST_ASSERT_EQUAL(Q.input_dropped, 3, "the overflow dropped the oldest")
	TEST_ASSERT_EQUAL(Q.input_queued, KERNEL_CLICK_QUEUE_MAX + 3, "every arrival counted as queued")
	var/list/m = Q.metrics()
	TEST_ASSERT_EQUAL(m["input_dropped"], 3, "metrics report drops")
	qdel(target)
	wait_ticks(3)
	TEST_ASSERT(QDELETED(target), "the target is gone before the drain")
	var/ran = Q.drain_clicks()
	TEST_ASSERT_EQUAL(ran, 0, "clicks on a deleted target do not run")
	TEST_ASSERT_EQUAL(Q.input_dropped, 3 + KERNEL_CLICK_QUEUE_MAX, "each was dropped and counted")
	TEST_ASSERT_NULL(Q.click_queue, "the drain empties the queue")

/// kernel_admit_lane() keys each shed lane's floor by name. A bare lane number indexed
/// floor_pass by position and runtimed the first time live shedding started.
/datum/unit_test/kernel_admit_lane_while_shedding

/datum/unit_test/kernel_admit_lane_while_shedding/Run()
	var/datum/kernel_latency/live = kernel_latency()
	set_var(live, "enabled", TRUE)
	set_var(live, "shedding", TRUE)
	set_var(live, "floor_pass", list())
	set_var(live, "shed_by_class", list(0, 0, 0, 0))
	TEST_ASSERT(kernel_admit_lane(LANE_PRESENTATION), "a shed lane's first pass is its floor")
	TEST_ASSERT(!kernel_admit_lane(LANE_PRESENTATION), "a second pass inside the floor is shed")
	TEST_ASSERT(kernel_admit_lane(LANE_BACKGROUND), "each lane has its own floor")
	TEST_ASSERT(kernel_admit_lane(LANE_SIMULATION), "a deferrable lane is never shed")
