// Rust-owned state read from reactive code (doc/rewrite/final_api.html section 7, mechanism 5, "Built-ins and Rust-owned state").
//
// A value the Rust simulation owns (a heat body's temperature) changes without a DM write, so a draw, a requirement or a stat input that read
// it raw (`vg_heat_body_temperature()`) could not hear it change. It reads it through
//
//   watched(A, WATCH_HEAT, list(level, level, ...))   a heat body (a native band watch in Rust)
//   watched(T, WATCH_LUM, list(level, ...))           a turf's lum (the lighting engine reports the turf when its corners change)
//   watched(S, WATCH_CHARGE, list(level, ...))        a SMES's stored charge (a native band watch on its Verdigris component)
//   watched(A, WATCH_GAS, list(level, ...), channel = CH_GAS_PRESSURE, air = nameof(air_contents))
//                                                     a gas reading (CH_GAS_* channel: pressure kPa, temperature K, total moles, or one gas's moles) of the
//                                                     mixture the atom holds in var `air`, or (air null) of the air of the turf it stands on: a native
//                                                     band watch on the mixture's gas handle (the field's watch port for a turf, the sync port for a
//                                                     main-owned mixture), the same Rust watches gas_level() uses
//
// instead: the band of the value among the increasing levels (0 below the first, one more for each level at or under it). The read stands for
// the key WATCHED_KEY on A (READS_AS): the reader subscribes to it like any published key. The first read of a band arms a native band watch on
// A (the watched system, after the read: an output does not register anything itself); every band change Rust reports publishes WATCHED_KEY on
// A, and the reader re-evaluates. One band watch per source on an atom: a read with other levels replaces it (a SMES's charge watch widens to every level asked). A watched atom keeps a heat
// body while the watch lives.

/// The band of `value` among the increasing `levels`: how many of them are at or under it.
/proc/watched_band(value, list/levels, strict = FALSE)
	READS_FROM()
	. = 0
	for(var/level in levels)
		if(strict ? value <= level : value < level)
			break
		.++

/// The levels a strict reader's watch is armed on: each level and the next value DM can tell above it, so a value that sits exactly on a
/// level and then rises still crosses something Rust reports (a band boundary is inclusive there).
/proc/watched_strict_levels(list/levels)
	READS_FROM()
	. = list()
	for(var/level in levels)
		. += level
		. += level > 0 ? level * 1.0000002 : (level < 0 ? level * 0.9999998 : 1e-30)

/// `A`'s Rust-owned `source` (WATCH_HEAT: its temperature), as its band among the increasing `levels`. Reactive code reads Rust-owned state only
/// through this: the read subscribes to WATCHED_KEY on A, which the band watch publishes.
READS_AS(/proc/watched, WATCHED_KEY)
/// `channel` and `air` are for WATCH_GAS only: the CH_GAS_* channel read, and the holder var naming the mixture (null: the air of A's turf).
/// `strict`: a level counts only once the value is above it (`value > level`, the old strict comparison of a reader that refused "above 1%");
/// by default a value on a level is in the band above it.
/proc/watched(atom/A, source, list/levels, strict = FALSE, channel = CH_GAS_PRESSURE, air = null)
	READS_FROM(A)
	if(!A || !length(levels))
		return 0
	var/value
	switch(source)
		if(WATCH_HEAT)
			value = A.get_temperature()
		if(WATCH_LUM)
			var/turf/T = A
			if(!istype(T))
				CRASH("watched(): WATCH_LUM reads a turf, not [A.type]")
			value = T.get_lumcount()
			if(!T.lighting_object)
				return watched_band(value, levels, strict) // no dynamic lighting: its lum is fixed
		if(WATCH_CHARGE)
			var/obj/machinery/power/smes/S = A
			if(!istype(S))
				CRASH("watched(): WATCH_CHARGE reads a SMES, not [A.type]")
			value = S.stored_charge()
			if(!S.vg_entity)
				return watched_band(value, levels, strict) // not registered with Rust yet: its charge is the seed, nothing to watch
		if(WATCH_GAS)
			var/datum/gas_mixture/mixture = gas_air_of(A, air)
			if(!mixture)
				return 0 // no air to read: band 0, and nothing to watch until the holder is given one (atmos_air_set() republishes)
			value = gas_level_read(mixture, channel)
		else
			CRASH("watched(): unknown source [source]")
	var/list/armed = strict ? watched_strict_levels(levels) : levels
	if(!watched_armed(A, source, armed, channel, air))
		SSwatched.request(A, source, armed, channel, air)
	return watched_band(value, levels, strict)

