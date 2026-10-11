// Native acceptance foundation regression coverage.

// Declaration inheritance, override, and pooled-context behavior.
#define DQ_ACCEPTANCE_CHANNEL "dq-acceptance"
/obj/item/dq_acceptance_native
	var/acceptance_limit = 0
	var/list/acceptance_changes
TRACKED(/obj/item/dq_acceptance_native, acceptance_limit)
TRACKED(/obj/item/dq_acceptance_native, acceptance_changes)
CAPABILITIES(/obj/item/dq_acceptance_native)
	acceptance(DQ_ACCEPTANCE_CHANNEL, req(PROC_REF(first_reason)))
/obj/item/dq_acceptance_native/proc/first_reason(datum/act/op/A)
	return acceptance_limit < 1 ? "first limit" : null
/obj/item/dq_acceptance_native/acceptance_overrides()
	return acceptance_changes
/obj/item/dq_acceptance_native/acceptance_override_reads()
	return list(list(src, nameof(acceptance_changes)))
/obj/item/dq_acceptance_native/appended
CAPABILITIES(/obj/item/dq_acceptance_native/appended)
	acceptance(DQ_ACCEPTANCE_CHANNEL, req(PROC_REF(second_reason)))
/obj/item/dq_acceptance_native/appended/proc/second_reason(datum/act/op/A)
	return acceptance_limit < 2 ? "second limit" : null
/obj/item/dq_acceptance_native/replaced
CAPABILITIES(/obj/item/dq_acceptance_native/replaced)
	acceptance(DQ_ACCEPTANCE_CHANNEL, req(PROC_REF(silent_reason)), mode = ACCEPTANCE_REPLACE)
/obj/item/dq_acceptance_native/replaced/proc/silent_reason(datum/act/op/A)
	return ""
/obj/item/dq_acceptance_native/empty
CAPABILITIES(/obj/item/dq_acceptance_native/empty)
	acceptance(DQ_ACCEPTANCE_CHANNEL, mode = ACCEPTANCE_EMPTY)

/datum/unit_test/dq_acceptance_native_foundation/Run()
	var/obj/item/dq_acceptance_native/appended/D = allocate(/obj/item/dq_acceptance_native/appended)
	var/obj/item/I = allocate(/obj/item)
	TEST_ASSERT_EQUAL(acceptance_reason(D, DQ_ACCEPTANCE_CHANNEL, D, I), "first limit", "Parent first refusal remains exact")
	D.set_acceptance_limit(1)
	TEST_ASSERT_EQUAL(acceptance_reason(D, DQ_ACCEPTANCE_CHANNEL, D, I), "second limit", "Append preserves ordered child refusal")
	D.set_acceptance_limit(2)
	TEST_ASSERT_NULL(acceptance_reason(D, DQ_ACCEPTANCE_CHANNEL, D, I), "Both native requirements allow")
	var/obj/item/dq_acceptance_native/replaced/R = allocate(/obj/item/dq_acceptance_native/replaced)
	TEST_ASSERT_EQUAL(acceptance_reason(R, DQ_ACCEPTANCE_CHANNEL, R, I), /datum/msg/req_silent, "Replacement drops inherited reason and preserves silent refusal")
	var/obj/item/dq_acceptance_native/empty/E = allocate(/obj/item/dq_acceptance_native/empty)
	TEST_ASSERT(!acceptance_declared(E, DQ_ACCEPTANCE_CHANNEL), "Explicit empty remains distinct from effective declared storage")
	TEST_ASSERT_NULL(acceptance_reason(E, DQ_ACCEPTANCE_CHANNEL, E, I), "Empty requirements allow when consumer does not require channel presence")
	var/list/before = D.acceptance_changes
	D.set_acceptance_changes(acceptance_override(D, before, DQ_ACCEPTANCE_CHANNEL, acceptance(DQ_ACCEPTANCE_CHANNEL, mode = ACCEPTANCE_EMPTY)))
	TEST_ASSERT_NULL(before, "Override setter does not mutate prior snapshot")
	TEST_ASSERT(!acceptance_declared(D, DQ_ACCEPTANCE_CHANNEL), "Explicit empty override wins")
	D.set_acceptance_changes(acceptance_inherit(D.acceptance_changes, DQ_ACCEPTANCE_CHANNEL))
	TEST_ASSERT(acceptance_declared(D, DQ_ACCEPTANCE_CHANNEL), "Removing override restores inheritance")
	var/datum/act/op/acceptance/A = acceptance_act(D, D, I)
	var/datum/acceptance_context/C = A.acceptance
	acceptance_act_release(A)
	TEST_ASSERT_NULL(A.acceptance, "Released act clears context reference")
	TEST_ASSERT_NULL(C.candidate, "Released context clears borrowed candidate")
	TEST_ASSERT_NULL(C.holder, "Released context clears borrowed holder")
	TEST_ASSERT(!QDELETED(D) && !QDELETED(I), "Pool release cannot delete borrowed entities")

