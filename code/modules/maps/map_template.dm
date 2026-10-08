/datum/map_template
	var/name = "Default Template Name"
	var/width = 0
	var/height = 0
	var/mappath = null
	var/loaded = 0 // Times loaded this round
	var/datum/parsed_map/parsed_map
	var/keep_cached_map = FALSE

	// Virgo stuff
	var/desc = "Some text should go here. Maybe."
	var/name_alias // Override to what this map gets registered as in map_templates_loaded
	var/template_group = null // If this is set, no more than one template in the same group will be spawned, per submap seeding.
	var/annihilate = FALSE // If true, all (movable) atoms at the location where the map is loaded will be deleted before the map is loaded in.

	var/cost = null /* The map generator has a set 'budget' it spends to place down different submaps. It will pick available submaps randomly until
	it runs out. The cost of a submap should roughly corrispond with several factors such as size, loot, difficulty, desired scarcity, etc.
	Set to -1 to force the submap to always be made. */
	var/allow_duplicates = FALSE // If false, only one map template will be spawned by the game. Doesn't affect admins spawning then manually.
	var/discard_prob = 0 // If non-zero, there is a chance that the map seeding algorithm will skip this template when selecting potential templates to use.

CAPABILITIES(/datum/map_template)
	owns_one(nameof(parsed_map), /datum/parsed_map)

/datum/map_template/New(path = null, rename = null, cache = FALSE)
	SHOULD_CALL_PARENT(TRUE)
	. = ..()
	if(path)
		mappath = path
	if(mappath)
		preload_size(mappath, cache)
	if(rename)
		name = rename

/datum/map_template/proc/preload_size(path, cache = FALSE)
	if(!cache)
		var/list/cached_bounds = build_time_template_bounds(path)
		if(cached_bounds)
			width = cached_bounds[MAP_MAXX] // Same rectangular, single-Z assumption as below
			height = cached_bounds[MAP_MAXY]
			return cached_bounds
	var/datum/parsed_map/parsed = new(file(path))
	var/bounds = parsed?.bounds
	if(bounds)
		width = bounds[MAP_MAXX] // Assumes all templates are rectangular, have a single Z level, and begin at 1,1,1
		height = bounds[MAP_MAXY]
		if(cache)
			rel_set(src, nameof(parsed_map), parsed)
	return bounds

/// Bounds written by the build (tools/build/lib/map_bounds.ts) so templates don't
/// have to be parsed just to learn their size (Q2). Returns a copy of the six bounds,
/// or null when the file has no entry or its size changed since the build.
/proc/build_time_template_bounds(path)
	var/static/list/bounds_by_path
	if(isnull(bounds_by_path))
		bounds_by_path = list()
		if(fexists("data/map_template_bounds.json"))
			var/list/decoded = json_decode(file2text("data/map_template_bounds.json"))
			if(islist(decoded))
				bounds_by_path = decoded
	if(!istext(path))
		return null
	var/list/entry = bounds_by_path[replacetext(path, "\\", "/")]
	if(length(entry) != 7 || !fexists(path) || length(file(path)) != entry[7])
		return null
	return entry.Copy(1, 7)

/datum/map_template/proc/initTemplateBounds(list/bounds)
	var/list/ctx = init_bounds_begin(bounds)
	if(!ctx)
		return // let proper initialisation handle it later
	SSatoms.InitializeAtoms(ctx["targets"])
	init_bounds_end(ctx)

/// The first half of initTemplateBounds(): gathers what the load made and holds the shuttle init queue. Returns a
/// context list (its "targets" are the atoms to initialize, in order: areas, turfs, then movables) for
/// init_bounds_end(), or null when SSatoms is still setting up (proper initialisation handles them later).
/datum/map_template/proc/init_bounds_begin(list/bounds)
	if(SSatoms.initialized == INITIALIZATION_INSSATOMS)
		return null

	var/prev_shuttle_queue_state = SSshuttles.block_init_queue
	SSshuttles.block_init_queue = TRUE

	var/list/atom/atoms = list()
	var/list/area/areas = list()
	var/list/obj/structure/cable/cables = list()
	var/list/obj/machinery/atmospherics/atmos_machines = list()
	var/list/turf/turfs = block(locate(bounds[MAP_MINX], bounds[MAP_MINY], bounds[MAP_MINZ]),
								locate(bounds[MAP_MAXX], bounds[MAP_MAXY], bounds[MAP_MAXZ]))
	for(var/turf/B as anything in turfs)
		areas |= B.loc
		for(var/A in B)
			atoms += A
			if(istype(A, /obj/structure/cable))
				cables += A
			else if(istype(A, /obj/machinery/atmospherics))
				atmos_machines += A
	for(var/obj/machinery/atmospherics/atmos_to_reenable as anything in atmos_machines)
		atmos_to_reenable.being_loaded = TRUE

	admin_notice(span_danger("Initializing newly created atom(s) in submap."), R_DEBUG)
	var/list/initialization_targets = areas.Copy()
	initialization_targets.Add(turfs)
	initialization_targets.Add(atoms)
	return list("targets" = initialization_targets, "areas" = areas, "atmos" = atmos_machines, "shuttle_queue" = prev_shuttle_queue_state)

