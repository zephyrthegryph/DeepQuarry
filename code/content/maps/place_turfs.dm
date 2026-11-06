// place_turfs(): post-boot construction of turfs as one load.
//
// A site built after boot (a generated station, a building, a carved cave) is a list of final turfs, not a series of
// edits. place_turfs() builds it the way a template placed at a location is built (map_load.dm): the world is told a
// map is loading (air registration waits), the new turfs and their contents are created without initializing, then one
// atom_init_job initializes them in one frame, so adjacency and cable binds flush once for the whole site. A turf that
// already is its final type is left alone.
//
//     place_turfs(types, areas, things)                to completion, returns the new turfs
//     place_turfs_async(types, areas, things, then =)  as lane work, then(placed turfs) runs when it ends
//
// types: turf (a current turf of the site) -> final turf path. areas: turf -> area it ends in. things: turf -> list of paths created on it
// (a thing that needs arguments is made by its creator afterwards, with make(), once the frame has closed).

#define PLACE_TURFS_PLACE 1
#define PLACE_TURFS_INIT 2
#define PLACE_TURFS_DONE 3
/// Turfs placed between two looks at the tick budget.
#define PLACE_TURFS_CHUNK 32

/// Turfs replaced by place_turfs() since boot (a deterministic cost counter for tests and the first-load report).
GLOBAL_VAR_INIT(place_turfs_replaced, 0)
/// Turfs place_turfs() left alone because they already were their final type.
GLOBAL_VAR_INIT(place_turfs_kept, 0)
/// Loads place_turfs() ran (one frame each).
GLOBAL_VAR_INIT(place_turfs_load_count, 0)

/datum/turf_placement
	var/list/types
	var/list/areas
	var/list/things
	/// Clear a turf's movables (not a player's mob) before it is replaced.
	var/clear = TRUE
	/// Keep a turf's outdoors flag across the replacement (ChangeTurf(preserve_outdoors =)).
	var/preserve_outdoors = FALSE
	/// ChangeTurf(tell_universe =): tell the universe state the turf changed (a placement of a few turfs in a running round, like a shuttle's ceiling).
	var/tell_universe = FALSE
	/// ChangeTurf(force_lighting_update =): rebuild the turf's lighting even when it did not change its opacity.
	var/force_lighting_update = FALSE
	var/phase = PLACE_TURFS_PLACE
	var/began = FALSE
	var/failed = FALSE
	/// The turfs still to place, and where the next one is.
	var/tmp/list/queue
	var/index = 1
	/// The new turfs, in placement order, and the contents made: the frame initializes the turfs, then the contents.
	var/tmp/list/placed
	var/tmp/list/things_made
	var/datum/atom_init_job/init_job
	var/replaced = 0
	var/kept = 0
	var/made = 0
	var/changes_at_start = 0
	var/started_at = 0
	var/then
	var/datum/then_owner
	var/list/then_with
	var/label = "turfs"

CAPABILITIES(/datum/turf_placement)
	ref_one(nameof(then_owner))
	owns_one(nameof(init_job), /datum/atom_init_job)

/datum/turf_placement/New(list/types, list/areas = null, list/things = null, clear = TRUE, label = "turfs", preserve_outdoors = FALSE, tell_universe = FALSE, force_lighting_update = FALSE)
	..()
	src.types = types
	src.areas = areas
	src.things = things
	src.clear = clear
	src.label = label
	src.preserve_outdoors = preserve_outdoors
	src.tell_universe = tell_universe
	src.force_lighting_update = force_lighting_update
	queue = types.Copy()
	placed = list()
	things_made = list()

/// This placement's tracked-init source for SSatoms.
/datum/turf_placement/proc/source()
	return "place_turfs [REF(src)]"

/// Starts the load, as lane work: then, owner and with run as after() does, with the new turfs added.
/datum/turf_placement/proc/submit(then = null, datum/then_owner = null, list/then_with = null)
	src.then = then
	if(then_owner)
		rel_set(src, nameof(then_owner), then_owner)
	src.then_with = then_with
	job(src, TYPE_PROC_REF(/datum/turf_placement, run_step), 30, TYPE_PROC_REF(/datum/turf_placement, finished))
	return src

/datum/turf_placement/proc/run_step(datum/act/timer/A)
	return advance(FALSE)

/datum/turf_placement/proc/finished(datum/act/timer/A)
	var/callback = then
	var/datum/callback_owner = then_owner
	var/list/callback_with = then_with
	var/list/result = placed
	then = null
	rel_clear(src, nameof(then_owner))
	if(callback)
		after(callback_owner, 0, callback, with = (callback_with || list()) + list(result))

/// One chunk of the load. JOB_MORE until it is over (JOB_DONE). `sync` runs a chunk to its end without looking at the tick.
/datum/turf_placement/proc/advance(sync = FALSE)
	if(!began)
		began = TRUE
		started_at = REALTIMEOFDAY
		changes_at_start = GLOB.turf_change_calls
		GLOB.place_turfs_load_count++
		Kernel.StartLoadingMap()
	// A runtime in a step must not leave SSatoms and the kernel believing a map is loading.
	try
		switch(phase)
			if(PLACE_TURFS_PLACE)
				return place_chunk(sync)
			if(PLACE_TURFS_INIT)
				return init_chunk(sync)
	catch(var/exception/e)
		dq_report_caught(e, "place_turfs ([label], phase [phase])")
		return abort()
	return JOB_DONE

