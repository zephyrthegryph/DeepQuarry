// A gas watch (doc/rewrite/final_api.html section 14, "Simulation and Rust": a thing that must not poll waits on a gas watch): the holder hears its
// gas change, in the parts of the change it cares about, the frame the change is published. Nothing polls: Rust reports the change.
//
//   gas_watch(air = nameof(air_contents), changed = PROC_REF(contents_changed))   // a canister: its own contents
//   gas_watch(changed = PROC_REF(room_changed), mask = GAS_DEPENDENCY_ALL)         // an air alarm: the air where it is
//
// `air` names the holder var holding the mixture; null watches the air the holder stands in (its turf's). `mask` is GAS_DEPENDENCY_* bits. The
// handler is x(list/observation, index): the observation record of the change, read with GAS_OBSERVED(observation, index, GAS_OBS_*) and never
// with a bare offset. The watch follows the mixture: atmos_air_set() re-arms it when the var is pointed at another mixture (a pipe network joined).

CAPABILITY_TYPE(gas_watch, CAP_GAS_WATCH, /datum/capability/lib/gas_watch, key = NONE, air = null, mask = GAS_DEPENDENCY_ALL, changed = null)

/datum/capability/lib/gas_watch
	holder_hooks = HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY

/datum/capability/lib/gas_watch/cap_data_type()
	return /datum/cap_data/gas_watch

/// The holder's watch and the mixture it is on.
/datum/cap_data/gas_watch
	var/tmp/datum/native_watch/gas/watch
	/// Arena id of the mixture `watch` is on.
	var/armed_id
	/// The holder (the watch's callback reaches it through its record).
	var/tmp/datum/watcher

/datum/cap_data/gas_watch/relations()
	. = ..()
	. += rel_one(nameof(watch), /datum/native_watch/gas, kind = RELK_OWNED, policy = OWN_DELETE)

/datum/capability/lib/gas_watch/on_holder_init(datum/act/eval/A)
	gas_watch_arm(A.holder)

/datum/capability/lib/gas_watch/on_holder_destroy(datum/act/eval/A)
	var/datum/cap_data/gas_watch/data = gas_watch_data(A.holder)
	if(!data)
		return
	own_clear(data, nameof(data.watch), OWN_DELETE)
	data.armed_id = null
	data.watcher = null // ALLOW(ownership): the record's back view of its holder, cleared as the holder goes; the activation drops the record

/// The watch record of `holder`, or null.
/proc/gas_watch_data(datum/holder)
	RETURN_TYPE(/datum/cap_data/gas_watch)
	var/datum/activation/act = cap_activation(holder, CAP_GAS_WATCH, null, TRUE)
	return act ? activation_data(act) : null

/// The mixture the holder's watch is on now.
/datum/capability/lib/gas_watch/proc/mixture_of(atom/holder)
	return gas_air_of(holder, air)

/// The mixture a gas watch or level on `holder` follows: the one in its var `air_var`, or (no var) the air of the turf it stands on.
/proc/gas_air_of(atom/holder, air_var)
	RETURN_TYPE(/datum/gas_mixture)
	if(air_var)
		return holder.vars[air_var]
	var/turf/T = get_turf(holder)
	return T?.return_air()

/// Points the holder's watch at its mixture now: nothing changes when it is the one already watched; a holder with no mixture has no watch.
/proc/gas_watch_arm(atom/holder)
	var/datum/capability/lib/gas_watch/def = cap_of(holder, CAP_GAS_WATCH)
	var/datum/cap_data/gas_watch/data = gas_watch_data(holder)
	if(!def || !data)
		return
	data.watcher = holder // ALLOW(ownership): the record's back view of its holder (the watch's callback reaches it through its record)
	var/datum/gas_mixture/mixture = def.mixture_of(holder)
	var/id = mixture?.arena_id()
	if(id == data.armed_id && (data.watch || isnull(id)))
		return
	own_clear(data, nameof(data.watch), OWN_DELETE)
	data.armed_id = id
	if(isnull(id))
		return
	rel_set(data, nameof(data.watch), gas_dependency_watch(data, id, def.mask, TYPE_PROC_REF(/datum/cap_data/gas_watch, heard)))

/// Rust reported a change of the watched mixture: the holder's handler hears it.
/datum/cap_data/gas_watch/proc/heard(datum/native_watch/gas/W, mixture_id, change_mask, list/observation, observation_index)
	var/atom/target = watcher
	if(!target || QDELETED(target))
		return
	var/datum/capability/lib/gas_watch/def = cap_of(target, CAP_GAS_WATCH)
	if(def?.changed)
		holder_call(target, def.changed, observation, observation_index)

// ---- a holder that sleeps on several mixtures ----
//
//   gas_watch_many(src, nameof(loop_watches), list(circ1.air1, circ1.air2), GAS_DEPENDENCY_PRESSURE, PROC_REF(loop_heard))
//
// A machine whose work stops until one of several mixtures changes (a generator's loops, a turbine's two sides, a leak's two faces) arms one native
// watch per mixture into a list var it owns (owns_many(nameof(x), /datum/native_watch/gas)); re-arming replaces them (a rebuilt network is a new
// mixture), gas_watch_many_clear() drops them. The handler is x(datum/native_watch/gas/W, mixture_id, change_mask, list/observation, observation_index).

/// Arms `holder`'s watches (its list var `watches_var`) on each of `mixtures`, replacing the ones it had.
/proc/gas_watch_many(datum/holder, watches_var, list/mixtures, mask, callback)
	var/list/ids = list()
	for(var/datum/gas_mixture/air as anything in mixtures)
		var/id = air?.arena_id()
		if(!isnull(id))
			ids |= id
	gas_watch_ids(holder, watches_var, ids, mask, callback)

/// gas_watch_many() over arena ids (a holder that keeps the ids it watches, not the mixtures).
/proc/gas_watch_ids(datum/holder, watches_var, list/ids, mask, callback)
	gas_watch_many_clear(holder, watches_var)
	for(var/id in ids)
		var/datum/native_watch/gas/W = gas_dependency_watch(holder, id, mask, callback)
		if(W)
			rel_add(holder, watches_var, W)

/// Drops `holder`'s watches in its list var `watches_var`.
/proc/gas_watch_many_clear(datum/holder, watches_var)
	rel_clear(holder, watches_var)
