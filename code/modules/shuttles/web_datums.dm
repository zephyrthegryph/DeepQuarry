// This file actually has four seperate datums.

/**********
 * Routes *
 **********/

// This is the first datum, and it connects shuttle_destinations together.
/datum/shuttle_route
	var/tmp/datum/shuttle_destination/start	// One of the two sides of this route.  Start just means it was the creator of this route.
	var/tmp/datum/shuttle_destination/end	// The second side.
	var/var/obj/effect/shuttle_landmark/interim	// Where the shuttle sits during the movement.  Make sure no other shuttle shares this or Very Bad Things will happen.
	var/travel_time = 0							// How long it takes to move from start to end, or end to start.  Set to 0 for instant travel.
	var/one_way = FALSE							// If true, you can't travel from end to start.

/datum/shuttle_route/New(_start, _end, _interim, _time = 0, _oneway = FALSE)
	rel_set(src, nameof(start), _start)
	rel_set(src, nameof(end), _end)
	if(_interim)
		interim = SSshuttles.get_landmark(_interim)
	travel_time = _time
	one_way = _oneway

/datum/shuttle_route/proc/get_other_side(datum/shuttle_destination/PoV)
	if(PoV == start())
		return end()
	if(PoV == end())
		return start()
	return null

/datum/shuttle_route/proc/display_route(datum/shuttle_destination/PoV)
	var/datum/shuttle_destination/target = null
	if(PoV == start())
		target = end()
	else if(PoV == end())
		target = start()
	else
		return "ERROR"

	return target.name

/****************
 * Destinations *
 ****************/

// This is the second datum, and contains information on all the potential destinations for a specific shuttle.
/datum/shuttle_destination
	var/name = "a place"				// Name of the destination, used for the flight computer.
	var/tmp/obj/effect/shuttle_landmark/my_landmark	// Where the shuttle will move to when it actually arrives.
	var/my_landmark_tag	// the tag it starts as; resolved into my_landmark at init
	var/tmp/datum/shuttle_web_master/master	// The datum that does the coordination with the actual shuttle datum.
	var/list/routes			// Routes that are connected to this destination.
	var/preferred_interim_tag = null	// When building a new route, use interim landmark with this tag.
	var/skip_me = FALSE					// We will not autocreate this one. Some map must be doing it.

	var/radio_announce = 0				// Whether it will make a station announcement (0) or a radio announcement (1).
	var/announcer = null				// The name of the 'announcer' that will say the arrival/departure messages.  Defaults to the map's boss name if blank.

	// When this destination is instantiated, it will go and instantiate other destinations in this assoc list and build routes between them.
	// The list format is '/datum/shuttle_destination/subtype = 1 MINUTES'
	var/list/destinations_to_create

	// When the web_master finishes creating all the destinations, it will go and build routes between this and them if they're on this list.
	// The list format is '/datum/shuttle_destination/subtype = 1 MINUTES'
	var/list/routes_to_make

/datum/shuttle_destination/New(new_master)
	var/landmark_tag = my_landmark_tag // Subtypes set the tag string; resolve it to the landmark obj.
	rel_set(src, nameof(my_landmark), SSshuttles.get_landmark(landmark_tag))
	if(!my_landmark())
		log_mapping("Web shuttle destination '[name]' could not find its landmark '[landmark_tag]'.") // Important error message
	rel_set(src, nameof(master), new_master)



// This builds destination instances connected to this instance, recursively.
/datum/shuttle_destination/proc/build_destinations(list/already_made = list())
	already_made += src.type
	to_chat(world, "SHUTTLES: [name] is going to build destinations.  already_made list is \[[english_list(already_made)]\]")
	for(var/type_to_make in destinations_to_create)
		if(type_to_make in already_made) // Avoid circular initializations.
			to_chat(world, "SHUTTLES: [name] can't build [type_to_make] due to being a duplicate.")
			continue

		// Instance the new destination, and call this proc on their 'downstream' destinations.
		var/datum/shuttle_destination/new_dest = new type_to_make()
		to_chat(world, "SHUTTLES: [name] has created [new_dest.name] and will make it build their own destinations.")
		already_made += new_dest.build_destinations(already_made)

		// Now link our new destination to us.
		var/travel_delay = LAZYACCESS(destinations_to_create, type_to_make)
		link_destinations(new_dest, preferred_interim_tag, travel_delay)
		to_chat(world, "SHUTTLES: [name] has linked themselves to [new_dest.name]")

	to_chat(world, "SHUTTLES: [name] has finished building destinations.  already_made list is \[[english_list(already_made)]\].")
	return already_made

