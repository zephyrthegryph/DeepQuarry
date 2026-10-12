#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// These fixtures publish actual registered endpoint keys, never legacy masks.
/datum/dq_edge_native_source
	var/ready = TRUE
	var/keep_link = TRUE
	var/left = 1
	var/right = 1
	var/ready_notifications = 0
	var/unlinks = 0
	var/inside_batch_linked = FALSE
	var/datum/dq_edge_native_policy/policy
	var/datum/relation_edge/setup_edge
	var/datum/dq_edge_native_target/setup_target
TRACKED(/datum/dq_edge_native_source, ready)
TRACKED(/datum/dq_edge_native_source, keep_link)
TRACKED(/datum/dq_edge_native_source, left)
TRACKED(/datum/dq_edge_native_source, right)
CAPABILITIES(/datum/dq_edge_native_source)
	ref_one(nameof(policy), /datum/dq_edge_native_policy)
	on_change(nameof(ready), ANY, then(PROC_REF(ready_changed)))
/datum/dq_edge_native_source/proc/ready_changed(datum/act/A)
	ready_notifications++
/datum/dq_edge_native_source/proc/whole_snapshot(datum/dq_edge_native_target/T)
	set_left(2)
	// Even an explicit drain cannot expose the incomplete publication batch.
	test_drain()
	inside_batch_linked = !!link_of(src, /datum/relation_definition/dq_edge_native)
	set_right(2)
	T.set_right(2)
/datum/dq_edge_native_source/proc/whole_snapshot_and_disable(datum/dq_edge_native_target/T)
	set_left(3)
	test_drain()
	set_right(3)
	T.set_right(3)
	T.set_ready(FALSE)

/// Instrument the real effect callback, never the pure requirements.
/datum/relation_edge_read_scope/dq_delivery_counter
	var/deliveries = 0
/datum/relation_edge_read_scope/dq_delivery_counter/inputs_changed(datum/producer, list/keys)
	deliveries++
	return ..()

/datum/dq_edge_native_target
	var/ready = TRUE
	var/keep_link = TRUE
	var/right = 1
TRACKED(/datum/dq_edge_native_target, ready)
TRACKED(/datum/dq_edge_native_target, keep_link)
TRACKED(/datum/dq_edge_native_target, right)

/datum/dq_edge_native_policy
	var/ready = TRUE
TRACKED(/datum/dq_edge_native_policy, ready)

/datum/requirement_definition/dq_edge_native_active/endpoint_reason(datum/act/eval/endpoint_query/A)
	var/datum/dq_edge_native_source/S = A.source
	var/datum/dq_edge_native_target/T = A.target
	return (S.ready && T.ready) ? null : "Endpoint inactive"

/datum/requirement_definition/dq_edge_native_hold/endpoint_reason(datum/act/eval/endpoint_query/A)
	var/datum/dq_edge_native_source/S = A.source
	var/datum/dq_edge_native_target/T = A.target
	return (S.keep_link && T.keep_link && S.left == S.right && S.right == T.right) ? null : "Endpoint cannot retain link"
// Observe the actual native producer key, without a computed cross-object getter.
/datum/relation_edge/dq_native_observed
	var/active_notifications = 0
CAPABILITIES(/datum/relation_edge/dq_native_observed)
	on_change(nameof(active), ANY, then(PROC_REF(active_changed)))
/datum/relation_edge/dq_native_observed/proc/active_changed(datum/act/A)
	active_notifications++
/datum/relation_definition/dq_edge_native/make_edge()
	return new /datum/relation_edge/dq_native_observed

/datum/relation_definition/dq_edge_native
	source_single = TRUE
	conflict = OM_REL_REPLACE
	active_if = /datum/requirement_definition/dq_edge_native_active
	holds_while = /datum/requirement_definition/dq_edge_native_hold
/datum/relation_definition/dq_edge_native/with_policy
	active_if = /datum/requirement_definition/dq_edge_native_policy_active
/datum/requirement_definition/dq_edge_native_policy_active/endpoint_reason(datum/act/eval/endpoint_query/A)
	var/datum/dq_edge_native_source/S = A.source
	var/datum/dq_edge_native_target/T = A.target
	return (S.ready && T.ready && S.policy && S.policy.ready) ? null : "Policy unavailable"

