// Explicit read-once admission is sampled again on each menu read, without invalidating tracked-only caches.
MSG_DEF_SELF(read_once_probe/unavailable, "probe is unavailable")

/obj/read_once_menu_probe
	var/admitted = FALSE
	var/fail = FALSE
	var/effects = 0

CAPABILITIES(/obj/read_once_menu_probe)
	op("sample", menu(), label("Sample"), needs(req_bool(PROC_REF(allow_sample), because = MSG(read_once_probe/unavailable))), then(PROC_REF(record_sample)))
	op("conditional", menu(), label("Conditional"), when(PROC_REF(allow_sample)), then(PROC_REF(record_sample)))

/obj/read_once_menu_probe/proc/allow_sample(datum/act/op/A)
	var/answer = admission_helper()
	if(read_once(fail))
		throw EXCEPTION("Expected read_once menu probe")
	return answer

/obj/read_once_menu_probe/proc/record_sample(datum/act/op/A)
	effects++
	return OP_OK

/obj/read_once_menu_probe/proc/admission_helper()
	return read_once(admitted)

/obj/read_once_tracked_menu_probe
	var/admitted = FALSE
TRACKED(/obj/read_once_tracked_menu_probe, admitted)
CAPABILITIES(/obj/read_once_tracked_menu_probe)
	op("sample", menu(), label("Sample"), needs(req_is(nameof(admitted), TRUE, because = MSG(read_once_probe/unavailable))), then(TYPE_PROC_REF(/atom, op_swallow)))

/datum/unit_test/read_once_menu_contract
	abstract_type = /datum/unit_test/read_once_menu_contract

/datum/unit_test/read_once_menu_contract/New()
	..()
	dview(0, test_floor())

/datum/unit_test/read_once_menu_contract/Run()
	test_driver_begin()
	set_global(nameof(GLOB.op_menu_builds), GLOB.op_menu_builds)
	try
		run_gate()
	catch(var/exception/fault)
		test_driver_end()
		throw fault
	test_driver_end()

/datum/unit_test/read_once_menu_contract/proc/run_gate()
	return

/datum/unit_test/read_once_menu_contract/proc/find_row(list/rows, key)
	for(var/list/row as anything in rows)
		if(row["key"] == key)
			return row
	return null

/datum/unit_test/read_once_menu_contract/visibility
/datum/unit_test/read_once_menu_contract/visibility/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/read_once_menu_probe/P = allocate(/obj/read_once_menu_probe)
	var/time_before = op_now()
	var/actor_gen = rx_of(H).act_gen
	var/probe_gen = rx_of(P).act_gen
	var/list/first = op_menu(H, P, null)
	var/list/disabled = find_row(first, "sample")
	TEST_ASSERT_NOTNULL(disabled, "The requirement row is offered when admission fails")
	TEST_ASSERT(!disabled["enabled"], "The real requirement disables the offered row")
	TEST_ASSERT_EQUAL(disabled["reason"], "probe is unavailable", "The requirement keeps its actual refusal")
	TEST_ASSERT_NULL(find_row(first, "conditional"), "The false condition hides its row")
	P.admitted = TRUE // intentionally no publication: explicit read_once input
	var/list/second = op_menu(H, P, null)
	var/list/enabled = find_row(second, "sample")
	TEST_ASSERT(enabled && enabled["enabled"], "Same-tick admission changes enable the requirement row")
	TEST_ASSERT_NOTNULL(find_row(second, "conditional"), "Same-tick admission changes expose the condition row")
	TEST_ASSERT_EQUAL(op_now(), time_before, "No passage of time repairs the menu")
	TEST_ASSERT_EQUAL(rx_of(H).act_gen, actor_gen, "The actor generation did not repair the menu")
	TEST_ASSERT_EQUAL(rx_of(P).act_gen, probe_gen, "The target generation did not repair the menu")
	var/datum/op_result/accepted = op_perform_by_key(H, P, null, "sample", ORIGIN_MENU, actor_authority(H), FALSE)
	TEST_ASSERT_EQUAL(accepted?.outcome, ACT_COMMITTED, "The public named menu operation accepts current admission")
	TEST_ASSERT_EQUAL(P.effects, 1, "Positive admission runs the actual effect once")
	P.admitted = FALSE
	var/datum/op_result/refused = op_perform_by_key(H, P, null, "sample", ORIGIN_MENU, actor_authority(H), FALSE)
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "The public named operation rechecks current failed admission")
	TEST_ASSERT_EQUAL(P.effects, 1, "Negative admission cannot run the actual effect")
	var/list/third = op_menu(H, P, null)
	TEST_ASSERT(!find_row(third, "sample")?["enabled"], "A subsequent current admission failure disables the row again")
	TEST_ASSERT_NULL(find_row(third, "conditional"), "A subsequent false condition hides the row again")

