// The points of interest world service (fold wave F4; was SSpoints_of_interest). POI loader
// landmarks queue here as they initialize. The MC loads the boot queue right after SSholomaps
// (boot_after; air and persistence boot after it). A POI loaded mid-round is placed by
// /datum/om/behaviour/world/pois (code/datums/om/world_lanes.dm), parked while the queue is empty.
GLOBAL_LIST_EMPTY(global_used_pois)
GLOBAL_DATUM_INIT(poi_service, /datum/world_service/pois, new)

/datum/world_service/pois
	name = "Points of Interest"
	boot_after = /datum/controller/subsystem/holomaps
	lane = /datum/om/behaviour/world/pois
	on_demand = TRUE
	var/list/obj/effect/landmark/poi_loader/poi_queue = list()
	/// TRUE while drain_queue() is loading the queue.
	var/loading = FALSE

/// Queued loader landmarks: each qdels itself once placed.
/datum/world_service/pois/declared_cache_vars()
	// ALLOW(sys_static_getter): the object model's per-type declaration hook (read once per type into its type table and parsed by declared_refs_lint.py / ref_kinds.py), owned by the refs lead; not a table getter
	var/static/list/names = list("poi_queue")
	return names

/datum/world_service/pois/initialize()
	if(initialized)
		return
	initialized = TRUE
	var/loaded = length(poi_queue)
	while (length(poi_queue))
		load_next_poi()
	log_mapping("Initializing POIs")
	log_world("World service [name] initialized: [loaded] POI\s loaded.")
	admin_notice(span_danger("Initializing POIs"), R_DEBUG)

/// Queues a POI loader; the lane places it (or the boot load does, before initialize()).
/datum/world_service/pois/proc/enqueue(obj/effect/landmark/poi_loader/loader)
	rel_add(src, "poi_queue", loader)
	demand()

/datum/world_service/pois/stat_line()
	return "Queued: [length(poi_queue)]"

/datum/world_service/pois/has_work()
	return length(poi_queue) && !loading

/datum/world_service/pois/service_step(resumed)
	if(loading || !length(poi_queue))
		return TRUE
	// A map template load yields (the reader stoplag()s), and the lane must not sleep: the
	// queue drains in one detached proc, one load at a time.
	loading = TRUE
	INVOKE_ASYNC(src, PROC_REF(drain_queue)) // ALLOW(scheduler): map template loads yield (reader stoplag)
	return TRUE

/// Loads every queued POI, yielding between them; runs detached from the lane.
/datum/world_service/pois/proc/drain_queue()
	while(length(poi_queue))
		try
			load_next_poi()
		catch(var/exception/e)
			dq_report_caught(e, "POI load") // a failed load must not wedge `loading` on
		CHECK_TICK
	loading = FALSE

/// We select and fire the next PoI in the list.
/datum/world_service/pois/proc/load_next_poi()
	var/obj/effect/landmark/poi_loader/poi_to_load = poi_queue[1]
	rel_remove(src, "poi_queue", poi_to_load)
	//We then fire it!
	load_poi(poi_to_load)

/datum/world_service/pois/proc/get_turfs_to_clean(obj/effect/landmark/poi_loader/poi_to_load)
	return block(locate(poi_to_load.x, poi_to_load.y, poi_to_load.z), locate((poi_to_load.x + poi_to_load.size_x - 1), (poi_to_load.y + poi_to_load.size_y - 1), poi_to_load.z))

/datum/world_service/pois/proc/annihilate_bounds(obj/effect/landmark/poi_loader/poi_to_load)
	var/list/turfs_to_clean = get_turfs_to_clean(poi_to_load)
	if(length(turfs_to_clean))
		for(var/x in 1 to 2) // Requires two passes to get everything.
			for(var/turf/T in turfs_to_clean)
				for(var/atom/movable/AM in contents_of(T))
					//++deleted_atoms
					qdel(AM)

/datum/world_service/pois/proc/load_poi(obj/effect/landmark/poi_loader/poi_to_load)
	if(!poi_to_load)
		return
	var/turf/T = get_turf(poi_to_load)
	if(!isturf(T))
		log_mapping("[log_info_line(poi_to_load)] not on a turf! Cannot place poi template.")
		return

	// Choose a poi
	if(!poi_to_load.poi_type)
		return

	if(!(length(GLOB.global_used_pois)) || !(GLOB.global_used_pois[poi_to_load.poi_type]))
		GLOB.global_used_pois[poi_to_load.poi_type] = list()
		var/list/poi_list = GLOB.global_used_pois[poi_to_load.poi_type]
		for(var/map in SSmapping.map_templates)
			var/template = SSmapping.map_templates[map]
			if(istype(template, poi_to_load.poi_type))
				poi_list += template

	var/datum/map_template/template_to_use = null

	var/list/our_poi_list = GLOB.global_used_pois[poi_to_load.poi_type]

	if(!length(our_poi_list))
		return
	else
		template_to_use = pick(our_poi_list)

	if(!template_to_use)
		return


	if(poi_to_load.remove_from_pool)
		GLOB.global_used_pois[poi_to_load.poi_type] -= template_to_use

	// Annihilate movable atoms
	annihilate_bounds(poi_to_load)
	// Actually load it
	template_to_use.load(T)
	qdel(poi_to_load)
