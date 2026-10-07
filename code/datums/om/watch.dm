// Gas wake helper for the machine pipeline (doc/rewrite/object_model_core.md, code/game/machinery/machine_pipeline.dm).
//
// What is left of the old gas-watch family, kept only for the machines still on the pipeline. Everything else sleeps on the engine forms:
// gas_watch() / gas_watch_many() (every change of a part of the gas, code/domains/atmos/gas_watch.dm) and gas_level() (a tracked var that
// turns when a reading crosses a level, code/domains/atmos/gas_level.dm; doc/rewrite/framework_gaps.md F5). The two flavours below go with
// the machine pipeline (F7): a firedoor's signature (om_watch_arm_value()) and an airlock sensor's eligibility rule (om_watch_arm_condition()).
//
// A watch is keyed by an arbitrary (entity, watch_id) pair. Delivery rides one native gas watch per mixture (Rust-owned, code/datums/om/native.dm),
// which carries the union of the interest masks armed on it; its owner (/datum/om_gas_watch_hub) hands each record to om_watch_dispatch_gas().
//
//  - om_watch_arm_value(): fires whenever a caller-supplied getter's return value differs from what it returned last time a matching gas
//    notification arrived (a firedoor's signature of its neighbours' pressure and temperature).
//  - om_watch_arm_condition(): a boolean `condition` re-evaluated on a matching notification; the watch fires on one that finds it TRUE.
//
// A fire calls the watch's `wake_callback` (if any) and then, if `channel` is set, changed(entity, channel), which is all an OM-pipeline
// machine needs to reschedule itself.

#define OM_WATCH_VALUE 3
#define OM_WATCH_CONDITION 6

/// Per-entity, per-watch_id watch state.
/datum/om_watch
	var/entity_ref
	var/watch_id // the key this watch is registered under on its entity (arbitrary string)
	var/channel // optional CHANGE_MACHINE_*/CHANGE_MOB_* bit: a fire raises changed(entity, channel)
	var/list/wake_callback // optional om_callable() spec: run (no args) on every fire, before changed
	var/mode = OM_WATCH_VALUE
	var/list/mixture_ids // every mixture this watch is indexed on
	var/interest_mask = GAS_DEPENDENCY_ALL // change-mask filter
	var/list/value_getter // om_callable() spec. OM_WATCH_VALUE: () -> comparable value; OM_WATCH_CONDITION: () -> boolean
	var/last_value // OM_WATCH_VALUE: the last value observed

// ---------------------------------------------------------------- registries

/// Every armed watch, keyed by "[REF(entity)]" -> (watch_id -> /datum/om_watch). Not a var on
/// the watching type: any datum with an OM handle can arm a watch.
GLOBAL_LIST_EMPTY(om_watch_registry)

/// Reverse index for gas-driven watches: "[mixture_id]" -> list of /datum/om_watch, so
/// om_watch_dispatch_gas() (called from SSmachines.wake_dirty_gas_subscribers()) doesn't have
/// to walk every watch in the registry for every dirty mixture.
GLOBAL_LIST_EMPTY(om_gas_watches_by_mixture)

/// The registry key of `entity`'s watches: its OM handle ("id:gen"), which arming allocates (the watch's
/// entity_ref) and which still names it while it is being deleted (om_handle_of()); null for an entity that
/// never had one, so never armed anything. Not its \ref text: a datum's first \ref string is a new
/// string, and at boot, with every machine's first wake arming in one pass, making one cost a millisecond
/// or more (HE pipes were half a second of that pass on Southern Cross).
/proc/om_watch_entity_key(datum/entity)
	return om_handle_of(entity)

/// Whether `entity` currently has watch_id armed (or, with watch_id omitted, anything armed at
/// all) -- the generic "is this thing asleep on a gas watch" check tests want, in place of the
/// deleted SSmachines.sleeping_gas_devices table.
/proc/om_watch_armed(datum/entity, watch_id)
	var/list/entity_watches = GLOB.om_watch_registry[om_watch_entity_key(entity)]
	if(!entity_watches)
		return FALSE
	if(isnull(watch_id))
		return length(entity_watches) > 0
	return !isnull(entity_watches[watch_id])

/// Adds/replaces `W` in the per-mixture reverse index and (re)arms the underlying Rust watch
/// with the union of every armed watch's interest mask on that mixture.
/proc/om_watch_index_gas(datum/om_watch/W, mixture_id)
	if(isnull(mixture_id) || (mixture_id in W.mixture_ids))
		return
	LAZYADD(W.mixture_ids, mixture_id)
	var/key = "[mixture_id]"
	var/list/L = GLOB.om_gas_watches_by_mixture[key]
	if(!L)
		L = list()
		GLOB.om_gas_watches_by_mixture[key] = L
	L += W
	om_watch_count_interest(key, W.interest_contribution(), 1)
	om_watch_republish_mixture(mixture_id)

