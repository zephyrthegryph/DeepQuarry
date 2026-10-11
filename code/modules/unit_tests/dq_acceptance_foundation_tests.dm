// Native acceptance foundation regression coverage.

// Declaration inheritance, override, and pooled-context behavior.
/obj/item/dq_acceptance_native
	var/acceptance_limit = 0
	var/list/acceptance_changes
TRACKED(/obj/item/dq_acceptance_native, acceptance_limit)
TRACKED(/obj/item/dq_acceptance_native, acceptance_changes)
CAPABILITIES(/obj/item/dq_acceptance_native)
	acceptance("dq-acceptance", req(PROC_REF(first_reason)))
/obj/item/dq_acceptance_native/proc/first_reason(datum/act/op/A)
	return acceptance_limit < 1 ? "first limit" : null
/obj/item/dq_acceptance_native/acceptance_overrides()
	return acceptance_changes
/obj/item/dq_acceptance_native/acceptance_override_reads()
	return list(list(src, nameof(acceptance_changes)))
/obj/item/dq_acceptance_native/appended
CAPABILITIES(/obj/item/dq_acceptance_native/appended)
	acceptance("dq-acceptance", req(PROC_REF(second_reason)))
/obj/item/dq_acceptance_native/appended/proc/second_reason(datum/act/op/A)
	return acceptance_limit < 2 ? "second limit" : null
/obj/item/dq_acceptance_native/replaced
CAPABILITIES(/obj/item/dq_acceptance_native/replaced)
	acceptance("dq-acceptance", req(PROC_REF(silent_reason)), mode = ACCEPTANCE_REPLACE)
/obj/item/dq_acceptance_native/replaced/proc/silent_reason(datum/act/op/A)
	return ""
/obj/item/dq_acceptance_native/empty
CAPABILITIES(/obj/item/dq_acceptance_native/empty)
	acceptance("dq-acceptance", mode = ACCEPTANCE_EMPTY)

/datum/unit_test/dq_acceptance_native_foundation/Run()
	var/obj/item/dq_acceptance_native/appended/D = allocate(/obj/item/dq_acceptance_native/appended)
	var/obj/item/I = allocate(/obj/item)
	TEST_ASSERT_EQUAL(acceptance_reason(D, "dq-acceptance", D, I), "first limit", "Parent first refusal remains exact")
	D.set_acceptance_limit(1)
	TEST_ASSERT_EQUAL(acceptance_reason(D, "dq-acceptance", D, I), "second limit", "Append preserves ordered child refusal")
	D.set_acceptance_limit(2)
	TEST_ASSERT_NULL(acceptance_reason(D, "dq-acceptance", D, I), "Both native requirements allow")
	var/obj/item/dq_acceptance_native/replaced/R = allocate(/obj/item/dq_acceptance_native/replaced)
	TEST_ASSERT_EQUAL(acceptance_reason(R, "dq-acceptance", R, I), /datum/msg/req_silent, "Replacement drops inherited reason and preserves silent refusal")
	var/obj/item/dq_acceptance_native/empty/E = allocate(/obj/item/dq_acceptance_native/empty)
	TEST_ASSERT(!acceptance_declared(E, "dq-acceptance"), "Explicit empty remains distinct from effective declared storage")
	TEST_ASSERT_NULL(acceptance_reason(E, "dq-acceptance", E, I), "Empty requirements allow when consumer does not require channel presence")
	var/list/before = D.acceptance_changes
	D.set_acceptance_changes(acceptance_override(D, before, "dq-acceptance", acceptance("dq-acceptance", mode = ACCEPTANCE_EMPTY)))
	TEST_ASSERT_NULL(before, "Override setter does not mutate prior snapshot")
	TEST_ASSERT(!acceptance_declared(D, "dq-acceptance"), "Explicit empty override wins")
	D.set_acceptance_changes(acceptance_inherit(D.acceptance_changes, "dq-acceptance"))
	TEST_ASSERT(acceptance_declared(D, "dq-acceptance"), "Removing override restores inheritance")
	var/datum/act/op/acceptance/A = acceptance_act(D, D, I)
	acceptance_act_release(A)
	TEST_ASSERT_NULL(A.target, "Released act clears borrowed target")
	TEST_ASSERT_NULL(A.holder, "Released act clears declaration owner")
	TEST_ASSERT_NULL(A.destination, "Released act clears destination")
	TEST_ASSERT(!QDELETED(D) && !QDELETED(I), "Pool release cannot delete borrowed entities")