/// TRUE when `A` already has the band watch `watched()` would arm for these levels.
/proc/watched_armed(atom/A, source, list/levels, channel = CH_GAS_PRESSURE, air = null)
	if(source == WATCH_GAS)
		var/datum/gas_mixture/mixture = gas_air_of(A, air)
		var/list/row = SSwatched.gas_watches[ref_token(A)]?["[channel]"]
		if(!mixture || !row || row[3] != mixture.arena_id())
			return FALSE
		for(var/level in levels)
			if(!(level in row[1]))
				return FALSE
		return TRUE
	if(source == WATCH_LUM)
		var/turf/T = A
		return !!T.lighting_object?.lum_watch?[jointext(levels, ",")]
	if(source == WATCH_CHARGE)
		var/obj/machinery/power/smes/S = A
		var/list/row = SSwatched.charge_watches[ref_token(S)]
		if(!row || row[3] != S.vg_entity)
			return FALSE
		for(var/level in levels)
			if(!(level in row[1]))
				return FALSE
		return TRUE
	for(var/datum/native_watch/heat/W as anything in A.heat_watches)
		if(W.kind == HEAT_WATCH_BAND && W.owner_ref == SSwatched.watch_owner() && islist(W.level) && W.level ~= levels)
			return TRUE
	return FALSE

/// Arms the band watches reactive reads asked for (watched()), after the read: an output never registers a watch itself.
SYSTEM_DEF(watched)
	name = "Watched bands"
	/// Rows list(atom handle, source, levels) waiting to be armed, oldest first (a handle: an atom deleted while it waits is skipped).
	VAR_PRIVATE/list/pending = list()
	/// Turf handles whose lighting changed since the last pass (lum_changed()), each once.
	VAR_PRIVATE/list/lum_pending = list()
	/// This system's entity handle, the owner every band watch it arms names (watched_armed() compares it).
	var/watch_owner_ref
	/// SMES charge band watches: the SMES's entity handle -> list(levels, the world watch's handle, Verdigris entity it watches). One per SMES, widened when
	/// a read asks other levels. The handle is weak: a deleted SMES's row is dropped on the next pass.
	var/list/charge_watches = list()
	/// A charge watch's SSvg handle -> the SMES's entity handle (the wake names only the watch).
	VAR_PRIVATE/list/charge_owners = list()
	/// Charge band wakes delivered (a trace for tests and the profiler).
	var/charge_wakes = 0
	/// Gas band watches: the atom's entity handle -> channel (as text) -> list(levels, the world watch's handle, arena id of the mixture it watches). One per
	/// atom and channel, widened when a read asks other levels; the handle is weak (a deleted atom's rows are dropped on the next pass).
	var/list/gas_watches = list()
	/// A gas watch's SSvg handle -> list(the atom's entity handle, channel text).
	VAR_PRIVATE/list/gas_owners = list()
	/// Gas band wakes delivered (a trace for tests and the profiler).
	var/gas_wakes = 0

/// This system's entity handle (taken on first use: handles do not exist yet while the systems are made).
/datum/system/watched/proc/watch_owner()
	if(!watch_owner_ref)
		watch_owner_ref = ref_token(src)
	return watch_owner_ref

