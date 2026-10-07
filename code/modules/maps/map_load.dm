// A map load as a job() (doc/rewrite/final_api.html, section 2 "Chunked work and paths"; section 19 "E6").
//
// Loading a template (or a whole z-level) is long work that must give the tick back, so it is one
// /datum/map_load: a job whose steps each do a bounded chunk of one phase and return JOB_MORE until the
// load is finished, and whose then() schedules the caller's then(). The phases, in order:
//
//   PREPARE  work out where it goes, annihilate what is in the way, allocate the z-level (new_z loads)
//   PARSE    parse the map text, a few regex matches per step (skipped when a parsed map is cached)
//   CACHE    build the model cache, a few models per step
//   BEGIN    SSatoms is told a map load is running; the world grows to fit
//   PLACE    build the cells, MAPLOAD_CHUNK_CELLS per step (parsed_map.load_chunk())
//   INIT     initialize the new atoms, one SSatoms chunk per step (the same frame InitializeAtoms() opens)
//   POST     atmos init, power, the shuttle queue, on_map_loaded()
//
// Loads run one at a time (they share SSatoms' load state and the world's size): a load submitted while
// another runs waits in GLOB.map_load_queue and starts when the running one finishes.
//
// The synchronous drive is the same machine run to completion inline with no budget: map_template.load()
// and load_new_z() use it for the boot map and templates (the kernel is not ticking jobs yet), for nested
// loads and for tests, and a sync parse still yields between matches as `new /datum/parsed_map` always did.

#define MAP_LOAD_AT 1
#define MAP_LOAD_NEW_Z 2

#define MAP_LOAD_PREPARE 1
#define MAP_LOAD_PARSE 2
#define MAP_LOAD_CACHE 3
#define MAP_LOAD_BEGIN 4
#define MAP_LOAD_PLACE 5
#define MAP_LOAD_INIT 6
#define MAP_LOAD_POST 7

/// Regex matches the parser handles per job step.
#define MAP_LOAD_PARSE_MATCHES 24
/// Models the cache builder handles per job step.
#define MAP_LOAD_CACHE_MODELS 12

/// Queued async loads, oldest first (the running load is GLOB.map_load_active).
GLOBAL_LIST_EMPTY(map_load_queue)
GLOBAL_VAR(map_load_active)

/// Queues a load behind the running one.
/proc/map_load_enqueue(datum/map_load/M)
	GLOB.map_load_queue += M

/datum/map_load
	// The load's inputs. Plain references: the load is a short-lived job and the template outlives it
	// (a template is a long-lived singleton; a deleted one fails the load at its next step).
	var/template
	var/mode = MAP_LOAD_AT
	var/centered = FALSE
	var/origin_x = 0
	var/origin_y = 0
	var/origin_z = 0
	/// Run as after(then_owner, 0, then, with = then_with + result) once the load is over (the result is the new z, TRUE, or FALSE); null: nothing.
	var/then
	var/datum/then_owner
	var/list/then_with

	var/phase = MAP_LOAD_PREPARE
	var/result = FALSE
	/// Where the map goes (the template's corner for an `at` load; 1,1 or centered on the new z).
	var/place_x = 0
	var/place_y = 0
	var/place_z = 0
	var/new_z = 0
	var/list/bounds
	var/started_at = 0
	var/timing_inc_z = 0
	var/timing_loaded = 0
	var/steps = 0

	// What is being parsed / placed.
	var/parsed
	/// The parsed map new_z loads copy from (GLOB.cached_maps), while it is still being parsed and cached.
	var/source
	var/cache_key
	var/init_job
	var/list/init_ctx

CAPABILITIES(/datum/map_load)
	ref_one(nameof(then_owner))

/datum/map_load/New(datum/map_template/template, mode, centered, turf/at, then, datum/then_owner, list/then_with)
	src.template = template
	src.mode = mode
	src.centered = centered
	src.then = then
	if(then_owner)
		rel_set(src, nameof(then_owner), then_owner)
	src.then_with = then_with
	if(at)
		origin_x = at.x
		origin_y = at.y
		origin_z = at.z

/// Runs the load as a job, or queues it behind the one running.
/datum/map_load/proc/submit()
	if(GLOB.map_load_active)
		map_load_enqueue(src)
		return src
	start_job()
	return src

/datum/map_load/proc/start_job()
	GLOB.map_load_active = src
	job(src, TYPE_PROC_REF(/datum/map_load, run_step), 20, TYPE_PROC_REF(/datum/map_load, finished))

/// Runs the whole load inline, to completion, and returns its result.
/datum/map_load/proc/run_sync()
	while(advance(TRUE) == JOB_MORE)
		continue
	return result

/// One job step.
/datum/map_load/proc/run_step(datum/act/timer/A)
	return advance(FALSE)