#undef DQ_ACCEPTANCE_CHANNEL


// Cold allocation and nested query purity.
#define DQ_ACCEPTANCE_PURE "dq-acceptance-pure"
#define DQ_ACCEPTANCE_NESTED "dq-acceptance-nested"
/obj/item/dq_acceptance_pure
CAPABILITIES(/obj/item/dq_acceptance_pure)
	acceptance(DQ_ACCEPTANCE_PURE, req(PROC_REF(context_reason)))
	acceptance(DQ_ACCEPTANCE_NESTED, part_make(/datum/entry/part/req/dq_nested_acceptance))
/obj/item/dq_acceptance_pure/proc/context_reason(datum/act/op/A)
	var/datum/acceptance_context/C = A.acceptance
	if(C.options?["fault"])
		CRASH("expected acceptance callback fault")
	if(A.held_provider() != C.candidate)
		return "held context mismatch"
	if(C.options?["refuse"])
		return "exact refusal"
	return null
// The nested requirement supplies the actual inner plan's dynamic dependencies.
/datum/entry/part/req/dq_nested_acceptance/check(datum/act/op/A)
	return acceptance_reason(A.holder, DQ_ACCEPTANCE_PURE, A.acceptance.holder, A.acceptance.candidate)
/datum/entry/part/req/dq_nested_acceptance/holds(datum/act/op/A)
	return isnull(check(A))
/datum/entry/part/req/dq_nested_acceptance/refusal(datum/act/op/A)
	return check(A)
/datum/entry/part/req/dq_nested_acceptance/read_keys(datum/act/op/A)
	return acceptance_read_keys(A.holder, DQ_ACCEPTANCE_PURE, A.acceptance.holder, A.acceptance.candidate)

// Unique pooled subtypes prove genuinely cold allocation independent of other tests.
/datum/act/op/acceptance/dq_acceptance_cold
/datum/acceptance_context/dq_acceptance_cold

/datum/unit_test/dq_acceptance_cold_pool/Run()
	var/obj/item/dq_acceptance_pure/D = allocate(/obj/item/dq_acceptance_pure)
	var/obj/item/I = allocate(/obj/item)
	var/datum/entry/part/acceptance_plan/P = acceptance_plan_for(D, DQ_ACCEPTANCE_PURE)
	TEST_ASSERT_NULL(GLOB.object_pools[/datum/act/op/acceptance/dq_acceptance_cold], "Unique act pool starts genuinely cold")
	TEST_ASSERT_NULL(GLOB.object_pools[/datum/acceptance_context/dq_acceptance_cold], "Unique context pool starts genuinely cold")
	var/datum/rx_state/DS = rx_of(D)
	var/datum/rx_state/IS = rx_of(I)
	var/holder_generation = DS.act_gen
	var/candidate_generation = IS.act_gen
	var/atom/location = I.loc
	var/violations = length(GLOB.op_pure_violations)
	op_pure_begin()
	var/datum/act/op/acceptance/dq_acceptance_cold/A = take(/datum/act/op/acceptance/dq_acceptance_cold)
	var/datum/acceptance_context/dq_acceptance_cold/C = take(/datum/acceptance_context/dq_acceptance_cold)
	A.acceptance = C
	A.holder = D
	A.target = I
	A.target_atom = I
	C.holder = D
	C.candidate = I
	var/why = P.check(A)
	acceptance_act_release(A)
	op_pure_end()
	TEST_ASSERT_NULL(why, "Real native plan allows cold borrowed held candidate")
	TEST_ASSERT_EQUAL(DS.act_gen, holder_generation, "Borrowed holder causes no ref publication")
	TEST_ASSERT_EQUAL(IS.act_gen, candidate_generation, "Borrowed held candidate causes no ref publication")
	TEST_ASSERT_EQUAL(I.loc, location, "Admission never transfers custody")
	TEST_ASSERT_EQUAL(length(GLOB.op_pure_violations), violations, "Cold pool allocation stays within native purity")
	var/datum/object_pool/AP = GLOB.object_pools[/datum/act/op/acceptance/dq_acceptance_cold]
	var/datum/object_pool/CP = GLOB.object_pools[/datum/acceptance_context/dq_acceptance_cold]
	TEST_ASSERT_EQUAL(AP.out, 0, "Cold act returned")
	TEST_ASSERT_EQUAL(CP.out, 0, "Cold context returned")
	TEST_ASSERT_NULL(A.acceptance, "Cold released act clears borrowed context")
	TEST_ASSERT_NULL(C.candidate, "Cold released context clears candidate")

