// The inbox's limits (code/engine/kernel/inbox.dm): the hard cap and the rate limit refuse the newest input and say so, an input that waited past its max_wait is
// refused with a reason, a release whose press ran is never too late, a Topic never is, and the counters the metrics source reads move.

/// The acting mob: records what the player was told.
/mob/living/carbon/human/dq_limits_actor
	var/list/told
	var/list/mouse_seen

/mob/living/carbon/human/dq_limits_actor/op_notify(text)
	LAZYADD(told, text)

/mob/living/carbon/human/dq_limits_actor/input_client_mouse(kind, atom/target, atom/over, params)
	LAZYADD(mouse_seen, kind)

/datum/unit_test/dq_input_limits
	abstract_type = /datum/unit_test/dq_input_limits

/// A driven input of the actor's lane that cannot coalesce, resolving by writing its id into the log.
/datum/unit_test/dq_input_limits/proc/limits_probe(mob/user, id, rate_limited = TRUE)
	var/datum/input_event/probe/P = inbox_probe(id, user)
	P.actor = user
	P.rate_limited = rate_limited
	return P

/datum/unit_test/dq_input_limits/hard_cap

/datum/unit_test/dq_input_limits/hard_cap/Run()
	test_driver_begin()
	GLOB.inbox_probe_log = list()
	var/mob/living/carbon/human/dq_limits_actor/user = allocate(/mob/living/carbon/human/dq_limits_actor, dq_containment_floor())
	var/refused_before = SSinput.hard_refused
	input_force_room(FALSE)
	for(var/i in 1 to INPUT_CLIENT_HARD_MAX + 10)
		input_submit(limits_probe(user, "p[i]", FALSE))
	TEST_ASSERT_EQUAL(length(SSinput.waiting(user)), INPUT_CLIENT_HARD_MAX, "the inbox stops at its hard cap: no unbounded growth")
	TEST_ASSERT_EQUAL(SSinput.hard_refused - refused_before, 10, "every input past it is counted")
	TEST_ASSERT_EQUAL(length(user.told), 1, "the player is told once, not once per input")
	TEST_ASSERT(findtext(user.told[1], "faster than the server"), "and told why")
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(GLOB.inbox_probe_log[1], "p1", "the ones that waited are served, oldest first: the newest were the ones refused")
	input_force_room(null)
	test_driver_end()

/datum/unit_test/dq_input_limits/rate

/datum/unit_test/dq_input_limits/rate/Run()
	test_driver_begin()
	GLOB.inbox_probe_log = list()
	var/mob/living/carbon/human/dq_limits_actor/user = allocate(/mob/living/carbon/human/dq_limits_actor, dq_containment_floor())
	var/refused_before = SSinput.rate_refused
	input_force_room(TRUE)
	for(var/i in 1 to INPUT_CLIENT_RATE_MAX + 3)
		input_submit(limits_probe(user, "r[i]"))
	TEST_ASSERT_EQUAL(length(GLOB.inbox_probe_log), INPUT_CLIENT_RATE_MAX, "a client past its rate limit is refused, even inputs that would resolve on the spot")
	TEST_ASSERT_EQUAL(SSinput.rate_refused - refused_before, 3, "and each refusal counted")
	TEST_ASSERT_EQUAL(length(user.told), 1, "the player is told once")
	test_time(INPUT_RATE_WINDOW + 1)
	input_submit(limits_probe(user, "after"))
	TEST_ASSERT_EQUAL(GLOB.inbox_probe_log[length(GLOB.inbox_probe_log)], "after", "the next window starts clean")
	input_force_room(null)
	test_driver_end()

/datum/unit_test/dq_input_limits/expiry