/datum/requirement_definition/dq_edge_native_fault/endpoint_reason(datum/act/eval/endpoint_query/A)
	CRASH("Intentional endpoint query fault exercises native lease cleanup")

// Deliberately lacks endpoint_reason: old callbacks must not become static native queries.
/datum/requirement_definition/dq_edge_native_missing/why_not(datum/actor, datum/target)
	return null

/datum/requirement_definition/dq_edge_native_source_only/endpoint_reason(datum/act/eval/endpoint_query/A)
	var/datum/dq_edge_native_source/S = A.source
	return S.ready ? null : "Source unavailable"
/datum/requirement_definition/dq_edge_native_target_only/endpoint_reason(datum/act/eval/endpoint_query/A)
	var/datum/dq_edge_native_target/T = A.target
	return T.ready ? null : "Target unavailable"

/datum/relation_definition/dq_edge_native/with_view
	source_view = "setup_target"

/datum/relation_definition/dq_edge_native/with_fault
	source_view = "setup_target"
	active_if = /datum/requirement_definition/dq_edge_native_fault
/datum/relation_definition/dq_edge_native/with_fault/on_link(datum/source, datum/target, datum/relation_edge/edge)
	var/datum/dq_edge_native_source/S = source
	S.setup_edge = edge

/datum/relation_definition/dq_edge_native/on_unlink(datum/source, datum/target, datum/relation_edge/edge)
	var/datum/dq_edge_native_source/S = source
	S.unlinks++

/datum/unit_test/dq_relation_edge_native
	abstract_type = /datum/unit_test/dq_relation_edge_native
/datum/unit_test/dq_relation_edge_native/proc/begin_fixture()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))

/datum/unit_test/dq_relation_edge_native/endpoint_keys/Run()
	begin_fixture()
	var/datum/dq_edge_native_source/S = allocate(/datum/dq_edge_native_source)
	var/datum/dq_edge_native_target/T = allocate(/datum/dq_edge_native_target)
	var/datum/relation_edge/dq_native_observed/E = relation_link(S, T, /datum/relation_definition/dq_edge_native)
	TEST_ASSERT(istype(E), "The actual graph must establish a real edge")
	TEST_ASSERT(E.active, "Both ready endpoints initially activate the edge")
	TEST_ASSERT_NOTNULL(E.read_scope, "The graph edge must own a real native dependency scope")
	TEST_ASSERT_EQUAL(length(E.read_scope.watching), 2, "Actual keys must group into exactly the two endpoint producers")
	TEST_ASSERT((S in E.read_scope.dependency_sources) && (T in E.read_scope.dependency_sources), "The scope must track both actual endpoint lifetimes")
	test_drain()
	var/before_active = E.active_notifications
	var/before = S.ready_notifications
	TEST_ASSERT(S.set_ready(FALSE), "A real source mutation must change its registered field")
	test_drain()
	TEST_ASSERT(!E.active, "The source's native key must deactivate the existing edge")
	TEST_ASSERT_EQUAL(E.active_notifications, before_active + 1, "An actual active-state flip must publish to its real observer")
	TEST_ASSERT_EQUAL(link_of(S, /datum/relation_definition/dq_edge_native), T, "Active refusal must not unlink a held edge")
	TEST_ASSERT_EQUAL(S.ready_notifications, before + 1, "The real source key publishes once")
	TEST_ASSERT(!S.set_ready(FALSE), "An unchanged setter must be a genuine no-op")
	test_drain()
	TEST_ASSERT_EQUAL(S.ready_notifications, before + 1, "An unchanged value must not republish its key")
	T.set_ready(FALSE)
	test_drain()
	TEST_ASSERT(!E.active, "An independent input mutation may preserve the same inactive result")
	TEST_ASSERT_EQUAL(E.active_notifications, before_active + 1, "An unchanged predicate result must not republish active state")
	T.set_ready(TRUE)
	test_drain()
	TEST_ASSERT_EQUAL(E.active_notifications, before_active + 1, "Still-inactive re-evaluation must not notify the active observer")
	S.set_ready(TRUE)
	test_drain()
	TEST_ASSERT(E.active, "Source recovery must reactivate the edge")
	TEST_ASSERT_EQUAL(E.active_notifications, before_active + 2, "Actual recovery must publish its active-state change")
	T.set_ready(FALSE)
	test_drain()
	TEST_ASSERT(!E.active, "The target's independent native key must deactivate the edge")
	T.set_ready(TRUE)
	test_drain()
	TEST_ASSERT(E.active, "Target recovery must reactivate the same edge")

