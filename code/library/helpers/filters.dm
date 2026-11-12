#define ICON_NOT_SET "Not Set"

//This is stored as a nested list instead of datums or whatever because it json encodes nicely for usage in tgui
GLOBAL_LIST_INIT(master_filter_info, list(
	"alpha" = list(
		"defaults" = list(
			"x" = 0,
			"y" = 0,
			"icon" = ICON_NOT_SET,
			"render_source" = "",
			"flags" = 0
		),
		"flags" = list(
			"MASK_INVERSE" = MASK_INVERSE,
			"MASK_SWAP" = MASK_SWAP
		)
	),
	"angular_blur" = list(
		"defaults" = list(
			"x" = 0,
			"y" = 0,
			"size" = 1
		)
	),
	"bloom" = list(
		"defaults" = list(
			"threshold" = COLOR_BLACK,
			"size" = 1,
			"offset" = 0,
			"alpha" = 255
		)
	),
	// Needs either a proper matrix editor, or just a hook to our existing one
	// Issue is filterrific assumes variables will have the same value type if they share the same name, which this violates
	// Gotta refactor this sometime
	"color" = list(
		"defaults" = list(
			"color" = matrix(),
			"space" = FILTER_COLOR_RGB
		),
		"enums" = list(
			"FILTER_COLOR_RGB" = FILTER_COLOR_RGB,
			"FILTER_COLOR_HSV" = FILTER_COLOR_HSV,
			"FILTER_COLOR_HSL" = FILTER_COLOR_HSL,
			"FILTER_COLOR_HCY" = FILTER_COLOR_HCY
		)
	),
	"displace" = list(
		"defaults" = list(
			"x" = 0,
			"y" = 0,
			"size" = 1,
			"icon" = ICON_NOT_SET,
			"render_source" = ""
		)
	),
	"drop_shadow" = list(
		"defaults" = list(
			"x" = 1,
			"y" = -1,
			"size" = 1,
			"offset" = 0,
			"color" = COLOR_HALF_TRANSPARENT_BLACK
		)
	),
	"blur" = list(
		"defaults" = list(
			"size" = 1
		)
	),
	"layer" = list(
		"defaults" = list(
			"x" = 0,
			"y" = 0,
			"icon" = ICON_NOT_SET,
			"render_source" = "",
			"flags" = FILTER_OVERLAY,
			"color" = "",
			"transform" = TRANSFORM_MATRIX_IDENTITY,
			"blend_mode" = BLEND_DEFAULT
		),
		"flags" = list(
			"FILTER_OVERLAY" = FILTER_OVERLAY,
			"FILTER_UNDERLAY" = FILTER_UNDERLAY
		),
		"enums" = list(
			"BLEND_DEFAULT" = BLEND_DEFAULT,
			"BLEND_OVERLAY" = BLEND_OVERLAY,
			"BLEND_ADD" = BLEND_ADD,
			"BLEND_SUBTRACT" = BLEND_SUBTRACT,
			"BLEND_MULTIPLY" = BLEND_MULTIPLY,
			"BLEND_INSET_OVERLAY" = BLEND_INSET_OVERLAY
		)
	),
	"motion_blur" = list(
		"defaults" = list(
			"x" = 0,
			"y" = 0
		)
	),
	"outline" = list(
		"defaults" = list(
			"size" = 0,
			"color" = COLOR_BLACK,
			"flags" = NONE
		),
		"flags" = list(
			"OUTLINE_SHARP" = OUTLINE_SHARP,
			"OUTLINE_SQUARE" = OUTLINE_SQUARE
		)
	),
	"radial_blur" = list(
		"defaults" = list(
			"x" = 0,
			"y" = 0,
			"size" = 0.01
		)
	),
	"rays" = list(
		"defaults" = list(
			"x" = 0,
			"y" = 0,
			"size" = 16,
			"color" = COLOR_WHITE,
			"offset" = 0,
			"density" = 10,
			"threshold" = 0.5,
			"factor" = 0,
			"flags" = FILTER_OVERLAY | FILTER_UNDERLAY
		),
		"flags" = list(
			"FILTER_OVERLAY" = FILTER_OVERLAY,
			"FILTER_UNDERLAY" = FILTER_UNDERLAY
		)
	),
	"ripple" = list(
		"defaults" = list(
			"x" = 0,
			"y" = 0,
			"size" = 1,
			"repeat" = 2,
			"radius" = 0,
			"falloff" = 1,
			"flags" = NONE
		),
		"flags" = list(
			"WAVE_BOUNDED" = WAVE_BOUNDED
		)
	),
	"wave" = list(
		"defaults" = list(
			"x" = 0,
			"y" = 0,
			"size" = 1,
			"offset" = 0,
			"flags" = NONE
		),
		"flags" = list(
			"WAVE_SIDEWAYS" = WAVE_SIDEWAYS,
			"WAVE_BOUNDED" = WAVE_BOUNDED
		)
	)
))

#undef ICON_NOT_SET

