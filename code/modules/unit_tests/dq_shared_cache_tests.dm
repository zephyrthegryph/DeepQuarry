// Shared keyed caches (doc/rewrite/caching.md).

/datum/om/event/shared_cache_test

GLOBAL_VAR_INIT(sc_test_builds, 0)

/proc/sc_test_build(key)
	GLOB.sc_test_builds++
	return list("key" = key, "n" = GLOB.sc_test_builds)

/proc/sc_test_build_pair(a, b)
	GLOB.sc_test_builds++
	return list(a, b)

/proc/sc_test_build_int(i)
	GLOB.sc_test_builds++
	return list(i * 2)

/proc/sc_test_build_falsy(key)
	GLOB.sc_test_builds++
	return 0

/proc/sc_test_build_same(key)
	return list("a", "b")

DECLARE_SHARED_CACHE(sc_test_plain, GLOBAL_PROC_REF(sc_test_build), SC_NEVER)
DECLARE_SHARED_CACHE(sc_test_pair, GLOBAL_PROC_REF(sc_test_build_pair), SC_EXPLICIT)
DECLARE_SHARED_CACHE_EX(sc_test_int, GLOBAL_PROC_REF(sc_test_build_int), SC_NEVER, 0, SC_INT_KEYS)
DECLARE_SHARED_CACHE(sc_test_falsy, GLOBAL_PROC_REF(sc_test_build_falsy), SC_NEVER)
DECLARE_SHARED_CACHE(sc_test_event, GLOBAL_PROC_REF(sc_test_build), SC_ON_EVENT(/datum/om/event/shared_cache_test))
DECLARE_SHARED_CACHE(sc_test_change, GLOBAL_PROC_REF(sc_test_build), SC_ON_WORLD_CHANGE(CHANGE_DATUM_D))
DECLARE_SHARED_CACHE_EX(sc_test_lru, GLOBAL_PROC_REF(sc_test_build), SC_NEVER, 4, 0)
DECLARE_SHARED_CACHE_EX(sc_test_intern, GLOBAL_PROC_REF(sc_test_build_same), SC_NEVER, 0, SC_INTERN)

/// Builds once per key, shares the value, and counts hits and misses.
/datum/unit_test/dq_shared_cache_basic

/datum/unit_test/dq_shared_cache_basic/Run()
	INVALIDATE_SHARED_CACHE(sc_test_plain)
	var/before = GLOB.sc_test_builds
	var/list/a = CACHED(sc_test_plain, "x")
	var/list/b = CACHED(sc_test_plain, "x")
	TEST_ASSERT(a == b, "a hit returns the same shared instance")
	TEST_ASSERT_EQUAL(GLOB.sc_test_builds - before, 1, "built once")
	TEST_ASSERT_EQUAL(a["key"], "x", "the builder gets the key")
	var/datum/shared_cache/C = SHARED_CACHE(sc_test_plain)
	TEST_ASSERT(C.hits() >= 1, "a hit is counted")
	TEST_ASSERT(C.misses >= 1, "a miss is counted")
	TEST_ASSERT_EQUAL(C.entry_count(), 1, "one entry")
	var/list/p = CACHED2(sc_test_pair, "k", 7)
	TEST_ASSERT_EQUAL(p[2], 7, "multi-key builders get their arguments")
	TEST_ASSERT(CACHED2(sc_test_pair, "k", 7) == p, "and hit on the joined key")
	INVALIDATE_SHARED_CACHE(sc_test_pair)
	TEST_ASSERT(CACHED2(sc_test_pair, "k", 7) != p, "an explicit bump rebuilds")
	var/list/i = CACHED_INT(sc_test_int, 5)
	TEST_ASSERT_EQUAL(i[1], 10, "integer keys")
	TEST_ASSERT(CACHED_INT(sc_test_int, 5) == i, "hit on integer keys")
	before = GLOB.sc_test_builds
	CACHED(sc_test_falsy, "z")
	CACHED(sc_test_falsy, "z")
	TEST_ASSERT_EQUAL(GLOB.sc_test_builds - before, 1, "a falsy value is built once too")

/// Event and channel policies clear the cache.
/datum/unit_test/dq_shared_cache_invalidation

/datum/unit_test/dq_shared_cache_invalidation/Run()
	var/list/e = CACHED(sc_test_event, "e")
	TEST_ASSERT(om_wants(GLOB.om_world, /datum/om/event/shared_cache_test), "an invalidating event is wanted on the world")
	om_emit(GLOB.om_world, new /datum/om/event/shared_cache_test)
	TEST_ASSERT(CACHED(sc_test_event, "e") != e, "the event cleared the cache")
	var/list/c = CACHED(sc_test_change, "c")
	TEST_ASSERT(CACHED(sc_test_change, "c") == c, "cached")
	om_changed(GLOB.om_world, CHANGE_DATUM_D)
	TEST_ASSERT(CACHED(sc_test_change, "c") != c, "the world channel cleared the cache")

/// Bounded caches evict, interning shares identical lists, and a mutation is caught.
/datum/unit_test/dq_shared_cache_bounds_guard

/datum/unit_test/dq_shared_cache_bounds_guard/Run()
	var/datum/shared_cache/L = SHARED_CACHE(sc_test_lru)
	for(var/k in 1 to 20)
		CACHED(sc_test_lru, "k[k]")
	TEST_ASSERT(L.entry_count() <= 4, "a bounded cache holds at most max_entries ([L.entry_count()])")
	TEST_ASSERT(L.evictions > 0, "and evicts")
	var/list/recent = CACHED(sc_test_lru, "k20")
	TEST_ASSERT(CACHED(sc_test_lru, "k20") == recent, "a recent key survives")
	TEST_ASSERT(CACHED(sc_test_intern, "one") == CACHED(sc_test_intern, "two"), "identical lists are interned")
	var/datum/shared_cache/P = SHARED_CACHE(sc_test_plain)
	var/list/v = CACHED(sc_test_plain, "guard")
	v["key"] = "mutated"
	var/caught = FALSE
	try
		CACHED(sc_test_plain, "guard")
	catch // ALLOW(silent_catch): the test expects this runtime and asserts on it
		caught = TRUE
	TEST_ASSERT(caught, "writing into a shared list runtimes on the next hit")
	TEST_ASSERT_EQUAL(v["key"], "guard", "and the entry is restored")
	P.mutations = 0

/// No cache in the build holds a mutated list at the end of the run.
/datum/unit_test/dq_shared_cache_sweep

/datum/unit_test/dq_shared_cache_sweep/Run()
	for(var/datum/shared_cache/C as anything in shared_cache_registry)
		TEST_ASSERT_EQUAL(C.verify_all(), 0, "cache [C.name] holds no mutated list")
		TEST_ASSERT_EQUAL(C.mutations, 0, "cache [C.name] caught no mutation")
