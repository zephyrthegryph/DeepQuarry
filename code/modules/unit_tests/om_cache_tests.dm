/datum/object_model/test_cached_entity
	var/base = 1
	var/other = 10
	var/computes = 0
	var/change_during_compute = FALSE

/datum/object_model/test_cached_entity/om_compute_cached(key)
	computes++
	switch(key)
		if("base")
			if(change_during_compute)
				change_during_compute = FALSE
				base++
				om_changed(src, "base")
			return base * 2
		if("other")
			return other
		if("sum")
			return base + other
		if("null")
			return null
		if("children")
			return length(om_children(src))
	return ..()

/datum/object_model/test_cached_entity/om_cache_channels(key)
	var/static/list/base_channels = list("base")
	var/static/list/other_channels = list("other")
	var/static/list/sum_channels = list("base", "other")
	var/static/list/children_channels = list("children")
	switch(key)
		if("base")
			return base_channels
		if("other")
			return other_channels
		if("sum")
			return sum_channels
		if("children")
			return children_channels
	return ..()

/datum/unit_test/om_cache_channels
	needs_test_block = FALSE

/datum/unit_test/om_cache_channels/Run()
	var/datum/object_model/test_cached_entity/S = new
	TEST_ASSERT_EQUAL(S.om_cached("base"), 2, "cold read computes")
	TEST_ASSERT_EQUAL(S.om_cached("base"), 2, "stable read hits cache")
	TEST_ASSERT_EQUAL(S.computes, 1, "one computation")
	TEST_ASSERT_NULL(S.om_cached("null"), "null result")
	TEST_ASSERT_NULL(S.om_cached("null"), "null cache hit")
	TEST_ASSERT_EQUAL(S.computes, 2, "null computed once")
	TEST_ASSERT_EQUAL(S.om_cached("other"), 10, "independent channel")
	S.base = 3
	om_changed(S, "base")
	TEST_ASSERT_EQUAL(S.om_cached("other"), 10, "other channel stays cached")
	TEST_ASSERT_EQUAL(S.computes, 3, "other did not recompute")
	TEST_ASSERT_EQUAL(S.om_cached("base"), 6, "base recomputes")
	om_changed(S)
	TEST_ASSERT_EQUAL(S.om_cached("other"), 10, "broad invalidation")
	TEST_ASSERT_EQUAL(S.computes, 5, "broad invalidation recomputes")
	om_cache_clear(S)
	TEST_ASSERT_EQUAL(S.om_cached("base"), 6, "explicit clear permits fresh read")
	qdel(S)

/datum/unit_test/om_cache_multiple_channels
	needs_test_block = FALSE

/datum/unit_test/om_cache_multiple_channels/Run()
	var/datum/object_model/test_cached_entity/S = new
	TEST_ASSERT_EQUAL(S.om_cached("sum"), 11, "two-input cold read")
	TEST_ASSERT_EQUAL(S.om_cached("sum"), 11, "stable hit")
	TEST_ASSERT_EQUAL(S.computes, 1, "computed once")
	S.other = 20
	om_changed(S, "other")
	TEST_ASSERT_EQUAL(S.om_cached("sum"), 21, "second dependency invalidates")
	S.base = 4
	om_changed(S, "base")
	TEST_ASSERT_EQUAL(S.om_cached("sum"), 24, "first dependency invalidates")
	TEST_ASSERT_EQUAL(S.computes, 3, "one recompute per mutation")
	qdel(S)

/datum/unit_test/om_cache_write_during_compute
	needs_test_block = FALSE

/datum/unit_test/om_cache_write_during_compute/Run()
	var/datum/object_model/test_cached_entity/S = new
	S.change_during_compute = TRUE
	TEST_ASSERT_EQUAL(S.om_cached("base"), 4, "write during compute retries")
	TEST_ASSERT_EQUAL(S.computes, 2, "unstable computation discarded")
	TEST_ASSERT_EQUAL(S.om_cached("base"), 4, "settled result cached")
	TEST_ASSERT_EQUAL(S.computes, 2, "settled read stayed cached")
	qdel(S)