/datum/turf_placement/proc/abort()
	failed = TRUE
	SSatoms.map_loader_stop(source())
	if(phase == PLACE_TURFS_PLACE)
		Kernel.StopLoadingMap()
	phase = PLACE_TURFS_DONE
	rel_clear(src, nameof(init_job))
	return JOB_DONE

/// PLACE: turfs from the cursor, created without initializing, until the budget is spent.
/datum/turf_placement/proc/place_chunk(sync)
	var/src_id = source()
	SSatoms.map_loader_begin(src_id)
	var/looked = 0
	var/list/chunk_turfs = list()
	var/list/chunk_things = list()
	while(index <= length(queue))
		place_one(queue[index++], chunk_turfs, chunk_things)
		if(!sync && ++looked >= PLACE_TURFS_CHUNK)
			looked = 0
			if(time_scheduler().out_of_budget())
				break
	SSatoms.map_loader_stop(src_id)
	placed += chunk_turfs
	things_made += chunk_things
	if(index <= length(queue))
		return JOB_MORE
	// Air waits for the whole site, as it waits for a template (SSair registers what the load made).
	Kernel.StopLoadingMap()
	queue = null
	var/datum/atom_init_job/I = new
	I.atoms = placed + things_made
	rel_set(src, nameof(init_job), I)
	phase = PLACE_TURFS_INIT
	return JOB_MORE

/datum/turf_placement/proc/place_one(turf/T, list/made_turfs, list/made_things)
	var/path = types[T]
	if(clear)
		for(var/atom/movable/AM in turf_contents_of_type(T, /atom/movable))
			if(ismob(AM))
				var/mob/M = AM
				if(M.client)
					continue
			spent(AM)
	var/turf/W = T
	if(T.type == path)
		kept++
		GLOB.place_turfs_kept++
	else
		W = T.ChangeTurf(path, tell_universe = tell_universe, force_lighting_update = force_lighting_update, preserve_outdoors = preserve_outdoors)
		replaced++
		GLOB.place_turfs_replaced++
		made_turfs += W
	var/area/A = areas?[T]
	if(A && get_area(W) != A)
		W.assign_area(A)
	for(var/content_path in things?[T])
		made_things += new content_path(W)
		made++

/// INIT: one atom_init_job over the new turfs and their contents (one frame: adjacency and cable binds flush when it closes).
/datum/turf_placement/proc/init_chunk(sync)
	var/datum/atom_init_job/I = init_job
	if(I.run_step(null, sync) == JOB_MORE)
		return JOB_MORE
	phase = PLACE_TURFS_DONE
	rel_clear(src, nameof(init_job))
	things_made = null
	log_world("place_turfs ([label]): [replaced] turfs replaced, [kept] kept, [made] contents, [GLOB.turf_change_calls - changes_at_start] ChangeTurf calls, [(REALTIMEOFDAY - started_at) / 10]s.")
	return JOB_DONE

/// Places `types` to completion and returns the new turfs.
/proc/place_turfs(list/types, list/areas = null, list/things = null, clear = TRUE, label = "turfs", preserve_outdoors = FALSE, tell_universe = FALSE, force_lighting_update = FALSE)
	var/datum/turf_placement/P = new(types, areas, things, clear, label, preserve_outdoors, tell_universe, force_lighting_update)
	while(P.advance(TRUE) == JOB_MORE)
		continue
	. = P.placed
	spent(P)

/// place_turfs() as lane work; then(placed turfs) runs on `owner` when it ends.
/proc/place_turfs_async(list/types, list/areas = null, list/things = null, then = null, datum/owner = null, list/with = null, clear = TRUE, label = "turfs", preserve_outdoors = FALSE, tell_universe = FALSE, force_lighting_update = FALSE)
	var/datum/turf_placement/P = new(types, areas, things, clear, label, preserve_outdoors, tell_universe, force_lighting_update)
	return P.submit(then, owner, with)

#undef PLACE_TURFS_CHUNK

/// Places `types` (turf -> final path) inside a load that is already running: the caller has told the kernel a map is loading and put SSatoms in a
/// map-load state, so the new turfs wait for the load's own init frame (nothing here opens one). `preloads` (turf -> attributes) are the map's
/// variable edits of a turf, set up for its creation as the map reader does. Every turf is replaced, even one already of its final path: a
/// template placed over used ground must end up exactly as the map says (a replacement drops the old turf's damage, decals and runtime edits).
/// Returns the new turfs.
/proc/place_turfs_in_load(list/types, list/preloads = null)
	var/list/placed = list()
	for(var/turf/T as anything in types)
		var/path = types[T]
		var/list/attributes = preloads?[T]
		if(length(attributes))
			world.preloader_setup(attributes, path)
		var/turf/W = T.ChangeTurf(path, FALSE, TRUE)
		GLOB.place_turfs_replaced++
		if(GLOB.use_preloader && W) // the second pass, for a turf that does not call ..() in New()
			world.preloader_load(W)
		if(W)
			placed += W
	return placed
