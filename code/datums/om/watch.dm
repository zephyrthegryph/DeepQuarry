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
// anything with an OM handle.
//
// Delivery for a gas-backed watch rides one native gas watch per mixture (Rust-owned,
// code/datums/om/native.dm), which carries the union of the interest masks armed on it.
// SSmachines.wake_dirty_gas_subscribers() (code/controllers/subsystems/machines.dm) fires
// that native watch per observation; its owner (/datum/om_gas_watch_hub) hands the record to
// om_watch_dispatch_gas(), which walks this file's per-mixture table
// (om_gas_watches_by_mixture) instead of a generic subscriber list.
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
// (if any) and then, if `channel` is set, changed(entity, channel) -- which is all an
// OM-pipeline (polls = FALSE) machine needs to reschedule itself. A polling (polls = TRUE)
// legacy machine instead supplies a wake_callback that does its old wake_gas_subscriber()
// branch inline (typically STOP watching + work_start(src)).

/// One band: a field name, a comparison edge, the threshold value and a hysteresis margin (in
/// the field's own units) so a value sitting exactly on the edge doesn't chatter.
/datum/om_watch_band
	var/field
	var/above // TRUE: armed when field >= value; FALSE: armed when field <= value
	var/value
	var/hysteresis = 0
	/// FALSE: only entering the band fires; leaving it re-arms silently. A "can this device act
	/// now" condition wants exactly that -- becoming ineligible is not a reason to wake.
	var/fire_on_exit = TRUE

/datum/om_watch_band/New(field, above, value, hysteresis = 0, fire_on_exit = TRUE)
	src.field = field
	src.above = above
	src.value = value
	src.hysteresis = hysteresis
	src.fire_on_exit = fire_on_exit

#define OM_WATCH_BANDS 1
#define OM_WATCH_REVISION 2
#define OM_WATCH_VALUE 3
#define OM_WATCH_RAW 4
#define OM_WATCH_DERIVED 5
#define OM_WATCH_CONDITION 6

/// Per-entity, per-watch_id watch state.
/datum/om_watch
	var/entity_ref
	var/watch_id // the key this watch is registered under on its entity (arbitrary string)
	var/channel // optional CHANGE_MACHINE_*/CHANGE_MOB_* bit: a crossing raises changed(entity, channel)
	var/list/wake_callback // optional om_callable() spec: run (no args) on every crossing, before changed
	var/mode = OM_WATCH_BANDS
	var/list/datum/om_watch_band/bands
	var/list/last_side // "field:above:value" -> TRUE/FALSE at last evaluation
	var/list/mixture_ids // every mixture this watch is indexed on (gas-driven modes, and a gas-driven derived condition)
	var/interest_mask = GAS_DEPENDENCY_ALL // change-mask filter for revision/value/raw modes
	var/armed_revision = -1 // OM_WATCH_REVISION: the revision captured at arm/last-fire time
	var/list/value_getter // om_callable() spec. OM_WATCH_VALUE: () -> comparable value; OM_WATCH_DERIVED: () -> current_value
	var/last_value // OM_WATCH_VALUE/OM_WATCH_DERIVED: the last value observed
	var/list/raw_observer // om_callable() spec. OM_WATCH_RAW: (mixture_id, change_mask, observation, observation_index)

CAPABILITIES(/datum/om_watch)
	owns_many(nameof(bands), /datum/om_watch_band)

/datum/om_watch/proc/gas_field_value(list/observation, observation_index, field)
	switch(field)
		if("pressure")
			return GAS_OBSERVED(observation, observation_index, GAS_OBS_PRESSURE)
		if("temperature")
			return GAS_OBSERVED(observation, observation_index, GAS_OBS_TEMPERATURE)
		if("volume")
			return GAS_OBSERVED(observation, observation_index, GAS_OBS_VOLUME)
		if("o2")
			return GAS_OBSERVED(observation, observation_index, GAS_OBS_OXYGEN)
		if("co2")
			return GAS_OBSERVED(observation, observation_index, GAS_OBS_CARBON_DIOXIDE)
		if("plasma")
			return GAS_OBSERVED(observation, observation_index, GAS_OBS_PLASMA)
		if("methane")
			return GAS_OBSERVED(observation, observation_index, GAS_OBS_METHANE)
		if("n2o")
			return GAS_OBSERVED(observation, observation_index, GAS_OBS_NITROUS_OXIDE)
		if("volatile_fuel")
			return GAS_OBSERVED(observation, observation_index, GAS_OBS_VOLATILE_FUEL)
		if("miasma")
			return GAS_OBSERVED(observation, observation_index, GAS_OBS_MIASMA)
		if("zauker")
			return GAS_OBSERVED(observation, observation_index, GAS_OBS_ZAUKER)
		if("total_moles")
			return GAS_OBSERVED(observation, observation_index, GAS_OBS_TOTAL_MOLES)
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
	return edge || B.fire_on_exit

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

/// The gas fields this watch needs its mixture's native watch to report: its bands' fields, or its interest mask.
/datum/om_watch/proc/interest_contribution()
	if(mode != OM_WATCH_BANDS)
		return interest_mask
	. = NONE
	for(var/datum/om_watch_band/B as anything in bands)
		. |= gas_field_mask(B.field)

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