/datum/system/watched/reactions()
	. = ..()
	. += every(1, PROC_REF(arm_pending), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/// Queues a band watch on `A`'s `source` over `levels`.
/datum/system/watched/proc/request(atom/A, source, list/levels, channel, air)
	pending += list(list(ref_token(A), source, levels.Copy(), channel, air))
	wake_work_item(PROC_REF(arm_pending))

/datum/system/watched/proc/arm_pending(dt)
	if(length(lum_pending))
		lum_publish()
	if(!length(pending))
		return STEP_PARK
	var/list/rows = pending
	pending = list()
	charge_prune()
	gas_prune()
	for(var/list/row as anything in rows)
		var/atom/A = resolve_token(row[1])
		if(!isatom(A) || QDELETED(A) || watched_armed(A, row[2], row[3], row[4], row[5]))
			continue
		if(row[2] == WATCH_GAS)
			if(!air_turfs_registered())
				pending += list(row) // a turf's air moves into its field cell when the turfs register: the watch is armed then (air_ready())
				continue
			gas_arm(A, row[3], row[4], row[5])
			continue
		if(row[2] == WATCH_CHARGE)
			charge_arm(A, row[3])
			continue
		if(row[2] == WATCH_LUM)
			lum_arm(A, row[3])
			continue
		// One band watch per source on an atom: the old levels go.
		for(var/datum/native_watch/heat/old as anything in A.heat_watches?.Copy())
			if(old.kind == HEAT_WATCH_BAND && old.owner_ref == watch_owner())
				spent(old)
		switch(row[2])
			if(WATCH_HEAT)
				// keep_body: the atom keeps a heat body while watched, so the band follows it at rest too (a body at rest reads its
				// surroundings unwatched).
				heat_watch_band(src, A, row[3], PROC_REF(band_changed), keep_body = TRUE)
	return STEP_PARK

/// Lum bands are DM's own (the lighting engine): the lighting object of `T` remembers each band a reader asked for and the band it last
/// published, and lighting_object/update() reports the turf here when its corners changed.
/datum/system/watched/proc/lum_arm(turf/T, list/levels)
	var/datum/lighting_object/O = T.lighting_object
	if(!O)
		return
	LAZYINITLIST(O.lum_watch)
	O.lum_watch[jointext(levels, ",")] = list(levels, watched_band(T.get_lumcount(), levels))

/// `T`'s lighting changed this tick: checked once at the next pass (coalesced per turf).
/datum/system/watched/proc/lum_changed(turf/T)
	var/handle = ref_token(T)
	if(lum_pending[handle])
		return
	lum_pending[handle] = TRUE
	wake_work_item(PROC_REF(arm_pending))

/// Publishes WATCHED_KEY on each pending turf whose lum left a band a reader watches.
/datum/system/watched/proc/lum_publish()
	var/list/turfs = lum_pending
	lum_pending = list()
	for(var/handle in turfs)
		var/turf/T = resolve_token(handle)
		var/datum/lighting_object/O = T?.lighting_object
		if(!O?.lum_watch)
			continue
		var/lum = T.get_lumcount()
		var/changed = FALSE
		for(var/key in O.lum_watch)
			var/list/row = O.lum_watch[key]
			var/band = watched_band(lum, row[1])
			if(band != row[2])
				row[2] = band
				changed = TRUE
		if(changed)
			PUBLISH_CHANGE(T, WATCHED_KEY)

/// A band watch fired: what reads the watched value re-evaluates.
/datum/system/watched/proc/band_changed(datum/native_watch/heat/watch, reason, source)
	var/atom/A = watch.target
	if(!QDELETED(A))
		PUBLISH_CHANGE(A, WATCHED_KEY)

/// The charge channel of the SMES component (a channel index Rust owns).
/proc/smes_charge_channel()
	var/static/channel
	if(isnull(channel))
		channel = vg_world_channel(VG_KIND_SMES, "charge")
	return channel

/// Arms (or widens) the band watch on `S`'s stored charge to cover `levels`: a world watch on the SMES component, owned by this system.
/datum/system/watched/proc/charge_arm(obj/machinery/power/smes/S, list/levels)
	if(!S.vg_entity)
		return
	var/handle = ref_token(S)
	// Readers with different levels share the one watch (the hybrid unit's gate reads its capacity, the modify requirement its 1%): it watches
	// every level asked of this entity, a crossing of any republishes, and each reader keeps its own band. Past CHARGE_LEVELS_MAX the oldest go.
	var/list/merged = list()
	var/list/old = charge_watches[handle]
	if(old && old[3] == S.vg_entity)
		merged += old[1]
	for(var/level in levels)
		if(!(level in merged))
			merged += level
	if(length(merged) > 8)
		merged = levels.Copy()
	merged = sortList(merged, GLOBAL_PROC_REF(cmp_numeric_asc))
	levels = merged
	charge_forget(handle)
	var/datum/native_watch/world/W = world_watch_when(src, COND_BAND(WORLD_HANDLE(VG_KIND_SMES, S.vg_entity), smes_charge_channel(), levels.Copy()), PROC_REF(charge_changed), LANE_SIMULATION)
	charge_watches[handle] = list(levels.Copy(), W.handle, S.vg_entity)
	charge_owners["[W.handle]"] = handle

/// Drops the charge watch of the SMES `handle`, if it has one.
/datum/system/watched/proc/charge_forget(handle)
	var/list/old = charge_watches[handle]
	if(!old)
		return
	charge_watches -= handle
	charge_owners -= "[old[2]]"
	var/datum/native_watch/world/W = kernel_native_native_watch_of(old[2])
	if(W)
		spent(W)

/// Drops the charge watches whose SMES is gone.
/datum/system/watched/proc/charge_prune()
	for(var/handle in charge_watches.Copy())
		var/atom/S = resolve_token(handle)
		if(!isatom(S) || QDELETED(S))
			charge_forget(handle)

/// A charge band watch fired: what reads the SMES's charge re-evaluates.
/datum/system/watched/proc/charge_changed(datum/native_watch/world/watch, reason, source, source_kind)
	charge_wakes++
	var/handle = charge_owners["[watch.handle]"]
	var/atom/S = handle ? resolve_token(handle) : null
	if(!isatom(S) || QDELETED(S))
		if(handle)
			charge_forget(handle)
		return
	PUBLISH_CHANGE(S, WATCHED_KEY)

/// The turfs are registered (SSair): the gas reads that waited for them are armed now.
/datum/system/watched/proc/air_ready()
	if(length(pending))
		wake_work_item(PROC_REF(arm_pending))

/// Arms (or widens) the band watch on `A`'s gas `channel` to cover `levels`: a world band watch on the gas handle of the mixture `A` reads (`air`
/// names the holder var, null the air of its turf), owned by this system.
/datum/system/watched/proc/gas_arm(atom/A, list/levels, channel, air)
	var/datum/gas_mixture/mixture = gas_air_of(A, air)
	var/id = mixture?.arena_id()
	if(isnull(id))
		return
	var/handle = ref_token(A)
	var/key = "[channel]"
	// Readers with other levels on the same channel share the one watch, as a SMES's charge does: it watches every level asked, a crossing of any
	// republishes, and each reader keeps its own band. Past GAS_WATCH_LEVELS_MAX the oldest go.
	var/list/merged = list()
	var/list/old = gas_watches[handle]?[key]
	if(old && old[3] == id)
		merged += old[1]
	for(var/level in levels)
		if(!(level in merged))
			merged += level
	if(length(merged) > GAS_WATCH_LEVELS_MAX)
		merged = levels.Copy()
	merged = sortList(merged, GLOBAL_PROC_REF(cmp_numeric_asc))
	gas_forget(handle, key)
	var/datum/native_watch/world/W = world_watch_when(src, COND_BAND(WORLD_GAS_HANDLE(mixture), channel, merged.Copy()), PROC_REF(gas_changed), LANE_SIMULATION)
	LAZYINITLIST(gas_watches[handle])
	gas_watches[handle][key] = list(merged, W.handle, id)
	gas_owners["[W.handle]"] = list(handle, key)

/// Drops the gas watch of atom `handle` on channel `key`, if it has one.
/datum/system/watched/proc/gas_forget(handle, key)
	var/list/rows = gas_watches[handle]
	var/list/old = rows?[key]
	if(!old)
		return
	rows -= key
	if(!length(rows))
		gas_watches -= handle
	gas_owners -= "[old[2]]"
	var/datum/native_watch/world/W = kernel_native_native_watch_of(old[2])
	if(W)
		spent(W)

/// Drops the gas watches whose atom is gone.
/datum/system/watched/proc/gas_prune()
	for(var/handle in gas_watches.Copy())
		var/atom/A = resolve_token(handle)
		if(isatom(A) && !QDELETED(A))
			continue
		for(var/key in gas_watches[handle].Copy())
			gas_forget(handle, key)

/// `A`'s air was pointed at another mixture (atmos_air_set()): its gas watches follow it. Each is dropped (the next read arms it on the new mixture)
/// and the readers re-run now.
/datum/system/watched/proc/gas_repointed(atom/A)
	var/handle = ref_token(A)
	if(!gas_watches[handle])
		return
	for(var/key in gas_watches[handle].Copy())
		gas_forget(handle, key)
	PUBLISH_CHANGE(A, WATCHED_KEY)

/// A gas band watch fired: what reads the mixture re-evaluates.
/datum/system/watched/proc/gas_changed(datum/native_watch/world/watch, reason, source, source_kind)
	gas_wakes++
	var/list/owner = gas_owners["[watch.handle]"]
	var/atom/A = owner ? resolve_token(owner[1]) : null
	if(!isatom(A) || QDELETED(A))
		if(owner)
			gas_forget(owner[1], owner[2])
		return
	PUBLISH_CHANGE(A, WATCHED_KEY)