/datum/unit_test/dq_relation_edge_native/hold_and_atomic_snapshot/Run()
	begin_fixture()
	var/datum/dq_edge_native_source/S = allocate(/datum/dq_edge_native_source)
	var/datum/dq_edge_native_target/T = allocate(/datum/dq_edge_native_target)
	var/datum/relation_edge/dq_native_observed/E = relation_link(S, T, /datum/relation_definition/dq_edge_native)
	TEST_ASSERT(istype(E) && E.active, "The initial complete snapshot must permit a real edge")
	test_drain()
	state_batch(S, TYPE_PROC_REF(/datum/dq_edge_native_source, whole_snapshot), list(T))
	test_drain()
	TEST_ASSERT(S.inside_batch_linked, "Even a forced drain must not unlink on an incomplete native publication snapshot")
	TEST_ASSERT_EQUAL(link_of(S, /datum/relation_definition/dq_edge_native), T, "A permitted complete snapshot must retain the edge")
	TEST_ASSERT(E.active, "A complete permitted snapshot remains active")
	TEST_ASSERT_EQUAL(S.unlinks, 0, "No transient refusal may run unlink consequences")
	var/datum/relation_edge_read_scope/scope = E.read_scope
	T.set_keep_link(FALSE)
	test_drain()
	TEST_ASSERT_NULL(link_of(S, /datum/relation_definition/dq_edge_native), "The target's real holds_while key must unlink the graph edge")
	TEST_ASSERT(QDELETED(scope), "A real refusal must retire its owned dependency scope")
	TEST_ASSERT_EQUAL(length(scope.watching), 0, "A refused edge must leave no native key bindings")
	TEST_ASSERT_EQUAL(S.unlinks, 1, "A real refusal runs exactly one unlink consequence")
	TEST_ASSERT_NULL(E.source, "The unlinked edge must clear its old source")
	TEST_ASSERT_NULL(E.target, "The unlinked edge must clear its old target")

/datum/unit_test/dq_relation_edge_native/replacement_rebinds/Run()
	begin_fixture()
	var/datum/dq_edge_native_source/S = allocate(/datum/dq_edge_native_source)
	var/datum/dq_edge_native_target/old_target = allocate(/datum/dq_edge_native_target)
	var/datum/dq_edge_native_target/new_target = allocate(/datum/dq_edge_native_target)
	var/datum/relation_edge/old_edge = relation_link(S, old_target, /datum/relation_definition/dq_edge_native)
	TEST_ASSERT(istype(old_edge) && old_edge.active, "The first real edge must be established")
	var/datum/relation_edge_read_scope/old_scope = old_edge.read_scope
	TEST_ASSERT_NOTNULL(old_scope, "The original edge must have actual dependency bindings")
	var/datum/relation_edge/new_edge = relation_link(S, new_target, /datum/relation_definition/dq_edge_native)
	TEST_ASSERT(istype(new_edge) && new_edge != old_edge, "Single-source replacement must create a distinct graph edge")
	TEST_ASSERT(QDELETED(old_scope), "Replacement must destroy the original owned dependency scope")
	TEST_ASSERT_EQUAL(length(old_scope.watching), 0, "Replacement must release old native key bindings")
	TEST_ASSERT(new_edge.read_scope && new_edge.read_scope != old_scope, "Replacement must bind a fresh dependency scope")
	TEST_ASSERT(!(old_target in new_edge.read_scope.dependency_sources), "The replacement scope must not retain the detached target")
	TEST_ASSERT_NULL(old_edge.source, "Replacement must detach the original source")
	TEST_ASSERT_NULL(old_edge.target, "Replacement must detach the original target")
	TEST_ASSERT_EQUAL(link_of(S, /datum/relation_definition/dq_edge_native), new_target, "The graph must name the replacement target")
	old_target.set_ready(FALSE)
	old_target.set_keep_link(FALSE)
	qdel(old_target)
	test_drain()
	TEST_ASSERT(new_edge.active, "Changes and deletion of the detached target must not affect the replacement edge")
	TEST_ASSERT_EQUAL(link_of(S, /datum/relation_definition/dq_edge_native), new_target, "Detached target teardown must not unlink the replacement")
	new_target.set_ready(FALSE)
	test_drain()
	TEST_ASSERT(!new_edge.active, "The newly bound target must still control activation")
	new_target.set_keep_link(FALSE)
	test_drain()
	TEST_ASSERT_NULL(link_of(S, /datum/relation_definition/dq_edge_native), "The newly bound target must still control holds_while")
	TEST_ASSERT_EQUAL(S.unlinks, 2, "Replacement and final refusal each run their own consequence once")