/// Arms (or re-arms) a threshold-band watch on a gas mixture, replacing whatever this
/// (entity, watch_id) pair previously watched. A crossing invokes `wake_callback` and/or
/// changed(entity, channel).
/proc/om_watch_arm_bands(datum/entity, watch_id, mixture_id, list/bands, channel, list/wake_callback)
	om_watch_disarm(entity, watch_id)
	if(isnull(mixture_id))
		return null
	var/datum/om_watch/W = new
	W.entity_ref = om_handle(entity)
	W.watch_id = watch_id
	W.channel = channel
	W.wake_callback = wake_callback
	W.mode = OM_WATCH_BANDS
	own_clear(W, nameof(W.bands), OWN_DELETE)
	for(var/datum/om_watch_band/band as anything in bands) // the watch owns its bands
		rel_add(W, nameof(W.bands), band)
	om_watch_register(W)
	om_watch_index_gas(W, mixture_id)
	return W

/// Arms a "wake on any change" watch: fires whenever the mixture's Rust-side revision counter
/// advances (subject to `interest_mask`). This is the generic replacement for every
/// "cache sleeping_mixture_revision, compare, wake" hand-rolled watch removed in this pass.
/proc/om_watch_arm_revision(datum/entity, watch_id, mixture_id, interest_mask = GAS_DEPENDENCY_ALL, channel, list/wake_callback, current_revision)
	om_watch_disarm(entity, watch_id)
	if(isnull(mixture_id))
		return null
	var/datum/om_watch/W = new
	W.entity_ref = om_handle(entity)
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

/// Arms a raw forwarder: every gas notification whose change mask matches `interest_mask` is
/// handed straight to `observer` as (mixture_id, change_mask, observation, observation_index) --
/// for a caller (material_service) that wants the numbers themselves, not a single crossing bit.
/proc/om_watch_arm_raw(datum/entity, watch_id, mixture_id, interest_mask, list/observer)
	om_watch_disarm(entity, watch_id)
	if(isnull(mixture_id))
		return null
	var/datum/om_watch/W = new
	W.entity_ref = om_handle(entity)
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
/proc/om_watch_arm_derived(datum/entity, watch_id, list/bands, channel, list/getter, list/wake_callback, list/mixture_ids, interest_mask = GAS_DEPENDENCY_ALL)
	om_watch_disarm(entity, watch_id)
	var/datum/om_watch/W = new
	W.entity_ref = om_handle(entity)
	W.watch_id = watch_id
	W.channel = channel
	W.wake_callback = wake_callback
	W.mode = OM_WATCH_DERIVED
	own_clear(W, nameof(W.bands), OWN_DELETE)
	for(var/datum/om_watch_band/band as anything in bands) // the watch owns its bands
		rel_add(W, nameof(W.bands), band)
	W.value_getter = getter
	W.interest_mask = interest_mask
	om_watch_register(W)
	W.evaluate_derived(getter ? om_run(getter) : null) // seed last_side without firing on registration
	// Optionally gas-driven: a dirty notification on any of these re-evaluates the getter, so a
	// band over a quantity computed from several mixtures needs no caller-side recheck.
	for(var/mixture_id in mixture_ids)
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

/proc/om_watch_recheck(datum/entity, watch_id)
	var/datum/om_watch/W = om_watch_lookup(entity, watch_id)
	if(!W || !W.value_getter)
		return
	if(W.mode == OM_WATCH_CONDITION)
		if(om_run(W.value_getter))
			om_watch_fire(W, entity)
		return
	if(W.mode == OM_WATCH_DERIVED && W.evaluate_derived(om_run(W.value_getter)))
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

/// Disarms every watch of every entity in `entities` (their om_watch_entity_key()s) as one
/// set (doc/rewrite/init_and_turfs.md sec 4.4 step 6): each entity leaves the registry once,
/// each mixture's reverse index drops the set's watches in one `-=`, and each touched mixture
/// is republished (or its native watch freed) once, not once per watch.
/proc/om_watch_disarm_keys(list/keys)
	var/list/by_mixture = list()
	for(var/key in keys)
		var/list/entity_watches = GLOB.om_watch_registry[key]
		if(!entity_watches)
			continue
		for(var/watch_id in entity_watches)
			var/datum/om_watch/W = entity_watches[watch_id]
			if(!W)
				continue
			for(var/mixture_id in W.mixture_ids)
				var/list/set_watches = by_mixture["[mixture_id]"]
				if(!set_watches)
					set_watches = list()
					by_mixture["[mixture_id]"] = set_watches
				set_watches += W
			W.mixture_ids = null
	GLOB.om_watch_registry -= keys
	for(var/mixture_key in by_mixture)
		var/list/L = GLOB.om_gas_watches_by_mixture[mixture_key]
		if(!L)
			continue
		L -= by_mixture[mixture_key]
		for(var/datum/om_watch/W as anything in by_mixture[mixture_key])
			om_watch_count_interest(mixture_key, W.interest_contribution(), -1)
		if(!length(L))
			om_watch_drop_mixture(mixture_key)
		else
			om_watch_republish_mixture(text2num(mixture_key))

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
			if(OM_WATCH_RAW)
				if(change_mask & W.interest_mask)
					om_run(W.raw_observer, mixture_id, change_mask, observation, observation_index)
			if(OM_WATCH_REVISION)
				if(!(change_mask & W.interest_mask))
					continue
				var/observed_revision = (observation && observation_index) ? GAS_OBSERVED(observation, observation_index, GAS_OBS_REVISION) : null
				if(isnull(observed_revision) || observed_revision != W.armed_revision)
					W.armed_revision = observed_revision
					om_watch_fire(W, entity)
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
			if(OM_WATCH_DERIVED)
				if(!(change_mask & W.interest_mask))
					continue
				if(W.evaluate_derived(om_run(W.value_getter)))
					om_watch_fire(W, entity)
			else // OM_WATCH_BANDS
				if(W.evaluate_gas(observation, observation_index))
					om_watch_fire(W, entity)


