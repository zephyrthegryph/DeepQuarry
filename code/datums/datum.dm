/**
 * The absolute base class for everything
 *
 * A datum instantiated has no physical world prescence, use an atom if you want something
 * that actually lives in the world
 *
 * Be very mindful about adding variables to this class, they are inherited by every single
 * thing in the entire game, and so you can easily cause memory usage to rise a lot with careless
 * use of variables at this level
 */
/datum
	#ifdef REFERENCE_TRACKING
	/// Remaining references requested by the debug reference walker.
	var/tmp/references_to_clear
	#endif
	/**
	  * Tick count time when this object was destroyed.
	  *
	  * If this is non zero then the object has been garbage collected and is awaiting either
	  * a hard del by the GC subsystme, or to be autocollected (if it has no references)
	  */
	var/tmp/gc_destroyed

	/// Open uis owned by this datum
	/// Lazy, since this case is semi rare
	var/tmp/list/open_tguis // FIXME: open_uis

	/// Status traits attached to this datum. associative list of the form: list(trait name (string) = list(source1, source2, source3,...))

	/// Datum level flags
	var/tmp/datum_flags = NONE



	/// List for handling persistent filters.
	var/tmp/list/filter_data

#ifdef REFERENCE_TRACKING
	var/tmp/running_find_references
	var/tmp/last_find_references = 0
	var/tmp/find_references_on_destroy = FALSE //set this to true on an item to have it find refs after
	#ifdef REFERENCE_TRACKING_DEBUG
	///Stores info about where refs are found, used for sanity checks and testing
	var/tmp/list/found_refs
	#endif
#endif

	// If we have called dump_harddel_info already. Used to avoid duped calls (since we call it immediately in some cases on failure to process)
	// Create and destroy is weird and I wanna cover my bases
	var/tmp/harddel_deets_dumped = FALSE

/**
 * Called when a href for this datum is clicked
 */
/datum/Topic(href, href_list[])
	..()

/**
 * Default implementation of clean-up code.
 *
 * This should be overridden to remove all references pointing to the object being destroyed, if
 * you do override it, make sure to call the parent and return its return value by default
 *
 * Return an appropriate [QDEL_HINT][QDEL_HINT_QUEUE] to modify handling of your deletion;
 * in most cases this is [QDEL_HINT_QUEUE].
 *
 * The base case is responsible for doing the following
 * * Erasing timers pointing to this datum
 * * Erasing compenents on this datum
 * * Dropping event hooks (lifecycle phase 4 does this: om_teardown_hooks())
 *
 * Returns [QDEL_HINT_QUEUE]
 */
// ALLOW(lifecycle): the base: timers, reactor and tgui.
/datum/proc/Destroy(force = FALSE)
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	tag = null

	#ifdef REFERENCE_TRACKING
	#ifdef REFERENCE_TRACKING_DEBUG
	found_refs = null
	#endif
	#endif


	SStgui.close_uis(src)

	#ifdef REFERENCE_TRACKING
	if(find_references_on_destroy)
		return QDEL_HINT_FINDREFERENCE
	if(SSgarbage.find_reference_on_fail_global_toggle)
		return QDEL_HINT_IFFAIL_FINDREFERENCE
	#endif

	return QDEL_HINT_QUEUE

/** Add a filter to the datum.
 * This is on datum level, despite being most commonly / primarily used on atoms, so that filters can be applied to images / mutable appearances.
 * Can also be used to assert a filter's existence. I.E. update a filter regardless if it exists or not.
 *
 * Arguments:
 * * name - Filter name
 * * priority - Priority used when sorting the filter.
 * * params - Parameters of the filter.
 */
/datum/proc/add_filter(name, priority, list/params)
	LAZYINITLIST(filter_data)
	var/list/copied_parameters = params.Copy()
	copied_parameters["priority"] = priority
	filter_data[name] = copied_parameters
	update_filters()

///A version of add_filter that takes a list of filters to add rather than being individual, to limit calls to update_filters().
/datum/proc/add_filters(list/list/filters)
	LAZYINITLIST(filter_data)
	for(var/list/individual_filter as anything in filters)
		var/list/params = individual_filter["params"]
		var/list/copied_parameters = params.Copy()
		copied_parameters["priority"] = individual_filter["priority"]
		filter_data[individual_filter["name"]] = copied_parameters
	update_filters()

/// Reapplies all the filters.
/datum/proc/update_filters()
	ASSERT(isatom(src) || isimage(src))
	var/atom/atom_cast = src // filters only work with images or atoms.
	atom_cast.filters = null
	sortTim(filter_data, GLOBAL_PROC_REF(cmp_filter_data_priority), TRUE)
	for(var/filter_raw in filter_data)
		var/list/data = filter_data[filter_raw]
		var/list/arguments = data.Copy()
		arguments -= "priority"
		atom_cast.filters += filter(arglist(arguments))
	UNSETEMPTY(filter_data)

/** Update a filter's parameter to the new one. If the filter doesn't exist we won't do anything.
 *
 * Arguments:
 * * name - Filter name
 * * new_params - New parameters of the filter
 * * overwrite - TRUE means we replace the parameter list completely. FALSE means we only replace the things on new_params.
 */
