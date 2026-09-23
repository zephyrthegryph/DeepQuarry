// Unit tests for the clock core (doc/medical_frameworks.md §1.12, K1): speed changes, parking at
// speed 0, composition, rebinding, cancellation on deletion, nested holders, split invariance
// of every clocked type, the reactor path, life_wake_in() on clocks, and PROB_OVER.
//
// Most tests pin the clocks' world time with GLOB.clock_time_override and call fire_due()
// directly, so the arithmetic is checked exactly and without waiting. One test goes through
// the real REACT_AT path.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Records clock events it receives.
/datum/clock_test_recorder
	var/list/fired = list()

/datum/clock_test_recorder/proc/on_clock(arg)
	fired += isnull(arg) ? "fired" : arg

/// A clocked probe: `decay` grows linearly at `rate` per clock second, and `charge` halves
/// every `half_life` clock seconds (closed forms, so any split of an interval is exact).
/// A threshold event fires when `decay` reaches `threshold`.
/obj/clock_test_probe
	name = "clock test probe"
	clocked = TRUE
	var/decay = 0
	var/rate = 1
	var/charge = 100
	var/half_life = 50
	var/threshold = 0
	var/threshold_hits = 0

/obj/clock_test_probe/on_settle(seconds)
	decay += rate * seconds
	charge *= 0.5 ** (seconds / half_life)

/obj/clock_test_probe/clock_next_threshold()
	if(threshold > decay && rate > 0)
		clock_schedule_in((threshold - decay) / rate, PROC_REF(threshold_reached))

/obj/clock_test_probe/proc/threshold_reached()
	clock_settle()
	threshold_hits++

/// A holder that provides a clock.
/obj/clock_test_holder
	name = "clock test holder"
	clock_speed = 0.1

/// A holder that provides no clock (a bag, a head).
/obj/clock_test_plain
	name = "clock test bag"

/// Base: pins clock time; subtypes move it with advance().
/datum/unit_test/dq_clock
	abstract_type = /datum/unit_test/dq_clock

/// Pins clock time at the current world time. Every Run() starts with it.
/datum/unit_test/dq_clock/proc/pin()
	GLOB.clock_time_override = world.time

/datum/unit_test/dq_clock/Destroy()
	GLOB.clock_time_override = null
	return ..()

/datum/unit_test/dq_clock/proc/advance(seconds)
	GLOB.clock_time_override += seconds SECONDS

/datum/unit_test/dq_clock/proc/fire(datum/clock/C)
	return C.fire_due()

/// An event at clock +100 s fires at world +100 s at speed 1; halving the speed at +50 s moves
/// it to world +150 s; at speed 0 it never fires and the clock holds no reactor token.
/datum/unit_test/dq_clock/speed_change

/datum/unit_test/dq_clock/speed_change/Run()
	pin()
	var/datum/clock/C = allocate(/datum/clock, CLOCK_KIND_HOLDER, 1)
	var/datum/clock_test_recorder/R = allocate(/datum/clock_test_recorder)
	var/start = GLOB.clock_time_override
	var/datum/clock_event/E = C.schedule_in(R, 100, TYPE_PROC_REF(/datum/clock_test_recorder, on_clock), "a")
	TEST_ASSERT_EQUAL(C.world_time_of(E.at_clock), start + 100 SECONDS, "at speed 1 the event maps to world +100 s")
	TEST_ASSERT(C.react_token, "a pending event arms one reactor token")
	advance(50)
	fire(C)
	TEST_ASSERT_EQUAL(length(R.fired), 0, "nothing is due at +50 s")
	C.set_own_speed(0.5, "test")
	TEST_ASSERT_EQUAL(C.world_time_of(E.at_clock), start + 150 SECONDS, "halving the speed at +50 s moves the event to world +150 s")
	advance(99)
	fire(C)
	TEST_ASSERT_EQUAL(length(R.fired), 0, "not due at world +149 s")
	advance(1)
	fire(C)
	TEST_ASSERT_EQUAL(length(R.fired), 1, "due at world +150 s")
	TEST_ASSERT(!E.clock, "a fired handle is dead")
	TEST_ASSERT(!C.cancel(E), "a stale handle cancels nothing")

	// Speed 0 parks.
	C.schedule_in(R, 10, TYPE_PROC_REF(/datum/clock_test_recorder, on_clock), "b")
	C.set_own_speed(CLOCK_SPEED_STOPPED, "test")
	TEST_ASSERT(!C.react_token, "a stopped clock holds no reactor token")
	TEST_ASSERT_NULL(C.world_time_of(C.now() + 1), "a stopped clock maps nothing to world time")
	advance(1000)
	fire(C)
	TEST_ASSERT_EQUAL(length(R.fired), 1, "a stopped clock never fires")
	C.set_own_speed(1, "test")
	TEST_ASSERT(C.react_token, "restarting rearms the parked event")
	advance(10)
	fire(C)
	TEST_ASSERT_EQUAL(length(R.fired), 2, "the parked event fires once time runs again")