/datum/unit_test/dq_input_limits/expiry/Run()
	test_driver_begin()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/dq_limits_actor/user = allocate(/mob/living/carbon/human/dq_limits_actor, T)
	var/obj/structure/dq_input_target/target = allocate(/obj/structure/dq_input_target, T)
	var/expired_before = SSinput.expired
	input_force_room(FALSE)

	var/datum/input_event/click/late = new(user, target, T, "mapwindow.map", "left=1")
	input_submit(late)
	late.arrived_clock -= INPUT_MAX_WAIT_CLICK + 1 SECONDS
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(SSinput.expired - expired_before, 1, "a click that waited past its limit expires")
	TEST_ASSERT_EQUAL(length(user.told), 1, "the player is told it was too late")
	TEST_ASSERT(findtext(user.told[1], "waited too long"), "with the reason")

	var/datum/input_event/click/hover/hovered = new(user, target, T, "mapwindow.map", "")
	input_submit(hovered)
	hovered.arrived_clock -= INPUT_MAX_WAIT_FEEDBACK + 1 SECONDS
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(SSinput.expired - expired_before, 2, "a late hover expires too")
	TEST_ASSERT_EQUAL(length(user.told), 1, "silently")

	var/datum/input_event/click/fresh = new(user, target, T, "mapwindow.map", "left=1")
	input_submit(fresh)
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(SSinput.expired - expired_before, 2, "a click served on time does not")
	input_force_room(null)
	test_driver_end()

/datum/unit_test/dq_input_limits/pairing

/datum/unit_test/dq_input_limits/pairing/Run()
	test_driver_begin()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/dq_limits_actor/user = allocate(/mob/living/carbon/human/dq_limits_actor, T)
	var/obj/structure/dq_input_target/target = allocate(/obj/structure/dq_input_target, T)
	var/expired_before = SSinput.expired
	input_force_room(TRUE)
	input_submit(new /datum/input_event/click/client_mouse(user, INPUT_MOUSE_DOWN, target, null, T, "mapwindow.map", "left=1"))
	TEST_ASSERT_EQUAL(jointext(user.mouse_seen, ","), INPUT_MOUSE_DOWN, "the press ran")
	input_force_room(FALSE)
	var/datum/input_event/click/client_mouse/release = new(user, INPUT_MOUSE_UP, target, null, T, "mapwindow.map", "left=1")
	input_submit(release)
	release.arrived_clock -= 10 SECONDS
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(jointext(user.mouse_seen, ","), "[INPUT_MOUSE_DOWN],[INPUT_MOUSE_UP]", "a release whose press ran is served however late")
	TEST_ASSERT_EQUAL(SSinput.expired, expired_before, "and is not expired")
	var/datum/input_event/click/client_mouse/orphan = new(user, INPUT_MOUSE_UP, target, null, T, "mapwindow.map", "left=1")
	input_submit(orphan)
	orphan.arrived_clock -= 10 SECONDS
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(length(user.mouse_seen), 2, "a release with no press behind it expires like any other input")
	TEST_ASSERT_EQUAL(SSinput.expired - expired_before, 1, "and is counted")
	input_force_room(null)
	test_driver_end()

/datum/unit_test/dq_input_limits/topic_never_expires

/datum/unit_test/dq_input_limits/topic_never_expires/Run()
	test_driver_begin()
	var/mob/living/carbon/human/dq_limits_actor/user = allocate(/mob/living/carbon/human/dq_limits_actor, dq_containment_floor())
	var/datum/holder = allocate(/datum)
	var/expired_before = SSinput.expired
	var/served_before = SSinput.resolved_queued
	input_force_room(FALSE)
	var/datum/input_event/topic/link = new(user, holder, "", list(), TRUE)
	input_submit(link)
	link.arrived_clock -= 1 HOURS
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(SSinput.resolved_queued - served_before, 1, "a Topic that waited an hour is still served")
	TEST_ASSERT_EQUAL(SSinput.expired, expired_before, "and never expires")
	var/list/stats = SSinput.metrics()
	TEST_ASSERT(!isnull(stats["hard_refused"]) && !isnull(stats["expired"]) && !isnull(stats["depth_p95"]), "the metrics report the counters and the depths")
	input_force_room(null)
	test_driver_end()