// Cold allocation and nested query purity.
/obj/item/dq_acceptance_pure
CAPABILITIES(/obj/item/dq_acceptance_pure)
	acceptance("dq-acceptance-pure", req(PROC_REF(context_reason)))
	acceptance("dq-acceptance-nested", part_make(/datum/entry/part/req/dq_nested_acceptance))
/obj/item/dq_acceptance_pure/proc/context_reason(datum/act/op/A)
	if(A.query_options?["fault"])
		CRASH("expected acceptance callback fault")
	if(A.held_provider() != A.target)
		return "held context mismatch"
	if(A.query_options?["refuse"])
		return "exact refusal"
	return null
// The nested requirement supplies the actual inner plan's dynamic dependencies.
/datum/entry/part/req/dq_nested_acceptance/check(datum/act/op/A)
	return acceptance_reason(A.holder, "dq-acceptance-pure", A.destination, A.target)
/datum/entry/part/req/dq_nested_acceptance/holds(datum/act/op/A)
	return isnull(check(A))
/datum/entry/part/req/dq_nested_acceptance/refusal(datum/act/op/A)
	return check(A)
/datum/entry/part/req/dq_nested_acceptance/read_keys(datum/act/op/A)
	return acceptance_read_keys(A.holder, "dq-acceptance-pure", A.destination, A.target)

// Unique pooled subtypes prove genuinely cold allocation independent of other tests.
/datum/act/op/acceptance/dq_acceptance_cold

/datum/unit_test/dq_acceptance_cold_pool/Run()
	var/obj/item/dq_acceptance_pure/D = allocate(/obj/item/dq_acceptance_pure)
	var/obj/item/I = allocate(/obj/item)
	var/datum/entry/part/acceptance_plan/P = acceptance_plan_for(D, "dq-acceptance-pure")
	TEST_ASSERT_NULL(GLOB.object_pools[/datum/act/op/acceptance/dq_acceptance_cold], "Unique act pool starts genuinely cold")
	var/datum/rx_state/DS = rx_of(D)
	var/datum/rx_state/IS = rx_of(I)
	var/holder_generation = DS.act_gen
	var/candidate_generation = IS.act_gen
	var/atom/location = I.loc
	var/violations = length(GLOB.op_pure_violations)
	op_pure_begin()
	var/datum/act/op/acceptance/dq_acceptance_cold/A = acceptance_act(D, D, I, query_type = /datum/act/op/acceptance/dq_acceptance_cold)
	var/why = P.check(A)
	acceptance_act_release(A)
	op_pure_end()
	TEST_ASSERT_NULL(why, "Real native plan allows cold borrowed held candidate")
	TEST_ASSERT_EQUAL(DS.act_gen, holder_generation, "Borrowed holder causes no ref publication")
	TEST_ASSERT_EQUAL(IS.act_gen, candidate_generation, "Borrowed held candidate causes no ref publication")
	TEST_ASSERT_EQUAL(I.loc, location, "Admission never transfers custody")
	TEST_ASSERT_EQUAL(length(GLOB.op_pure_violations), violations, "Cold pool allocation stays within native purity")
	var/datum/object_pool/AP = GLOB.object_pools[/datum/act/op/acceptance/dq_acceptance_cold]
	TEST_ASSERT_EQUAL(AP.out, 0, "Cold act returned")
	TEST_ASSERT_NULL(A.target, "Cold released act clears borrowed context")
	TEST_ASSERT_NULL(A.target, "Cold released context clears candidate")

