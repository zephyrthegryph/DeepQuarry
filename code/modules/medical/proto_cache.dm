// Shared proto cache.
//
// The book builder, audit tests, and surgery registry all need to read
// instance vars off every subtype of /datum/medical_issue/condition,
// /datum/medical_symptom, and /datum/dq_surgery — `name`, `cured_by`,
// `audiences`, etc. DM's `initial()` only reads scalars off compile-time
// defaults and can't see list literals from outside the type, so the
// idiom historically has been `var/proto = new T(); ...; qdel(proto)`.
//
// That allocates and frees once per subtype per call site, every time
// the call site fires. For the book — rendered each time a player opens
// the encyclopedia — that's ~80 allocations on every read.
//
// This file caches one instance per subtype for the lifetime of the
// world. Callers get the cached proto via dq_proto(T) and must not
// mutate it. The cache is keyed by typepath so subtypes added at
// runtime (admin spawn?) work as expected.

GLOBAL_LIST_EMPTY(dq_proto_cache)
GLOBAL_PROTECT(dq_proto_cache)

/// Return a long-lived prototype instance of the given /datum typepath.
/// Useful for reading instance-default vars (`name`, list literals,
/// etc) without paying for an alloc+free on every call. NEVER mutate
/// the returned proto — it is shared across every caller.
/proc/dq_proto(typepath)
	if(!typepath)
		return null
	var/cached = GLOB.dq_proto_cache[typepath]
	if(cached)
		return cached
	cached = new typepath()
	GLOB.dq_proto_cache[typepath] = cached
	return cached