/// Events fire in clock-time order, a handler may schedule more, and cancel is exact.
/datum/unit_test/dq_clock/ordering_and_cancel

/datum/unit_test/dq_clock/ordering_and_cancel/Run()
	pin()
	var/datum/clock/C = allocate(/datum/clock, CLOCK_KIND_HOLDER, 1)
	var/datum/clock_test_recorder/R = allocate(/datum/clock_test_recorder)
	var/on_clock = TYPE_PROC_REF(/datum/clock_test_recorder, on_clock)
	C.schedule_in(R, 30, on_clock, "third")
	C.schedule_in(R, 10, on_clock, "first")
	var/datum/clock_event/doomed = C.schedule_in(R, 15, on_clock, "cancelled")
	C.schedule_in(R, 20, on_clock, "second")
	TEST_ASSERT(C.cancel(doomed), "cancelling a pending event")
	TEST_ASSERT(!C.cancel(doomed), "cancelling twice")
	advance(40)
	fire(C)
	TEST_ASSERT_EQUAL(R.fired.Join(","), "first,second,third", "events fire in clock order; the cancelled one never")
	C.schedule_in(R, 5, on_clock, "x")
	C.cancel_all(R)
	TEST_ASSERT_EQUAL(LAZYLEN(C.events), 0, "cancel_all drops every event for the target")
	TEST_ASSERT(!C.react_token, "no pending events, no token")

/// A holder in a holder composes its speed; a speed change on the outer one moves the inner
/// one's pending event. A brain in a head in a bag in a freezer uses the freezer's clock (the
/// regression test for the one-level `preserved` bug).
/datum/unit_test/dq_clock/composition