/datum/unit_test/dq_acceptance_pooled_purity/Run()
	var/obj/item/dq_acceptance_pure/D = allocate(/obj/item/dq_acceptance_pure)
	var/obj/item/I = allocate(/obj/item)
	var/before_violations = length(GLOB.op_pure_violations)
	var/datum/object_pool/act_pool = GLOB.object_pools[/datum/act/op/acceptance]
	var/datum/object_pool/context_pool = GLOB.object_pools[/datum/acceptance_context]
	var/act_out = act_pool ? act_pool.out : 0
	var/context_out = context_pool ? context_pool.out : 0
	// First native acceptance use exercises cold pools when not used earlier; subsequent lap always exercises repeats.
	for(var/lap in 1 to 2)
		op_pure_begin()
		var/why = acceptance_reason(D, DQ_ACCEPTANCE_PURE, D, I)
		op_pure_end()
		TEST_ASSERT_NULL(why, "Pure admission allows real held-provider context")
		op_pure_begin()
		why = acceptance_reason(D, DQ_ACCEPTANCE_PURE, D, I, options = list("refuse" = TRUE))
		op_pure_end()
		TEST_ASSERT_EQUAL(why, "exact refusal", "Pure refusal text remains exact")
		op_pure_begin()
		why = acceptance_reason(D, DQ_ACCEPTANCE_NESTED, D, I)
		op_pure_end()
		TEST_ASSERT_NULL(why, "Nested admission owns independent synchronous contexts")
		var/caught = FALSE
		op_pure_begin()
		try
			acceptance_reason(D, DQ_ACCEPTANCE_PURE, D, I, options = list("fault" = TRUE))
		catch(var/exception/fault)
			caught = TRUE
		op_pure_end()
		TEST_ASSERT(caught, "Actual requirement callback fault propagates")
		act_pool = GLOB.object_pools[/datum/act/op/acceptance]
		context_pool = GLOB.object_pools[/datum/acceptance_context]
		TEST_ASSERT_EQUAL(act_pool.out, act_out, "Every allow/refusal/nested/fault path releases act")
		TEST_ASSERT_EQUAL(context_pool.out, context_out, "Every allow/refusal/nested/fault path releases context")
	TEST_ASSERT_EQUAL(length(GLOB.op_pure_violations), before_violations, "Cold/repeated constructors and callback checks publish nothing")
	TEST_ASSERT(!QDELETED(D) && !QDELETED(I), "Borrowed entities remain alive")
	var/datum/act/op/acceptance/A = acceptance_act(D, D, I)
	var/datum/acceptance_context/C = A.acceptance
	acceptance_act_release(A)
	TEST_ASSERT_NULL(A.acceptance, "Released act cannot retain context")
	TEST_ASSERT_NULL(C.candidate, "Released context cannot retain candidate")
	TEST_ASSERT_NULL(C.holder, "Released context cannot retain destination")

