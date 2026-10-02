/// The kernel's injected clock and the driver's kernel forms (code/tests/driver/kernel_clock.dm; doc/rewrite/final_api.html
/// section 19, E6): test_time() runs every(1 SECOND) work exactly once per second in the phase order K, S, N, D, P, R, G;
/// test_phase() moves no clock; a fixture system with needs, phase, roles and every() boots lazily and stays out of the live kernel.

/// The SYSTEM_DEF fixture of E6's gate: needs, phase, roles and every(), created on demand (lazy_only) so it never boots with
/// the live kernel.
/datum/system/e6_clock_fixture
	name = "e6 clock fixture"
	lazy_only = TRUE
	needs = list(/datum/system/mapping)
	phase = KERNEL_PHASE_P
	roles = list("load", "source")
	var/list/dts
	var/list/order

/datum/system/e6_clock_fixture/reactions()
	. = ..()
	. += every(1 SECOND, PROC_REF(tick))
	. += every(1 SECOND, PROC_REF(at_k), phase = KERNEL_PHASE_K)
	. += every(1 SECOND, PROC_REF(at_s), phase = KERNEL_PHASE_S)
	. += every(1 SECOND, PROC_REF(at_n), phase = KERNEL_PHASE_N)
	. += every(1 SECOND, PROC_REF(at_d), phase = KERNEL_PHASE_D)
	. += every(1 SECOND, PROC_REF(at_r), phase = KERNEL_PHASE_R)
	. += every(1 SECOND, PROC_REF(at_g), phase = KERNEL_PHASE_G)

/datum/system/e6_clock_fixture/proc/tick(dt)
	LAZYADD(dts, dt)
	LAZYADD(order, "P")

/datum/system/e6_clock_fixture/proc/at_k(dt)
	LAZYADD(order, "K")

/datum/system/e6_clock_fixture/proc/at_s(dt)
	LAZYADD(order, "S")

/datum/system/e6_clock_fixture/proc/at_n(dt)
	LAZYADD(order, "N")

/datum/system/e6_clock_fixture/proc/at_d(dt)
	LAZYADD(order, "D")

/datum/system/e6_clock_fixture/proc/at_r(dt)
	LAZYADD(order, "R")

/datum/system/e6_clock_fixture/proc/at_g(dt)
	LAZYADD(order, "G")

/// The fixture system is gone from the registry again: nothing that walks the systems after this test meets it.
/proc/e6_clock_fixture_forget()
	var/list/table = system_table()
	table -= /datum/system/e6_clock_fixture

/datum/unit_test/kernel_test_clock

/datum/unit_test/kernel_test_clock/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(e6_clock_fixture_forget))
	var/datum/system/e6_clock_fixture/S = system(/datum/system/e6_clock_fixture)
	TEST_ASSERT_NOTNULL(S, "a lazy_only system is created by system(path)")
	TEST_ASSERT(system_lazy_only(/datum/system/e6_clock_fixture), "the boot passes leave a lazy_only system to system(path)")
	kernel_boot_system(S)
	TEST_ASSERT(S.initialized, "kernel_boot_system initializes the fixture")
	var/datum/controller/kernel/K = kernel()

	// Declared in the system: needs and phase, in the final form's names.
	TEST_ASSERT(/datum/system/mapping in S.needs, "needs names the node it boots after")
	TEST_ASSERT_EQUAL(S.phase, KERNEL_PHASE_P, "phase is the system's default")

	// test_phase moves no clock: nothing is due yet at time 0.
	var/now_before = K.test_now
	test_phase(KERNEL_PHASE_P)
	TEST_ASSERT_EQUAL(K.test_now, now_before, "test_phase moves no clock")
	TEST_ASSERT_EQUAL(length(S.dts), 0, "an item that is not due stays pending")

	// test_time(5 SECONDS) runs every(1 SECOND) exactly five times, each with dt one second.
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(length(S.dts), 5, "every(1 SECOND) ran exactly five times in five seconds")
	for(var/dt in S.dts)
		TEST_ASSERT_EQUAL(dt, 1 SECOND, "each run's dt is the interval")
	TEST_ASSERT_EQUAL(K.test_now, 5 SECONDS, "the kernel clock moved by the time advanced")

	// The phase order inside one second: K, S, N, D, P, R, G.
	var/list/first_second = S.order.Copy(1, 8)
	TEST_ASSERT_EQUAL(jointext(first_second, ""), "KSNDPRG", "a slot runs the phases in order: [jointext(first_second, "")]")

	// A phase run on its own runs that phase's due items at the current time, and nothing else.
	var/count_before = length(S.order)
	test_time(1 SECOND)
	test_phase(KERNEL_PHASE_P) // already ran this second: not due again
	TEST_ASSERT_EQUAL(length(S.order) - count_before, 7, "one more second, one run of each phase item")

	// The injected clock does not leak: the live graph holds none of the fixture's items.
	for(var/datum/work_item/W as anything in K.work_all)
		if(W.owner_type == /datum/system/e6_clock_fixture)
			TEST_ASSERT(W.test_owned, "[W.key] was registered under the test clock and is test-owned")
	test_driver_end()
	TEST_ASSERT_NULL(K.test_now, "test_driver_end hands the clock back")