/datum/unit_test/dq_relation_edge_native/endpoint_teardown/Run()
	begin_fixture()
	var/datum/dq_edge_native_source/S = allocate(/datum/dq_edge_native_source)
	var/datum/dq_edge_native_target/T = allocate(/datum/dq_edge_native_target)
	var/datum/relation_edge/dq_native_observed/E = relation_link(S, T, /datum/relation_definition/dq_edge_native)
	TEST_ASSERT(istype(E) && E.active, "Target teardown fixture must establish an active edge")
	var/datum/relation_edge_read_scope/target_scope = E.read_scope
	TEST_ASSERT_NOTNULL(target_scope, "Target teardown fixture must have native dependency bindings")
	qdel(T)
	test_drain()
	TEST_ASSERT_NULL(link_of(S, /datum/relation_definition/dq_edge_native), "Deleting the actual target must unlink its graph edge")
	TEST_ASSERT_EQUAL(S.unlinks, 1, "Target deletion must run one unlink consequence")
	TEST_ASSERT(QDELETED(target_scope), "Target deletion must retire its actual native binding scope")
	TEST_ASSERT_EQUAL(length(target_scope.watching), 0, "Target deletion leaves no native key bindings")
	TEST_ASSERT_NULL(E.source, "Target deletion clears the old edge source")
	TEST_ASSERT_NULL(E.target, "Target deletion clears the old edge target")
	S.set_ready(FALSE)
	S.set_keep_link(FALSE)
	test_drain()
	TEST_ASSERT_EQUAL(S.unlinks, 1, "Later source mutations must not deliver a detached edge again")
	var/datum/dq_edge_native_source/other_source = allocate(/datum/dq_edge_native_source)
	var/datum/dq_edge_native_target/other_target = allocate(/datum/dq_edge_native_target)
	E = relation_link(other_source, other_target, /datum/relation_definition/dq_edge_native)
	TEST_ASSERT(istype(E) && E.active, "Source teardown fixture must establish an active edge")
	var/datum/relation_edge_read_scope/source_scope = E.read_scope
	TEST_ASSERT_NOTNULL(source_scope, "Source teardown fixture must have native dependency bindings")
	qdel(other_source)
	test_drain()
	TEST_ASSERT_EQUAL(length(linked_to(other_target, /datum/relation_definition/dq_edge_native)), 0, "Deleting the actual source removes the target's incoming edge")
	TEST_ASSERT(QDELETED(source_scope), "Source deletion must retire its actual native binding scope")
	TEST_ASSERT_EQUAL(length(source_scope.watching), 0, "Source deletion leaves no native key bindings")
	TEST_ASSERT_NULL(E.source, "Source deletion clears the old edge source")
	TEST_ASSERT_NULL(E.target, "Source deletion clears the old edge target")
	other_target.set_ready(FALSE)
	other_target.set_keep_link(FALSE)
	test_drain()
	TEST_ASSERT_EQUAL(length(linked_to(other_target, /datum/relation_definition/dq_edge_native)), 0, "Later target mutations must not resurrect a detached edge")

