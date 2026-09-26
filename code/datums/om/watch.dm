// Generic threshold/change watch helper for OM-pipeline machines and any other datum
// (doc/rewrite/object_model_core.md, code/game/machinery/machine_pipeline.dm).
//
// This is the *only* gas-dependency transport left in the codebase (SSmachines'
// subscribe_gas_dependency()/unsubscribe_gas_dependency()/gas_dependency_changed()/
// hibernate_air_alarm() and the sleeping_mixture_* bookkeeping they drove are gone --
// see doc history on the rewrite/om-atmos-machines branch). Every caller that used to
// hand-roll a "subscribe to a mixture, compare a cached revision/signature, decide
// whether to wake" pattern now arms one of the watch flavours below instead, keyed by an
// arbitrary (entity, watch_id) pair -- no `om_watches` var needed on the watching type,
// so this works for /obj/machinery, /datum/material_service, pipes, doors, generators,
// anything with a weak reference.
//
// Delivery for a gas-backed watch still rides the low-level Rust dirty-gas-mixture
// transport (vg_watch_dirty_gas_mixture()/vg_drain_dirty_gas_observations(), the
// GAS_DEPENDENCY_OBSERVATION_STRIDE flat array); this file owns that transport's only
// subscriber table now (om_gas_watches_by_mixture) and SSmachines.wake_dirty_gas_subscribers()
// (code/controllers/subsystems/machines.dm) calls straight into om_watch_dispatch_gas()
// per dirty mixture instead of walking a generic subscriber list.
//
// Four watch flavours, chosen by which arm proc a caller uses:
//  - om_watch_arm_bands(): a set of threshold bands (pressure, temperature, or a named
//    gas's moles) on a gas mixture. Fires on a band crossing (with hysteresis). This is
//    "any gas quantity in a gas mixture" (case b).
//  - om_watch_arm_revision(): fires whenever the watched mixture's Rust-side revision
//    counter advances at all (subject to an interest mask) -- the generalization of every
//    "cache a revision, wake when it differs" hand-rolled watch this replaces.
//  - om_watch_arm_value(): fires whenever a caller-supplied getter's return value differs
//    from what it returned last time a matching gas notification arrived (a mixture-driven
//    generalization of a "signature changed" check -- air_alarm's TLV-crossing signature).
//  - om_watch_arm_raw(): forwards the raw (mixture_id, change_mask, observation,
//    observation_index) tuple straight to a callback whenever the change mask matches
//    (material_service's corrosion/pressure-stress accounting wants the raw numbers, not
//    a single crossing bit).
//  - om_watch_arm_derived(): a DM-side/vg-component value with no Rust watch backing it at
//    all -- re-evaluated only when the caller calls om_watch_recheck(), the same way a
//    producer raises a CHANGE_MACHINE_* channel elsewhere. This is "any vg field" and
//    "arbitrary DM-derived/computed values via a callback" (cases a and c): the callback
//    passed as `getter` is exactly that generic proc reference, and it can read anything --
//    a vg pipeline field, a computed number, whatever the caller wants watched.
//
// Every flavour ends the same way: a crossing/change calls the watch's `wake_callback`
// (if any) and then, if `channel` is set, om_changed(entity, channel) -- which is all an
// OM-pipeline (polls = FALSE) machine needs to reschedule itself. A polling (polls = TRUE)
// legacy machine instead supplies a wake_callback that does its old wake_gas_subscriber()
// branch inline (typically STOP watching + START_MACHINE_PROCESSING(src)).

/// One band: a field name, a comparison edge, the threshold value and a hysteresis margin (in
/// the field's own units) so a value sitting exactly on the edge doesn't chatter.
/datum/om_watch_band
	var/field
	var/above // TRUE: armed when field >= value; FALSE: armed when field <= value
	var/value
	var/hysteresis = 0

/datum/om_watch_band/New(field, above, value, hysteresis = 0)
	src.field = field
	src.above = above
	src.value = value
	src.hysteresis = hysteresis

#define OM_WATCH_BANDS 1
#define OM_WATCH_REVISION 2
#define OM_WATCH_VALUE 3
#define OM_WATCH_RAW 4
#define OM_WATCH_DERIVED 5

