// Lifecycle diagnostics (doc/rewrite/object_model_core.md, lifecycle section):
// a caught exception is reported, mutual ownership is detected, and the
// destroy postcondition names a cycle between deleted objects. Each check
// raises a runtime in normal use; these tests switch on the capture lists
// (GLOB.dq_caught_capture, GLOB.dq_lifecycle_report_capture) so they can look
// at the report without failing the run.

// ---- Fixtures ----

/// Two types that REF_OWN each other: the shape of the old overmap mob/marker bug.
/datum/dq_diag_owner_a
	var/datum/dq_diag_owner_b/b

/datum/dq_diag_owner_b
	var/datum/dq_diag_owner_a/a

// ALLOW(ownership_cycle): deliberate fixture for the runtime cycle check
REF_OWNED(/datum/dq_diag_owner_a, "b")
// ALLOW(ownership_cycle): deliberate fixture for the runtime cycle check
REF_OWNED(/datum/dq_diag_owner_b, "a")

/// A holder that deletes its members in Destroy() but keeps its list of them,
/// while each member keeps a reference back: after both are deleted, neither
/// can ever be freed (the reagent_by_id bug, synthetically).
/datum/dq_diag_leaker
	var/tmp/list/members

/datum/dq_diag_leaker/Destroy()
	for(var/datum/dq_diag_leaked/member as anything in members)
		qdel(member)
	// deliberately no `members = null`
	return ..()

/datum/dq_diag_leaked
	var/tmp/datum/dq_diag_leaker/holder

/datum/dq_diag_clean
	var/tmp/datum/dq_diag_leaked/other

/proc/dq_diag_sleep_then_throw()
	sleep(1)
	CRASH("dq_diag: thrown after sleeping")

/proc/dq_diag_capture_has(list/capture, text)
	for(var/line in capture)
		if(findtext(line, text))
			return TRUE
	return FALSE

// ---- Tests ----

/// dq_report_caught() reports (captured here instead of world/Error), the
/// scheduler's report_caught() goes through it, and the OM trampoline reports
/// a runtime raised after its callee slept instead of dropping it.
/datum/unit_test/dq_lifecycle_diag_catch_reports

/datum/unit_test/dq_lifecycle_diag_catch_reports/Run()
	GLOB.dq_caught_capture = list()
	try
		CRASH("dq_diag direct")
	catch(var/exception/e)
		dq_report_caught(e, "dq_diag direct catch")
	var/datum/om/scheduler/sched = om_scheduler()
	var/was_expecting = sched.expect_errors
	sched.expect_errors = FALSE
	try
		CRASH("dq_diag scheduler")
	catch(var/exception/e2)
		sched.report_caught(e2, "dq_diag scheduler catch")
	sched.expect_errors = was_expecting

	GLOB.om_expect_sleep = TRUE
	om_guarded_call(null, /proc/dq_diag_sleep_then_throw, list())
	GLOB.om_expect_sleep = FALSE
	for(var/i in 1 to 20)
		if(dq_diag_capture_has(GLOB.dq_caught_capture, "OM trampoline"))
			break
		sleep(world.tick_lag)
	var/list/capture = GLOB.dq_caught_capture
	GLOB.dq_caught_capture = null
	TEST_ASSERT(dq_diag_capture_has(capture, "dq_diag direct catch: dq_diag direct"), "dq_report_caught() reported the direct catch: [json_encode(capture)]")
	TEST_ASSERT(dq_diag_capture_has(capture, "dq_diag scheduler catch"), "scheduler report_caught() went through dq_report_caught(): [json_encode(capture)]")
	TEST_ASSERT(dq_diag_capture_has(capture, "OM trampoline (after sleep)"), "the trampoline reported a runtime raised after its callee slept: [json_encode(capture)]")

/// Two types that own each other: destroying one reports the cycle and does
/// not qdel either twice.
/datum/unit_test/dq_lifecycle_diag_mutual_ownership

/datum/unit_test/dq_lifecycle_diag_mutual_ownership/Run()
	GLOB.dq_lifecycle_report_capture = list()
	var/datum/dq_diag_owner_a/A = new
	var/datum/dq_diag_owner_b/B = new
	A.b = B
	B.a = A
	qdel(A)
	var/list/capture = GLOB.dq_lifecycle_report_capture
	GLOB.dq_lifecycle_report_capture = null
	TEST_ASSERT(QDELETED(A) && QDELETED(B), "both ends were deleted")
	TEST_ASSERT(dq_diag_capture_has(capture, "LIFECYCLE OWNERSHIP CYCLE: /datum/dq_diag_owner_a.b"), "the mutual ownership was reported: [json_encode(capture)]")
	TEST_ASSERT(isnull(A.b) && isnull(B.a), "both owned vars were cleared")

