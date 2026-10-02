// Object pools (doc/rewrite/lifecycle.md §4.1).
//
// A pooled type is declared once, next to the type:
//
//     POOL_DECLARE(/datum/damage_packet)
//     DECLARE_REF(/datum/damage_packet, "source", TRANSIENT, null)  (one line per field)
//
// Take one with pool_take(type), give it back with pool_release(obj) or
// obj.release(). Release resets every DECLARE_REF(..., TRANSIENT) field to its initial value
// from the declaration, so no hand-written clearing can forget a reference.
// Releasing twice crashes. Pooled objects refuse a normal qdel (POOL_DECLARE
// overrides Destroy()).
//
// The new form is /datum/pooled: a pooled type is a subtype of it and declares nothing.
//
//     /datum/damage_packet
//         parent_type = /datum/pooled
//         var/zone            (any var: it is reset to its initial value on release)
//         var/list/amounts    (a list New() allocates is kept and emptied, not replaced)
//
//     var/datum/damage_packet/P = take(/datum/damage_packet)
//     ... P.release()
//
// Release resets every field of the type to its initial value automatically (no per-field declaration
// to forget), then calls reset() for anything a field cannot express. pool_max_free caps how many free
// objects the type keeps; snapshot() lists the fields, so a test can prove a released object equals a
// fresh one. Poisoning is always on in test builds. tools/ci/pool_lint.py rejects `new` of a pooled
// type, and a take() whose file never releases.
//
// Poisoning (pool_set_poison(TRUE), off by default outside test builds, for tests and debugging):
// a released object is marked POOL_STATE_POISONED and never handed out again,
// so a holder that kept it past its release sees POOL_ASSERT_LIVE crash instead
// of reading another taker's data.

/// Type -> its /datum/object_pool, created on first take.
GLOBAL_LIST_EMPTY(object_pools)
/// When TRUE, released objects are poisoned instead of recycled.
#ifdef UNIT_TESTS
GLOBAL_VAR_INIT(pool_poison, TRUE)
#else
GLOBAL_VAR_INIT(pool_poison, FALSE)
#endif

/// How many released objects a pooled type keeps free unless it says pool_max_free.
#define POOL_DEFAULT_MAX_FREE 128

/datum
	/// Pool bookkeeping: null for anything not pooled, else POOL_STATE_*.
	/// Unset on almost every datum, so it costs no per-instance memory.
	var/tmp/pool_state

/// TRUE for types declared with POOL_DECLARE.
/datum/proc/is_pooled()
	return FALSE

/**
 * The base of a pooled type. A subtype's fields are reset to their initial values when it is released
 * (a list its New() allocated is kept and emptied), then reset() runs. It refuses a normal qdel.
 */
/datum/pooled
	/// How many released objects the type keeps free; a release past it destroys the object.
	var/pool_max_free = POOL_DEFAULT_MAX_FREE

/datum/pooled/is_pooled()
	return TRUE

/// Give this object back to its pool.
/datum/pooled/proc/release()
	pool_release(src)

/// A pooled object is only deleted by a forced qdel(); an unforced one is refused and counted.
/datum/pooled/lifecycle_keep(force)
	if(!force)
		pool_refused_qdel(src)
		return TRUE
	return ..()

/// Hook run at release, after every field went back to its initial value: anything a field can't say
/// (a registration, a cached appearance). Call ..() first.
/datum/pooled/proc/reset()
	return

/// name -> value of the fields a release resets (lists copied). Two snapshots are equal when the
/// objects are indistinguishable to their next taker.
/datum/pooled/proc/snapshot()
	. = list()
	var/list/plan = pool_reset_plan(src)
	for(var/name in plan)
		var/value = vars[name]
		.[name] = islist(value) ? json_encode(value) : value

/// The fields of a pooled datum a release resets: var name -> POOL_RESET_VALUE / POOL_RESET_LIST
/// (a list New() allocated). A list var keeps its list and gets the contents a fresh instance had (empty for one New()
/// allocates, the declared items for `var/list/x = list(1, 2)`: DM reports no compile-time initial for a list).
/// Built once per type from a fresh instance.
/proc/pool_reset_plan(datum/pooled/D)
	var/static/list/plans = list()
	var/list/plan = plans[D.type]
	if(plan)
		return plan
	plan = list()
	var/static/list/base_vars
	if(!base_vars)
		base_vars = list()
		var/datum/pooled/probe = new /datum/pooled
		for(var/name in probe.vars)
			base_vars[name] = TRUE
	for(var/name in D.vars)
		if(base_vars[name])
			continue
		var/current = D.vars[name]
		if(islist(current))
			plan[name] = POOL_RESET_LIST
			GLOB.pool_list_templates["[D.type]:[name]"] = pool_deep_copy(current)
		else
			plan[name] = POOL_RESET_VALUE
	plans[D.type] = plan
	return plan

/// type:var -> the list contents a fresh instance had (pool_reset_plan()).
GLOBAL_LIST_EMPTY(pool_list_templates)

/// A copy of `source` with nested lists copied too.
/proc/pool_deep_copy(list/source)
	. = list()
	for(var/key in source)
		var/value = isnum(key) ? null : source[key]
		if(islist(key))
			key = pool_deep_copy(key)
		if(isnull(value))
			. += list(key)
		else
			.[key] = islist(value) ? pool_deep_copy(value) : value

/// A pooled `type` ready to use: `take(/datum/damage_packet)`. Give it back with .release().
/proc/take(type)
	return pool_take(type)