#define DQ_ACCEPTANCE_METADATA_FAULT "dq-acceptance-metadata-fault"
/obj/item/dq_acceptance_metadata_fault
	var/probe = 0
TRACKED(/obj/item/dq_acceptance_metadata_fault, probe)
CAPABILITIES(/obj/item/dq_acceptance_metadata_fault)
	acceptance(DQ_ACCEPTANCE_METADATA_FAULT, part_make(/datum/entry/part/req/dq_acceptance_metadata_fault))
/datum/entry/part/req/dq_acceptance_metadata_fault/check(datum/act/op/A)
	return null
/datum/entry/part/req/dq_acceptance_metadata_fault/read_keys(datum/act/op/A)
	var/obj/item/dq_acceptance_metadata_fault/D = A.holder
	D.set_probe(D.probe + 1)
	CRASH("expected acceptance read metadata fault")

/datum/unit_test/dq_acceptance_direct_metadata_purity/Run()
	var/obj/item/dq_acceptance_metadata_fault/D = allocate(/obj/item/dq_acceptance_metadata_fault)
	var/obj/item/I = allocate(/obj/item)
	// Precompile declaration and initialize tracked state outside admission.
	TEST_ASSERT(acceptance_plan_for(D, DQ_ACCEPTANCE_METADATA_FAULT), "Real native metadata plan compiled")
	rx_of(D)
	rx_of(I)
	var/list/previous_violations = GLOB.op_pure_violations.Copy()
	var/previous_expected = GLOB.op_pure_expected
	var/previous_depth = GLOB.op_pure_depth
	var/datum/object_pool/AP = GLOB.object_pools[/datum/act/op/acceptance]
	var/datum/object_pool/CP = GLOB.object_pools[/datum/acceptance_context]
	var/act_out = AP ? AP.out : 0
	var/context_out = CP ? CP.out : 0
	GLOB.op_pure_expected = TRUE
	// No caller pure bracket: each public query must guard its own metadata callback.
	for(var/query in 1 to 2)
		var/count_before = length(GLOB.op_pure_violations)
		var/probe_before = D.probe
		var/caught = FALSE
		try
			if(query == 1)
				acceptance_reason(D, DQ_ACCEPTANCE_METADATA_FAULT, D, I)
			else
				acceptance_read_keys(D, DQ_ACCEPTANCE_METADATA_FAULT, D, I)
		catch(var/exception/fault)
			caught = TRUE
		TEST_ASSERT(caught, "Direct metadata callback fault propagates")
		TEST_ASSERT_EQUAL(D.probe, probe_before + 1, "Real tracked setter executed in read metadata callback")
		TEST_ASSERT(length(GLOB.op_pure_violations) > count_before, "Query's native purity guard detected the actual tracked write")
		TEST_ASSERT_EQUAL(GLOB.op_pure_depth, previous_depth, "Metadata fault restores exact caller purity depth")
		AP = GLOB.object_pools[/datum/act/op/acceptance]
		CP = GLOB.object_pools[/datum/acceptance_context]
		TEST_ASSERT_EQUAL(AP.out, act_out, "Metadata fault releases borrowed act")
		TEST_ASSERT_EQUAL(CP.out, context_out, "Metadata fault releases borrowed context")
	GLOB.op_pure_expected = previous_expected
	GLOB.op_pure_violations = previous_violations
	TEST_ASSERT(!QDELETED(D) && !QDELETED(I), "Fault cleanup keeps borrowed entities alive")

#undef DQ_ACCEPTANCE_METADATA_FAULT
#undef DQ_ACCEPTANCE_NESTED
#undef DQ_ACCEPTANCE_PURE


/datum/dq_acceptance_dependency
	var/allowed = TRUE
TRACKED(/datum/dq_acceptance_dependency, allowed)

/obj/dq_acceptance_wait
	var/datum/dq_acceptance_dependency/dependency
	var/finished = 0