/datum/unit_test/dq_acceptance_pooled_purity/Run()
	var/obj/item/dq_acceptance_pure/D = allocate(/obj/item/dq_acceptance_pure)
	var/obj/item/I = allocate(/obj/item)
	var/before_violations = length(GLOB.op_pure_violations)
	var/datum/object_pool/act_pool = GLOB.object_pools[/datum/act/op/acceptance]
	var/act_out = act_pool ? act_pool.out : 0
	// First native acceptance use exercises cold pools when not used earlier; subsequent lap always exercises repeats.
	for(var/lap in 1 to 2)
		op_pure_begin()
		var/why = acceptance_reason(D, "dq-acceptance-pure", D, I)
		op_pure_end()
		TEST_ASSERT_NULL(why, "Pure admission allows real held-provider context")
		op_pure_begin()
		why = acceptance_reason(D, "dq-acceptance-pure", D, I, options = list("refuse" = TRUE))
		op_pure_end()
		TEST_ASSERT_EQUAL(why, "exact refusal", "Pure refusal text remains exact")
		op_pure_begin()
		why = acceptance_reason(D, "dq-acceptance-nested", D, I)
		op_pure_end()
		TEST_ASSERT_NULL(why, "Nested admission owns independent synchronous contexts")
		var/caught = FALSE
		op_pure_begin()
		try
			acceptance_reason(D, "dq-acceptance-pure", D, I, options = list("fault" = TRUE))
		catch(var/exception/fault)
			caught = TRUE
		op_pure_end()
		TEST_ASSERT(caught, "Actual requirement callback fault propagates")
		act_pool = GLOB.object_pools[/datum/act/op/acceptance]
		TEST_ASSERT_EQUAL(act_pool.out, act_out, "Every allow/refusal/nested/fault path releases act")
	TEST_ASSERT_EQUAL(length(GLOB.op_pure_violations), before_violations, "Cold/repeated constructors and callback checks publish nothing")
	TEST_ASSERT(!QDELETED(D) && !QDELETED(I), "Borrowed entities remain alive")
	var/datum/act/op/acceptance/A = acceptance_act(D, D, I)
	acceptance_act_release(A)
	TEST_ASSERT_NULL(A.target, "Released act cannot retain target")
	TEST_ASSERT_NULL(A.target, "Released act cannot retain candidate")
	TEST_ASSERT_NULL(A.destination, "Released act cannot retain destination")

/obj/item/dq_acceptance_metadata_fault
	var/probe = 0
TRACKED(/obj/item/dq_acceptance_metadata_fault, probe)
CAPABILITIES(/obj/item/dq_acceptance_metadata_fault)
	acceptance("dq-acceptance-metadata-fault", part_make(/datum/entry/part/req/dq_acceptance_metadata_fault))
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
	TEST_ASSERT(acceptance_plan_for(D, "dq-acceptance-metadata-fault"), "Real native metadata plan compiled")
	rx_of(D)
	rx_of(I)
	var/list/previous_violations = GLOB.op_pure_violations.Copy()
	var/previous_expected = GLOB.op_pure_expected
	var/previous_depth = GLOB.op_pure_depth
	var/datum/object_pool/AP = GLOB.object_pools[/datum/act/op/acceptance]
	var/act_out = AP ? AP.out : 0
	GLOB.op_pure_expected = TRUE
	// No caller pure bracket: each public query must guard its own metadata callback.
	for(var/query in 1 to 2)
		var/count_before = length(GLOB.op_pure_violations)
		var/probe_before = D.probe
		var/caught = FALSE
		try
			if(query == 1)
				acceptance_reason(D, "dq-acceptance-metadata-fault", D, I)
			else
				acceptance_read_keys(D, "dq-acceptance-metadata-fault", D, I)
		catch(var/exception/fault)
			caught = TRUE
		TEST_ASSERT(caught, "Direct metadata callback fault propagates")
		TEST_ASSERT_EQUAL(D.probe, probe_before + 1, "Real tracked setter executed in read metadata callback")
		TEST_ASSERT(length(GLOB.op_pure_violations) > count_before, "Query's native purity guard detected the actual tracked write")
		TEST_ASSERT_EQUAL(GLOB.op_pure_depth, previous_depth, "Metadata fault restores exact caller purity depth")
		AP = GLOB.object_pools[/datum/act/op/acceptance]
		TEST_ASSERT_EQUAL(AP.out, act_out, "Metadata fault releases borrowed act")
	GLOB.op_pure_expected = previous_expected
	GLOB.op_pure_violations = previous_violations
	TEST_ASSERT(!QDELETED(D) && !QDELETED(I), "Fault cleanup keeps borrowed entities alive")



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
	catch(var/exception/metadata_fault_0)
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
		catch(var/exception/metadata_fault_1)
			caught = TRUE
		TEST_ASSERT(caught, "Real menu metadata callback fault propagates")
		TEST_ASSERT_EQUAL(pool.out, out_before, "Menu fault releases the actual pooled candidate act")
		TEST_ASSERT_EQUAL(GLOB.op_pure_depth, depth, "Menu fault restores exact caller purity depth")
		TEST_ASSERT_EQUAL(GLOB.op_menu_read_frame, frame_before, "Menu fault restores prior read frame")
		TEST_ASSERT(length(GLOB.op_pure_violations) > count_before, "Menu callback's actual setter was detected")
	GLOB.op_pure_expected = expected_before
	GLOB.op_pure_violations = violations_before
	test_driver_end()