/// Per-entity, per-watch_id watch state.
/datum/om_watch
	var/datum/weakref/entity_ref
	var/watch_id // the key this watch is registered under on its entity (arbitrary string)
	var/channel // optional CHANGE_MACHINE_*/CHANGE_MOB_* bit: a crossing raises om_changed(entity, channel)
	var/datum/callback/wake_callback // optional: invoked (no args) on every crossing, before om_changed
	var/mode = OM_WATCH_BANDS
	var/list/datum/om_watch_band/bands
	var/list/last_side // "field:above:value" -> TRUE/FALSE at last evaluation
	var/mixture_id // set for every gas-driven mode (bands/revision/value/raw)
	var/interest_mask = GAS_DEPENDENCY_ALL // change-mask filter for revision/value/raw modes
	var/armed_revision = -1 // OM_WATCH_REVISION: the revision captured at arm/last-fire time
	var/datum/callback/value_getter // OM_WATCH_VALUE: () -> comparable value; OM_WATCH_DERIVED: () -> current_value
	var/last_value // OM_WATCH_VALUE/OM_WATCH_DERIVED: the last value observed
	var/datum/callback/raw_observer // OM_WATCH_RAW: (mixture_id, change_mask, observation, observation_index)

/datum/om_watch/proc/gas_field_value(list/observation, observation_index, field)
	switch(field)
		if("pressure")
			return observation[observation_index + 3]
		if("temperature")
			return observation[observation_index + 4]
		if("volume")
			return observation[observation_index + 5]
		if("o2")
			return observation[observation_index + 6]
		if("co2")
			return observation[observation_index + 7]
		if("plasma")
			return observation[observation_index + 8]
		if("methane")
			return observation[observation_index + 9]
		if("n2o")
			return observation[observation_index + 10]
		if("volatile_fuel")
			return observation[observation_index + 11]
		if("miasma")
			return observation[observation_index + 12]
		if("zauker")
			return observation[observation_index + 13]
		if("total_moles")
			return observation[observation_index + 14]
	return null

/// The interest mask a field belongs to, for aggregating a mixture's Rust-side publish mask
/// from the bands a caller armed.
/datum/om_watch/proc/gas_field_mask(field)
	switch(field)
		if("pressure")
			return GAS_DEPENDENCY_PRESSURE
		if("temperature")
			return GAS_DEPENDENCY_TEMPERATURE
	return GAS_DEPENDENCY_COMPOSITION

/// Evaluates every band against `current_value` (already read, from either the gas observation
/// stride or a derived getter). Returns TRUE the first time any band crosses its edge;
/// hysteresis holds off re-firing until the value clears back past the margin.
/datum/om_watch/proc/evaluate_band(datum/om_watch_band/B, current_value)
	if(isnull(current_value))
		return FALSE
	if(!last_side)
		last_side = list()
	var/key = "[B.field]:[B.above]:[B.value]"
	var/edge = B.above ? (current_value >= B.value) : (current_value <= B.value)
	var/prior = last_side[key]
	if(isnull(prior))
		last_side[key] = edge
		return FALSE
	if(edge == prior)
		return FALSE
	if(!edge && B.hysteresis > 0)
		var/settled = B.above ? (current_value <= B.value - B.hysteresis) : (current_value >= B.value + B.hysteresis)
		if(!settled)
			return FALSE
	last_side[key] = edge
	return TRUE

/// Re-evaluates every band of a gas watch against one delivered observation. Returns TRUE the
/// first time any band crosses.
/datum/om_watch/proc/evaluate_gas(list/observation, observation_index)
	. = FALSE
	for(var/datum/om_watch_band/B as anything in bands)
		if(evaluate_band(B, gas_field_value(observation, observation_index, B.field)))
			. = TRUE

/// Re-evaluates every band of a derived watch against the latest getter result. Returns TRUE the
/// first time any band crosses.
/datum/om_watch/proc/evaluate_derived(current_value)
	last_value = current_value
	. = FALSE
	for(var/datum/om_watch_band/B as anything in bands)
		if(evaluate_band(B, current_value))
			. = TRUE

// ---------------------------------------------------------------- registries

/// Every armed watch, keyed by "[REF(entity)]" -> (watch_id -> /datum/om_watch). Not a var on
/// the watching type: any datum with a resolvable weak reference can arm a watch.
GLOBAL_LIST_EMPTY(om_watch_registry)

/// Reverse index for gas-driven watches: "[mixture_id]" -> list of /datum/om_watch, so
/// om_watch_dispatch_gas() (called from SSmachines.wake_dirty_gas_subscribers()) doesn't have
/// to walk every watch in the registry for every dirty mixture.
GLOBAL_LIST_EMPTY(om_gas_watches_by_mixture)

/proc/om_watch_entity_key(datum/entity)
	return REF(entity)