CAPABILITIES(/obj/dq_acceptance_wait)
	ref_one(nameof(dependency), /datum/dq_acceptance_dependency)
	op("dependent_wait", ui_act("dependent_wait"), needs(part_make(/datum/entry/part/req/dq_acceptance_wait)), wait(10 SECONDS), then(PROC_REF(finished_wait)))
	op("dependency_menu", hand(), needs(part_make(/datum/entry/part/req/dq_acceptance_wait)), then(PROC_REF(finished_wait)))
	op("dependency_selector", hand(), priority(OP_PRIORITY_DEFAULT - 1), when(part_make(/datum/entry/part/req/dq_acceptance_wait)), then(PROC_REF(finished_wait)))
/obj/dq_acceptance_wait/proc/finished_wait(datum/act/op/A)
	finished++
	return OP_OK
/datum/entry/part/req/dq_acceptance_wait/holds(datum/act/op/A)
	return isnull(check(A))
/datum/entry/part/req/dq_acceptance_wait/refusal(datum/act/op/A)
	return check(A)
/datum/entry/part/req/dq_acceptance_wait/check(datum/act/op/A)
	var/obj/dq_acceptance_wait/F = A.holder
	if(!F.dependency || QDELETED(F.dependency))
		return "dependency deleted"
	return F.dependency.allowed ? null : "dependency refused"
/datum/entry/part/req/dq_acceptance_wait/read_keys(datum/act/op/A)
	var/obj/dq_acceptance_wait/F = A.holder
	. = list(list(F, nameof(F.dependency)))
	if(F.dependency)
		. += list(list(F.dependency, nameof(F.dependency.allowed)), list(F.dependency, nameof(F.dependency.allowed)))

/datum/unit_test/dq_acceptance_pending_replacement/Run()
	test_driver_begin()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/dq_acceptance_wait/F = allocate(/obj/dq_acceptance_wait)
	var/datum/dq_acceptance_dependency/old = new
	var/datum/dq_acceptance_dependency/replacement = new
	var/key = nameof(old.allowed)
	var/old_readers = old.rx?.observed?[key] || 0
	var/replacement_readers = replacement.rx?.observed?[key] || 0
	rel_set(F, nameof(F.dependency), old)
	var/datum/op_result/R = test_ui(M, F, "dependent_wait", list())
	TEST_ASSERT_NULL(R.outcome, "Real native op waits")
	var/datum/pending_op/P = op_pending_for(M, "dependent_wait")
	TEST_ASSERT(P?.active, "Real pending record exists")
	TEST_ASSERT_EQUAL((old.rx?.observed?[key] || 0), old_readers + 1, "Duplicate declared dependency is subscribed once")
	var/mob/living/simple_mob/e0_fixture/answerer = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/item/kept = allocate(/obj/item)
	// Engine-only supplemental registration: verifies union bookkeeping, not simulated client consent.
	P.watch_answerer(answerer)
	P.watch_kept(kept)
	rel_set(F, nameof(F.dependency), replacement)
	test_time(1 TICK)
	TEST_ASSERT(P.active && isnull(R.outcome), "Successful real tracked recheck keeps wait alive")
	TEST_ASSERT_EQUAL((old.rx?.observed?[key] || 0), old_readers, "Old dependency subscription released")
	TEST_ASSERT_EQUAL((replacement.rx?.observed?[key] || 0), replacement_readers + 1, "New dependency subscribed exactly once")
	TEST_ASSERT(P in GLOB.op_watchers["[REF(answerer)]|[OP_KEEP_MOVED]"], "Answerer supplement survives requirement replacement")
	TEST_ASSERT(P in GLOB.op_watchers["[REF(kept)]|[OP_KEEP_MOVED]"], "Kept-answer supplement survives requirement replacement")
	old.set_allowed(FALSE)
	test_time(1 TICK)
	TEST_ASSERT_NULL(R.outcome, "Obsolete dependency changes cannot cancel wait")
	replacement.set_allowed(FALSE)
	test_time(1 TICK)
	TEST_ASSERT_EQUAL(R.outcome, ACT_REFUSED, "Actual replacement tracked state cancels wait")
	TEST_ASSERT_EQUAL(reason_text(R.reason), "dependency refused", "Exact native refusal retained")
	TEST_ASSERT_EQUAL(F.finished, 0, "Cancelled wait never commits effect")
	TEST_ASSERT_EQUAL((replacement.rx?.observed?[key] || 0), replacement_readers, "Cancellation releases replacement reader")
	TEST_ASSERT(!(P in GLOB.op_watchers["[REF(kept)]|[OP_KEEP_MOVED]"]), "Cancellation releases supplement registry membership")
	replacement.set_allowed(TRUE)
	R = test_ui(M, F, "dependent_wait", list())
	TEST_ASSERT_NULL(R.outcome, "Second real wait starts")
	qdel(replacement)
	test_time(1 TICK)
	TEST_ASSERT_EQUAL(R.outcome, ACT_REFUSED, "Deleting declared dependency publishes relation change and cancels wait")
	TEST_ASSERT_EQUAL(reason_text(R.reason), "dependency deleted", "Deleted dependency refusal is exact")
	TEST_ASSERT_NULL(op_pending_for(M, "dependent_wait"), "Deleted dependency leaves no pending record")
	qdel(old)
	test_driver_end()

