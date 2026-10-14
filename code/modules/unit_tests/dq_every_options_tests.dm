// Falsifiable proofs for parts-form every() options; no live systems boot these fixtures.
/obj/every_options_probe
	var/active = FALSE
	var/list/order
	var/cap_ticks = 0

TRACKED(/obj/every_options_probe, active)

CAPABILITIES(/obj/every_options_probe)
	every(1 SECOND, then(PROC_REF(at_deadline)), when = nameof(active))
	every(1 SECOND, then(PROC_REF(at_presentation)), when = nameof(active), phase = KERNEL_PHASE_R, lane = LANE_PRESENTATION)
	every(1 SECOND, then(PROC_REF(at_work)), when = nameof(active), lane = LANE_SIMULATION)

/obj/every_options_probe/proc/at_deadline(datum/act/timer/A)
	LAZYADD(order, "D")

/obj/every_options_probe/proc/at_presentation(datum/act/timer/A)
	LAZYADD(order, "R")

/obj/every_options_probe/proc/at_work(datum/act/timer/A)
	LAZYADD(order, "P")

CAPABILITY_DEF(every_options_ticker, CAP_EVERY_OPTIONS_TICKER, key = NONE)

/datum/capability/def/every_options_ticker/entries()
	return list(every(1 SECOND, then(CAP_PROC(tick)), phase = KERNEL_PHASE_G, lane = LANE_BACKGROUND))

/datum/capability/def/every_options_ticker/proc/tick(datum/act/timer/A)
	var/obj/every_options_probe/P = A.holder
	P.cap_ticks++

/datum/system/every_options_members
	abstract_type = /datum/system/every_options_members
	lazy_only = TRUE
	var/list/seen
	var/last_dt

CAPABILITIES(/datum/system/every_options_members)
	every(1 SECOND, then(PROC_REF(visit)), members = /datum/system/every_options_members, phase = KERNEL_PHASE_P, lane = LANE_SIMULATION)

/datum/system/every_options_members/proc/visit(datum/act/timer/A)
	LAZYADD(seen, A.target)
	last_dt = A.dt

/datum/unit_test/dq_every_options
	abstract_type = /datum/unit_test/dq_every_options

/datum/unit_test/dq_every_options/Run()
	test_driver_begin()
	run_options()
	test_driver_end()

/datum/unit_test/dq_every_options/proc/run_options()
	return

/datum/unit_test/dq_every_options/phase_lane_and_parking

/datum/unit_test/dq_every_options/phase_lane_and_parking/run_options()
	var/obj/every_options_probe/P = allocate(/obj/every_options_probe)
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(P.order, "Tracked false gates park every periodic entry")
	P.set_active(TRUE)
	test_drain()
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(jointext(P.order, ","), "D,P,R", "Default deadline and explicit work/presentation phases deliver in kernel order")
	var/list/entries = compiled_entries(table_of(P), ENTRY_EVERY)
	var/datum/centry/C = entries[2]
	var/datum/work_item/every_dispatch/W = every_dispatch_item(C.item)
	TEST_ASSERT_EQUAL(W.phase, KERNEL_PHASE_R, "The explicit phase reaches the scheduler")
	TEST_ASSERT_EQUAL(W.lane, LANE_PRESENTATION, "The explicit lane pays for the scheduled work")
	P.set_active(FALSE)
	test_drain()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(length(P.order), 3, "Parking prevents further handler deliveries")
	P.set_active(TRUE)
	test_drain()
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(length(P.order), 6, "Waking re-arms each parked entry exactly once")

/datum/unit_test/dq_every_options/revoke_ready_activation

/datum/unit_test/dq_every_options/revoke_ready_activation/run_options()
	var/obj/every_options_probe/P = allocate(/obj/every_options_probe)
	var/datum/activation/A = grant(P, every_options_ticker(), source = src)
	TEST_ASSERT_NOTNULL(A, "Grant creates a live periodic activation")
	var/list/entries = A.def.entries()
	var/datum/entry/E = entries[1]
	activation_every_fire(A, E)
	var/datum/work_item/every_dispatch/W = every_dispatch_item(E)
	TEST_ASSERT_EQUAL(length(W.pending), 1, "The ready activation has an actual captured delivery queued")
	TEST_ASSERT_EQUAL(W.phase, KERNEL_PHASE_G, "Capability periodic work honors its requested phase")
	TEST_ASSERT_EQUAL(W.lane, LANE_BACKGROUND, "Capability periodic work honors its requested lane")
	TEST_ASSERT_EQUAL(P.cap_ticks, 0, "Explicit-phase work stays queued before that phase")
	revoke(P, every_options_ticker(), source = src)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(P.cap_ticks, 0, "Revoking a ready activation cancels its queued delivery as well as its timer")

/datum/unit_test/dq_every_options/system_members

/datum/unit_test/dq_every_options/system_members/run_options()
	var/datum/system/every_options_members/S = allocate(/datum/system/every_options_members)
	var/obj/first = allocate(/obj)
	var/obj/second = allocate(/obj)
	join(/datum/system/every_options_members, first, src)
	join(/datum/system/every_options_members, second, src)
	type_every_arm(S, table_of(S))
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(length(S.seen), 2, "The system runs once for each current member")
	TEST_ASSERT((first in S.seen) && (second in S.seen), "A.target contains the actual member, not the system")
	TEST_ASSERT_EQUAL(S.last_dt, 1 SECOND, "Member contexts retain the periodic interval")
	leave(/datum/system/every_options_members, first, src)
	S.seen = null
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(length(S.seen), 1, "A departed member does not receive the next run")
	TEST_ASSERT_EQUAL(S.seen[1], second, "Only the remaining member is delivered")
	leave(/datum/system/every_options_members, second, src)