/// The second half of initTemplateBounds(), once the atoms are initialized.
/datum/map_template/proc/init_bounds_end(list/ctx)
	var/list/area/areas = ctx["areas"]
	var/list/obj/machinery/atmospherics/atmos_machines = ctx["atmos"]
	admin_notice(span_danger("Initializing atmos pipenets and machinery in submap."), R_DEBUG)
	// The old SSmachines.setup_atmos_machinery was stubbed by the LINDA
	// migration. SSair now owns atmos-machine init; for submap loads (which
	// run after SSair.Initialize) wire just the freshly-loaded devices
	// instead of re-scanning the whole all_machines list.
	for(var/obj/machinery/atmospherics/AM as anything in atmos_machines)
		AM.atmos_init()

	// Ensure all machines in loaded areas get notified of power status
	for(var/area/A as anything in areas)
		A.power_change()

	for(var/obj/machinery/atmospherics/atmos_to_reenable as anything in atmos_machines)
		atmos_to_reenable.being_loaded = FALSE

	SSshuttles.block_init_queue = ctx["shuttle_queue"]
	SSshuttles.process_init_queues() // We will flush the queue unless there were other blockers, in which case they will do it.

	admin_notice(span_danger("Submap initializations finished."), R_DEBUG)

/// Loads this template onto a brand new z-level and returns it (FALSE on failure), to completion without yielding:
/// the boot, nested and test drive of the map load (map_load.dm). A load that runs while players are on is
/// load_new_z_async().
/datum/map_template/proc/load_new_z(centered = FALSE)
	var/datum/map_load/M = new(src, MAP_LOAD_NEW_Z, centered)
	return M.run_sync()

/// load_new_z() as a job: once it has loaded, after(owner, 0, then, with = with + new z (or FALSE)) runs.
/datum/map_template/proc/load_new_z_async(centered = FALSE, then = null, datum/owner = null, list/with = null)
	var/datum/map_load/M = new(src, MAP_LOAD_NEW_Z, centered, null, then, owner, with)
	return M.submit()

/// Loads this template at `T`, to completion without yielding (boot, nested and test loads; see load_new_z()).
/// Returns TRUE if it loaded. A load that runs while players are on is load_async().
/datum/map_template/proc/load(turf/T, centered = FALSE)
	if(!T)
		return FALSE
	var/datum/map_load/M = new(src, MAP_LOAD_AT, centered, T)
	return M.run_sync()

/// load() as a job: once the template has loaded, after(owner, 0, then, with = with + TRUE or FALSE) runs.
/datum/map_template/proc/load_async(turf/T, centered = FALSE, then = null, datum/owner = null, list/with = null)
	if(!T)
		if(then)
			after(owner, 0, then, with = (with || list()) + list(FALSE))
		return null
	var/datum/map_load/M = new(src, MAP_LOAD_AT, centered, T, then, owner, with)
	return M.submit()

/// An admin-placed template finished loading (load_async()'s completion).
/datum/map_template/proc/admin_placed(mob/user, ok)
	if(ok)
		message_admins(span_adminnotice("[key_name_admin(user)] has placed a map template ([name])."))
	else
		to_chat(user, "Failed to place map")

/// An admin-placed template finished loading on a new z-level (load_new_z_async()'s completion).
/datum/map_template/proc/admin_placed_z(mob/user, z)
	if(z)
		message_admins(span_adminnotice("[key_name_admin(user)] has placed a map template ([name]) on Z level [z]."))
	else
		to_chat(user, "Failed to place map")

