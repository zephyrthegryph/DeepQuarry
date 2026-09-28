// Shared cache lookup cost against a hand-rolled `var/static/list/cache` (doc/rewrite/caching.md).
// Each arm does the same lookups over a warm key set; the fast path is the release CACHED().
//   tools/build/build.sh bench --scenario=shared_cache [--arg lookups=2000000]

/proc/sc_bench_build(key)
	return list(key)

/proc/sc_bench_build_int(i)
	return list(i)

DECLARE_SHARED_CACHE(sc_bench, GLOBAL_PROC_REF(sc_bench_build), SC_NEVER)
DECLARE_SHARED_CACHE_EX(sc_bench_int, GLOBAL_PROC_REF(sc_bench_build_int), SC_NEVER, 0, SC_INT_KEYS)

/proc/sc_bench_static(key)
	var/static/list/cache = list() // ALLOW(cache): the hand-rolled baseline the benchmark compares against
	var/value = cache[key]
	if(!value)
		value = cache[key] = sc_bench_build(key)
	return value

/datum/benchmark/shared_cache
	id = "shared_cache"
	description = "DECLARE_SHARED_CACHE lookups vs a hand-rolled static list"

/datum/benchmark/shared_cache/Run()
	var/n = param("lookups", 2000000)
	var/list/keys = list()
	for(var/i in 1 to 64)
		keys += "key[i]"
	for(var/k in keys)
		sc_bench_static(k)
		CACHED_FAST(sc_bench, k)
	var/v
	// Inline static list (what most hand-rolled caches are: a lookup and a fallback in place).
	var/static/list/inline = list() // ALLOW(cache): benchmark baseline
	for(var/k in keys)
		inline[k] = list(k)
	var/start = TICK_USAGE
	for(var/i in 1 to n)
		var/k = keys[(i & 63) + 1]
		v = inline[k] || (inline[k] = list(k))
	var/inline_ms = TICK_USAGE_TO_MS(start)
	start = TICK_USAGE
	for(var/i in 1 to n)
		v = sc_bench_static(keys[(i & 63) + 1])
	var/proc_ms = TICK_USAGE_TO_MS(start)
	start = TICK_USAGE
	for(var/i in 1 to n)
		var/k = keys[(i & 63) + 1]
		v = CACHED_FAST(sc_bench, k)
	var/fast_ms = TICK_USAGE_TO_MS(start)
	start = TICK_USAGE
	for(var/i in 1 to n)
		var/k = keys[(i & 63) + 1]
		v = CACHED_COUNTED(sc_bench, k)
	var/counted_ms = TICK_USAGE_TO_MS(start)
	start = TICK_USAGE
	for(var/i in 1 to n)
		v = CACHED_INT_FAST(sc_bench_int, (i & 63) + 1)
	var/int_ms = TICK_USAGE_TO_MS(start)
	start = TICK_USAGE
	for(var/i in 1 to n)
		var/k = keys[(i & 63) + 1]
		v = CACHED(sc_bench, k)
	var/guarded_ms = TICK_USAGE_TO_MS(start)
	if(!v)
		fail("no value")
	metric("shared_cache_static_inline_ns", inline_ms * 1e6 / n, "ns")
	metric("shared_cache_static_proc_ns", proc_ms * 1e6 / n, "ns")
	metric("shared_cache_cached_ns", fast_ms * 1e6 / n, "ns")
	metric("shared_cache_cached_counted_ns", counted_ms * 1e6 / n, "ns")
	metric("shared_cache_cached_int_ns", int_ms * 1e6 / n, "ns")
	metric("shared_cache_test_guarded_ns", guarded_ms * 1e6 / n, "ns")
	metric("shared_cache_ratio_vs_inline", inline_ms ? fast_ms / inline_ms : 0, "x")