/proc/om_watch_unindex_gas(datum/om_watch/W)
	for(var/mixture_id in W.mixture_ids)
		var/key = "[mixture_id]"
		var/list/L = GLOB.om_gas_watches_by_mixture[key]
		if(!L)
			continue
		L -= W
		om_watch_count_interest(key, W.interest_contribution(), -1)
		if(!length(L))
			om_watch_drop_mixture(key)
		else
			om_watch_republish_mixture(mixture_id)
	W.mixture_ids = null

/// The last watch on mixture `key` left: its index entry and native watch go.
/proc/om_watch_drop_mixture(key)
	GLOB.om_gas_watches_by_mixture -= key
	GLOB.om_gas_watch_interest_counts -= key
	var/datum/native_watch/gas/native = GLOB.om_gas_native_watches[key]
	GLOB.om_gas_native_watches -= key
	spent(native)

/// The gas fields this watch needs its mixture's native watch to report.
/datum/om_watch/proc/interest_contribution()
	return interest_mask

/// "[mixture_id]" -> how many of its watches want each gas field (pressure, temperature, composition), so
/// the union of their interests is known without walking them: a pipeline's mixture carries a watch per
/// pipe, and every pipe re-arming its watch rescanned all of them (quadratic over a whole map's pipes).
GLOBAL_LIST_EMPTY(om_gas_watch_interest_counts)

/// Adds `delta` to the counts of each gas field in `mask` on mixture `key`.
/proc/om_watch_count_interest(key, mask, delta)
	var/list/counts = GLOB.om_gas_watch_interest_counts[key]
	if(!counts)
		counts = list(0, 0, 0)
		GLOB.om_gas_watch_interest_counts[key] = counts
	if(mask & GAS_DEPENDENCY_PRESSURE)
		counts[1] += delta
	if(mask & GAS_DEPENDENCY_TEMPERATURE)
		counts[2] += delta
	if(mask & GAS_DEPENDENCY_COMPOSITION)
		counts[3] += delta

/// Recomputes and (re)publishes the aggregate interest mask Rust should watch a mixture for:
/// the union of every watch currently armed on it, from om_gas_watch_interest_counts. One native gas watch per mixture
/// (code/datums/om/native.dm) carries the aggregate; its wakes fan out through
/// om_watch_dispatch_gas().
/proc/om_watch_republish_mixture(mixture_id)
	var/key = "[mixture_id]"
	var/list/L = GLOB.om_gas_watches_by_mixture[key]
	if(!length(L))
		return
	var/list/counts = GLOB.om_gas_watch_interest_counts[key]
	var/aggregate_mask = NONE
	if(counts)
		if(counts[1] > 0)
			aggregate_mask |= GAS_DEPENDENCY_PRESSURE
		if(counts[2] > 0)
			aggregate_mask |= GAS_DEPENDENCY_TEMPERATURE
		if(counts[3] > 0)
			aggregate_mask |= GAS_DEPENDENCY_COMPOSITION
	var/datum/native_watch/gas/native = GLOB.om_gas_native_watches[key]
	if(native && !QDELETED(native))
		if(native.mask == aggregate_mask)
			return
		native.unregister()
		native.mask = aggregate_mask
		native.register()
		return
	native = gas_dependency_watch(om_gas_watch_hub(), mixture_id, aggregate_mask, TYPE_PROC_REF(/datum/om_gas_watch_hub, on_gas))
	if(native)
		GLOB.om_gas_native_watches[key] = native

/// "[mixture_id]" -> the one native gas watch carrying that mixture's aggregate interest mask.
GLOBAL_LIST_EMPTY(om_gas_native_watches)

/// Owner of the per-mixture native gas watches: hands each wake to the OM watches on it.
/datum/om_gas_watch_hub

/proc/om_gas_watch_hub()
	var/static/datum/om_gas_watch_hub/hub
	if(!hub)
		hub = new
	return hub

/datum/om_gas_watch_hub/proc/on_gas(datum/native_watch/gas/watch, mixture_id, change_mask, list/observation, observation_index)
	om_watch_dispatch_gas(mixture_id, change_mask, observation, observation_index)

/proc/om_watch_register(datum/om_watch/W)
	// The watch's entity_ref is its entity's handle: the registry key (om_watch_entity_key()).
	var/key = W.entity_ref
	if(!key)
		return
	var/list/entity_watches = GLOB.om_watch_registry[key]
	if(!entity_watches)
		entity_watches = list()
		GLOB.om_watch_registry[key] = entity_watches
	entity_watches[W.watch_id] = W

// ---------------------------------------------------------------- arming