/datum/proc/modify_filter(name, list/new_params, overwrite = FALSE)
	var/filter = get_filter(name)
	if(!filter)
		return
	if(overwrite)
		filter_data[name] = new_params
	else
		for(var/thing in new_params)
			filter_data[name][thing] = new_params[thing]
	update_filters()

/** Update a filter's parameter and animate this change. If the filter doesn't exist we won't do anything.
 * Basically a [datum/proc/modify_filter] call but with animations. Unmodified filter parameters are kept.
 *
 * Arguments:
 * * name - Filter name
 * * new_params - New parameters of the filter
 * * time - time arg of the BYOND animate() proc.
 * * easing - easing arg of the BYOND animate() proc.
 * * loop - loop arg of the BYOND animate() proc.
 */
/datum/proc/transition_filter(name, list/new_params, time, easing, loop)
	var/filter = get_filter(name)
	if(!filter)
		return
	// This can get injected by the filter procs, we want to support them so bye byeeeee
	new_params -= "type"
	animate(filter, new_params, time = time, easing = easing, loop = loop)
	modify_filter(name, new_params)

/** Keeps the steps in the correct order.
* Arguments:
* * params - the parameters you want this step to animate to
* * duration - the time it takes to animate this step
* * easing - the type of easing this step has
*/
/proc/FilterChainStep(params, duration, easing)
	params -= "type"
	return list("params"= params, "duration"=duration, "easing"=easing)

/** Similar to transition_filter(), except it creates an animation chain that moves between a list of states.
 * Arguments:
 * * name - Filter name
 * * num_loops - Amount of times the chain loops. INDEFINITE = Infinite
 * * ... - a list of each link in the animation chain. Use FilterChainStep(params, duration, easing) for each link
 * Example use:
 * * add_filter("blue_pulse", 1, color_matrix_filter(COLOR_WHITE))
 * * transition_filter_chain(src, "blue_pulse", INDEFINITE,\
 * *	FilterChainStep(color_matrix_filter(COLOR_BLUE), 10 SECONDS, CUBIC_EASING),\
 * *	FilterChainStep(color_matrix_filter(COLOR_WHITE), 10 SECONDS, CUBIC_EASING))
 * The above code would edit a color_matrix_filter() to slowly turn blue over 10 seconds before returning back to white 10 seconds after, repeating this chain forever.
 */
/datum/proc/transition_filter_chain(name, num_loops, ...)
	var/list/transition_steps = args.Copy(3)
	var/filter = get_filter(name)
	if(!filter)
		return
	var/list/first_step = transition_steps[1]
	animate(filter, first_step["params"], time = first_step["duration"], easing = first_step["easing"], loop = num_loops)
	for(var/transition_step in 2 to length(transition_steps))
		var/list/this_step = transition_steps[transition_step]
		animate(this_step["params"], time = this_step["duration"], easing = this_step["easing"])

/// Updates the priority of the passed filter key
/datum/proc/change_filter_priority(name, new_priority)
	if(!filter_data || !filter_data[name])
		return

	filter_data[name]["priority"] = new_priority
	update_filters()

/// Returns the filter associated with the passed key
/datum/proc/get_filter(name)
	ASSERT(isatom(src) || isimage(src))
	if(filter_data && filter_data[name])
		var/atom/atom_cast = src // filters only work with images or atoms.
		return atom_cast.filters[filter_data.Find(name)]

/// Returns the indice in filters of the given filter name.
/// If it is not found, returns null.
/datum/proc/get_filter_index(name)
	return filter_data?.Find(name)

/// Removes the passed filter, or multiple filters, if supplied with a list.
/datum/proc/remove_filter(name_or_names)
	if(!filter_data)
		return

	var/list/names = islist(name_or_names) ? name_or_names : list(name_or_names)

	. = FALSE
	for(var/name in names)
		if(filter_data[name])
			filter_data -= name
			. = TRUE

	if(.)
		update_filters()
	return .

/datum/proc/clear_filters()
	ASSERT(isatom(src) || isimage(src))
	var/atom/atom_cast = src // filters only work with images or atoms.
	filter_data = null
	atom_cast.filters = null

/// Return text from this proc to provide extra context to hard deletes that happen to it
/// Optional, you should use this for cases where replication is difficult and extra context is required
/// Can be called more then once per object, use harddel_deets_dumped to avoid duplicate calls (I am so sorry)
///images are pretty generic, this should help a bit with tracking harddels related to them
/image/proc/dump_harddel_info()
	if(harddel_deets_dumped)
		return
	harddel_deets_dumped = TRUE
	return "Image icon: [icon] - icon_state: [icon_state] [loc ? "loc: [loc] ([loc.x],[loc.y],[loc.z])" : ""]"

/// Begin coordinated remote viewing, this will call look() when the view begins, and unlook() when it ends.
/proc/start_coordinated_remoteview(datum/coordinator, mob/user, atom/target, list/viewer_managed_list, remote_view_config_path = null)
	ASSERT(islist(viewer_managed_list))
	user.begin_remote_view(/datum/remote_view/viewer_managed, target, null, remote_view_config_path, coordinator, viewer_managed_list)

/// Called from /datum/remote_view/viewer_managed when the view begins.
/datum/proc/look(mob/user)
	return

/// Called from /datum/remote_view/viewer_managed when the view ends.
/datum/proc/unlook(mob/user)
	return