/datum/unit_test/dq_clock/composition/Run()
	pin()
	var/obj/clock_test_holder/freezer = allocate(/obj/clock_test_holder)
	var/obj/clock_test_holder/cryobag = allocate(/obj/clock_test_holder, freezer)
	cryobag.clock_speed = 0.01
	var/obj/clock_test_probe/in_bag = allocate(/obj/clock_test_probe, cryobag)
	var/datum/clock/bag_clock = in_bag.holder_clock()
	TEST_ASSERT_EQUAL(bag_clock, cryobag.own_clock, "the probe resolves the cryobag's clock")
	TEST_ASSERT_EQUAL(bag_clock.parent, freezer.own_clock, "the cryobag's clock composes on the freezer's")
	TEST_ASSERT(abs(bag_clock.speed - 0.001) < 1e-9, "composed speed is the product ([bag_clock.speed])")

	in_bag.clock_bind()
	var/start = GLOB.clock_time_override
	var/datum/clock_event/E = in_bag.clock_schedule_in(1, TYPE_PROC_REF(/obj/clock_test_probe, threshold_reached))
	TEST_ASSERT(abs(bag_clock.world_time_of(E.at_clock) - (start + 1000 SECONDS)) < 0.01, "1 clock second at 0.001 is 1000 world seconds")
	advance(100)
	freezer.set_clock_speed(0.2, "test")
	TEST_ASSERT(abs(bag_clock.speed - 0.002) < 1e-9, "the freezer's speed change recomposes the bag's clock")
	// 0.1 clock s elapsed; 0.9 left at 0.002/s = 450 s after the change.
	TEST_ASSERT(abs(bag_clock.world_time_of(E.at_clock) - (start + 550 SECONDS)) < 0.01, "the pending event moved with the freezer's speed")

	// Nested preservation: freezer > bag > head > brain.
	var/obj/clock_test_plain/bag = allocate(/obj/clock_test_plain, freezer)
	var/obj/clock_test_plain/head = allocate(/obj/clock_test_plain, bag)
	var/obj/clock_test_probe/brain = allocate(/obj/clock_test_probe, head)
	TEST_ASSERT_EQUAL(brain.holder_clock(), freezer.own_clock, "a brain in a head in a bag in a freezer uses the freezer's clock")
	brain.clock_settle()
	advance(100)
	brain.clock_settle()
	TEST_ASSERT(abs(brain.decay - 100 * 0.2) < 1e-6, "it rots at the freezer's speed ([brain.decay])")

/// An object moved from a slow holder to the floor settles at the slow speed up to the move
/// and at world speed after it; its pending event keeps its remaining clock seconds.
/datum/unit_test/dq_clock/rebind

/datum/unit_test/dq_clock/rebind/Run()
	pin()
	var/obj/clock_test_holder/holder = allocate(/obj/clock_test_holder)
	var/obj/clock_test_probe/P = allocate(/obj/clock_test_probe, holder)
	P.threshold = 30
	P.clock_bind()
	TEST_ASSERT_EQUAL(P.bound_clock, holder.own_clock, "bound to the holder's clock")
	TEST_ASSERT(P.clock_handles, "binding scheduled the threshold")
	advance(100)
	P.forceMove(holder.loc)
	P.clock_on_moved() // The J5 move hook's clock side.
	TEST_ASSERT_EQUAL(P.bound_clock, GLOB.world_clock, "on the floor it runs on the world clock")
	TEST_ASSERT(abs(P.decay - 10) < 1e-6, "settled at 0.1 up to the move ([P.decay])")
	var/datum/clock_event/E = P.clock_handles
	TEST_ASSERT(istype(E) && E.clock == GLOB.world_clock, "the threshold event moved with it")
	TEST_ASSERT(abs(E.at_clock - GLOB.world_clock.now() - 20) < 1e-6, "with its remaining 20 clock seconds")
	advance(100)
	P.clock_settle()
	TEST_ASSERT(abs(P.decay - 110) < 1e-6, "and at 1 after it ([P.decay])")
	P.clock_cancel(E)
	TEST_ASSERT_NULL(P.clock_handles, "cancel prunes the handle")

/// A deleted target's events never fire. A deleted holder's objects rebind to the parent
/// clock without losing events, and nothing keeps a reference to the dead clock.
/datum/unit_test/dq_clock/deletion

