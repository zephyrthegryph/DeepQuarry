// Shared keyed caches: the miss path, invalidation, interning, LRU bounds, stats and the
// test-build mutation guard (doc/rewrite/caching.md; macros in code/__defines/shared_cache.dm).
//
// Global-init order is unspecified, so nothing here has an initializer that could run after
// a cache registered itself: the registry and the policy maps are created lazily.

/// Every declared cache, in declaration (global init) order.
SHARED_CACHE_GLOBAL(list/shared_cache_registry)
/// Event type (subtypes flattened) -> list of caches it clears. Null until a cache with an
/// SC_ON_EVENT policy builds its first entry.
SHARED_CACHE_GLOBAL(list/shared_cache_event_types)
/// Channel bits some active cache clears on when raised on GLOB.om_world.
SHARED_CACHE_GLOBAL(shared_cache_change_mask = 0)
/// Interned lists shared by every SC_INTERN cache: signature -> list.
SHARED_CACHE_GLOBAL(list/shared_cache_interned)

/datum/shared_cache
	/// The declared name (the store is the global `_scs_<name>`).
	var/name
	/// Proc path called on a miss.
	var/builder
	/// The SC_* policy list (null: SC_NEVER).
	var/list/policy
	/// 0: unbounded. Otherwise the young generation holds at most max_entries / 2 entries
	/// before it becomes the old one (approximate LRU: a hit in the old generation promotes).
	var/max_entries = 0
	var/flags = 0
	/// The store (the same list as the global `_scs_<name>`; resolved on first use).
	var/list/store
	/// Previous generation (bounded caches only).
	var/list/old
	/// key -> list(value) for built values that are falsy (the fast path cannot hold them).
	var/list/falsy
	var/misses = 0
	var/builds = 0
	var/evictions = 0
	var/invalidations = 0
	/// Hits counted by the test-build guarded path (the release path counts in `_sch_<name>`).
	var/guard_lookups = 0
	/// Policy hooks registered (done on the first build, when GLOB exists).
	var/active = FALSE
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	/// key -> copy of the value as built, for the mutation guard.
	var/list/snapshots
	/// Mutations caught (tests assert zero).
	var/mutations = 0
#endif

/datum/shared_cache/New(name, builder, policy, max_entries, flags)
	src.name = name
	src.builder = builder
	src.policy = policy
	src.max_entries = max_entries
	src.flags = flags
	if(!shared_cache_registry)
		shared_cache_registry = list()
	shared_cache_registry += src

/datum/shared_cache/proc/resolve_store()
	store = global.vars["_scs_[name]"]
	if(!islist(store))
		store = list()
		global.vars["_scs_[name]"] = store // ALLOW(api): the framework binds its own declared store global by name
	return store

/// Registers the invalidation policy (lazy: nothing needs invalidating before the first build).
/datum/shared_cache/proc/activate()
	active = TRUE
	if(!length(policy))
		return
	switch(policy[1])
		if("event")
			if(!shared_cache_event_types)
				shared_cache_event_types = list()
			for(var/path in typesof(policy[2]))
				LAZYADD(shared_cache_event_types[path], src)
		if("change")
			shared_cache_change_mask |= policy[2]
			var/datum/W = GLOB.om_world
			W?.om_listen |= policy[2]

/// Builds and stores the value for `key`. Extra arguments go to the builder instead of the key.
/datum/shared_cache/proc/miss(key, ...)
	if(!store)
		resolve_store()
	misses++
	var/list/boxed = falsy?[key]
	if(boxed)
		return boxed[1]
	if(old)
		var/aged = old[key]
		if(aged)
			old -= key
			put(key, aged)
			return aged
	if(!active)
		activate()
	var/value = (length(args) > 1) ? call(builder)(arglist(args.Copy(2))) : call(builder)(key)
	builds++
	if(!value)
		LAZYSET(falsy, key, list(value))
		return value
	if((flags & SC_INTERN) && islist(value))
		value = shared_cache_intern(value)
	put(key, value)
	return value

/datum/shared_cache/proc/put(key, value)
	if(max_entries && length(store) >= max(1, round(max_entries / 2)))
		evictions += length(old)
		old = store.Copy()
		store.Cut()
	store[key] = value
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	if(islist(value))
		var/list/L = value
		LAZYSET(snapshots, key, L.Copy())
#endif

/// Integer-keyed miss (SC_INT_KEYS): the store is a flat list grown to fit.
/datum/shared_cache/proc/miss_int(index)
	if(!store)
		resolve_store()
	if(!isnum(index) || index < 1 || index != round(index))
		CRASH("shared cache [name]: CACHED_INT key must be a positive integer, got [index]")
	misses++
	if(index <= length(store) && !isnull(store[index]))
		return store[index]
	if(!active)
		activate()
	var/value = call(builder)(index)
	builds++
	if(index > length(store))
		store.len = index
	if((flags & SC_INTERN) && islist(value))
		value = shared_cache_intern(value)
	store[index] = value
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	if(islist(value))
		var/list/L = value
		LAZYSET(snapshots, "[index]", L.Copy())
#endif
	return value

/// Drops every entry (a version bump). The store list is kept, so the fast path needs no rebind.
/datum/shared_cache/proc/invalidate()
	if(!store)
		resolve_store()
	invalidations++
	store.Cut()
	old = null
	falsy = null
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	snapshots = null
#endif

