#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/dq_lazy_memo_source
	var/amount = 1

TRACKED(/datum/dq_lazy_memo_source, amount)

/datum/dq_lazy_memo_key
	var/marker = 2

TRACKED(/datum/dq_lazy_memo_key, marker)

/datum/dq_lazy_memo_map
	var/datum/dq_lazy_memo_key/index_key
	var/list/values

CAPABILITIES(/datum/dq_lazy_memo_map)
	ref_one(nameof(index_key), /datum/dq_lazy_memo_key)
	owns_many(nameof(values), /datum/dq_lazy_memo_source)
	memo("indexed_value", PROC_REF(compute_indexed_value))
	memo("first_key", PROC_REF(compute_first_key))
	memo("membership", PROC_REF(compute_membership))

/datum/dq_lazy_memo_map/proc/compute_indexed_value(datum/act/eval/A)
	if(!index_key || !values)
		return 0
	var/datum/dq_lazy_memo_source/member = values[index_key]
	return QDELETED(member) ? 0 : member.amount

/datum/dq_lazy_memo_map/proc/compute_first_key(datum/act/eval/A)
	if(!length(values))
		return 0
	var/datum/dq_lazy_memo_key/first = values[1]
	return QDELETED(first) ? 0 : first.marker

/datum/dq_lazy_memo_map/proc/compute_membership(datum/act/eval/A)
	return length(values)

/datum/unit_test/dq_lazy_memo/datum_keyed_value/Run()
	var/datum/dq_lazy_memo_map/F = allocate(/datum/dq_lazy_memo_map)
	var/datum/dq_lazy_memo_key/K = allocate(/datum/dq_lazy_memo_key)
	var/datum/dq_lazy_memo_source/V = allocate(/datum/dq_lazy_memo_source)
	V.set_amount(5)
	rel_set(F, nameof(F.index_key), K)
	rel_add(F, nameof(F.values), V, K)
	TEST_ASSERT_EQUAL(memo_value(F, "indexed_value"), 5, "datum-keyed index followed the key instead of its distinct value")
	TEST_ASSERT_EQUAL(memo_value(F, "first_key"), 2, "numeric position followed an associative value instead of its actual key")
	TEST_ASSERT_EQUAL(memo_value(F, "membership"), 1, "the real keyed membership was lost")
	K.set_marker(11)
	TEST_ASSERT_EQUAL(memo_value(F, "indexed_value"), 5, "key-field mutation changed the selected value")
	TEST_ASSERT_EQUAL(memo_cell_of(F, "indexed_value").computations, 1, "index receiver was replaced by its datum key")
	TEST_ASSERT_EQUAL(memo_value(F, "first_key"), 11, "the real positional key producer did not invalidate")
	V.set_amount(9)
	TEST_ASSERT_EQUAL(memo_value(F, "indexed_value"), 9, "selected datum value mutation did not invalidate")
	TEST_ASSERT_EQUAL(memo_value(F, "membership"), 1, "value mutation changed actual membership")
	TEST_ASSERT_EQUAL(memo_cell_of(F, "membership").computations, 1, "membership subscribed an unrelated member field")
	qdel(V)
	TEST_ASSERT_EQUAL(memo_value(F, "indexed_value"), 0, "deleted indexed value remained cached")
	TEST_ASSERT_EQUAL(memo_value(F, "membership"), 0, "actual value deletion did not invalidate membership-only inputs")
	TEST_ASSERT_EQUAL(memo_value(F, "first_key"), 0, "the removed map key survived in the positional output")

/datum/dq_lazy_memo_fixture
	var/local_value = 1
	var/mode = 0
	var/datum/dq_lazy_memo_source/source
	var/list/members
	var/observations = 0
	var/inside_batch_value
	var/inside_batch_observations

TRACKED(/datum/dq_lazy_memo_fixture, local_value)
TRACKED(/datum/dq_lazy_memo_fixture, mode)

CAPABILITIES(/datum/dq_lazy_memo_fixture)
	ref_one(nameof(source), /datum/dq_lazy_memo_source)
	ref_many(nameof(members), /datum/dq_lazy_memo_source)
	memo("value", PROC_REF(compute_value))
	memo("result", PROC_REF(compute_result))
	memo("cycle", PROC_REF(compute_cycle))
	on_change("memo:value", then(PROC_REF(observed)))

/datum/dq_lazy_memo_fixture/proc/compute_value(datum/act/eval/A)
	var/total = local_value + (source ? source.amount : 0)
	for(var/datum/dq_lazy_memo_source/member as anything in members)
		total += member.amount
	return total

/datum/dq_lazy_memo_fixture/proc/compute_result(datum/act/eval/A)
	switch(mode)
		if(0)
			return null
		if(1)
			return FALSE
		if(2)
			return list(local_value)
		if(3)
			throw EXCEPTION("Expected memo computation fault")
	return source

/datum/dq_lazy_memo_fixture/proc/compute_cycle(datum/act/eval/A)
	if(mode)
		return memo_value(src, "cycle")
	return local_value

/datum/dq_lazy_memo_fixture/proc/observed(datum/act/notice/A)
	observations++