/datum/unit_test/dq_clock/deletion/Run()
	pin()
	var/datum/clock/C = allocate(/datum/clock, CLOCK_KIND_HOLDER, 1)
	var/datum/clock_test_recorder/R = new
	C.schedule_in(R, 5, TYPE_PROC_REF(/datum/clock_test_recorder, on_clock))
	TEST_ASSERT(C in R.clock_ties, "the target is tied to the clock")
	qdel(R)
	TEST_ASSERT_EQUAL(LAZYLEN(C.events), 0, "clock_teardown() cancelled the deleted target's event")
	TEST_ASSERT(!(R in C.tied), "and dropped the tie")
	advance(10)
	TEST_ASSERT_EQUAL(fire(C), 0, "nothing fires for a deleted target")

	// A holder that stops providing a clock: its contents rebind to the parent clock and keep
	// their events.
	var/obj/clock_test_holder/outer = allocate(/obj/clock_test_holder)
	outer.clock_speed = 0.5
	var/obj/clock_test_holder/inner = allocate(/obj/clock_test_holder, outer)
	var/obj/clock_test_probe/P = allocate(/obj/clock_test_probe, inner)
	P.threshold = 10
	P.clock_bind()
	var/datum/clock/dead = inner.own_clock
	advance(20) // 20 * 0.05 = 1 clock second
	inner.set_clock_speed(null, "test")
	TEST_ASSERT(QDELETED(dead), "the holder's clock was deleted")
	TEST_ASSERT_EQUAL(P.bound_clock, outer.own_clock, "the probe rebound to the parent clock")
	TEST_ASSERT(!(dead in P.clock_ties), "no tie to the dead clock remains")
	var/datum/clock_event/E = P.clock_handles
	TEST_ASSERT(istype(E) && abs(E.at_clock - outer.own_clock.now() - 9) < 1e-6, "its threshold kept 9 clock seconds")
	TEST_ASSERT(abs(P.decay - 1) < 1e-6, "it settled at the dead clock before rebinding ([P.decay])")
	advance(18)
	TEST_ASSERT_EQUAL(fire(outer.own_clock), 1, "the moved threshold fires on the parent clock")
	TEST_ASSERT_EQUAL(P.threshold_hits, 1, "the probe saw its threshold")
	TEST_ASSERT(abs(P.decay - 10) < 1e-6, "at the threshold level ([P.decay])")

	// A deleted provider deletes its clock, and nothing keeps it.
	var/obj/clock_test_holder/gone = new(run_loc_floor_bottom_left)
	var/datum/clock/gone_clock = gone.provided_clock()
	qdel(gone)
	TEST_ASSERT(QDELETED(gone_clock), "deleting the provider deleted its clock")
	TEST_ASSERT(!(gone_clock in GLOB.world_clock.children), "and unhooked it from its parent")

/// Split invariance: settling N times over T gives the same state as settling once over T, for
/// every clocked type (generated over `clocked` types).
/datum/unit_test/dq_clock/split_invariance

/datum/unit_test/dq_clock/split_invariance/Run()
	pin()
	var/checked = 0
	for(var/path in subtypesof(/obj))
		var/obj/prototype = path
		if(!initial(prototype.clocked))
			continue
		checked++
		var/obj/clock_test_holder/holder = allocate(/obj/clock_test_holder)
		var/obj/split = allocate(path, holder)
		var/obj/once = allocate(path, holder)
		split.clock_bind()
		once.clock_bind()
		for(var/i in 1 to 10)
			advance(7)
			split.clock_settle()
		once.clock_settle()
		for(var/name in split.vars)
			var/a = split.vars[name]
			if(!isnum(a) || name == "clock_settled_at")
				continue
			var/b = once.vars[name]
			TEST_ASSERT(abs(a - b) <= max(abs(b), 1) * 1e-5, "[path]: [name] is [a] settled in ten steps but [b] settled once")
		qdel(split)
		qdel(once)
	TEST_ASSERT(checked > 0, "no clocked types found")

/// life_wake_in(): a world-kind wake rides the world clock; a body-kind wake rides the mob's
/// body clock (its holder clock until K2), so a slow holder stretches it. One wake per kind,
/// earliest wins, and clearing the life systems cancels both.
/datum/unit_test/dq_clock/life_wake_in