/datum/unit_test/om_cache_ownership_invalidation
	needs_test_block = FALSE

/datum/unit_test/om_cache_ownership_invalidation/Run()
	var/datum/object_model/test_cached_entity/owner = new
	var/datum/object_model/test_cached_entity/child = new
	TEST_ASSERT_EQUAL(owner.om_cached("children"), 0, "empty owner")
	TEST_ASSERT(om_claim(owner, "om:test", child), "claim succeeds")
	TEST_ASSERT_EQUAL(owner.om_cached("children"), 1, "claim invalidates")
	TEST_ASSERT(om_release(child), "release succeeds")
	TEST_ASSERT_EQUAL(owner.om_cached("children"), 0, "release invalidates")
	TEST_ASSERT_EQUAL(owner.computes, 3, "one compute per ownership state")
	qdel(owner)
	qdel(child)

/datum/object_model/test_declared_cache
	var/amount = 2
	var/computes = 0

/datum/object_model/test_declared_cache/om_declare(datum/object_model/archetype/A)
	..()
	A.slot("children", /datum/object_model/test_declared_cache, 4, OM_SLOT_DELETE)
	A.cache(PROC_REF(compute_total), fields = list(NAMEOF(src, amount)), slots = list("children"), relations = list(/datum/object_model/test_cache_relation))

/datum/object_model/test_declared_cache/proc/compute_total()
	computes++
	return amount + length(om_children(src, "children")) + length(om_linked(src, /datum/object_model/test_cache_relation))

/datum/object_model/test_cache_relation
	parent_type = /datum/object_model/relation
	from_type = /datum/object_model/test_declared_cache
	to_type = /datum/object_model/test_declared_cache

/datum/unit_test/om_cache_declared_dependencies
	needs_test_block = FALSE

/datum/unit_test/om_cache_declared_dependencies/Run()
	var/datum/object_model/test_declared_cache/owner = new
	var/datum/object_model/test_declared_cache/child = new
	var/datum/object_model/test_declared_cache/peer = new
	TEST_ASSERT_EQUAL(owner.om_cached(TYPE_PROC_REF(/datum/object_model/test_declared_cache, compute_total)), 2, "declared cache computes")
	TEST_ASSERT_EQUAL(owner.om_cached(TYPE_PROC_REF(/datum/object_model/test_declared_cache, compute_total)), 2, "unchanged declared cache hits")
	TEST_ASSERT_EQUAL(owner.computes, 1, "declared cache computed once")
	owner.amount = 4
	om_field_changed(owner, NAMEOF(owner, amount))
	TEST_ASSERT_EQUAL(owner.om_cached(TYPE_PROC_REF(/datum/object_model/test_declared_cache, compute_total)), 4, "field notification invalidates")
	TEST_ASSERT(om_claim(owner, "children", child), "slot claim succeeds")
	TEST_ASSERT_EQUAL(owner.om_cached(TYPE_PROC_REF(/datum/object_model/test_declared_cache, compute_total)), 5, "slot mutation invalidates")
	TEST_ASSERT(om_link(owner, /datum/object_model/test_cache_relation, peer), "relation link succeeds")
	TEST_ASSERT_EQUAL(owner.om_cached(TYPE_PROC_REF(/datum/object_model/test_declared_cache, compute_total)), 6, "relation mutation invalidates")
	TEST_ASSERT_EQUAL(owner.computes, 4, "one compute per declared input change")
	qdel(owner)
	qdel(peer)

/datum/unit_test/om_cache_invalid_declaration
	needs_test_block = FALSE

/datum/unit_test/om_cache_invalid_declaration/Run()
	var/datum/object_model/archetype/A = new
	A.entity_type = /datum/object_model/test_declared_cache
	A.cache("missing_compute")
	A.cache("missing_compute")
	TEST_ASSERT(!A.validate(), "missing and duplicate cache computations reject declaration")
	TEST_ASSERT(length(A.errors) >= 2, "both invalid cases are diagnosed")
	qdel(A)