/datum/dq_lazy_memo_fixture/proc/batched_write()
	set_local_value(8)
	inside_batch_value = memo_value(src, "value")
	inside_batch_observations = observations

/datum/dq_lazy_memo_parent
	var/datum/dq_lazy_memo_fixture/child

CAPABILITIES(/datum/dq_lazy_memo_parent)
	ref_one(nameof(child), /datum/dq_lazy_memo_fixture)
	memo("envelope", PROC_REF(compute_envelope))

/datum/dq_lazy_memo_parent/proc/compute_envelope(datum/act/eval/A)
	return child ? memo_value(child, "value") + 1 : 0

/datum/unit_test/dq_lazy_memo/nested_scalar_sources/Run()
	var/datum/dq_lazy_memo_parent/P = allocate(/datum/dq_lazy_memo_parent)
	var/datum/dq_lazy_memo_fixture/F = allocate(/datum/dq_lazy_memo_fixture)
	rel_set(P, nameof(P.child), F)
	TEST_ASSERT_EQUAL(memo_value(P, "envelope"), 2, "parent did not read its actual child's memo")
	TEST_ASSERT_EQUAL(memo_value(P, "envelope"), 2, "reused parent changed its value")
	TEST_ASSERT_EQUAL(memo_cell_of(P, "envelope").computations, 1, "child population caused needless parent recomputation")
	TEST_ASSERT_EQUAL(memo_cell_of(F, "value").computations, 1, "parent reuse recomputed its child")
	F.set_local_value(5)
	TEST_ASSERT_EQUAL(memo_value(P, "envelope"), 6, "nested output was stale before observer delivery")
	qdel(F)
	TEST_ASSERT_EQUAL(memo_value(P, "envelope"), 0, "parent cache retained its deleted child")

/datum/dq_lazy_memo_fixture/lifetime

/datum/dq_lazy_memo_fixture/lifetime/compute_value(datum/act/eval/A)
	return QDELETED(source) ? local_value : local_value + source.amount

/datum/dq_lazy_memo_batch_probe
	var/datum/dq_lazy_memo_parent/parent
	var/observed
	var/source_was_doomed = FALSE

CAPABILITIES(/datum/dq_lazy_memo_batch_probe)
	ref_one(nameof(parent), /datum/dq_lazy_memo_parent)

/datum/dq_lazy_memo_batch_probe/lifecycle_unbind()
	// qdel_batch reverses the root order. This probe runs while the source
	// is marked doomed but its reactive record has not been torn down.
	source_was_doomed = parent.child.source.gc_destroyed == GC_BATCH_DOOMED
	observed = memo_value(parent, "envelope")
	. = ..()

/datum/unit_test/dq_lazy_memo/pre_teardown_batch_lifetime/Run()
	var/datum/dq_lazy_memo_parent/P = allocate(/datum/dq_lazy_memo_parent)
	var/datum/dq_lazy_memo_fixture/lifetime/F = allocate(/datum/dq_lazy_memo_fixture/lifetime)
	var/datum/dq_lazy_memo_source/S = allocate(/datum/dq_lazy_memo_source)
	var/datum/dq_lazy_memo_batch_probe/probe = allocate(/datum/dq_lazy_memo_batch_probe)
	rel_set(P, nameof(P.child), F)
	rel_set(F, nameof(F.source), S)
	rel_set(probe, nameof(probe.parent), P)
	S.set_amount(7)
	TEST_ASSERT_EQUAL(memo_value(P, "envelope"), 9, "parent and child were not warmed against the live source")
	qdel_batch(list(S, probe))
	TEST_ASSERT(probe.source_was_doomed, "probe did not run before source teardown at the batch marking boundary")
	TEST_ASSERT_EQUAL(probe.observed, 2, "parent returned its cached live-source result after the source was marked doomed")
	TEST_ASSERT_EQUAL(memo_value(P, "envelope"), 2, "completed teardown changed the already-current scalar result")

/datum/unit_test/dq_lazy_memo/scalar_cache/Run()
	var/datum/dq_lazy_memo_fixture/F = allocate(/datum/dq_lazy_memo_fixture)
	TEST_ASSERT_NULL(memo_value(F, "result"), "null is not a valid memo result")
	TEST_ASSERT_NULL(memo_value(F, "result"), "cached null changed shape")
	TEST_ASSERT_EQUAL(memo_cell_of(F, "result").computations, 1, "null was recomputed instead of cached")
	F.set_mode(1)
	TEST_ASSERT_EQUAL(memo_value(F, "result"), FALSE, "FALSE is not a valid memo result")
	TEST_ASSERT_EQUAL(memo_value(F, "result"), FALSE, "cached FALSE changed shape")
	TEST_ASSERT_EQUAL(memo_cell_of(F, "result").computations, 2, "FALSE was recomputed instead of cached")