/obj/item/dq_acceptance_target_reads
CAPABILITIES(/obj/item/dq_acceptance_target_reads)
	acceptance("dq-query-target", req(PROC_REF(target_reason)))
/obj/item/dq_acceptance_target_reads/proc/target_reason(datum/act/op/A)
	var/obj/item/dq_acceptance_native/I = A.target
	return I.acceptance_limit < 1 ? "target limit" : null
/datum/unit_test/dq_acceptance_typed_query_reads/Run()
	var/obj/item/dq_acceptance_target_reads/D = allocate(/obj/item/dq_acceptance_target_reads)
	var/obj/item/dq_acceptance_native/I = allocate(/obj/item/dq_acceptance_native)
	TEST_ASSERT_EQUAL(acceptance_reason(D, "dq-query-target", D, I), "target limit", "Real target callback refuses before setter")
	var/list/pairs = acceptance_read_keys(D, "dq-query-target", D, I)
	var/found = FALSE
	for(var/list/pair as anything in pairs)
		if(pair[1] == I && pair[2] == nameof(I.acceptance_limit))
			found = TRUE
	TEST_ASSERT(found, "Generated target root resolves actual candidate key")
	I.set_acceptance_limit(1)
	TEST_ASSERT_NULL(acceptance_reason(D, "dq-query-target", D, I), "Candidate setter allows without changing declarer")
	var/list/options = list("refuse" = TRUE)
	var/datum/act/op/acceptance/A = acceptance_act(D, D, I, options = options)
	options["refuse"] = FALSE
	TEST_ASSERT_EQUAL(A.query_options["refuse"], TRUE, "Caller map mutation cannot change invocation options")
	acceptance_act_release(A)
	var/caught = FALSE
	try
		acceptance_act(D, D, I, options = list("escape" = I))
	catch(var/exception/fault)
		caught = TRUE
	TEST_ASSERT(caught, "World references cannot escape through query options")

/obj/item/dq_acceptance_query_hop
	var/obj/item/dq_acceptance_native/next
CAPABILITIES(/obj/item/dq_acceptance_query_hop)
	ref_one(nameof(next), /obj/item/dq_acceptance_native)
/obj/item/dq_acceptance_query_hop_reader
CAPABILITIES(/obj/item/dq_acceptance_query_hop_reader)
	acceptance("dq-query-hop", req(PROC_REF(hop_reason)))
/obj/item/dq_acceptance_query_hop_reader/proc/hop_reason(datum/act/op/A)
	var/obj/item/dq_acceptance_query_hop/I = A.target
	return I.next && I.next.acceptance_limit < 1 ? "hop limit" : null