/datum/shuttle_destination/proc/enter(datum/shuttle_destination/old_destination)
	announce_arrival()

/datum/shuttle_destination/proc/exit(datum/shuttle_destination/new_destination)
	announce_departure()

/datum/shuttle_destination/proc/get_departure_message()
	return null

/datum/shuttle_destination/proc/announce_departure()
	if(isnull(get_departure_message()) || master().my_shuttle().cloaked)
		return

	if(!radio_announce)
		GLOB.command_announcement.Announce(get_departure_message(),(announcer ? announcer : "[using_map.boss_name]"))
	else
		GLOB.global_announcer.autosay(get_departure_message(),(announcer ? announcer : "[using_map.boss_name]"))

/datum/shuttle_destination/proc/get_arrival_message()
	return null

/datum/shuttle_destination/proc/announce_arrival()
	if(isnull(get_arrival_message()) || master().my_shuttle().cloaked)
		return

	if(!radio_announce)
		GLOB.command_announcement.Announce(get_arrival_message(),(announcer ? announcer : "[using_map.boss_name]"))
	else
		GLOB.global_announcer.autosay(get_arrival_message(),(announcer ? announcer : "[using_map.boss_name]"))

/datum/shuttle_destination/proc/link_destinations(datum/shuttle_destination/other_place, interim_tag, travel_time = 0)
	// First, check to make sure this doesn't cause a duplicate route.
	for(var/datum/shuttle_route/R in routes)
		if(R.start() == other_place || R.end() == other_place)
			return

	// Now we can connect them.
	var/datum/shuttle_route/new_route = new(src, other_place, interim_tag, travel_time)
	rel_add(src, nameof(routes), new_route)
	rel_add(other_place, nameof(other_place.routes), new_route)

// Depending on certain circumstances, the shuttles can fail.
// What happens depends on where the shuttle is.  If it's in space, it just can't move until its fixed.
// If it's flying in Sif, however, things get interesting.
/datum/shuttle_destination/proc/flight_failure()
	return

// Returns a /datum/shuttle_route connecting this destination to origin, if one exists.
/datum/shuttle_destination/proc/get_route_to(origin_type)
	for(var/datum/shuttle_route/R in routes)
		if(R.start().type == origin_type || R.end().type == origin_type)
			return R
	return null

/***************
 * Web Masters *
 ***************/

// This is the third and final datum, which coordinates with the shuttle datum to tell it where it is, where it can go, and how long it will take.
// It is also responsible for instancing all the destinations it has control over, and linking them together.
/datum/shuttle_web_master
	var/tmp/datum/shuttle/autodock/web_shuttle/my_shuttle	// Ref to the shuttle this datum is coordinating with.
	var/tmp/datum/shuttle_destination/current_destination	// Where the shuttle currently is.  Bit of a misnomer.
	var/tmp/datum/shuttle_destination/future_destination	// Where it will be in the near future.
	var/starting_destination = null	// Where the shuttle will start at, generally at the home base.
	// ALLOW(instance_list): d: web shuttle destinations, built at init
	var/list/destinations = list()								// List of currently instanced destinations.
	var/destination_class = null								// Type to use in typesof(), to build destinations.

	var/tmp/datum/shuttle_autopath/autopath	// Datum used to direct an autopilot.
	var/list/autopaths									// Potential autopaths the autopilot can use. The autopath's start var must equal current_destination to be viable.
	var/autopath_class = null									// Similar to destination_class, used for typesof().