/datum/unit_test/read_once_menu_contract/tracked_cache
/datum/unit_test/read_once_menu_contract/tracked_cache/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/read_once_tracked_menu_probe/P = allocate(/obj/read_once_tracked_menu_probe)
	var/list/first = op_menu(H, P, null)
	var/builds_after_first = GLOB.op_menu_builds
	TEST_ASSERT(!find_row(first, "sample")?["enabled"], "Tracked FALSE really disables the row")
	op_menu(H, P, null)
	TEST_ASSERT_EQUAL(GLOB.op_menu_builds, builds_after_first, "An unchanged tracked-only menu uses its cache")
	P.set_admitted(TRUE)
	var/list/second = op_menu(H, P, null)
	TEST_ASSERT(find_row(second, "sample")?["enabled"], "The genuine tracked setter changes the requirement")
	TEST_ASSERT_EQUAL(GLOB.op_menu_builds, builds_after_first + 1, "A real tracked change rebuilds only once")

/datum/unit_test/read_once_menu_contract/nested
/datum/unit_test/read_once_menu_contract/nested/run_gate()
	var/list/frame_before = GLOB.op_menu_read_frame
	var/depth_before = GLOB.op_pure_depth
	// Represent an enclosing synchronous read without a world output inside a condition.
	var/list/outer_frame = list(null, FALSE)
	set_global(nameof(GLOB.op_menu_read_frame), outer_frame)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/read_once_menu_probe/inner = allocate(/obj/read_once_menu_probe)
	var/list/first = op_menu(H, inner, null)
	TEST_ASSERT(!find_row(first, "sample")?["enabled"], "The actual inner requirement initially refuses")
	TEST_ASSERT(outer_frame[2], "The transitive inner read_once marks its enclosing read scope")
	TEST_ASSERT_EQUAL(GLOB.op_menu_read_frame, outer_frame, "The inner successful read restores its enclosing frame")
	TEST_ASSERT_EQUAL(GLOB.op_pure_depth, depth_before, "The inner successful read restores entry purity depth")
	outer_frame[2] = FALSE
	inner.admitted = TRUE
	var/list/second = op_menu(H, inner, null)
	TEST_ASSERT(find_row(second, "sample")?["enabled"], "The changed inner requirement is sampled on its next menu read")
	TEST_ASSERT(outer_frame[2], "A subsequent inner read again marks the enclosing scope")
	TEST_ASSERT_EQUAL(GLOB.op_menu_read_frame, outer_frame, "The later read also restores its enclosing frame")
	set_global(nameof(GLOB.op_menu_read_frame), frame_before)
	TEST_ASSERT_EQUAL(GLOB.op_menu_read_frame, frame_before, "The test restores the original ambient scope")

/datum/unit_test/read_once_menu_contract/exception
/datum/unit_test/read_once_menu_contract/exception/run_gate()
	var/list/frame_before = GLOB.op_menu_read_frame
	var/depth_before = GLOB.op_pure_depth
	var/list/outer_frame = list(null, FALSE)
	set_global(nameof(GLOB.op_menu_read_frame), outer_frame)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/read_once_menu_probe/inner = allocate(/obj/read_once_menu_probe)
	inner.fail = TRUE
	var/exception/caught
	try
		op_menu(H, inner, null)
	catch(var/exception/fault)
		caught = fault
	TEST_ASSERT_NOTNULL(caught, "The inner admission handler actually throws")
	TEST_ASSERT_EQUAL(caught.name, "Expected read_once menu probe", "The original exception is preserved")
	TEST_ASSERT(outer_frame[2], "The admission read reached its enclosing scope before throwing")
	TEST_ASSERT_EQUAL(GLOB.op_menu_read_frame, outer_frame, "Exceptional inner evaluation restores its enclosing frame")
	TEST_ASSERT_EQUAL(GLOB.op_pure_depth, depth_before, "Exceptional inner evaluation restores entry purity depth")
	outer_frame[2] = FALSE
	var/obj/read_once_tracked_menu_probe/normal = allocate(/obj/read_once_tracked_menu_probe)
	op_menu(H, normal, null)
	var/builds_after_first = GLOB.op_menu_builds
	op_menu(H, normal, null)
	TEST_ASSERT_EQUAL(GLOB.op_menu_builds, builds_after_first, "An aborted read cannot poison unrelated tracked-only caching")
	TEST_ASSERT(!outer_frame[2], "A tracked-only read does not inherit a discarded inner marker")
	TEST_ASSERT_EQUAL(GLOB.op_menu_read_frame, outer_frame, "Tracked-only reads also restore their enclosing scope")
	set_global(nameof(GLOB.op_menu_read_frame), frame_before)
	TEST_ASSERT_EQUAL(GLOB.op_menu_read_frame, frame_before, "The exception test restores the original ambient scope")