/datum/unit_test/dq_acceptance_typed_query_hop/Run()
	var/obj/item/dq_acceptance_query_hop_reader/D = allocate(/obj/item/dq_acceptance_query_hop_reader)
	var/obj/item/dq_acceptance_query_hop/I = allocate(/obj/item/dq_acceptance_query_hop)
	var/obj/item/dq_acceptance_native/first = allocate(/obj/item/dq_acceptance_native)
	var/obj/item/dq_acceptance_native/second = allocate(/obj/item/dq_acceptance_native)
	rel_set(I, nameof(I.next), first)
	var/list/pairs = acceptance_read_keys(D, "dq-query-hop", D, I)
	var/membership = FALSE
	var/first_key = FALSE
	for(var/list/pair as anything in pairs)
		membership |= pair[1] == I && pair[2] == nameof(I.next)
		first_key |= pair[1] == first && pair[2] == nameof(first.acceptance_limit)
	TEST_ASSERT(membership && first_key, "Generated relation hop watches membership and actual far owner")
	rel_set(I, nameof(I.next), second)
	pairs = acceptance_read_keys(D, "dq-query-hop", D, I)
	var/second_key = FALSE
	first_key = FALSE
	for(var/list/pair as anything in pairs)
		first_key |= pair[1] == first && pair[2] == nameof(first.acceptance_limit)
		second_key |= pair[1] == second && pair[2] == nameof(second.acceptance_limit)
	TEST_ASSERT(second_key && !first_key, "Replacement resolves new dependency before notice draining")
	var/mob/living/carbon/human/wearer = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/mover = allocate(/mob/living/carbon/human)
	var/datum/act/op/acceptance/A = acceptance_act(D, I, first, wearer, mover, SLOT_HEAD, wearer_is_actor = TRUE)
	TEST_ASSERT_EQUAL(A.wearer, wearer, "Equipment wearer remains explicit")
	TEST_ASSERT_EQUAL(A.mover, mover, "Distinct transfer actor remains explicit")
	TEST_ASSERT_EQUAL(A.actor, wearer, "Compatibility equipment evaluation uses wearer role")
	TEST_ASSERT_EQUAL(A.destination, I, "Physical destination differs from declarer")
	TEST_ASSERT_EQUAL(A.target, first, "Candidate is actual action target")
	acceptance_act_release(A)
	TEST_ASSERT_NULL(A.wearer, "Release clears borrowed wearer")
	TEST_ASSERT_NULL(A.mover, "Release clears borrowed mover")
	TEST_ASSERT_NULL(A.destination, "Release clears borrowed destination")

// Actual SYSTEM_ACCESSOR + tracked singleton setter, without mock publications.
/obj/item/dq_acceptance_system_query
CAPABILITIES(/obj/item/dq_acceptance_system_query)
	acceptance("dq-system-query", req(PROC_REF(system_reason)))
/obj/item/dq_acceptance_system_query/proc/system_reason(datum/act/op/A)
	return night_shift_active() ? "night shift active" : null
/datum/unit_test/dq_acceptance_system_query_dependency/Run()
	var/obj/item/dq_acceptance_system_query/D = allocate(/obj/item/dq_acceptance_system_query)
	var/obj/item/I = allocate(/obj/item)
	var/before = SSnightshift.nightshift_active
	var/list/old_frame = GLOB.op_menu_read_frame
	var/list/frame = list(null, FALSE, list())
	GLOB.op_menu_read_frame = frame
	var/fault
	try
		var/why = acceptance_reason(D, "dq-system-query", D, I)
		TEST_ASSERT_EQUAL(why, before ? "night shift active" : null, "Actual singleton accessor gives exact reason")
		var/list/pairs = acceptance_read_keys(D, "dq-system-query", D, I)
		var/found = FALSE
		for(var/list/pair as anything in pairs)
			found |= pair[1] == SSnightshift && pair[2] == nameof(SSnightshift.nightshift_active)
		TEST_ASSERT(found, "Generated system root watches real singleton/key")
		TEST_ASSERT(op_menu_dependencies_valid(frame[3]), "Captured real dependency initially validates")
		SSnightshift.set_nightshift_active(!before)
		TEST_ASSERT(!op_menu_dependencies_valid(frame[3]), "Real tracked setter invalidates cached query dependency without manual publication")
		TEST_ASSERT_EQUAL(acceptance_reason(D, "dq-system-query", D, I), !before ? "night shift active" : null, "Re-evaluation reads changed actual singleton")
	catch(var/exception/error)
		fault = error
	SSnightshift.set_nightshift_active(before)
	GLOB.op_menu_read_frame = old_frame
	if(fault)
		throw fault