/proc/om_watch_lookup(datum/entity, watch_id)
	var/list/entity_watches = GLOB.om_watch_registry[om_watch_entity_key(entity)]
	return entity_watches?[watch_id]

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
	if(isnull(mixture_id))
		return
	W.mixture_id = mixture_id
	var/key = "[mixture_id]"
	var/list/L = GLOB.om_gas_watches_by_mixture[key]
	if(!L)
		L = list()
		GLOB.om_gas_watches_by_mixture[key] = L
	L += W
	om_watch_republish_mixture(mixture_id)

/proc/om_watch_unindex_gas(datum/om_watch/W)
	if(isnull(W.mixture_id))
		return
	var/mixture_id = W.mixture_id
	var/key = "[mixture_id]"
	var/list/L = GLOB.om_gas_watches_by_mixture[key]
	W.mixture_id = null
	if(!L)
		return
	L -= W
	if(!length(L))
		GLOB.om_gas_watches_by_mixture -= key
		vg_unwatch_dirty_gas_mixture(mixture_id)
	else
		om_watch_republish_mixture(mixture_id)

/// Recomputes and (re)publishes the aggregate interest mask Rust should watch a mixture for,
/// from the union of every watch currently armed on it. Cheap: the watch list per mixture is
/// always small (a handful of nearby machines at most).
/proc/om_watch_republish_mixture(mixture_id)
	var/list/L = GLOB.om_gas_watches_by_mixture["[mixture_id]"]
	if(!length(L))
		return
	var/aggregate_mask = NONE
	for(var/datum/om_watch/W as anything in L)
		if(W.mode == OM_WATCH_BANDS)
			for(var/datum/om_watch_band/B as anything in W.bands)
				aggregate_mask |= W.gas_field_mask(B.field)
		else
			aggregate_mask |= W.interest_mask
	vg_watch_dirty_gas_mixture(mixture_id, aggregate_mask)

/proc/om_watch_register(datum/om_watch/W)
	var/key = om_watch_entity_key(W.entity_ref.resolve())
	var/list/entity_watches = GLOB.om_watch_registry[key]
	if(!entity_watches)
		entity_watches = list()
		GLOB.om_watch_registry[key] = entity_watches
	entity_watches[W.watch_id] = W

// ---------------------------------------------------------------- arming

/// Arms (or re-arms) a threshold-band watch on a gas mixture, replacing whatever this
/// (entity, watch_id) pair previously watched. A crossing invokes `wake_callback` and/or
/// om_changed(entity, channel).
/proc/om_watch_arm_bands(datum/entity, watch_id, mixture_id, list/datum/om_watch_band/bands, channel, datum/callback/wake_callback)
	om_watch_disarm(entity, watch_id)
	if(isnull(mixture_id))
		return null
	var/datum/om_watch/W = new
	W.entity_ref = WEAKREF(entity)
	W.watch_id = watch_id
	W.channel = channel
	W.wake_callback = wake_callback
	W.mode = OM_WATCH_BANDS
	W.bands = bands
	om_watch_register(W)
	om_watch_index_gas(W, mixture_id)
	return W

/// Arms a "wake on any change" watch: fires whenever the mixture's Rust-side revision counter
/// advances (subject to `interest_mask`). This is the generic replacement for every
/// "cache sleeping_mixture_revision, compare, wake" hand-rolled watch removed in this pass.
/proc/om_watch_arm_revision(datum/entity, watch_id, mixture_id, interest_mask = GAS_DEPENDENCY_ALL, channel, datum/callback/wake_callback, current_revision)
	om_watch_disarm(entity, watch_id)
	if(isnull(mixture_id))
		return null
	var/datum/om_watch/W = new
	W.entity_ref = WEAKREF(entity)
	W.watch_id = watch_id
	W.channel = channel
	W.wake_callback = wake_callback
	W.mode = OM_WATCH_REVISION
	W.interest_mask = interest_mask
	W.armed_revision = isnull(current_revision) ? -1 : current_revision
	om_watch_register(W)
	om_watch_index_gas(W, mixture_id)
	return W

/// Arms a "wake when this computed value changes" watch on a gas mixture: `getter` is invoked
/// with no args whenever a matching gas notification arrives, and a crossing fires if the
/// return value differs from what it returned last time (air_alarm's TLV-signature check
/// generalized).
/proc/om_watch_arm_value(datum/entity, watch_id, mixture_id, interest_mask = GAS_DEPENDENCY_ALL, datum/callback/getter, channel, datum/callback/wake_callback)
	om_watch_disarm(entity, watch_id)
	if(isnull(mixture_id))
		return null
	var/datum/om_watch/W = new
	W.entity_ref = WEAKREF(entity)
	W.watch_id = watch_id
	W.channel = channel
	W.wake_callback = wake_callback
	W.mode = OM_WATCH_VALUE
	W.interest_mask = interest_mask
	W.value_getter = getter
	W.last_value = getter?.Invoke()
	om_watch_register(W)
	om_watch_index_gas(W, mixture_id)
	return W

