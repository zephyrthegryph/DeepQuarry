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
// Poisoning (pool_set_poison(TRUE), off by default, for tests and debugging):
// a released object is marked POOL_STATE_POISONED and never handed out again,
// so a holder that kept it past its release sees POOL_ASSERT_LIVE crash instead
// of reading another taker's data.

/// Type -> its /datum/object_pool, created on first take.
GLOBAL_LIST_EMPTY(object_pools)
/// When TRUE, released objects are poisoned instead of recycled.
GLOBAL_VAR_INIT(pool_poison, FALSE)

/datum
	/// Pool bookkeeping: null for anything not pooled, else POOL_STATE_*.
	/// Unset on almost every datum, so it costs no per-instance memory.
	var/tmp/pool_state

/// TRUE for types declared with POOL_DECLARE.
/datum/proc/is_pooled()
	return FALSE

/// One per pooled type: the free list, the per-use fields and the counters.
/datum/object_pool
	var/pool_type
	/// Released objects waiting to be taken again. The pool owns them.
	var/list/free = list() // ALLOW(instance_list): one pool per pooled type (a handful per round), always used as the free list
	/// The type's DECLARE_REF(..., TRANSIENT) names, read once from the first instance.
	var/list/transient
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
			pool.transient = own_table_of(D).pool_reset_vars || list()
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
	pool.released++
	pool.out--
	if(GLOB.pool_poison)
		D.pool_state = POOL_STATE_POISONED
		pool.poisoned++
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
			"use_after_release" = pool.use_after_release,
			"refused_qdels" = pool.refused_qdels,
		)