/datum/unit_test/dq_relation_edge_native/third_party_policy/Run()
	begin_fixture()
	var/datum/dq_edge_native_source/S = allocate(/datum/dq_edge_native_source)
	var/datum/dq_edge_native_target/T = allocate(/datum/dq_edge_native_target)
	var/datum/dq_edge_native_policy/old_policy = allocate(/datum/dq_edge_native_policy)
	var/datum/dq_edge_native_policy/new_policy = allocate(/datum/dq_edge_native_policy)
	rel_set(S, nameof(S.policy), old_policy)
	var/datum/relation_edge/dq_native_observed/E = relation_link(S, T, /datum/relation_definition/dq_edge_native/with_policy)
	TEST_ASSERT(istype(E) && E.active, "An actual third-party policy must permit the real edge")
	TEST_ASSERT(old_policy in E.read_scope.dependency_sources, "The scope must bind the actual policy producer lifetime")
	old_policy.set_ready(FALSE)
	test_drain()
	TEST_ASSERT(!E.active, "The actual third-party key must deactivate the edge")
	rel_set(S, nameof(S.policy), new_policy)
	test_drain()
	TEST_ASSERT(E.active, "Retargeting the actual relation key must activate from the new policy")
	TEST_ASSERT(!(old_policy in E.read_scope.dependency_sources) && (new_policy in E.read_scope.dependency_sources), "Rebinding must stop retaining the old policy producer")
	old_policy.set_ready(TRUE)
	old_policy.set_ready(FALSE)
	qdel(old_policy)
	test_drain()
	TEST_ASSERT(E.active, "Detached policy mutation and deletion must not change the retargeted edge")
	qdel(new_policy)
	test_drain()
	TEST_ASSERT_NULL(S.policy, "The actual borrowed policy view must clear its deleted producer")
	TEST_ASSERT(!E.active, "Deleting a current third-party dependency must re-evaluate its refusal")
	TEST_ASSERT_EQUAL(link_of(S, /datum/relation_definition/dq_edge_native/with_policy), T, "Active policy refusal must not unlink a still-held edge")
	TEST_ASSERT_EQUAL(length(E.read_scope.dependency_sources), 2, "A deleted policy must leave only live endpoint dependencies")

/datum/unit_test/dq_relation_edge_native/multiple_producer_deliveries/Run()
	begin_fixture()
	var/datum/dq_edge_native_source/S = allocate(/datum/dq_edge_native_source)
	var/datum/dq_edge_native_target/T = allocate(/datum/dq_edge_native_target)
	var/datum/relation_edge/dq_native_observed/E = relation_link(S, T, /datum/relation_definition/dq_edge_native)
	TEST_ASSERT(istype(E) && E.active, "The actual graph must establish a permitted edge")
	var/datum/relation_edge_read_scope/original = E.read_scope
	var/datum/relation_edge_read_scope/dq_delivery_counter/probe = allocate(/datum/relation_edge_read_scope/dq_delivery_counter)
	rel_set(E, nameof(E.read_scope), probe)
	rel_set(probe, nameof(probe.edge), E)
	relation_edge_refresh(E)
	test_drain()
	TEST_ASSERT(QDELETED(original), "Replacing the owned scope must release the actual old bindings")
	TEST_ASSERT_EQUAL(length(probe.watching), 2, "The actual counter scope must bind exactly the two producer groups")
	var/before = probe.deliveries
	var/before_active = E.active_notifications
	state_batch(S, TYPE_PROC_REF(/datum/dq_edge_native_source, whole_snapshot), list(T))
	test_drain()
	TEST_ASSERT_EQUAL(probe.deliveries, before + 2, "Two producer groups deliver two real callbacks, coalescing each producer's changed keys")
	TEST_ASSERT(E.active, "Both callbacks must evaluate the same complete permitted snapshot")
	TEST_ASSERT_EQUAL(E.active_notifications, before_active, "Re-evaluating an unchanged result must not publish active state")
	TEST_ASSERT_EQUAL(S.unlinks, 0, "A partial snapshot must never run unlink consequences")
	before = probe.deliveries
	before_active = E.active_notifications
	state_batch(S, TYPE_PROC_REF(/datum/dq_edge_native_source, whole_snapshot_and_disable), list(T))
	test_drain()
	TEST_ASSERT_EQUAL(probe.deliveries, before + 2, "Multiple changed keys on each endpoint still coalesce per producer/listener")
	TEST_ASSERT(!E.active, "Both callbacks must evaluate the same complete inactive snapshot")
	TEST_ASSERT_EQUAL(E.active_notifications, before_active + 1, "The two complete evaluations produce only the one actual active-state flip")
	TEST_ASSERT_EQUAL(link_of(S, /datum/relation_definition/dq_edge_native), T, "Inactive snapshots must retain a still-held edge")
	TEST_ASSERT_EQUAL(S.unlinks, 0, "Completed inactive snapshots must not invent a holds_while refusal")