/// Arms a raw forwarder: every gas notification whose change mask matches `interest_mask` is
/// handed straight to `observer` as (mixture_id, change_mask, observation, observation_index) --
/// for a caller (material_service) that wants the numbers themselves, not a single crossing bit.
/proc/om_watch_arm_raw(datum/entity, watch_id, mixture_id, interest_mask, datum/callback/observer)
	om_watch_disarm(entity, watch_id)
	if(isnull(mixture_id))
		return null
	var/datum/om_watch/W = new
	W.entity_ref = WEAKREF(entity)
	W.watch_id = watch_id
	W.mode = OM_WATCH_RAW
	W.interest_mask = interest_mask
	W.raw_observer = observer
	om_watch_register(W)
	om_watch_index_gas(W, mixture_id)
	return W

/// Registers a DM-side derived watch: no Rust watch backs it, so the caller is responsible for
/// calling om_watch_recheck(entity, watch_id) whenever something that could move the value
/// happens (a producer's job, same as any other CHANGE_MACHINE_* channel). `getter`, if given,
/// is invoked automatically by om_watch_recheck(); otherwise the caller passes the fresh value
/// straight to om_watch_recheck_value(). This is the generic hook for (a) any vg/pipeline
/// component field and (c) any other computed value: `getter` is an arbitrary proc reference.
/proc/om_watch_arm_derived(datum/entity, watch_id, list/datum/om_watch_band/bands, channel, datum/callback/getter, datum/callback/wake_callback)
	om_watch_disarm(entity, watch_id)
	var/datum/om_watch/W = new
	W.entity_ref = WEAKREF(entity)
	W.watch_id = watch_id
	W.channel = channel
	W.wake_callback = wake_callback
	W.mode = OM_WATCH_DERIVED
	W.bands = bands
	W.value_getter = getter
	om_watch_register(W)
	W.evaluate_derived(getter ? getter.Invoke() : null) // seed last_side without firing on registration
	return W

/proc/om_watch_recheck(datum/entity, watch_id)
	var/datum/om_watch/W = om_watch_lookup(entity, watch_id)
	if(!W || W.mode != OM_WATCH_DERIVED || !W.value_getter)
		return
	if(W.evaluate_derived(W.value_getter.Invoke()))
		om_watch_fire(W, entity)

/proc/om_watch_recheck_value(datum/entity, watch_id, current_value)
	var/datum/om_watch/W = om_watch_lookup(entity, watch_id)
	if(!W || W.mode != OM_WATCH_DERIVED)
		return
	if(W.evaluate_derived(current_value))
		om_watch_fire(W, entity)

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
		W.wake_callback.Invoke()
	if(W.channel)
		om_changed(entity, W.channel)

/// Called from SSmachines.wake_dirty_gas_subscribers() (code/controllers/subsystems/machines.dm)
/// for every dirty mixture Rust reports. Walks every watch armed on that mixture and fires the
/// ones whose mode says this notification is actionable.
/proc/om_watch_dispatch_gas(mixture_id, change_mask, list/observation, observation_index)
	var/list/L = GLOB.om_gas_watches_by_mixture["[mixture_id]"]
	if(!length(L))
		return
	for(var/datum/om_watch/W as anything in L.Copy())
		var/datum/entity = W.entity_ref?.resolve()
		SSmachines.current_gas_wake_subscribers++
		if(!entity)
			SSmachines.gas_dead_last++
			om_watch_unindex_gas(W) // stale: the watching object is gone, drop it
			continue
		switch(W.mode)
			if(OM_WATCH_RAW)
				if(change_mask & W.interest_mask)
					W.raw_observer.Invoke(mixture_id, change_mask, observation, observation_index)
			if(OM_WATCH_REVISION)
				if(!(change_mask & W.interest_mask))
					continue
				var/observed_revision = (observation && observation_index) ? observation[observation_index + 2] : null
				if(isnull(observed_revision) || observed_revision != W.armed_revision)
					W.armed_revision = observed_revision
					om_watch_fire(W, entity)
			if(OM_WATCH_VALUE)
				if(!(change_mask & W.interest_mask))
					continue
				var/current_value = W.value_getter.Invoke()
				if(current_value != W.last_value)
					W.last_value = current_value
					om_watch_fire(W, entity)
			else // OM_WATCH_BANDS
				if(W.evaluate_gas(observation, observation_index))
					om_watch_fire(W, entity)