/datum/unit_test/dq_clock/life_wake_in/Run()
	pin()
	var/obj/clock_test_holder/holder = allocate(/obj/clock_test_holder)
	holder.clock_speed = 0.5
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, holder)
	H.life_wake_in(LIFE_SYS_BODY, 10 SECONDS)
	H.life_wake_in(LIFE_SYS_HUD, 20 SECONDS)
	TEST_ASSERT_EQUAL(H.life_timed_wake_bits(CLOCK_KIND_WORLD), LIFE_SYS_BODY | LIFE_SYS_HUD, "a later world wake rides the earlier one")
	var/datum/life_timed_wake/W = H.life_timed_wakes[CLOCK_KIND_WORLD]
	TEST_ASSERT_EQUAL(W.clock, GLOB.world_clock, "world kind is on the world clock")
	H.life_wake_in(LIFE_SYS_BODY, 10 SECONDS, CLOCK_KIND_BODY)
	var/datum/life_timed_wake/B = H.life_timed_wakes[CLOCK_KIND_BODY]
	TEST_ASSERT_EQUAL(B.clock, holder.own_clock, "body kind is on the mob's body clock (its holder's until K2)")
	TEST_ASSERT(abs(B.clock.world_time_of(B.at) - (GLOB.clock_time_override + 20 SECONDS)) < 0.01, "a half-speed clock stretches a 10 s body wake to 20 s")
	H.life_awake &= ~LIFE_SYS_BODY
	advance(10)
	// Fire only this mob's wake (firing the whole world clock would run other mobs' wakes).
	TEST_ASSERT(W.at <= GLOB.world_clock.now(), "the world wake is due at 10 s")
	H.life_timed_wake_fired(CLOCK_KIND_WORLD)
	TEST_ASSERT(H.life_awake & LIFE_SYS_BODY, "the world wake woke its systems")
	TEST_ASSERT_EQUAL(H.life_timed_wake_bits(CLOCK_KIND_WORLD), NONE, "and is spent")
	TEST_ASSERT_EQUAL(H.life_timed_wake_bits(CLOCK_KIND_BODY), LIFE_SYS_BODY, "the body wake is still pending at 10 s")
	H.clear_life_systems()
	TEST_ASSERT_EQUAL(H.life_timed_wake_bits(CLOCK_KIND_BODY), NONE, "clearing the life systems cancels the body wake")
	TEST_ASSERT_EQUAL(LAZYLEN(holder.own_clock.events), 0, "and leaves nothing on the clock")

/// PROB_OVER turns a per-nominal-cycle chance into a chance over any interval.
/datum/unit_test/dq_clock_prob_over

/datum/unit_test/dq_clock_prob_over/Run()
	TEST_ASSERT(abs(PROB_OVER(10, LIFE_NOMINAL_SECONDS) - 10) < 1e-6, "one nominal cycle is the nominal chance")
	TEST_ASSERT(abs(PROB_OVER(10, 2 * LIFE_NOMINAL_SECONDS) - 19) < 1e-6, "two cycles compound (1 - 0.9^2)")
	TEST_ASSERT_EQUAL(PROB_OVER(10, 0), 0, "no time, no chance")

/// The real path: a world-clock event fires through the clock's REACT_AT.
/datum/unit_test/dq_clock_reactor_path

/datum/unit_test/dq_clock_reactor_path/Run()
	var/datum/clock_test_recorder/R = allocate(/datum/clock_test_recorder)
	var/datum/clock/C = allocate(/datum/clock, CLOCK_KIND_HOLDER, 2)
	C.schedule_in(R, 0.4, TYPE_PROC_REF(/datum/clock_test_recorder, on_clock), "reactor")
	TEST_ASSERT(C.react_token, "the clock armed a REACT_AT")
	sleep(0.1 SECONDS)
	TEST_ASSERT_EQUAL(length(R.fired), 0, "not before 0.2 world seconds")
	sleep(1 SECONDS)
	TEST_ASSERT_EQUAL(R.fired.Join(","), "reactor", "fired through the reactor")
	TEST_ASSERT(!C.react_token, "and the clock dropped its spent token")

#endif