/datum/unit_test/dq_acceptance_native_menu_dependencies/proc/row(list/rows, key)
	for(var/list/R as anything in rows)
		if(R["key"] == key)
			return R
	return null
/datum/unit_test/dq_acceptance_native_menu_dependencies/Run()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/dq_acceptance_wait/F = allocate(/obj/dq_acceptance_wait)
	var/datum/dq_acceptance_dependency/D = new
	rel_set(F, nameof(F.dependency), D)
	D.set_allowed(FALSE)
	var/list/menu = op_menu(M, F, null)
	var/list/R = row(menu, "dependency_menu")
	TEST_ASSERT(R && !R["enabled"], "Real menu keeps refused native requirement row")
	TEST_ASSERT_EQUAL(R["reason"], "dependency refused", "Menu displays exact dependency reason")
	TEST_ASSERT_NULL(row(menu, "dependency_selector"), "False selector is genuinely absent")
	// Warm cache; only external dependency generation changes next, not holder/actor keys.
	op_menu(M, F, null)
	var/holder_generation = rx_of(F).act_gen
	D.set_allowed(TRUE)
	TEST_ASSERT_EQUAL(rx_of(F).act_gen, holder_generation, "External state does not fake holder invalidation")
	menu = op_menu(M, F, null)
	R = row(menu, "dependency_menu")
	TEST_ASSERT(R && R["enabled"], "External dependency invalidates previously refused menu")
	TEST_ASSERT(row(menu, "dependency_selector"), "Reads of failed selector invalidate cached absence")
	D.set_allowed(FALSE)
	menu = op_menu(M, F, null)
	TEST_ASSERT_NULL(row(menu, "dependency_selector"), "Reverse transition also removes selector")
	qdel(D)
	menu = op_menu(M, F, null)
	R = row(menu, "dependency_menu")
	TEST_ASSERT(R && !R["enabled"], "Deleted dependency fails closed")
	TEST_ASSERT_EQUAL(R["reason"], "dependency deleted", "Deletion reason retained")
	TEST_ASSERT_NULL(F.dependency, "Declared reference clears on target deletion")

// Add to the existing foundation test translation unit.
/obj/dq_acceptance_metadata_cleanup
	var/fault_metadata = FALSE
	var/probe = 0
TRACKED(/obj/dq_acceptance_metadata_cleanup, fault_metadata)
TRACKED(/obj/dq_acceptance_metadata_cleanup, probe)
/obj/dq_acceptance_metadata_cleanup/needs_fault
CAPABILITIES(/obj/dq_acceptance_metadata_cleanup/needs_fault)
	op("cleanup", ui_act("cleanup"), needs(part_make(/datum/entry/part/req/dq_metadata_cleanup)), wait(10 SECONDS), then(PROC_REF(done)))
/obj/dq_acceptance_metadata_cleanup/when_fault
CAPABILITIES(/obj/dq_acceptance_metadata_cleanup/when_fault)
	op("cleanup", ui_act("cleanup"), when(part_make(/datum/entry/part/req/dq_metadata_cleanup)), then(PROC_REF(done)))
/obj/dq_acceptance_metadata_cleanup/proc/done(datum/act/op/A)
	return OP_OK
/datum/entry/part/req/dq_metadata_cleanup/check(datum/act/op/A)
	return null