/datum/map_template/proc/get_affected_turfs(turf/T, centered = FALSE)
	var/turf/placement = T
	if(centered)
		var/turf/corner = locate(placement.x - round(width/2), placement.y - round(height/2), placement.z)
		if(corner)
			placement = corner
	return block(placement.x, placement.y, placement.z, placement.x+width-1, placement.y+height-1, placement.z)

/datum/map_template/proc/annihilate_bounds(turf/origin, centered = FALSE)
	var/deleted_atoms = 0
	admin_notice(span_danger("Annihilating objects in submap loading locatation."), R_DEBUG)
	var/list/turfs_to_clean = get_affected_turfs(origin, centered)
	if(length(turfs_to_clean))
		for(var/turf/T in turfs_to_clean)
			for(var/atom/movable/AM in contents_of(T))
				++deleted_atoms
				spent(AM)
	admin_notice(span_danger("Annihilated [deleted_atoms] objects."), R_DEBUG)

/// Takes in a type path, locates an instance of that type in the cached map, and calculates its offset from the origin of the map, returns this offset in the form list(x, y).
/datum/map_template/proc/discover_offset(obj/marker)
	var/key
	var/list/models = parsed_map.grid_models
	for(key in models)
		if(findtext(models[key], "[marker]")) // Yay compile time checks
			break // This works by assuming there will ever only be one mobile dock in a template at most

	for(var/datum/grid_set/gset as anything in parsed_map.gridSets)
		var/ycrd = gset.ycrd
		for(var/line in gset.gridLines)
			var/xcrd = gset.xcrd
			for(var/j in 1 to length(line) step parsed_map.key_len)
				if(key == copytext(line, j, j + parsed_map.key_len))
					return list(xcrd, ycrd)
				++xcrd
			--ycrd

//for your ever biggening badminnery kevinz000
//❤ - Cyberboss
/proc/load_new_z_level(file, name)
	var/datum/map_template/template = new(file, name, TRUE)
	if(!template.parsed_map || template.parsed_map.check_for_errors())
		return FALSE
	template.load_new_z()
	return TRUE