/datum/unit_test/kernel_test_clock_roles

/datum/unit_test/kernel_test_clock_roles/Run()
	defer_cleanup(null, GLOBAL_PROC_REF(e6_clock_fixture_forget))
	var/datum/system/e6_clock_fixture/S = system(/datum/system/e6_clock_fixture)
	var/datum/test_work_owner/member = allocate(/datum/test_work_owner)
	join(S, member, "e6", "load")
	TEST_ASSERT_EQUAL(length(members_of(S.type, "load")), 1, "a declared role indexes the member")
	leave(S, member, "e6", TRUE)
	var/crashed
	try
		join(S, member, "e6", "not_a_role")
	catch(var/exception/e)
		crashed = "[e.name]"
	TEST_ASSERT(crashed, "a role the system did not declare is refused")
	TEST_ASSERT(!member_is(S.type, member), "and the member did not join")

/// The recorder's store: rows carry their position and the kernel time they were reported at, a delta is kept only for a
/// named entity, and a record is bounded.
/datum/unit_test/kernel_test_recorder

/datum/unit_test/kernel_test_recorder/Run()
	test_driver_begin()
	var/datum/test_work_owner/named = allocate(/datum/test_work_owner)
	var/datum/test_work_owner/other = allocate(/datum/test_work_owner)
	TEST_ASSERT(!test_recording(), "nothing records before test_record()")
	test_record(named)
	TEST_ASSERT(test_recording(), "test_record() opens a record")
	TEST_REC_DELTA(named, "heat", 1, 2)
	TEST_REC_DELTA(other, "heat", 1, 2)
	test_time(3)
	TEST_REC_OUTCOME("e6.key", ACT_COMMITTED, null, other)
	var/list/rows = test_recorded()
	TEST_ASSERT(!test_recording(), "test_recorded() closes the record")
	TEST_ASSERT_EQUAL(length(rows), 2, "a delta of an entity nobody named is not kept, an outcome is")
	var/datum/test_event/first = rows[1]
	var/datum/test_event/second = rows[2]
	TEST_ASSERT_EQUAL(first.seq, 1, "rows are numbered in order")
	TEST_ASSERT_EQUAL(second.seq, 2, "rows are numbered in order")
	TEST_ASSERT_EQUAL(first.at, 0, "a row carries the kernel time it was reported at")
	TEST_ASSERT_EQUAL(second.at, 3, "a row after test_time(3) is at 3")
	TEST_ASSERT_EQUAL(first.role, 1, "the named entity is role 1")
	TEST_ASSERT_NULL(second.role, "an unnamed entity has no role")

	// Bounded: past TEST_RECORD_MAX rows the record counts what it refused.
	test_record(named)
	for(var/i in 1 to TEST_RECORD_MAX + 5)
		TEST_REC_DELTA(named, "heat", i, i + 1)
	TEST_ASSERT_EQUAL(test_recorded_dropped(), 5, "five rows past the cap are counted")
	TEST_ASSERT_EQUAL(length(test_recorded()), TEST_RECORD_MAX, "the record holds the cap")
	test_driver_end()
