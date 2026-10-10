// The points of interest system (was SSpoints_of_interest). POI loader landmarks queue here as they initialize.
// The kernel loads the boot queue right after SSholomaps (needs; air and persistence boot after it). A POI loaded
// mid-round is placed by the system's every() item, which parks while the queue is empty and wakes when a loader
// enqueues. The API is in poi_api.dm.
GLOBAL_LIST_EMPTY(global_used_pois)

SYSTEM_DEF(pois)
	name = "Points of Interest"
	needs = list(/datum/system/holomaps)
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	VAR_PRIVATE/list/obj/effect/landmark/poi_loader/poi_queue = list()
	/// TRUE while drain_queue() is loading the queue.
	VAR_PRIVATE/loading = FALSE
	/// The items spawned for allocated gamma loot (code/datums/loot/loot.dm; a relation list: a deleted item leaves it).
	VAR_PRIVATE/list/obj/item/allocated_gamma_items

/datum/system/pois/reactions()
	. = ..()
	. += every(1 SECOND, PROC_REF(place_pois), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

CAPABILITIES(/datum/system/pois)
	ref_many(nameof(allocated_gamma_items))

/// Queued loader landmarks: each qdels itself once placed.
/datum/system/pois/declared_cache_vars()
	// ALLOW(sys_static_getter): the object model's per-type declaration hook (read once per type into its type table and parsed by declared_refs_lint.py / ref_kinds.py), owned by the refs lead; not a table getter
	var/static/list/names = list("poi_queue")
	return names

/datum/system/pois/initialize()
	if(initialized)
		return
	initialized = TRUE
	var/loaded = length(poi_queue)
	while (length(poi_queue))
		load_next_poi()
	log_mapping("Initializing POIs")
	log_world("System [name] initialized: [loaded] POI\s loaded.")
	admin_notice(span_danger("Initializing POIs"), R_DEBUG)

/datum/system/pois/stat_entry(msg)
	return "[msg]Queued: [length(poi_queue)]"

/// TRUE while there is queued work and no template load in flight.
/datum/system/pois/proc/has_work()
	return length(poi_queue) && !loading

/// The kernel step: parks while there is nothing to place (enqueue() wakes it).
/datum/system/pois/proc/place_pois(dt)
	if(!has_work())
		return STEP_PARK
	// The queue drains one template load at a time: each load is a job (map_load.dm) whose completion
	// places the next POI, so the kernel never waits on one.
	loading = TRUE
	drain_next()
	return STEP_DONE

/// Starts loading queued POIs until one becomes a pending job (poi_loaded() resumes the drain), or the queue is empty.
/datum/system/pois/proc/drain_next()
	while(length(poi_queue))
		var/pending = FALSE
		try
			pending = load_next_poi_async()
		catch(var/exception/e)
			dq_report_caught(e, "POI load") // a failed load must not wedge `loading` on
		if(pending)
			return
	loading = FALSE

/// A queued POI's template finished loading: place the next one.
/datum/system/pois/proc/poi_loaded(ok)
	drain_next()

/// We select and fire the next PoI in the list, to completion (the boot load).
/datum/system/pois/proc/load_next_poi()
	var/obj/effect/landmark/poi_loader/poi_to_load = poi_queue[1]
	rel_remove(src, nameof(poi_queue), poi_to_load)
	//We then fire it!
	load_poi(poi_to_load)

/// load_next_poi() as a job: TRUE when a template load is pending (poi_loaded() is then called when it finishes).
/datum/system/pois/proc/load_next_poi_async()
	var/obj/effect/landmark/poi_loader/poi_to_load = poi_queue[1]
	rel_remove(src, nameof(poi_queue), poi_to_load)
	return load_poi_async(poi_to_load)

/datum/system/pois/proc/get_turfs_to_clean(obj/effect/landmark/poi_loader/poi_to_load)
	return block(locate(poi_to_load.x, poi_to_load.y, poi_to_load.z), locate((poi_to_load.x + poi_to_load.size_x - 1), (poi_to_load.y + poi_to_load.size_y - 1), poi_to_load.z))

/datum/system/pois/proc/annihilate_bounds(obj/effect/landmark/poi_loader/poi_to_load)
	var/list/turfs_to_clean = get_turfs_to_clean(poi_to_load)
	if(length(turfs_to_clean))
		for(var/x in 1 to 2) // Requires two passes to get everything.
			for(var/turf/T in turfs_to_clean)
				for(var/atom/movable/AM in contents_of(T))
					//++deleted_atoms
					spent(AM)

/// Picks the template a POI loader places and clears its footprint. Null when there is nothing to place.
/datum/system/pois/proc/prepare_poi(obj/effect/landmark/poi_loader/poi_to_load)
	if(!poi_to_load)
		return null
	var/turf/T = get_turf(poi_to_load)
	if(!isturf(T))
		log_mapping("[log_info_line(poi_to_load)] not on a turf! Cannot place poi template.")
		return null

	// Choose a poi
	if(!poi_to_load.poi_type)
		return null

	if(!(length(GLOB.global_used_pois)) || !(GLOB.global_used_pois[poi_to_load.poi_type]))
		GLOB.global_used_pois[poi_to_load.poi_type] = list()
		var/list/poi_list = GLOB.global_used_pois[poi_to_load.poi_type]
		for(var/map in mapping_map_templates())
			var/template = mapping_map_templates()[map]
			if(istype(template, poi_to_load.poi_type))
				poi_list += template

	var/datum/map_template/template_to_use = null

	var/list/our_poi_list = GLOB.global_used_pois[poi_to_load.poi_type]

	if(!length(our_poi_list))
		return null
	else
		template_to_use = pick(our_poi_list)

	if(!template_to_use)
		return null


	if(poi_to_load.remove_from_pool)
		GLOB.global_used_pois[poi_to_load.poi_type] -= template_to_use

	// Annihilate movable atoms
	annihilate_bounds(poi_to_load)
	return template_to_use

/datum/system/pois/proc/load_poi(obj/effect/landmark/poi_loader/poi_to_load)
	var/turf/T = get_turf(poi_to_load)
	var/datum/map_template/template_to_use = prepare_poi(poi_to_load)
	if(!template_to_use)
		return
	// Actually load it
	template_to_use.load(T)
	spent(poi_to_load, src)

/// load_poi() as a job. TRUE when the load is pending: poi_loaded() runs when it finishes.
/datum/system/pois/proc/load_poi_async(obj/effect/landmark/poi_loader/poi_to_load)
	var/turf/T = get_turf(poi_to_load)
	var/datum/map_template/template_to_use = prepare_poi(poi_to_load)
	if(!template_to_use)
		return FALSE
	// The loader is already gone: annihilate_bounds() removed it with the rest of its tile.
	template_to_use.load_async(T, FALSE, PROC_REF(poi_loaded), src)
	return TRUE
