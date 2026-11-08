// Rust-owned state read from reactive code (doc/rewrite/final_api.html section 7, mechanism 5, "Built-ins and Rust-owned state").
//
// A value the Rust simulation owns (a heat body's temperature) changes without a DM write, so a draw, a requirement or a stat input that read
// it raw (`vg_heat_body_temperature()`) could not hear it change. It reads it through
//
//   watched(A, WATCH_HEAT, list(level, level, ...))   a heat body (a sensing, code/domains/heat/heat_sense.dm)
//   watched(T, WATCH_LUM, list(level, ...))           a turf's lum (the lighting engine reports the turf when its corners change)
//   watched(S, WATCH_CHARGE, list(level, ...))        a SMES's stored charge (the SMES senses its levels: sensed(), code/content/power/smes.dm)
//
// instead: the band of the value among the increasing levels (0 below the first, one more for each level at or under it). The read stands for
// the key WATCHED_KEY on A (READS_AS): the reader subscribes to it like any published key. The first read of a band arms a heat sensing on
// A (the watched system, after the read: an output does not register anything itself); every band change Rust reports publishes WATCHED_KEY on
// A, and the reader re-evaluates. One sensing per source on an atom: a read with other levels replaces it (a SMES senses its own levels instead). A watched atom keeps a heat
// body while the sensing lives.

/// The band of `value` among the increasing `levels`: how many of them are at or under it.
/proc/watched_band(value, list/levels, strict = FALSE)
	READS_FROM()
	. = 0
	for(var/level in levels)
		if(strict ? value <= level : value < level)
			break
		.++

/// `A`'s Rust-owned `source` (WATCH_HEAT: its temperature), as its band among the increasing `levels`. Reactive code reads Rust-owned state only
/// through this: the read subscribes to WATCHED_KEY on A, which the band watch publishes.
READS_AS(/proc/watched, WATCHED_KEY)
/// `strict`: a level counts only once the value is above it (`value > level`, the old strict comparison of a reader that refused "above 1%");
/// by default a value on a level is in the band above it.
/proc/watched(atom/A, source, list/levels, strict = FALSE)
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
			if(!T.lighting_ensure_object())
				return watched_band(value, levels, strict) // no dynamic lighting: its lum is fixed
		if(WATCH_CHARGE)
			var/obj/machinery/power/smes/S = A
			if(!istype(S))
				CRASH("watched(): WATCH_CHARGE reads a SMES, not [A.type]")
			value = S.stored_charge()
			if(!S.vg_entity)
				return watched_band(value, levels, strict) // not registered with Rust yet: its charge is the seed, nothing to watch
		else
			CRASH("watched(): unknown source [source]")
	if(source != WATCH_CHARGE && !watched_armed(A, source, levels))
		SSwatched.request(A, source, levels) // a SMES senses its own levels (sensed()): nothing is armed for a read of its charge
	return watched_band(value, levels, strict)

/// TRUE when `A` already has the band watch `watched()` would arm for these levels.
/proc/watched_armed(atom/A, source, list/levels)
	if(source == WATCH_LUM)
		var/turf/T = A
		return !!T.lighting_object?.lum_watch?[jointext(levels, ",")]
	for(var/datum/sense_sub/heat/watched/W as anything in A.heat_subs)
		if(W.levels ~= levels)
			return TRUE
	return FALSE

/// Arms the sensings reactive reads asked for (watched()), after the read: an output never registers a watch itself.
SYSTEM_DEF(watched)
	name = "Watched bands"
	/// Rows list(atom handle, source, levels) waiting to be armed, oldest first (a handle: an atom deleted while it waits is skipped).
	VAR_PRIVATE/list/pending = list()
	/// Turf handles whose lighting changed since the last pass (lum_changed()), each once.
	VAR_PRIVATE/list/lum_pending = list()

/datum/system/watched/reactions()
	. = ..()
	. += every(1, PROC_REF(arm_pending), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/// Queues a heat sensing on `A`'s `source` over `levels`.
/datum/system/watched/proc/request(atom/A, source, list/levels)
	pending += list(list(handle_of(A), source, levels.Copy()))
	wake_work_item(PROC_REF(arm_pending))

/datum/system/watched/proc/arm_pending(dt)
	if(length(lum_pending))
		lum_publish()
	if(!length(pending))
		return STEP_PARK
	var/list/rows = pending
	pending = list()
	for(var/list/row as anything in rows)
		var/atom/A = handle_get(row[1])
		if(!isatom(A) || QDELETED(A) || watched_armed(A, row[2], row[3]))
			continue
		if(row[2] == WATCH_LUM)
			lum_arm(A, row[3])
			continue
		// One sensing per source on an atom: the old levels go.
		for(var/datum/sense_sub/heat/watched/old as anything in A.heat_subs?.Copy())
			spent(old)
		switch(row[2])
			if(WATCH_HEAT)
				// keep_body: the atom keeps a heat body while watched, so the band follows it at rest too (a body at rest reads its
				// surroundings unwatched).
				sense_heat(A, TYPE_PROC_REF(/atom, watched_band_heard), A, row[3], sub_type = /datum/sense_sub/heat/watched)
				PUBLISH_CHANGE(A, WATCHED_KEY) // the reader read before this was armed: it reads again, so a move in between is not lost
	return STEP_PARK

/// Lum bands are DM's own (the lighting engine): the lighting object of `T` remembers each band a reader asked for and the band it last
/// published, and lighting_object/update() reports the turf here when its corners changed.
/datum/system/watched/proc/lum_arm(turf/T, list/levels)
	var/datum/lighting_object/O = T.lighting_ensure_object()
	if(!O)
		return
	LAZYINITLIST(O.lum_watch)
	O.lum_watch[jointext(levels, ",")] = list(levels, watched_band(T.get_lumcount(), levels))

/// `T`'s lighting changed this tick: checked once at the next pass (coalesced per turf).
/datum/system/watched/proc/lum_changed(turf/T)
	var/handle = handle_of(T)
	if(lum_pending[handle])
		return
	lum_pending[handle] = TRUE
	wake_work_item(PROC_REF(arm_pending))

/// Publishes WATCHED_KEY on each pending turf whose lum left a band a reader watches.
/datum/system/watched/proc/lum_publish()
	var/list/turfs = lum_pending
	lum_pending = list()
	for(var/handle in turfs)
		var/turf/T = handle_get(handle)
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

/// A watched band moved: what reads the watched value re-evaluates.
/atom/proc/watched_band_heard(band, was)
	PUBLISH_CHANGE(src, WATCHED_KEY)

/// A heat sensing a reactive read asked for (watched()); the atom is its own owner.
/datum/sense_sub/heat/watched