/datum/unit_test/dq_every_options/member_sweep_yields_and_rechecks

/datum/unit_test/dq_every_options/member_sweep_yields_and_rechecks/run_options()
	var/datum/system/every_options_members/S = allocate(/datum/system/every_options_members)
	var/obj/first = allocate(/obj)
	var/obj/departing = allocate(/obj)
	var/obj/deleted = allocate(/obj)
	var/obj/late_join = allocate(/obj)
	join(/datum/system/every_options_members, first, src)
	join(/datum/system/every_options_members, departing, src)
	join(/datum/system/every_options_members, deleted, src)
	var/list/entries = compiled_entries(table_of(S), ENTRY_EVERY)
	var/datum/centry/C = entries[1]
	cancel_after(S, "every:type:1")
	type_every_fire(S, C, 1, TRUE)
	var/datum/work_item/every_dispatch/W = every_dispatch_item(C.item)
	TEST_ASSERT_EQUAL(length(W.pending), 1, "One actual member continuation begins the sweep")
	var/saved_limit = Kernel.current_ticklimit
	Kernel.current_ticklimit = -1
	var/result = W.perform(W, null, 0)
	Kernel.current_ticklimit = saved_limit
	TEST_ASSERT_EQUAL(result, STEP_YIELD, "Exhausting the work share yields with a saved continuation")
	TEST_ASSERT_EQUAL(length(S.seen), 1, "The yielded slice visits exactly one member")
	TEST_ASSERT_EQUAL(S.seen[1], first, "The first snapshot member receives the context")
	TEST_ASSERT(!after_pending(S, "every:type:1"), "An outstanding sweep has no periodic timer backlog")
	leave(/datum/system/every_options_members, departing, src)
	qdel(deleted)
	join(/datum/system/every_options_members, late_join, src)
	Kernel.current_ticklimit = INFINITY
	result = W.perform(W, null, 0)
	Kernel.current_ticklimit = saved_limit
	TEST_ASSERT_EQUAL(result, STEP_PARK, "Finishing the saved snapshot parks the empty dispatcher")
	TEST_ASSERT_EQUAL(length(S.seen), 1, "Departed/deleted snapshot members and late joins do not receive this sweep")
	TEST_ASSERT(after_pending(S, "every:type:1"), "Completing the sweep arms exactly the next interval")
	S.seen = null
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(length(S.seen), 2, "The next interval takes a fresh snapshot")
	TEST_ASSERT((first in S.seen) && (late_join in S.seen), "The newly joined member participates on the next interval")
	leave(/datum/system/every_options_members, first, src)
	leave(/datum/system/every_options_members, late_join, src)

CAPABILITY_DEF(every_options_member_ticker, CAP_EVERY_OPTIONS_MEMBER_TICKER, key = NONE)

/datum/capability/def/every_options_member_ticker/entries()
	return list(every(1 SECOND, then(CAP_PROC(visit)), members = /datum/system/every_options_members, phase = KERNEL_PHASE_P, lane = LANE_SIMULATION))

/datum/capability/def/every_options_member_ticker/proc/visit(datum/act/timer/A)
	var/datum/system/every_options_members/S = A.holder
	LAZYADD(S.seen, A.target)

/datum/unit_test/dq_every_options/revoke_member_sweep_continuation

/datum/unit_test/dq_every_options/revoke_member_sweep_continuation/run_options()
	var/datum/system/every_options_members/S = allocate(/datum/system/every_options_members)
	var/obj/first = allocate(/obj)
	var/obj/second = allocate(/obj)
	join(/datum/system/every_options_members, first, src)
	join(/datum/system/every_options_members, second, src)
	cancel_after(S, "every:type:1")
	var/datum/activation/A = grant(S, every_options_member_ticker(), source = src)
	TEST_ASSERT_NOTNULL(A, "The system owns a live member-sweep activation")
	var/list/entries = A.def.entries()
	var/datum/entry/E = entries[1]
	var/timer_key = activation_every_key(A, E)
	cancel_after(S, timer_key)
	activation_every_fire(A, E, TRUE)
	var/datum/work_item/every_dispatch/W = every_dispatch_item(E)
	var/saved_limit = Kernel.current_ticklimit
	Kernel.current_ticklimit = -1
	var/result = W.perform(W, null, 0)
	Kernel.current_ticklimit = saved_limit
	TEST_ASSERT_EQUAL(result, STEP_YIELD, "The live activation reaches a real yielded member continuation")
	TEST_ASSERT_EQUAL(length(S.seen), 1, "One member runs before revocation")
	revoke(S, every_options_member_ticker(), source = src)
	W.perform(W, null, 0)
	TEST_ASSERT_EQUAL(length(S.seen), 1, "Revocation prevents the next member from running")
	TEST_ASSERT_NULL(W.pending, "The revoked continuation is discarded")
	TEST_ASSERT(!after_pending(S, timer_key), "A revoked sweep never re-arms its timer")
	leave(/datum/system/every_options_members, first, src)
	leave(/datum/system/every_options_members, second, src)