/datum/unit_test/dq_relation_edge_native/query_fault_cleanup/Run()
	begin_fixture()
	// Use production recycling semantics, scoped back to the test default afterward.
	set_global(nameof(GLOB.pool_poison), FALSE)
	var/datum/dq_edge_native_source/S = allocate(/datum/dq_edge_native_source)
	var/datum/dq_edge_native_target/T = allocate(/datum/dq_edge_native_target)
	var/datum/relation_edge/dq_native_observed/E = relation_link(S, T, /datum/relation_definition/dq_edge_native)
	TEST_ASSERT(istype(E) && E.active, "The fault fixture must first establish a real permitted edge")
	test_drain()
	var/datum/requirement_definition/fault_requirement = definition_check_get(/datum/requirement_definition/dq_edge_native_fault)
	var/datum/object_pool/pool = object_pool_for(/datum/act/eval/endpoint_query)
	var/before_out = pool.out
	var/before_taken = pool.taken
	var/before_released = pool.released
	var/before_pure = GLOB.op_pure_depth
	S.set_ready(FALSE)
	var/crashed = FALSE
	try
		fault_requirement.endpoint_query(S, T, list())
	catch
		crashed = TRUE
	TEST_ASSERT(crashed, "A real endpoint callback failure must reach the caller")
	TEST_ASSERT(pool.taken > before_taken, "The crashing callback must actually lease an endpoint query context")
	TEST_ASSERT_EQUAL(pool.taken - before_taken, pool.released - before_released, "Every callback context lease must be released on the fault path")
	TEST_ASSERT_EQUAL(pool.out, before_out, "A callback fault must leave no additional outstanding leases")
	TEST_ASSERT_EQUAL(GLOB.op_pure_depth, before_pure, "The callback failure must restore the surrounding purity guard")
	// Inspect a newly leased context, never retain or escape the callback's pooled A.
	var/datum/act/eval/endpoint_query/fresh = pool_take(/datum/act/eval/endpoint_query)
	var/clean_source = isnull(fresh.source)
	var/clean_target = isnull(fresh.target)
	fresh.release()
	TEST_ASSERT(clean_source && clean_target, "Recycled endpoint contexts must reset both generic endpoint fields")
	TEST_ASSERT_EQUAL(pool.out, before_out, "The reset inspection must release its own lease too")
	S.set_ready(TRUE)
	test_drain()
	TEST_ASSERT(E.active, "Recovery after the query fault must evaluate the same real edge normally")
	T.set_ready(FALSE)
	// Recover before draining the deliberate fault condition; exercise a normal refresh afterward.
	T.set_ready(TRUE)
	relation_edge_refresh(E)
	test_drain()
	TEST_ASSERT(E.active, "Subsequent native refreshes must remain usable after fault cleanup")

/datum/unit_test/dq_relation_edge_native/missing_descriptor/Run()
	begin_fixture()
	var/datum/dq_edge_native_source/S = allocate(/datum/dq_edge_native_source)
	var/datum/dq_edge_native_target/T = allocate(/datum/dq_edge_native_target)
	var/datum/requirement_definition/R = definition_check_get(/datum/requirement_definition/dq_edge_native_missing)
	TEST_ASSERT_NULL(R.why_not(S, T), "The legacy-only fixture really permits its old callback")
	var/crashed = FALSE
	try
		R.endpoint_query(S, T, list())
	catch
		crashed = TRUE
	TEST_ASSERT(crashed, "A missing generated endpoint implementation must fail closed, never silently become static")