/datum/entry/part/req/dq_metadata_cleanup/holds(datum/act/op/A)
	return TRUE
/datum/entry/part/req/dq_metadata_cleanup/read_keys(datum/act/op/A)
	var/obj/dq_acceptance_metadata_cleanup/F = A.holder
	if(F.fault_metadata)
		F.set_probe(F.probe + 1)
		CRASH("expected metadata cleanup fault")
	return list(list(F, nameof(F.probe)))

/datum/unit_test/dq_acceptance_metadata_cleanup/Run()
	test_driver_begin()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/dq_acceptance_metadata_cleanup/needs_fault/F = allocate(/obj/dq_acceptance_metadata_cleanup/needs_fault)
	var/datum/op_result/result = test_ui(M, F, "cleanup", list())
	TEST_ASSERT_NULL(result.outcome, "Real native wait starts without metadata fault")
	var/datum/pending_op/P = op_pending_for(M, "cleanup")
	TEST_ASSERT(P?.active, "Real wait has a live pending record")
	var/key = nameof(F.probe)
	var/readers = F.rx.observed[key]
	var/list/index_before = P.watch_index.Copy()
	var/depth = GLOB.op_pure_depth
	var/expected_before = GLOB.op_pure_expected
	var/list/violations_before = GLOB.op_pure_violations
	GLOB.op_pure_violations = violations_before ? violations_before.Copy() : list()
	GLOB.op_pure_expected = TRUE
	// Test-only flag change avoids invoking automatic recheck before the explicit fault probe.
	F.fault_metadata = TRUE
	var/caught = FALSE
	var/count_before = length(GLOB.op_pure_violations)
	try
		P.watch_reconcile(P.act)
	catch(var/exception/fault)
		caught = TRUE
	TEST_ASSERT(caught, "Pending metadata fault propagates")
	TEST_ASSERT_EQUAL(F.probe, 1, "Real metadata setter ran")
	TEST_ASSERT(length(GLOB.op_pure_violations) > count_before, "Pending metadata runs under purity guard")
	TEST_ASSERT_EQUAL(GLOB.op_pure_depth, depth, "Pending fault restores exact caller purity depth")
	TEST_ASSERT_EQUAL(F.rx.observed[key], readers, "Failed read collection preserves live reader count")
	TEST_ASSERT_EQUAL(length(P.watch_index), length(index_before), "Failed collection preserves subscription count")
	for(var/index in index_before)
		TEST_ASSERT(P in GLOB.op_watchers[index], "Failed collection preserves every original registration")
	F.fault_metadata = FALSE
	P.end_with(ACT_REFUSED, /datum/msg/op/cancelled)
	// Both requirement and selector fault paths must release pooled candidate acts.
	for(var/path in list(/obj/dq_acceptance_metadata_cleanup/needs_fault, /obj/dq_acceptance_metadata_cleanup/when_fault))
		var/obj/dq_acceptance_metadata_cleanup/target = allocate(path)
		// Warm pools without caching a faulting row.
		op_menu(M, target, null)
		target.set_fault_metadata(TRUE)
		var/datum/object_pool/pool = GLOB.object_pools[/datum/act/op]
		var/out_before = pool.out
		var/list/frame_before = GLOB.op_menu_read_frame
		count_before = length(GLOB.op_pure_violations)
		caught = FALSE
		try
			op_menu(M, target, null)
		catch(var/exception/fault)
			caught = TRUE
		TEST_ASSERT(caught, "Real menu metadata callback fault propagates")
		TEST_ASSERT_EQUAL(pool.out, out_before, "Menu fault releases the actual pooled candidate act")
		TEST_ASSERT_EQUAL(GLOB.op_pure_depth, depth, "Menu fault restores exact caller purity depth")
		TEST_ASSERT_EQUAL(GLOB.op_menu_read_frame, frame_before, "Menu fault restores prior read frame")
		TEST_ASSERT(length(GLOB.op_pure_violations) > count_before, "Menu callback's actual setter was detected")
	GLOB.op_pure_expected = expected_before
	GLOB.op_pure_violations = violations_before
	test_driver_end()