//Helpers to generate lists for filter helpers
//This is the only practical way of writing these that actually produces sane lists
/proc/alpha_mask_filter(x, y, icon/icon, render_source, flags)
	. = list("type" = "alpha")
	if(!isnull(x))
		.["x"] = x
	if(!isnull(y))
		.["y"] = y
	if(!isnull(icon))
		.["icon"] = icon
	if(!isnull(render_source))
		.["render_source"] = render_source
	if(!isnull(flags))
		.["flags"] = flags

/proc/color_matrix_filter(matrix/in_matrix, space)
	. = list("type" = "color")
	.["color"] = in_matrix
	if(!isnull(space))
		.["space"] = space

/proc/drop_shadow_filter(x, y, size, offset, color)
	. = list("type" = "drop_shadow")
	if(!isnull(x))
		.["x"] = x
	if(!isnull(y))
		.["y"] = y
	if(!isnull(size))
		.["size"] = size
	if(!isnull(offset))
		.["offset"] = offset
	if(!isnull(color))
		.["color"] = color

/proc/wave_filter(x, y, size, offset, flags)
	. = list("type" = "wave")
	if(!isnull(size))
		.["size"] = size
	if(!isnull(x))
		.["x"] = x
	if(!isnull(y))
		.["y"] = y
	if(!isnull(offset))
		.["offset"] = offset
	if(!isnull(flags))
		.["flags"] = flags

/proc/apply_wibbly_filters(atom/in_atom, length)
	for(var/i in 1 to 7)
		//This is a very baffling and strange way of doing this but I am just preserving old functionality
		var/X
		var/Y
		var/rsq
		do
			X = 60*rand() - 30
			Y = 60*rand() - 30
			rsq = X*X + Y*Y
		while(rsq<100 || rsq>900) // Yeah let's just loop infinitely due to bad luck what's the worst that could happen?
		var/random_roll = rand()
		in_atom.add_filter("wibbly-[i]", 5, wave_filter(x = X, y = Y, size = rand() * 2.5 + 0.5, offset = random_roll))
		var/filter = in_atom.get_filter("wibbly-[i]")
		animate(filter, offset = random_roll, time = 0, loop = -1, flags = ANIMATION_PARALLEL)
		animate(offset = random_roll - 1, time = rand() * 20 + 10)

/proc/remove_wibbly_filters(atom/in_atom, remove_duration = 0)
	if(QDELETED(in_atom))
		return
	var/filter
	for(var/i in 1 to 7)
		filter = in_atom.get_filter("wibbly-[i]")
		if(remove_duration == 0)
			animate(filter)
			in_atom.remove_filter("wibbly-[i]")
			continue
		animate(filter, x = 0, y = 0, size = 0, offset = 0, time = remove_duration)
		after(in_atom, remove_duration, TYPE_PROC_REF(/atom, remove_filter), with = list("wibbly-[i]"))

/proc/convert_list_to_filter(list/list_filter)
	var/list/arguments = list_filter.Copy()
	arguments -= "priority"
	return filter(arglist(arguments))

/** Add a filter to the atom.
 * Filters live on atoms only: each filter proc is a slot in every atom type's proc table, so they stay off /datum.
 * Can also be used to assert a filter's existence. I.E. update a filter regardless if it exists or not.
 *
 * Arguments:
 * * name - Filter name
 * * priority - Priority used when sorting the filter.
 * * params - Parameters of the filter.
 */
/atom/proc/add_filter(name, priority, list/params)
	LAZYINITLIST(filter_data)
	var/list/copied_parameters = params.Copy()
	copied_parameters["priority"] = priority
	filter_data[name] = copied_parameters
	update_filters()

/// Reapplies all the filters.
/atom/proc/update_filters()
	filters = null
	sortTim(filter_data, GLOBAL_PROC_REF(cmp_filter_data_priority), TRUE)
	for(var/filter_raw in filter_data)
		var/list/data = filter_data[filter_raw]
		var/list/arguments = data.Copy()
		arguments -= "priority"
		filters += filter(arglist(arguments))
	UNSETEMPTY(filter_data)

/** Update a filter's parameter to the new one. If the filter doesn't exist we won't do anything.
 *
 * Arguments:
 * * name - Filter name
 * * new_params - New parameters of the filter
 * * overwrite - TRUE means we replace the parameter list completely. FALSE means we only replace the things on new_params.
 */
/atom/proc/modify_filter(name, list/new_params, overwrite = FALSE)
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
 * Basically a [atom/proc/modify_filter] call but with animations. Unmodified filter parameters are kept.
 *
 * Arguments:
 * * name - Filter name
 * * new_params - New parameters of the filter
 * * time - time arg of the BYOND animate() proc.
 * * easing - easing arg of the BYOND animate() proc.
 * * loop - loop arg of the BYOND animate() proc.
 */
/atom/proc/transition_filter(name, list/new_params, time, easing, loop)
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
/atom/proc/transition_filter_chain(name, num_loops, ...)
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
/atom/proc/change_filter_priority(name, new_priority)
	if(!filter_data || !filter_data[name])
		return

	filter_data[name]["priority"] = new_priority
	update_filters()

/// Returns the filter associated with the passed key
/atom/proc/get_filter(name)
	if(filter_data && filter_data[name])
		return filters[filter_data.Find(name)]

/// Removes the passed filter, or multiple filters, if supplied with a list.
/atom/proc/remove_filter(name_or_names)
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