// Very similar to the /tg/ version.
/proc/seed_submaps(list/z_levels, budget = 0, whitelist = /area/space, desired_map_template_type = null)
	set background = TRUE

	if(!z_levels || !length(z_levels))
		admin_notice("seed_submaps() was not given any Z-levels.", R_DEBUG)
		return

	for(var/zl in z_levels)
		var/turf/T = locate(1, 1, zl)
		if(!T)
			admin_notice("Z level [zl] does not exist - Not generating submaps", R_DEBUG)
			return

	var/overall_sanity = 100 // If the proc fails to place a submap more than this, the whole thing aborts.
	var/list/potential_submaps = list() // Submaps we may or may not place.
	var/list/priority_submaps = list() // Submaps that will always be placed.

	// Lets go find some submaps to make.
	for(var/map in SSmapping.map_templates)
		var/datum/map_template/MT = SSmapping.map_templates[map]
		if(!MT.allow_duplicates && MT.loaded > 0) // This probably won't be an issue but we might as well.
			continue
		if(!istype(MT, desired_map_template_type)) // Not the type wanted.
			continue
		if(MT.discard_prob && prob(MT.discard_prob))
			continue
		if(MT.cost && MT.cost < 0) // Negative costs always get spawned.
			priority_submaps += MT
		else
			potential_submaps += MT

	CHECK_TICK

	var/list/loaded_submap_names = list()
	var/list/template_groups_used = list() // Used to avoid spawning three seperate versions of the same PoI.

	// Now lets start choosing some.
	while(budget > 0 && overall_sanity > 0)
		overall_sanity--
		var/datum/map_template/chosen_template = null

		if(length(potential_submaps))
			if(length(priority_submaps)) // Do these first.
				chosen_template = pick(priority_submaps)
			else
				chosen_template = pick(potential_submaps)

		else // We're out of submaps.
			admin_notice("Submap loader had no submaps to pick from with [budget] left to spend.", R_DEBUG)
			break

		CHECK_TICK

		// Can we afford it?
		if(chosen_template.cost > budget)
			priority_submaps -= chosen_template
			potential_submaps -= chosen_template
			continue

		// Is single use template already placed
		if(!chosen_template.allow_duplicates && chosen_template.loaded)
			priority_submaps -= chosen_template
			potential_submaps -= chosen_template
			continue

		// Did we already place down a very similar submap?
		if(chosen_template.template_group && (chosen_template.template_group in template_groups_used))
			priority_submaps -= chosen_template
			potential_submaps -= chosen_template
			continue

		// If so, try to place it.
		var/specific_sanity = 100 // A hundred chances to place the chosen submap.
		while(specific_sanity > 0)
			specific_sanity--

			chosen_template.preload_size(chosen_template.mappath)
			var/width_border = SUBMAP_MAP_EDGE_PAD + round((chosen_template.width) / 2)
			var/height_border = SUBMAP_MAP_EDGE_PAD + round((chosen_template.height) / 2)
			var/z_level = pick(z_levels)
			var/turf/T = locate(rand(width_border, world.maxx - width_border), rand(height_border, world.maxy - height_border), z_level)
			var/valid = TRUE

			for(var/turf/check in chosen_template.get_affected_turfs(T,TRUE))
				var/area/new_area = get_area(check)
				if(!(istype(new_area, whitelist)))
					valid = FALSE // Probably overlapping something important.
					break
				CHECK_TICK

			CHECK_TICK

			if(!valid)
				continue

			admin_notice("Submap \"[chosen_template.name]\" placed at ([T.x], [T.y], [T.z])\n", R_DEBUG)

			if(specific_sanity < 0)
				// I have no idea how this function has a race condition for the sanity check, but forcing the inner check loop to end like this fixes it...
				// If a template doesn't allow duplicates, it tries to double place a template. this fixes that.
				break
			if(!chosen_template.allow_duplicates)
				specific_sanity = -1 // force end the placement loop

			// Do loading here.
			chosen_template.load(T, centered = TRUE) // This is run before the main map's initialization routine, so that can initilize our submaps for us instead.

			CHECK_TICK

			// For pretty maploading statistics.
			if(loaded_submap_names[chosen_template.name])
				loaded_submap_names[chosen_template.name] += 1
			else
				loaded_submap_names[chosen_template.name] = 1

			// To avoid two 'related' similar submaps existing at the same time.
			if(chosen_template.template_group)
				template_groups_used += chosen_template.template_group

			// To deduct the cost.
			if(chosen_template.cost >= 0)
				budget -= chosen_template.cost

			// Remove the submap from our options.
			if(chosen_template in priority_submaps) // Always remove priority submaps.
				priority_submaps -= chosen_template
			else if(!chosen_template.allow_duplicates)
				potential_submaps -= chosen_template

			break // Load the next submap.

	var/list/pretty_submap_list = list()
	for(var/submap_name in loaded_submap_names)
		var/count = loaded_submap_names[submap_name]
		if(count > 1)
			pretty_submap_list += "[count] <b>[submap_name]</b>"
		else
			pretty_submap_list += span_bold("[submap_name]")

	if(!overall_sanity)
		admin_notice("Submap loader gave up with [budget] left to spend.", R_DEBUG)
	else
		admin_notice("Submaps loaded.", R_DEBUG)
	admin_notice("Loaded: [english_list(pretty_submap_list)]", R_DEBUG)


/// An asslist of name=z for map_templates that have been loaded
GLOBAL_LIST_EMPTY(map_templates_loaded)

/// Registers the map into GLOB.map_templates_loaded
/datum/map_template/proc/on_map_preload(z)
	if(name_alias)
		GLOB.map_templates_loaded[name_alias] = z
	else
		GLOB.map_templates_loaded[name] = z

/datum/map_template/proc/on_map_loaded(z)
	//We missed air init!
	// was T.update_air_properties() (ZAS zone-graph refresh). LINDA
	// equivalent: rebuild adjacency + add to active so SSair processes the
	// newly-loaded turfs next tick.
	if(SSair.initialized)
		for(var/turf/simulated/T in block(locate(1,1,z), locate(world.maxx, world.maxy, z)))
			T.air_update_turf(TRUE, FALSE)
	//We missed sslighting init!
	if(SSlighting.initialized)
		for(var/Trf in block(locate(1,1,z), locate(world.maxx, world.maxy, z)))
			var/turf/T = Trf //faster than implicit istype with typed for loop
			T.lighting_build_overlay()

	return