/datum/unit_test/dq_relation_edge_native/composition/Run()
	begin_fixture()
	var/datum/dq_edge_native_source/S = allocate(/datum/dq_edge_native_source)
	var/datum/dq_edge_native_target/T = allocate(/datum/dq_edge_native_target)
	var/datum/requirement_definition/all = definition_check_get(list("all", /datum/requirement_definition/dq_edge_native_source_only, /datum/requirement_definition/dq_edge_native_target_only))
	var/datum/requirement_definition/any = definition_check_get(list("any", /datum/requirement_definition/dq_edge_native_source_only, /datum/requirement_definition/dq_edge_native_target_only))
	var/datum/requirement_definition/inverse = definition_check_get(list("not", /datum/requirement_definition/dq_edge_native_source_only))
	S.set_ready(FALSE)
	T.set_ready(FALSE)
	var/list/pairs = list()
	TEST_ASSERT_EQUAL(all.endpoint_query(S, T, pairs), "Source unavailable", "All must preserve the first refusal's declared order")
	TEST_ASSERT_EQUAL(length(pairs), 2, "All must collect both actual dependency producers despite the first refusal")
	TEST_ASSERT(pairs[1][1] == S && pairs[2][1] == T, "The automatic dependency union must contain the real source and target")
	pairs = list()
	TEST_ASSERT_EQUAL(any.endpoint_query(S, T, pairs), "Source unavailable", "Any must preserve the first refusal when every part refuses")
	TEST_ASSERT_EQUAL(length(pairs), 2, "Any must collect every refusing part's actual dependency")
	TEST_ASSERT_NULL(inverse.endpoint_query(S, T, list()), "Not must allow when its real child refuses")
	S.set_ready(TRUE)
	pairs = list()
	TEST_ASSERT_NULL(any.endpoint_query(S, T, pairs), "Any must allow when its first child allows")
	TEST_ASSERT_EQUAL(length(pairs), 2, "A permitting first child must not short-circuit later dependency discovery")
	TEST_ASSERT_EQUAL(all.endpoint_query(S, T, list()), "Target unavailable", "All must return the remaining target refusal")
	TEST_ASSERT_EQUAL(inverse.endpoint_query(S, T, list()), "not allowed", "Not must refuse when its child allows")
	T.set_ready(TRUE)
	TEST_ASSERT_NULL(all.endpoint_query(S, T, list()), "All must permit the complete ready endpoint snapshot")
	var/datum/requirement_definition/combinator/empty = allocate(/datum/requirement_definition/combinator)
	empty.op = "any"
	TEST_ASSERT_NULL(empty.endpoint_query(S, T, list()), "Empty any must preserve the legacy null result without indexing a missing row")
	test_drain()

