// A gas watch (doc/rewrite/final_api.html section 14, "Simulation and Rust": a thing that must not poll waits on a gas watch): the holder hears its
// gas change, in the parts of the change it cares about, the frame the change is published. Nothing polls: Rust reports the change.
//
//   gas_watch(air = nameof(air_contents), changed = PROC_REF(contents_changed))   // a canister: its own contents
//   gas_watch(changed = PROC_REF(room_changed), mask = GAS_DEPENDENCY_ALL)         // an air alarm: the air where it is
//
// `air` names the holder var holding the mixture; null watches the air the holder stands in (its turf's). `mask` is GAS_DEPENDENCY_* bits (the
// pressure, temperature and composition channels of the mixture). The handler is x(): it carries no record of the change, so it reads what it needs
// (read_gas_mixtures() for several values of a mixture in one call); a holder that only needs to know a level was passed declares a sensed()
// reading (code/domains/verdigris/sense.dm) and has no gas watch at all. The watch is a world change watch on the mixture's gas handle (the field's watch port for
// a turf cell, the sync port for a main-owned mixture or a pipe region). It follows the mixture: atmos_air_set() re-arms it when the var is
// pointed at another mixture (a pipe network joined).

CAPABILITY_TYPE(gas_watch, CAP_GAS_WATCH, /datum/capability/lib/gas_watch, key = NONE, air = null, mask = GAS_DEPENDENCY_ALL, changed = null)

/datum/capability/lib/gas_watch
	holder_hooks = HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY

/datum/capability/lib/gas_watch/cap_data_type()
	return /datum/cap_data/gas_watch

/// The holder's watch and the mixture it is on.
/datum/cap_data/gas_watch
	var/tmp/datum/native_watch/world/watch
	/// Arena id of the mixture `watch` is on.
	var/armed_id
	/// Wakes delivered to the holder (a trace for tests and the profiler).
	var/wakes = 0
	/// The holder (the watch's callback reaches it through its record).
	var/tmp/datum/watcher

CAPABILITIES(/datum/cap_data/gas_watch)
	ref_one(nameof(watcher)) // the holder: the watch's callback reaches it through its record
	owns_one(nameof(watch), /datum/native_watch/world)

/datum/capability/lib/gas_watch/on_holder_init(datum/act/eval/A)
	gas_watch_arm(A.holder)

/datum/capability/lib/gas_watch/on_holder_destroy(datum/act/eval/A)
	var/datum/cap_data/gas_watch/data = gas_watch_data(A.holder)
	if(!data)
		return
	own_clear(data, nameof(data.watch), OWN_DELETE)
	data.armed_id = null
	rel_set(data, nameof(data.watcher), null)

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
	rel_set(data, nameof(data.watcher), holder)
	var/datum/gas_mixture/mixture = def.mixture_of(holder)
	var/id = mixture?.arena_id()
	if(id == data.armed_id && (data.watch || isnull(id)))
		return
	own_clear(data, nameof(data.watch), OWN_DELETE)
	data.armed_id = id
	if(isnull(id))
		return
	rel_set(data, nameof(data.watch), gas_world_watch(data, mixture, def.mask, TYPE_PROC_REF(/datum/cap_data/gas_watch, heard)))

/// Rust reported a change of the watched mixture: the holder's handler runs.
/datum/cap_data/gas_watch/proc/heard(datum/native_watch/world/W, reason, source, source_kind)
	wakes++
	var/atom/target = watcher
	if(!target || QDELETED(target))
		return
	var/datum/capability/lib/gas_watch/def = cap_of(target, CAP_GAS_WATCH)
	if(def?.changed)
		holder_call(target, def.changed, list())

/// The CH_BIT() mask of the gas channels a GAS_DEPENDENCY_* mask names.
/proc/gas_dependency_channels(mask)
	. = 0
	if(mask & GAS_DEPENDENCY_PRESSURE)
		. |= CH_BIT(CH_GAS_PRESSURE)
	if(mask & GAS_DEPENDENCY_TEMPERATURE)
		. |= CH_BIT(CH_GAS_TEMPERATURE)
	if(mask & GAS_DEPENDENCY_COMPOSITION)
		. |= CH_BIT(CH_GAS_COMPOSITION)

/// A world watch on `mixture`: `callback` runs on `owner` as (watch, reason, source, source_kind) when a channel of `mask` (GAS_DEPENDENCY_*) changes. The
/// watch is on the mixture's gas handle: a turf's cell, a pipe region or a main-owned slot. A watch armed before the turfs register waits for them
/// (a turf's air moves into its cell then, so the handle is read once they have): the watch object exists at once, Rust learns of it at registration.
/proc/gas_world_watch(datum/owner, datum/gas_mixture/mixture, mask, callback, lane = LANE_SIMULATION)
	RETURN_TYPE(/datum/native_watch/world)
	var/channels = gas_dependency_channels(mask)
	if(!mixture || !channels)
		return null
	if(!SSair.turfs_registered)
		var/datum/native_watch/world/waiting = world_watch_new(owner, callback, lane)
		SSair.defer_gas_watch(waiting, mixture, channels)
		return waiting
	return world_watch_changed(owner, WORLD_GAS_HANDLE(mixture), channels, callback, lane)

// ---- a holder that sleeps on several mixtures ----
//
//   gas_watch_many(src, nameof(loop_watches), list(circ1.air1, circ1.air2), GAS_DEPENDENCY_PRESSURE, PROC_REF(loop_heard))
//
// A machine whose work stops until one of several mixtures changes (a generator's loops, a turbine's two sides, a leak's two faces) arms one native
// watch per mixture into a list var it owns (owns_many(nameof(x), /datum/native_watch/world)); re-arming replaces them (a rebuilt network is a new
// mixture), gas_watch_many_clear() drops them. The handler is x(datum/native_watch/world/W, reason, source, source_kind): it reads what it needs.

/// Arms `holder`'s watches (its list var `watches_var`) on each of `mixtures`, replacing the ones it had.
/proc/gas_watch_many(datum/holder, watches_var, list/mixtures, mask, callback)
	gas_watch_many_clear(holder, watches_var)
	var/list/seen = list()
	for(var/datum/gas_mixture/air as anything in mixtures)
		var/id = air?.arena_id()
		if(isnull(id) || (id in seen))
			continue
		seen += id
		var/datum/native_watch/world/W = gas_world_watch(holder, air, mask, callback)
		if(W)
			rel_add(holder, watches_var, W)

/// gas_watch_many() over arena ids (a holder that keeps the ids it watches, not the mixtures).
/proc/gas_watch_ids(datum/holder, watches_var, list/ids, mask, callback)
	gas_watch_many_clear(holder, watches_var)
	var/channels = gas_dependency_channels(mask)
	if(!channels)
		return
	for(var/id in ids)
		var/datum/native_watch/world/W = world_watch_changed(holder, list(VG_GAS_HANDLES, id), channels, callback, LANE_SIMULATION)
		if(W)
			rel_add(holder, watches_var, W)

/// Drops `holder`'s watches in its list var `watches_var`.
/proc/gas_watch_many_clear(datum/holder, watches_var)
	rel_clear(holder, watches_var)