/datum/shared_cache/proc/entry_count()
	return length(store) + length(old) + length(falsy)

/// Hits, or null when this build doesn't count them (release without -DSHARED_CACHE_STATS).
/datum/shared_cache/proc/hits()
#if defined(SHARED_CACHE_STATS) || defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	var/lookups = global.vars["_sch_[name]"] + guard_lookups
	return max(lookups - misses, 0)
#else
	return null
#endif

/// Rough bytes: 24 per entry plus the contents of up to 64 sampled values, scaled.
/datum/shared_cache/proc/approx_bytes()
	if(!store)
		resolve_store()
	var/n = entry_count()
	if(!n)
		return 0
	var/sampled = 0
	var/sample_bytes = 0
	for(var/key in store)
		if(sampled >= 64)
			break
		var/value = (flags & SC_INT_KEYS) ? key : store[key]
		sampled++
		sample_bytes += shared_cache_value_bytes(value)
	var/per = sampled ? sample_bytes / sampled : 0
	return round(n * (24 + per))

/proc/shared_cache_value_bytes(value)
	if(islist(value))
		var/list/L = value
		return 16 + length(L) * 24
	if(istext(value))
		return length(value) + 16
	if(isicon(value))
		return 512
	if(isdatum(value) || istype(value, /image) || istype(value, /mutable_appearance))
		return 64
	return 8

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/// Test-build CACHED(): a miss as usual, a hit verified against the build-time snapshot.
/datum/shared_cache/proc/guarded(key, ...)
	if(!store)
		resolve_store()
	if(isnum(key))
		CRASH("shared cache [name]: numeric key [key] (use CACHED_INT or a text key)")
	guard_lookups++
	var/value = store[key]
	if(!value)
		return (length(args) > 1) ? miss(arglist(args)) : miss(key)
	verify(key, value)
	return value

/datum/shared_cache/proc/guarded_int(index)
	if(!store)
		resolve_store()
	guard_lookups++
	if(isnum(index) && index >= 1 && index <= length(store) && !isnull(store[index]))
		var/value = store[index]
		verify("[index]", value)
		return value
	return miss_int(index)

/// Runtimes when a caller wrote into a shared list, then restores the entry so later
/// callers still see the built value.
/datum/shared_cache/proc/verify(key, value)
	if(!islist(value))
		return
	var/list/snap = snapshots?[key]
	if(!snap)
		return
	var/list/L = value
	if(L ~= snap)
		return
	mutations++
	L.Cut()
	for(var/i in 1 to length(snap))
		var/k = snap[i]
		L += list(k)
		if(!isnum(k) && !isnull(snap[k]))
			L[k] = snap[k]
	CRASH("shared cache [name]: a caller mutated the shared list for key [key]; Copy() a cached value before writing")

/// Verifies every stored list (the unit-test sweep at the end of a run).
/datum/shared_cache/proc/verify_all()
	. = 0
	for(var/key in snapshots)
		var/list/snap = snapshots[key]
		var/list/L = (flags & SC_INT_KEYS) ? store[text2num(key)] : store[key]
		if(islist(L) && !(L ~= snap))
			.++
#endif

/// Returns the interned instance of list L (primitives, types and datums by ref).
/proc/shared_cache_intern(list/L)
	var/list/parts = list()
	for(var/k in L)
		var/v = isnum(k) ? null : L[k]
		parts += "[istext(k) ? "t" : ""][isdatum(k) ? ref(k) : k]=[isdatum(v) ? ref(v) : v]"
	var/sig = jointext(parts, ";")
	if(!shared_cache_interned)
		shared_cache_interned = list()
	var/list/existing = shared_cache_interned[sig]
	if(existing)
		return existing
	shared_cache_interned[sig] = L
	return L

// ---- OM hooks (called from om_wants/om_emit/om_dispatch_change) ----

/proc/shared_cache_on_event(etype)
	for(var/datum/shared_cache/C as anything in shared_cache_event_types[etype])
		C.invalidate()

/proc/shared_cache_on_world_change(bits)
	for(var/datum/shared_cache/C as anything in shared_cache_registry)
		if(C.active && length(C.policy) && C.policy[1] == "change" && (C.policy[2] & bits))
			C.invalidate()

/// Rows for the OM profiler panel.
/proc/shared_cache_stats()
	. = list()
	for(var/datum/shared_cache/C as anything in shared_cache_registry)
		var/hits = C.hits()
		var/lookups = isnull(hits) ? 0 : hits + C.misses
		var/policy_text = "never"
		if(length(C.policy))
			policy_text = C.policy[1] == "explicit" ? "explicit" : "[C.policy[1]] [C.policy[2]]"
		. += list(list(
			"name" = C.name,
			"hits" = hits,
			"misses" = C.misses,
			"hit_rate" = lookups ? round(hits * 100 / lookups, 0.1) : 0,
			"entries" = C.entry_count(),
			"max_entries" = C.max_entries,
			"evictions" = C.evictions,
			"invalidations" = C.invalidations,
			"kb" = round(C.approx_bytes() / 1024, 0.1),
			"policy" = policy_text,
		))