/// One per pooled type: the free list, the per-use fields and the counters.
/datum/object_pool
	var/pool_type
	/// Released objects waiting to be taken again. The pool owns them.
	var/list/free = list() // ALLOW(instance_list): one pool per pooled type (a handful per round), always used as the free list
	/// The type's DECLARE_REF(..., TRANSIENT) names, read once from the first instance.
	var/list/transient
	/// From pool_reset_plan(), for a /datum/pooled type.
	var/list/plan
	var/max_free = POOL_DEFAULT_MAX_FREE
	var/dropped = 0
	var/created = 0
	var/taken = 0
	var/released = 0
	var/out = 0
	var/peak_out = 0
	var/double_releases = 0
	var/poisoned = 0
	var/use_after_release = 0
	var/refused_qdels = 0


/datum/object_pool/New(pool_type)
	src.pool_type = pool_type

/// The pool for `type`, created on first use. Null (with a crash) when `type`
/// isn't declared with POOL_DECLARE.
/proc/object_pool_for(type)
	var/datum/object_pool/pool = GLOB.object_pools[type]
	if(pool)
		return pool
	if(!ispath(type, /datum))
		CRASH("pool_take: [type] is not a datum type.")
	pool = new /datum/object_pool(type)
	GLOB.object_pools[type] = pool
	return pool

/// A clean object of pooled `type`: a released one when the pool has any,
/// else a new one. Give it back with pool_release().
/proc/pool_take(type)
	var/datum/object_pool/pool = object_pool_for(type)
	if(!pool)
		return null
	var/datum/D
	var/list/free = pool.free
	if(length(free))
		D = free[length(free)]
		free.len--
	else
		D = new type
		if(!D.is_pooled())
			CRASH("pool_take: [type] is not declared with POOL_DECLARE.")
		pool.created++
		if(isnull(pool.transient))
			// The table is a shared cache entry: the pool keeps its own copy.
			var/list/reset_names = own_table_of(D).pool_reset_vars
			pool.transient = reset_names ? reset_names.Copy() : list()
			if(istype(D, /datum/pooled))
				var/datum/pooled/P = D
				pool.plan = pool_reset_plan(P)
				pool.max_free = P.pool_max_free
	D.pool_state = POOL_STATE_TAKEN
	pool.taken++
	pool.out++
	if(pool.out > pool.peak_out)
		pool.peak_out = pool.out
	return D

/// Give `D` back: reset its DECLARE_REF(..., TRANSIENT) fields and put it in its pool (or
/// poison it). Releasing an object that isn't taken crashes.
/proc/pool_release(datum/D)
	if(!D)
		return
	var/datum/object_pool/pool = GLOB.object_pools[D.type]
	if(!pool || D.pool_state != POOL_STATE_TAKEN)
		if(pool)
			pool.double_releases++
		CRASH("pool_release: [D.type] released while not taken (state [isnull(D.pool_state) ? "unpooled" : D.pool_state]).")
	for(var/name in pool.transient)
		D.vars[name] = initial(D.vars[name]) // ALLOW(api): pool_release(): resets the DECLARE_REF(..., TRANSIENT) vars named by the declaration
	if(pool.plan)
		for(var/name in pool.plan)
			if(pool.plan[name] == POOL_RESET_LIST)
				var/list/kept = D.vars[name]
				if(kept)
					kept.Cut()
					kept += pool_deep_copy(GLOB.pool_list_templates["[D.type]:[name]"])
			else
				D.vars[name] = initial(D.vars[name]) // ALLOW(api): pool_release(): a /datum/pooled goes back to its declared initial values
		var/datum/pooled/P = D
		P.reset()
	pool.released++
	pool.out--
	if(GLOB.pool_poison)
		D.pool_state = POOL_STATE_POISONED
		pool.poisoned++
		return
	if(length(pool.free) >= pool.max_free)
		// Past the cap: the object is destroyed, not kept (and can't be used again).
		D.pool_state = POOL_STATE_POISONED
		pool.dropped++
		// ALLOW(lifecycle): the pool and the native watch table are the lifecycle owners for these objects and delete them directly
		qdel(D, TRUE)
		return
	D.pool_state = POOL_STATE_FREE
	pool.free += D

/// POOL_ASSERT_LIVE failed: `D` was used after its release.
/proc/pool_use_after_release(datum/D)
	var/datum/object_pool/pool = GLOB.object_pools[D.type]
	if(pool)
		pool.use_after_release++
	CRASH("Pooled [D.type] used after release (state [D.pool_state]).")

/// A pooled object was qdel'd without force: it stays alive (release it instead).
/proc/pool_refused_qdel(datum/D)
	var/datum/object_pool/pool = GLOB.object_pools[D.type]
	if(pool)
		pool.refused_qdels++
	if(D.pool_state == POOL_STATE_TAKEN)
		stack_trace("qdel() on a taken pooled [D.type]: release() it instead.")

/// Turn poisoning on or off. Returns the previous setting.
/proc/pool_set_poison(on)
	. = GLOB.pool_poison
	GLOB.pool_poison = !!on

/// Per pooled type: free, out, peak, created, taken, released and the error counts.
/proc/pool_diagnostics()
	. = list()
	for(var/type in GLOB.object_pools)
		var/datum/object_pool/pool = GLOB.object_pools[type]
		.["[type]"] = list(
			"free" = length(pool.free),
			"out" = pool.out,
			"peak_out" = pool.peak_out,
			"created" = pool.created,
			"taken" = pool.taken,
			"released" = pool.released,
			"double_releases" = pool.double_releases,
			"poisoned" = pool.poisoned,
			"dropped" = pool.dropped,
			"use_after_release" = pool.use_after_release,
			"refused_qdels" = pool.refused_qdels,
		)