/// The job finished: hand over the result and start whatever was waiting.
/datum/map_load/proc/finished(datum/act/timer/A)
	if(GLOB.map_load_active == src)
		GLOB.map_load_active = null
	after_done(then_owner, then, then_with, result)
	then = null
	rel_clear(src, nameof(then_owner))
	then_with = null
	release()
	if(!GLOB.map_load_active && length(GLOB.map_load_queue))
		var/datum/map_load/next = GLOB.map_load_queue[1]
		GLOB.map_load_queue.Cut(1, 2)
		next.start_job()

/// Drops what the finished load held.
/datum/map_load/proc/release()
	parsed = null
	source = null
	init_job = null
	init_ctx = null

/// Does one chunk of the current phase. JOB_MORE until the load is over (JOB_DONE).
/datum/map_load/proc/advance(sync)
	steps++
	var/datum/map_template/T = template
	if(!istype(T) || QDELETED(T))
		log_mapping("map load: its template was deleted; dropping the load.")
		return abandon()
	var/more = JOB_MORE
	// A runtime in a step must not leave the load (and SSatoms' load state) half open, or every later load would wait on it.
	try
		switch(phase)
			if(MAP_LOAD_PREPARE)
				more = do_prepare(T, sync)
			if(MAP_LOAD_PARSE)
				more = do_parse(sync)
			if(MAP_LOAD_CACHE)
				more = do_cache(sync)
			if(MAP_LOAD_BEGIN)
				more = do_begin(T, sync)
			if(MAP_LOAD_PLACE)
				more = do_place(sync)
			if(MAP_LOAD_INIT)
				more = do_init(T, sync)
			if(MAP_LOAD_POST)
				more = do_post(T)
	catch(var/exception/e)
		dq_report_caught(e, "map load ([T.name], phase [phase])")
		return abandon()
	return more

/// Ends a load that cannot finish: SSatoms and the kernel stop treating a map as loading.
/datum/map_load/proc/abandon()
	var/datum/parsed_map/P = parsed
	if(P?.loading)
		P.load_finish()
		Kernel.StopLoadingMap()
	if(init_ctx)
		var/datum/map_template/T = template
		T?.init_bounds_end(init_ctx)
	result = FALSE
	release()
	return JOB_DONE

/// PREPARE: where it goes and what gets in the way.
/datum/map_load/proc/do_prepare(datum/map_template/T, sync)
	started_at = REALTIMEOFDAY
	if(mode == MAP_LOAD_AT)
		var/turf/origin = locate(origin_x, origin_y, origin_z)
		var/turf/place = origin
		if(centered)
			place = locate(origin_x - round((T.width)/2) , origin_y - round((T.height)/2) , origin_z) // %180 catches East/West (90,270) rotations on true, North/South (0,180) rotations on false
		if(!place)
			return abandon()
		if(place.x+T.width > world.maxx)
			return abandon()
		if(place.y+T.height > world.maxy)
			return abandon()
		if(T.annihilate)
			T.annihilate_bounds(origin, centered)
		place_x = place.x
		place_y = place.y
		place_z = place.z
		// Accept cached maps, but don't save them automatically - we don't want
		// ruins clogging up memory for the whole round.
		var/datum/parsed_map/P = T.parsed_map
		if(!P)
			P = new /datum/parsed_map()
		parsed = P
		source = P
		rel_set(T, nameof(T.parsed_map), T.keep_cached_map ? P : null)
		phase = P.bounds ? MAP_LOAD_CACHE : MAP_LOAD_PARSE
		if(phase == MAP_LOAD_PARSE)
			P.parse_begin(file(T.mappath), -INFINITY, INFINITY, -INFINITY, INFINITY, -INFINITY, INFINITY, FALSE)
		return JOB_MORE
	// A whole new z-level.
	var/x = 1
	var/y = 1
	if(centered)
		x = round((world.maxx - T.width)/2)
		y = round((world.maxy - T.height)/2)
	// This would normally be handled by SSmapping. Capture the allocated z
	// up front: the load yields, and re-reading world.maxz afterward
	// would pick up any z allocated meanwhile, building this map onto the
	// wrong (possibly occupied) z-level. Use new_z everywhere and return it.
	var/old_top_z = world.maxz
	// A freshly allocated template z is an independent level unless its own
	// map_data landmarks explicitly describe a multiz stack. While old_top_z
	// was the top of the world, HasAbove(old_top_z) masked any stale TRUE entry
	// in GLOB.z_levels. Growing world.maxz would otherwise activate that latent
	// edge and vertically join an unrelated shuttle/sector z to this template.
	if(length(GLOB.z_levels) < old_top_z)
		GLOB.z_levels.len = old_top_z
	GLOB.z_levels[old_top_z] = FALSE
	new_z = world.increment_max_z()
	timing_inc_z = REALTIMEOFDAY
	place_x = x
	place_y = y
	place_z = new_z
	T.on_map_preload(new_z)
	cache_key = file(T.mappath)
	if(!(cache_key in GLOB.cached_maps))
		var/datum/parsed_map/P = new /datum/parsed_map()
		source = P
		parsed = P
		phase = MAP_LOAD_PARSE
		P.parse_begin(cache_key, -INFINITY, INFINITY, -INFINITY, INFINITY, -INFINITY, INFINITY, FALSE)
	else
		source = GLOB.cached_maps[cache_key]
		phase = MAP_LOAD_CACHE
	return JOB_MORE