/datum/unit_test/dq_relation_edge_native/setup_fault_cleanup/Run()
	begin_fixture()
	var/datum/dq_edge_native_source/S = allocate(/datum/dq_edge_native_source)
	var/datum/dq_edge_native_target/T = allocate(/datum/dq_edge_native_target)
	var/datum/scheduler_record/source_record = scheduler_record_of(S)
	var/datum/scheduler_record/target_record = scheduler_record_of(T)
	test_drain()
	var/source_listeners = length(S.rx?.listeners)
	var/target_listeners = length(T.rx?.listeners)
	var/primary_fault = FALSE
	try
		relation_link(S, T, /datum/relation_definition/dq_edge_native/with_fault)
	catch(var/exception/fault)
		primary_fault = findtext("[fault]", "Intentional endpoint query fault") > 0
	TEST_ASSERT(primary_fault, "Link setup must rethrow the original endpoint fault, never a cleanup error")
	TEST_ASSERT_NULL(link_of(S, /datum/relation_definition/dq_edge_native/with_fault), "Failed setup must remove the source graph membership")
	TEST_ASSERT_EQUAL(length(linked_to(T, /datum/relation_definition/dq_edge_native/with_fault)), 0, "Failed setup must remove the target graph membership")
	TEST_ASSERT_NULL(S.setup_target, "Failed setup must clear the actual source relation view")
	TEST_ASSERT_EQUAL(length(source_record.edges), 0, "Failed setup leaves no source record edge")
	TEST_ASSERT_EQUAL(length(target_record.edges), 0, "Failed setup leaves no target record edge")
	var/datum/relation_edge/failed = S.setup_edge
	TEST_ASSERT_NOTNULL(failed, "The actual setup hook must witness the allocated edge before the failure")
	TEST_ASSERT_NULL(failed.source, "The failed edge must detach its source")
	TEST_ASSERT_NULL(failed.target, "The failed edge must detach its target")
	TEST_ASSERT_NULL(failed.read_scope, "Failed setup must release its owned native dependency scope")
	test_drain()
	TEST_ASSERT_EQUAL(length(S.rx?.listeners), source_listeners, "Failed setup must leave no source observer bindings")
	TEST_ASSERT_EQUAL(length(T.rx?.listeners), target_listeners, "Failed setup must leave no target observer bindings")
	S.set_ready(FALSE)
	T.set_ready(FALSE)
	test_drain()
	TEST_ASSERT_NULL(link_of(S, /datum/relation_definition/dq_edge_native/with_fault), "Later native publications must not resurrect failed setup")
	S.setup_edge = null

/datum/unit_test/dq_relation_edge_native/initial_hold_refusal/Run()
	begin_fixture()
	var/datum/dq_edge_native_source/S = allocate(/datum/dq_edge_native_source)
	var/datum/dq_edge_native_target/T = allocate(/datum/dq_edge_native_target)
	T.set_keep_link(FALSE)
	test_drain()
	var/datum/scheduler_record/source_record = scheduler_record_of(S)
	var/datum/scheduler_record/target_record = scheduler_record_of(T)
	var/source_listeners = length(S.rx?.listeners)
	var/target_listeners = length(T.rx?.listeners)
	var/datum/relation_edge/dq_native_observed/E = relation_link(S, T, /datum/relation_definition/dq_edge_native/with_view)
	TEST_ASSERT(istype(E), "Initial holds refusal preserves the public edge-shaped return")
	TEST_ASSERT_NULL(E.source, "The refused initial edge must already detach its source")
	TEST_ASSERT_NULL(E.target, "The refused initial edge must already detach its target")
	TEST_ASSERT_NULL(E.read_scope, "Initial refusal releases its owned dependency scope")
	TEST_ASSERT_NULL(S.setup_target, "Initial refusal clears the real source relation view")
	TEST_ASSERT_NULL(E.cache, "Initial refusal leaves no edge contribution cache")
	TEST_ASSERT(!E.active, "A refused initial edge must not contribute active state")
	TEST_ASSERT_NULL(link_of(S, /datum/relation_definition/dq_edge_native/with_view), "An initially refused edge is not linked")
	TEST_ASSERT_EQUAL(length(linked_to(T, /datum/relation_definition/dq_edge_native/with_view)), 0, "An initial refusal leaves no incoming graph membership")
	TEST_ASSERT_EQUAL(length(source_record.edges), 0, "An initial refusal leaves no source record membership")
	TEST_ASSERT_EQUAL(length(target_record.edges), 0, "An initial refusal leaves no target record membership")
	TEST_ASSERT_EQUAL(S.unlinks, 1, "Initial refusal must run exactly one genuine unlink consequence")
	test_drain()
	TEST_ASSERT_EQUAL(length(S.rx?.listeners), source_listeners, "Initial refusal leaves no source native binding")
	TEST_ASSERT_EQUAL(length(T.rx?.listeners), target_listeners, "Initial refusal leaves no target native binding")
	T.set_keep_link(TRUE)
	test_drain()
	TEST_ASSERT_NULL(link_of(S, /datum/relation_definition/dq_edge_native/with_view), "Recovery must not resurrect an initially refused detached edge")
	TEST_ASSERT_EQUAL(S.unlinks, 1, "Recovery must not repeat a detached edge's consequence")

#endif