/// Arms a "wake when this computed value changes" watch on a gas mixture: `getter` is invoked
/// with no args whenever a matching gas notification arrives, and a crossing fires if the
/// return value differs from what it returned last time (air_alarm's TLV-signature check
/// generalized).
/proc/om_watch_arm_value(datum/entity, watch_id, mixture_id, interest_mask = GAS_DEPENDENCY_ALL, list/getter, channel, list/wake_callback, current_value)
	om_watch_disarm(entity, watch_id)
	if(isnull(mixture_id))
		return null
	var/datum/om_watch/W = new
	W.entity_ref = om_handle(entity)
	W.watch_id = watch_id
	W.channel = channel
	W.wake_callback = wake_callback
	W.mode = OM_WATCH_VALUE
	W.interest_mask = interest_mask
	W.value_getter = getter
	// `current_value`: the getter's value now, when the caller has it (several watches sharing one getter).
	W.last_value = isnull(current_value) ? om_run(getter) : current_value
	om_watch_register(W)
	om_watch_index_gas(W, mixture_id)
	return W

/// "Wake me only when I can act": a boolean `condition` getter re-evaluated whenever any of
/// `mixture_ids` publishes a change in `interest_mask`; the watch fires on a notification that
/// finds it TRUE. Level-triggered on purpose: a device that went to sleep while the condition
/// already held by its own coarser test (a network's settle residual) must still wake on the
/// next change rather than wait for a FALSE-to-TRUE edge that may never come. Each wake callback
/// disarms the watch, so one change wakes a device at most once. This is how a device states
/// its own eligibility rule (enough moles, a pressure delta past its deadband, a temperature
/// past its thermostat) instead of waking on every revision and deciding afterwards.
/proc/om_watch_arm_condition(datum/entity, watch_id, list/mixture_ids, interest_mask, list/condition, channel, list/wake_callback)
	om_watch_disarm(entity, watch_id)
	var/datum/om_watch/W = new
	W.entity_ref = om_handle(entity)
	W.watch_id = watch_id
	W.channel = channel
	W.wake_callback = wake_callback
	W.mode = OM_WATCH_CONDITION
	W.value_getter = condition
	W.interest_mask = interest_mask
	om_watch_register(W)
	for(var/mixture_id in mixture_ids)
		om_watch_index_gas(W, mixture_id)
	return W

/proc/om_watch_disarm(datum/entity, watch_id)
	var/key = om_watch_entity_key(entity)
	var/list/entity_watches = GLOB.om_watch_registry[key]
	if(!entity_watches)
		return
	var/datum/om_watch/W = entity_watches[watch_id]
	if(!W)
		return
	entity_watches -= watch_id
	if(!length(entity_watches))
		GLOB.om_watch_registry -= key
	om_watch_unindex_gas(W)

/proc/om_watch_disarm_all(datum/entity)
	var/key = om_watch_entity_key(entity)
	var/list/entity_watches = GLOB.om_watch_registry[key]
	if(!entity_watches)
		return
	for(var/watch_id in entity_watches.Copy())
		om_watch_disarm(entity, watch_id)

/// Force-fires every watch an entity currently has armed, regardless of what its bands/revision
/// say -- for a caller that knows something changed independent of the gas transport (a moved
/// device, a topology change) and just wants to wake now. A no-op if nothing is armed (the
/// entity is already awake/running).
/proc/om_watch_fire_all(datum/entity)
	var/list/entity_watches = GLOB.om_watch_registry[om_watch_entity_key(entity)]
	if(!entity_watches)
		return
	for(var/watch_id in entity_watches.Copy())
		var/datum/om_watch/W = entity_watches[watch_id]
		if(W)
			om_watch_fire(W, entity)

// ---------------------------------------------------------------- dispatch

/proc/om_watch_fire(datum/om_watch/W, datum/entity)
	SSmachines.gas_woken_last++
	if(istype(entity, /obj/machinery))
		var/obj/machinery/M = entity
		M.gas_dependency_wake_count++
	if(W.wake_callback)
		om_run(W.wake_callback)
	if(W.channel)
		native_changed(entity, W.channel, NATIVE_SRC_GAS_WATCH)

/// Called from SSmachines.wake_dirty_gas_subscribers() (code/controllers/subsystems/machines.dm)
/// for every dirty mixture Rust reports. Walks every watch armed on that mixture and fires the
/// ones whose mode says this notification is actionable.
/proc/om_watch_dispatch_gas(mixture_id, change_mask, list/observation, observation_index)
	var/list/L = GLOB.om_gas_watches_by_mixture["[mixture_id]"]
	if(!length(L))
		return
	for(var/datum/om_watch/W as anything in L.Copy())
		var/datum/entity = om_resolve(W.entity_ref)
		SSmachines.current_gas_wake_subscribers++
		if(!entity)
			SSmachines.gas_dead_last++
			om_watch_unindex_gas(W) // stale: the watching object is gone, drop it
			continue
		switch(W.mode)
			if(OM_WATCH_VALUE)
				if(!(change_mask & W.interest_mask))
					continue
				var/current_value = om_run(W.value_getter)
				if(current_value != W.last_value)
					W.last_value = current_value
					om_watch_fire(W, entity)
			if(OM_WATCH_CONDITION)
				if((change_mask & W.interest_mask) && om_run(W.value_getter))
					om_watch_fire(W, entity)