CAPABILITIES(/datum/shuttle_web_master)
	owns_many(nameof(autopaths))
	owns_many(nameof(destinations))

/datum/shuttle_web_master/New(new_shuttle, new_destination_class = null)
	rel_set(src, nameof(my_shuttle), new_shuttle)
	if(new_destination_class)
		destination_class = new_destination_class
	build_destinations()
	rel_set(src, nameof(current_destination), get_destination_by_type(starting_destination))
	build_autopaths()


/datum/shuttle_web_master/proc/build_destinations()
	// First, instantiate all the destination subtypes relevant to this datum.
	var/list/destination_types = subtypesof(destination_class)
	for(var/new_type in destination_types)
		var/datum/shuttle_destination/D = new_type
		if(initial(D.skip_me))
			continue
		D = new new_type(src)
		// A destination whose map landmark didn't resolve (e.g. it lived on a
		// z-level this map doesn't load) is unreachable — pruning it here keeps
		// routes, flight computers and autopaths from ever offering a null jump.
		if(!D.my_landmark())
			log_mapping("Web shuttle destination '[D.name]' ([new_type]) pruned: no landmark on this map.")
			spent(D)
			continue
		rel_add(src, nameof(destinations), D)

	// Now start the process of connecting all of them.
	for(var/datum/shuttle_destination/D in destinations)
		for(var/type_to_link in D.routes_to_make)
			var/datum/shuttle_destination/other = get_destination_by_type(type_to_link)
			if(!other) // Pruned above (or a typo'd type) — skip the route instead of building a half-null one.
				continue
			var/travel_delay = LAZYACCESS(D.routes_to_make, type_to_link)
			D.link_destinations(other, D.preferred_interim_tag, travel_delay)

/datum/shuttle_web_master/proc/on_shuttle_departure()
	current_destination().exit()

/datum/shuttle_web_master/proc/on_shuttle_arrival()
	if(future_destination())
		future_destination().enter()
		rel_set(src, nameof(current_destination), future_destination())
		rel_clear(src, nameof(future_destination))

/datum/shuttle_web_master/proc/get_available_routes()
	if(current_destination())
		return LAZYCOPY(current_destination().routes)

/datum/shuttle_web_master/proc/get_current_destination()
	RETURN_TYPE(/datum/shuttle_destination)
	return current_destination()

/datum/shuttle_web_master/proc/get_destination_by_type(type_to_get)
	return locate_in_list(destinations, type_to_get)

// Autopilot stuff.
/datum/shuttle_web_master/proc/build_autopaths()
	for(var/datum/shuttle_autopath/built as anything in init_subtypes(autopath_class))
		rel_add(src, nameof(autopaths), built)
	for(var/datum/shuttle_autopath/P in autopaths)
		rel_set(P, nameof(P.master), src)
	// Drop autopaths that reference destinations pruned in build_destinations()
	// (landmark missing on this map) — walking one would dead-end mid-route.
	for(var/datum/shuttle_autopath/P in autopaths)
		var/valid = !isnull(get_destination_by_type(P.start))
		for(var/node_type in P.path_nodes)
			if(!get_destination_by_type(node_type))
				valid = FALSE
				break
		if(!valid)
			log_mapping("Web shuttle autopath [P.type] pruned: references a destination with no landmark on this map.")
			rel_remove(src, nameof(autopaths), P)

/datum/shuttle_web_master/proc/choose_path()
	if(!length(autopaths) || !current_destination())
		return
	for(var/datum/shuttle_autopath/path in autopaths)
		if(path.start == current_destination().type)
			rel_set(src, nameof(autopath), path)
			break

/datum/shuttle_web_master/proc/path_finished(datum/shuttle_autopath/path)
	rel_clear(src, nameof(autopath))