/// PARSE: a few regex matches per step.
/datum/map_load/proc/do_parse(sync)
	var/datum/parsed_map/P = source
	if(P.parse_step(sync ? INFINITY : MAP_LOAD_PARSE_MATCHES, sync))
		return JOB_MORE
	P.parse_finish()
	phase = MAP_LOAD_CACHE
	return JOB_MORE

/// CACHE: a few models per step. The cache is built the way the sync loader builds it (no_changeturf FALSE).
/datum/map_load/proc/do_cache(sync)
	var/datum/parsed_map/P = source
	if(!isnull(P.bounds))
		P.build_cache(FALSE, null, sync ? INFINITY : MAP_LOAD_CACHE_MODELS)
		if(P.cache_building)
			return JOB_MORE
	if(mode == MAP_LOAD_NEW_Z)
		if(!(cache_key in GLOB.cached_maps))
			GLOB.cached_maps[cache_key] = P
		var/datum/parsed_map/cached = GLOB.cached_maps[cache_key]
		parsed = isnull(cached.bounds) ? cached : cached.copy()
	phase = MAP_LOAD_BEGIN
	return JOB_MORE

/// BEGIN: the load starts (the kernel and SSatoms are told), and the world grows to fit.
/datum/map_load/proc/do_begin(datum/map_template/T, sync)
	var/datum/parsed_map/P = parsed
	if(isnull(P.bounds))
		// Nothing parsed: nothing to place (load_map() skipped the load the same way).
		return finish_place(T, FALSE)
	Kernel.StartLoadingMap()
	if(mode == MAP_LOAD_AT)
		P.load_begin(sync, place_x, place_y, place_z, TRUE, FALSE, -INFINITY, INFINITY, -INFINITY, INFINITY, -INFINITY, INFINITY, FALSE, FALSE)
	else
		P.load_begin(sync, place_x, place_y, place_z, FALSE, TRUE, -INFINITY, INFINITY, -INFINITY, INFINITY, -INFINITY, INFINITY, FALSE, TRUE)
	phase = MAP_LOAD_PLACE
	return JOB_MORE

/// PLACE: a chunk of cells per step.
/datum/map_load/proc/do_place(sync)
	var/datum/parsed_map/P = parsed
	if(P.load_chunk(sync) == JOB_MORE)
		return JOB_MORE
	var/ok = P.load_finish()
	Kernel.StopLoadingMap()
	return finish_place(template, ok)

/// The map is placed: on to initializing it, or the end if it placed nothing.
/datum/map_load/proc/finish_place(datum/map_template/T, ok)
	var/datum/parsed_map/P = parsed
	timing_loaded = REALTIMEOFDAY
	if(!ok)
		return abandon()
	bounds = P.bounds
	if(!bounds)
		return abandon()
	// initialize things that are normally initialized after map load
	init_ctx = T.init_bounds_begin(bounds)
	if(!init_ctx)
		phase = MAP_LOAD_POST
		return JOB_MORE
	var/datum/atom_init_job/I = new
	I.atoms = init_ctx["targets"]
	init_job = I
	phase = MAP_LOAD_INIT
	return JOB_MORE

/// SSatoms initializes the new atoms, one chunk per step, through the same frame InitializeAtoms() opens.
/datum/map_load/proc/do_init(datum/map_template/T, sync)
	var/datum/atom_init_job/I = init_job
	if(I.run_step(null, sync) == JOB_MORE)
		return JOB_MORE
	phase = MAP_LOAD_POST
	return JOB_MORE

/// POST: atmos, power and shuttle init for what loaded, then the load's own bookkeeping.
/datum/map_load/proc/do_post(datum/map_template/T)
	if(init_ctx)
		T.init_bounds_end(init_ctx)
		init_ctx = null
	if(mode == MAP_LOAD_AT)
		log_game("[T.name] loaded at at [place_x],[place_y],[place_z]")
		T.loaded++
		result = TRUE
	else
		// Phase timing (real seconds) -- runtime z-loads are rare and were once
		// pathologically slow; keep the breakdown in the log.
		log_game("load_new_z timing: maxz++=[(timing_inc_z - started_at) / 10]s load_map=[(timing_loaded - timing_inc_z) / 10]s initTemplateBounds=[(REALTIMEOFDAY - timing_loaded) / 10]s")
		log_world("load_new_z timing: maxz++=[(timing_inc_z - started_at) / 10]s load_map=[(timing_loaded - timing_inc_z) / 10]s initTemplateBounds=[(REALTIMEOFDAY - timing_loaded) / 10]s")
		log_game("Z-level [T.name] loaded at at [place_x],[place_y],[new_z]")
		T.on_map_loaded(new_z)
		result = new_z
	release()
	return JOB_DONE
