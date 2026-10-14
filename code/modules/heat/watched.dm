// Rust-owned state read from reactive code (doc/rewrite/final_api.html section 7, mechanism 5, "Built-ins and Rust-owned state").
//
// A value the Rust simulation owns (a heat body's temperature) changes without a DM write, so a draw, a requirement or a stat input that read
// it raw (`vg_heat_body_temperature()`) could not hear it change. It reads it through
//
//   watched(A, WATCH_HEAT, list(level, level, ...))   a heat body (a native band watch in Rust)
//   watched(T, WATCH_LUM, list(level, ...))           a turf's lum (the lighting engine reports the turf when its corners change)
//
// instead: the band of the value among the increasing levels (0 below the first, one more for each level at or under it). The read stands for
// the key WATCHED_KEY on A (READS_AS): the reader subscribes to it like any published key. The first read of a band arms a native band watch on
// A (the watched system, after the read: an output does not register anything itself); every band change Rust reports publishes WATCHED_KEY on
// A, and the reader re-evaluates. One band watch per source on an atom: a read with other levels replaces it. A watched atom keeps a heat
// body while the watch lives.

/// The band of `value` among the increasing `levels`: how many of them are at or under it.
/proc/watched_band(value, list/levels)
	READS_FROM()
	. = 0
	for(var/level in levels)
		if(value < level)
			break
		.++

/// `A`'s Rust-owned `source` (WATCH_HEAT: its temperature), as its band among the increasing `levels`. Reactive code reads Rust-owned state only
/// through this: the read subscribes to WATCHED_KEY on A, which the band watch publishes.
READS_AS(/proc/watched, WATCHED_KEY)
/proc/watched(atom/A, source, list/levels)
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
				return watched_band(value, levels) // no dynamic lighting: its lum is fixed
		else
			CRASH("watched(): unknown source [source]")
	if(!watched_armed(A, source, levels))
		SSwatched.request(A, source, levels)
	return watched_band(value, levels)

/// TRUE when `A` already has the band watch `watched()` would arm for these levels.
/proc/watched_armed(atom/A, source, list/levels)
	if(source == WATCH_LUM)
		var/turf/T = A
		return !!T.lighting_object?.lum_watch?[jointext(levels, ",")]
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

/// This system's entity handle (taken on first use: handles do not exist yet while the systems are made).
/datum/system/watched/proc/watch_owner()
	if(!watch_owner_ref)
		watch_owner_ref = entity_handle(src)
	return watch_owner_ref

/datum/system/watched/reactions()
	. = ..()
	. += every(1, PROC_REF(arm_pending), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/// Queues a band watch on `A`'s `source` over `levels`.
/datum/system/watched/proc/request(atom/A, source, list/levels)
	pending += list(list(entity_handle(A), source, levels.Copy()))
	wake_work_item(PROC_REF(arm_pending))

/datum/system/watched/proc/arm_pending(dt)
	if(length(lum_pending))
		lum_publish()
	if(!length(pending))
		return STEP_PARK
	var/list/rows = pending
	pending = list()
	for(var/list/row as anything in rows)
		var/atom/A = resolve_handle(row[1])
		if(!isatom(A) || QDELETED(A) || watched_armed(A, row[2], row[3]))
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
	var/handle = entity_handle(T)
	if(lum_pending[handle])
		return
	lum_pending[handle] = TRUE
	wake_work_item(PROC_REF(arm_pending))

/// Publishes WATCHED_KEY on each pending turf whose lum left a band a reader watches.
/datum/system/watched/proc/lum_publish()
	var/list/turfs = lum_pending
	lum_pending = list()
	for(var/handle in turfs)
		var/turf/T = resolve_handle(handle)
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