/datum/shuttle_web_master/proc/walk_path(target_type)
	if(!current_destination())
		return FALSE
	var/datum/shuttle_route/R = current_destination().get_route_to(target_type)
	if(!R)
		return FALSE
	rel_set(src, nameof(future_destination), R.get_other_side(current_destination()))
	if(!future_destination()?.my_landmark()) // Nowhere to actually land; abort the hop rather than jumping to null.
		log_shuttle("Web shuttle [my_shuttle()] aborted a hop to [target_type]: destination has no landmark.")
		rel_clear(src, nameof(future_destination))
		return FALSE

	var/travel_time = R.travel_time * my_shuttle().flight_time_modifier * 2 // Autopilot is less efficent than having someone flying manually.
	// TODO - Leshana - Change this to use proccess stuff of autodock!
	if(R.interim && R.travel_time > 0)
		my_shuttle().long_jump(future_destination().my_landmark(), R.interim, travel_time / 10)
	else
		my_shuttle().short_jump(future_destination().my_landmark())
	return TRUE // Note this will return before the shuttle actually arrives.

/datum/shuttle_web_master/proc/process_autopath()
	if(!autopath()) // If we don't have a path, get one.
		if(!length(autopaths))
			// No flyable route exists from anywhere (e.g. every autopath was pruned
			// because its destinations aren't on this map). Autopiloting is pointless;
			// switch it off so the shuttle stops announcing takeoffs it can't make.
			my_shuttle().adjust_autopilot(FALSE)
			return
		choose_path()

	if(!autopath()) // Still nothing, oh well.
		return

	var/datum/shuttle_destination/target = autopath().get_next_node()
	if(walk_path(target))
		autopath().walk_path()
	else
		// The hop failed (missing route/landmark). Drop the path so we re-plan
		// instead of retrying the same broken hop every process tick.
		autopath().reset_path()
		rel_clear(src, nameof(autopath))

// Call this to reset everything related to autopiloting.
/datum/shuttle_web_master/proc/reset_autopath()
	rel_clear(src, nameof(autopath))
	my_shuttle().autopilot = FALSE

/*************
 * Autopaths *
 *************/

// Fourth datum, this one essentially acts as directions for an autopilot to go to the correct places.
/datum/shuttle_autopath
	var/tmp/datum/shuttle_web_master/master
	var/start = null
	var/list/path_nodes
	var/index = 1

/datum/shuttle_autopath/proc/reset_path()
	index = 1

/datum/shuttle_autopath/proc/get_next_node()
	return LAZYACCESS(path_nodes, index)

/datum/shuttle_autopath/proc/walk_path()
	index++
	if(index > length(path_nodes))
		finish_path()

/datum/shuttle_autopath/proc/finish_path()
	reset_path()
	master().path_finished(src)

/// One of the two sides of this route.  Start just means it was the creator of this route.
/datum/shuttle_route/proc/start() as /datum/shuttle_destination
	return start

/// The second side.
/datum/shuttle_route/proc/end() as /datum/shuttle_destination
	return end

/// The datum that does the coordination with the actual shuttle datum.
/datum/shuttle_destination/proc/master() as /datum/shuttle_web_master
	return master

/// Ref to the shuttle this datum is coordinating with.
/datum/shuttle_web_master/proc/my_shuttle() as /datum/shuttle/autodock/web_shuttle
	return my_shuttle

/// Datum used to direct an autopilot.
/datum/shuttle_web_master/proc/autopath() as /datum/shuttle_autopath
	return autopath

/// Accessor for the master var.
/datum/shuttle_autopath/proc/master() as /datum/shuttle_web_master
	return master

/// Where it will be in the near future.
/datum/shuttle_web_master/proc/future_destination() as /datum/shuttle_destination
	return future_destination

/// Where the shuttle currently is.  Bit of a misnomer.
/datum/shuttle_web_master/proc/current_destination() as /datum/shuttle_destination
	return current_destination

/// Where the shuttle will move to when it actually arrives.
/datum/shuttle_destination/proc/my_landmark() as /obj/effect/shuttle_landmark
	return my_landmark

// A route names both endpoints (one-sided views); each endpoint lists the route (a list view).
// Not pairs: one routes list would need two partner vars (start and end).
CAPABILITIES(/datum/shuttle_route)
	ref_one(nameof(start))
	ref_one(nameof(end))
CAPABILITIES(/datum/shuttle_destination)
	ref_many(nameof(routes))