/// The postcondition names a var still holding a deleted object that holds
/// its holder back, and stays quiet for a clean object.
/datum/unit_test/dq_lifecycle_diag_leak_postcondition

/datum/unit_test/dq_lifecycle_diag_leak_postcondition/Run()
	var/old_level = GLOB.dq_lifecycle_leak_check
	GLOB.dq_lifecycle_leak_check = 1
	GLOB.dq_lifecycle_report_capture = list()

	var/datum/dq_diag_leaker/leaker = new
	var/datum/dq_diag_leaked/leaked = new
	leaked.holder = leaker
	leaker.members = list(leaked)
	qdel(leaker)

	var/datum/dq_diag_clean/clean = new
	var/datum/dq_diag_leaked/bystander = new
	clean.other = bystander // live, and holds nothing back: not a leak
	qdel(clean)

	var/list/capture = GLOB.dq_lifecycle_report_capture
	GLOB.dq_lifecycle_report_capture = null
	GLOB.dq_lifecycle_leak_check = old_level
	var/list/gc_lines = dq_lifecycle_leak_lines(leaker)

	// Break the cycle by hand so the fixtures themselves collect.
	leaker.members = null
	leaked.holder = null
	clean.other = null
	qdel(bystander)

	TEST_ASSERT(dq_diag_capture_has(capture, "LIFECYCLE LEAK: /datum/dq_diag_leaker.members still holds a list with deleted /datum/dq_diag_leaked"), "the leaker's list was reported: [json_encode(capture)]")
	TEST_ASSERT(dq_diag_capture_has(capture, "LIFECYCLE LEAK: /datum/dq_diag_leaked.holder still holds deleted /datum/dq_diag_leaker"), "the member's back reference was reported: [json_encode(capture)]")
	TEST_ASSERT(!dq_diag_capture_has(capture, "/datum/dq_diag_clean"), "a clean object is not reported: [json_encode(capture)]")
	TEST_ASSERT(length(gc_lines), "the GC report's line source finds the leak on the live deleted object")

// ---- INITIALIZE_HINT_QDEL ----

/// Refuses to exist the way a brainless AI core does: returns
/// INITIALIZE_HINT_QDEL before its own setup, so nothing Initialize() would
/// set up exists when it is destroyed. (Listed in build_list_of_uncreatables().)
/obj/item/dq_diag_init_refuser
	name = "init refuser"
	var/tmp/datum/dq_diag_clean/made_in_init
	var/fragile_destroy = FALSE
	latent_safe = FALSE

/obj/item/dq_diag_init_refuser/Initialize(mapload)
	..()
	return INITIALIZE_HINT_QDEL

/obj/item/dq_diag_init_refuser/Destroy()
	if(fragile_destroy)
		// Touches state Initialize() never built: a runtime mid-Destroy().
		made_in_init.other = null
	return ..()

/obj/item/dq_diag_init_refuser/fragile
	fragile_destroy = TRUE

/// An atom whose Initialize() returns INITIALIZE_HINT_QDEL leaves its turf and
/// is fully destroyed, even when its Destroy() runtimes on the state it never
/// set up; the runtime is reported instead of abandoning the transaction.
/datum/unit_test/dq_lifecycle_diag_init_qdel_leaves_loc

/datum/unit_test/dq_lifecycle_diag_init_qdel_leaves_loc/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/dq_diag_init_refuser/clean = new(T)
	TEST_ASSERT(QDELETED(clean), "an INITIALIZE_HINT_QDEL atom is deleted")
	TEST_ASSERT(isnull(clean.loc), "it left its turf")
	TEST_ASSERT(!(locate_within(T, /obj/item/dq_diag_init_refuser)), "nothing of it is left on the turf")

	GLOB.dq_caught_capture = list()
	var/obj/item/dq_diag_init_refuser/fragile/fragile = new(T)
	var/list/capture = GLOB.dq_caught_capture
	GLOB.dq_caught_capture = null
	TEST_ASSERT(QDELETED(fragile), "one whose Destroy() runtimes is still deleted")
	TEST_ASSERT(isnull(fragile.loc), "and still leaves its turf")
	TEST_ASSERT(fragile.gc_destroyed != GC_CURRENTLY_BEING_QDELETED, "and is handed to the GC, not left mid-destroy")
	TEST_ASSERT(dq_diag_capture_has(capture, "destroy transaction of /obj/item/dq_diag_init_refuser/fragile"), "the runtime in its Destroy() was reported: [json_encode(capture)]")