/obj/item/dq_acceptance_query_members
	var/list/members
CAPABILITIES(/obj/item/dq_acceptance_query_members)
	owns_many(nameof(members), /obj/item/dq_acceptance_native)
/obj/item/dq_acceptance_query_members_reader
CAPABILITIES(/obj/item/dq_acceptance_query_members_reader)
	acceptance("dq-query-members", req(PROC_REF(member_reason)))
	acceptance("dq-query-map", req(PROC_REF(map_reason)))
/obj/item/dq_acceptance_query_members_reader/proc/member_reason(datum/act/op/A)
	var/obj/item/dq_acceptance_query_members/I = A.target
	for(var/obj/item/dq_acceptance_native/member as anything in I.members)
		if(member.acceptance_limit < 1)
			return "member limit"
	return null
/obj/item/dq_acceptance_query_members_reader/proc/map_reason(datum/act/op/A)
	var/obj/item/dq_acceptance_query_members/I = A.target
	var/obj/item/dq_acceptance_native/member = I.members?["left"]
	return member && member.acceptance_limit < 1 ? "map limit" : null
/datum/unit_test/dq_acceptance_query_list_hops/proc/assert_pair(list/pairs, datum/owner, key)
	for(var/list/pair as anything in pairs)
		if(pair[1] == owner && pair[2] == key)
			return
	TEST_FAIL("Missing actual list dependency [owner.type].[key]")
/datum/unit_test/dq_acceptance_query_list_hops/Run()
	var/obj/item/dq_acceptance_query_members_reader/D = allocate(/obj/item/dq_acceptance_query_members_reader)
	var/obj/item/dq_acceptance_query_members/I = allocate(/obj/item/dq_acceptance_query_members)
	var/obj/item/dq_acceptance_native/first = allocate(/obj/item/dq_acceptance_native)
	var/obj/item/dq_acceptance_native/second = allocate(/obj/item/dq_acceptance_native)
	rel_add(I, nameof(I.members), first)
	rel_add(I, nameof(I.members), second)
	var/list/pairs = acceptance_read_keys(D, "dq-query-members", D, I)
	assert_pair(pairs, I, nameof(I.members))
	assert_pair(pairs, first, nameof(first.acceptance_limit))
	assert_pair(pairs, second, nameof(second.acceptance_limit))
	TEST_ASSERT_EQUAL(acceptance_reason(D, "dq-query-members", D, I), "member limit", "Actual foreach callback refuses")
	first.set_acceptance_limit(1)
	second.set_acceptance_limit(1)
	TEST_ASSERT_NULL(acceptance_reason(D, "dq-query-members", D, I), "Real member setter values allow")
	var/obj/item/dq_acceptance_native/removed = rel_take(I, nameof(I.members), second)
	TEST_ASSERT_EQUAL(removed, second, "Real member take removes only selected member")
	pairs = acceptance_read_keys(D, "dq-query-members", D, I)
	assert_pair(pairs, I, nameof(I.members))
	assert_pair(pairs, first, nameof(first.acceptance_limit))
	for(var/list/pair as anything in pairs)
		TEST_ASSERT(pair[1] != second, "Removed member no longer contributes dependency")
	var/obj/item/dq_acceptance_query_members/map_holder = allocate(/obj/item/dq_acceptance_query_members)
	var/obj/item/dq_acceptance_native/mapped = allocate(/obj/item/dq_acceptance_native)
	rel_add(map_holder, nameof(map_holder.members), mapped, "left")
	pairs = acceptance_read_keys(D, "dq-query-map", map_holder, map_holder)
	assert_pair(pairs, map_holder, nameof(map_holder.members))
	assert_pair(pairs, mapped, nameof(mapped.acceptance_limit))
	TEST_ASSERT_EQUAL(acceptance_reason(D, "dq-query-map", map_holder, map_holder), "map limit", "Real keyed member callback refuses")
	mapped.set_acceptance_limit(1)
	TEST_ASSERT_NULL(acceptance_reason(D, "dq-query-map", map_holder, map_holder), "Actual keyed member setter permits")