/datum/unit_test/dq_lazy_memo/member_replacement_and_deletion/Run()
	var/datum/dq_lazy_memo_fixture/F = allocate(/datum/dq_lazy_memo_fixture)
	var/datum/dq_lazy_memo_source/first = allocate(/datum/dq_lazy_memo_source)
	var/datum/dq_lazy_memo_source/second = allocate(/datum/dq_lazy_memo_source)
	rel_set(F, nameof(F.source), first)
	rel_add(F, nameof(F.members), second)
	TEST_ASSERT_EQUAL(memo_value(F, "value"), 3, "memo omitted its actual child inputs")
	second.set_amount(7)
	TEST_ASSERT_EQUAL(memo_value(F, "value"), 9, "member write returned stale value without a drain")
	rel_clear(F, nameof(F.source))
	TEST_ASSERT_EQUAL(memo_value(F, "value"), 8, "source replacement retained the old child")
	qdel(second)
	TEST_ASSERT_EQUAL(memo_value(F, "value"), 1, "deleted member remained in cached output")
	TEST_ASSERT_EQUAL(memo_cell_of(F, "value").computations, 4, "membership/deletion did not invalidate the actual memo")

/datum/unit_test/dq_lazy_memo/batch_is_current/Run()
	var/datum/dq_lazy_memo_fixture/F = allocate(/datum/dq_lazy_memo_fixture)
	TEST_ASSERT_EQUAL(memo_value(F, "value"), 1, "initial memo computation failed")
	test_drain()
	var/before = F.observations
	state_batch(F, TYPE_PROC_REF(/datum/dq_lazy_memo_fixture, batched_write))
	TEST_ASSERT_EQUAL(F.inside_batch_value, 8, "memo read inside a setter batch returned stale state")
	TEST_ASSERT_EQUAL(F.inside_batch_observations, before, "memo invalidation woke its observer inside the writer cohort")
	test_drain()
	TEST_ASSERT_EQUAL(F.observations, before + 1, "batch completion did not publish the real memo output once")

/datum/unit_test/dq_lazy_memo/container_and_borrowed_result/Run()
	var/datum/dq_lazy_memo_fixture/F = allocate(/datum/dq_lazy_memo_fixture)
	F.set_mode(2)
	var/list_fault = FALSE
	try
		memo_value(F, "result")
	catch(var/exception/fault)
		list_fault = TRUE
	TEST_ASSERT(list_fault, "memo exposed a mutable cached list to its caller")
	TEST_ASSERT(!memo_cell_of(F, "result").valid, "rejected list became a valid cached result")
	F.set_mode(4)
	var/datum/dq_lazy_memo_source/S = allocate(/datum/dq_lazy_memo_source)
	rel_set(F, nameof(F.source), S)
	var/datum_fault = FALSE
	try
		memo_value(F, "result")
	catch(var/exception/fault)
		datum_fault = TRUE
	TEST_ASSERT(datum_fault, "memo retained and returned a borrowed world object")
	qdel(S)
	TEST_ASSERT_NULL(memo_value(F, "result"), "deleted source did not resolve to the supported null result")

/datum/unit_test/dq_lazy_memo/fault_and_cycle_unwind/Run()
	var/datum/dq_lazy_memo_fixture/F = allocate(/datum/dq_lazy_memo_fixture)
	var/prior_pure = GLOB.op_pure_depth
	var/prior_output = GLOB.derived_evaluating
	F.set_mode(3)
	var/faulted = FALSE
	try
		memo_value(F, "result")
	catch(var/exception/fault)
		faulted = TRUE
	TEST_ASSERT(faulted, "computation fault did not propagate")
	TEST_ASSERT(!memo_cell_of(F, "result").evaluating && !memo_cell_of(F, "result").valid, "computation fault retained a partial cache or evaluating guard")
	var/cycled = FALSE
	try
		memo_value(F, "cycle")
	catch(var/exception/fault)
		cycled = TRUE
	TEST_ASSERT(cycled, "recursive memo did not reject its cycle")
	TEST_ASSERT_EQUAL(GLOB.op_pure_depth, prior_pure, "fault/cycle leaked purity depth")
	TEST_ASSERT_EQUAL(GLOB.derived_evaluating, prior_output, "fault/cycle leaked output depth")
	F.set_mode(0)
	TEST_ASSERT_EQUAL(memo_value(F, "cycle"), 1, "cycle guard prevented later valid computation")
	TEST_ASSERT_NULL(memo_value(F, "result"), "faulted cache could not recover")
	var/datum/memo_cell/result_cell = memo_cell_of(F, "result")
	var/datum/memo_cell/cycle_cell = memo_cell_of(F, "cycle")
	qdel(F)
	TEST_ASSERT(QDELETED(result_cell) && QDELETED(cycle_cell), "holder teardown left fault-recovered cells without custody")
	for(var/key in GLOB.memo_read_index)
		var/list/cells = GLOB.memo_read_index[key]
		TEST_ASSERT(!(result_cell in cells) && !(cycle_cell in cells), "fault-recovered cell left a field subscription after its owner died")
	for(var/key in GLOB.memo_lifetime_index)
		var/list/cells = GLOB.memo_lifetime_index[key]
		TEST_ASSERT(!(result_cell in cells) && !(cycle_cell in cells), "fault-recovered cell left a borrowed identity subscription after its owner died")

#endif