// Physical path nesting differs from DM inheritance; declaration is inherited.
/obj/item/dq_acceptance_query_nonlexical
	parent_type = /obj/item/dq_acceptance_target_reads
/datum/unit_test/dq_acceptance_query_actual_parent/Run()
	var/obj/item/dq_acceptance_query_nonlexical/D = allocate(/obj/item/dq_acceptance_query_nonlexical)
	var/obj/item/dq_acceptance_native/I = allocate(/obj/item/dq_acceptance_native)
	TEST_ASSERT_EQUAL(acceptance_reason(D, "dq-query-target", D, I), "target limit", "Actual inherited requirement executes")
	var/list/pairs = acceptance_read_keys(D, "dq-query-target", D, I)
	var/found = FALSE
	for(var/list/pair as anything in pairs)
		found |= pair[1] == I && pair[2] == nameof(I.acceptance_limit)
	TEST_ASSERT(found, "Generated parent row follows actual parent_type instead of slash nesting")

// Distinct actual invocation roots retain ordered refusal and setter recovery.
/mob/dq_acceptance_role_reads
	var/query_ready = FALSE
TRACKED(/mob/dq_acceptance_role_reads, query_ready)
/obj/item/dq_acceptance_role_destination
	var/query_ready = FALSE
TRACKED(/obj/item/dq_acceptance_role_destination, query_ready)
CAPABILITIES(/obj/item/dq_acceptance_role_destination)
	acceptance("dq-query-distinct-roles", req(PROC_REF(roles_reason)))
/obj/item/dq_acceptance_role_destination/proc/roles_reason(datum/act/op/A)
	var/mob/dq_acceptance_role_reads/W = A.wearer
	var/mob/dq_acceptance_role_reads/M = A.mover
	var/obj/item/dq_acceptance_role_destination/D = A.destination
	if(!W.query_ready)
		return "wearer not ready"
	if(!M.query_ready)
		return "mover not ready"
	if(!D.query_ready)
		return "destination not ready"
	return null
/datum/unit_test/dq_acceptance_distinct_role_reads/Run()
	var/obj/item/dq_acceptance_role_destination/declarer = allocate(/obj/item/dq_acceptance_role_destination)
	var/obj/item/dq_acceptance_role_destination/destination = allocate(/obj/item/dq_acceptance_role_destination)
	var/obj/item/dq_acceptance_native/candidate = allocate(/obj/item/dq_acceptance_native)
	var/mob/dq_acceptance_role_reads/wearer = allocate(/mob/dq_acceptance_role_reads)
	var/mob/dq_acceptance_role_reads/mover = allocate(/mob/dq_acceptance_role_reads)
	var/list/pairs = acceptance_read_keys(declarer, "dq-query-distinct-roles", destination, candidate, wearer, mover)
	for(var/datum/expected in list(wearer, mover, destination))
		var/found = FALSE
		for(var/list/pair as anything in pairs)
			found |= pair[1] == expected && pair[2] == "query_ready"
		TEST_ASSERT(found, "Compiled callback tracks each distinct actual role owner before first refusal")
	TEST_ASSERT_EQUAL(acceptance_reason(declarer, "dq-query-distinct-roles", destination, candidate, wearer, mover), "wearer not ready", "Wearer has first refusal")
	wearer.set_query_ready(TRUE)
	TEST_ASSERT_EQUAL(acceptance_reason(declarer, "dq-query-distinct-roles", destination, candidate, wearer, mover), "mover not ready", "Wearer setter lifts only its refusal")
	mover.set_query_ready(TRUE)
	TEST_ASSERT_EQUAL(acceptance_reason(declarer, "dq-query-distinct-roles", destination, candidate, wearer, mover), "destination not ready", "Mover setter lifts only its refusal")
	destination.set_query_ready(TRUE)
	TEST_ASSERT_NULL(acceptance_reason(declarer, "dq-query-distinct-roles", destination, candidate, wearer, mover), "Actual destination setter allows")
	declarer.set_query_ready(FALSE)
	TEST_ASSERT_NULL(acceptance_reason(declarer, "dq-query-distinct-roles", destination, candidate, wearer, mover), "Declaration owner is not silently substituted for destination")
