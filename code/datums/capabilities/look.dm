// The look builder (doc/rewrite/dx_conventions.md §3). draw(look) describes the whole presentation;
// the builder produces a change key, so an identical result costs a string compare and churns no
// overlays. One builder is reused for every draw (draws never sleep). Everything an atom shows goes
// through it: raw add_overlay()/overlays += outside it is banned (dx_raw_overlays), because it would
// bypass the key and leak overlays.

/datum/look
	var/icon_state
	var/icon
	var/color
	var/alpha
	var/matrix/transform
	var/dir
	var/plane
	var/layer
	var/list/overlays
	var/list/glows
	/// name -> filter params (look.add_look_filter()).
	var/list/filters
	var/list/vis
	/// A one-shot flick state: played when the look is applied, not part of the key's steady state.
	var/flick_state
	/// Anything was set: a type that draws nothing keeps its mapped appearance.
	var/touched = FALSE

GLOBAL_DATUM_INIT(look_builder, /datum/look, new)

/datum/look/proc/reset()
	icon_state = null
	icon = null
	color = null
	alpha = null
	transform = null
	dir = null
	plane = null
	layer = null
	overlays = null
	glows = null
	filters = null
	vis = null
	flick_state = null
	touched = FALSE

/// The base icon_state. The last call wins (a capability's broken state is overridden by a type
/// that draws its own broken state after ..()).
/datum/look/proc/state(name)
	icon_state = name
	touched = TRUE

/// An overlay icon_state (or an image / mutable_appearance), added only `when` is true.
/datum/look/proc/overlay(name, when = TRUE)
	touched = TRUE
	if(!when || isnull(name))
		return
	LAZYADD(overlays, name)

/// A gauge overlay: "[name][step]" for level (0..1) quantised to 0..levels. Null level: nothing.
/datum/look/proc/gauge(name, level, levels = 4)
	touched = TRUE
	if(isnull(level))
		return
	var/step = clamp(round(level * levels), 0, levels)
	LAZYADD(overlays, "[name][step]")

/// An overlay that also glows in the dark (the state plus its emissive), only `when` is true.
/datum/look/proc/glow(name, when = TRUE)
	touched = TRUE
	if(!when || isnull(name))
		return
	LAZYADD(glows, name)

/// Another icon file for the base state.
/datum/look/proc/set_icon(file)
	icon = file
	touched = TRUE

/datum/look/proc/set_color(value)
	color = value
	touched = TRUE

/datum/look/proc/set_alpha(value)
	alpha = value
	touched = TRUE

/datum/look/proc/set_transform(matrix/M)
	transform = M
	touched = TRUE

/datum/look/proc/set_dir(value)
	dir = value
	touched = TRUE

/datum/look/proc/set_plane(value)
	plane = value
	touched = TRUE

/datum/look/proc/set_layer(value)
	layer = value
	touched = TRUE

/// A named filter (filter(type = ..., ...) params), only `when` is true.
/datum/look/proc/add_look_filter(name, list/params, when = TRUE)
	touched = TRUE
	if(!when || isnull(name))
		return
	LAZYSET(filters, name, params)

/// An atom shown in vis_contents (movables only), only `when` is true.
/datum/look/proc/show(atom/movable/thing, when = TRUE)
	touched = TRUE
	if(!when || !thing)
		return
	LAZYADD(vis, thing)

/// A one-shot animation state, played when this look is applied.
/datum/look/proc/play_flick(name)
	flick_state = name
	touched = TRUE

/// The change key: equal keys draw equally (the flick is part of it, so a new flick re-applies).
/datum/look/proc/change_key()
	var/list/parts = list(icon_state, "[icon]", color, alpha, transform ? jointext(list(transform.a, transform.b, transform.c, transform.d, transform.e, transform.f), ",") : null, dir, plane, layer, flick_state)
	parts += jointext(overlays || list(), ",")
	parts += jointext(glows || list(), ",")
	if(filters)
		for(var/name in filters)
			parts += "[name]=[json_encode(filters[name])]"
	if(vis)
		for(var/atom/movable/thing as anything in vis)
			parts += "vis:[SHARED_CACHE_UID(thing)]"
	return jointext(parts, "|")

/atom
	/// The filter names the last applied look added (removed on the next change).
	var/tmp/list/look_filters
	/// The vis_contents the last applied look added.
	var/tmp/list/look_vis

/// Applies the look to A. Only what the look set is touched; what it set last time and not now is
/// taken back (overlays, filters, vis_contents).
/datum/look/proc/apply_to(atom/A)
	if(!isnull(icon))
		A.icon = icon
	if(!isnull(icon_state))
		A.icon_state = icon_state
	if(!isnull(color))
		A.color = color
	if(!isnull(alpha))
		A.alpha = alpha
	if(transform)
		A.transform = transform
	if(!isnull(dir))
		A.dir = dir
	if(!isnull(plane))
		A.plane = plane
	if(!isnull(layer))
		A.layer = layer
	if(A.look_overlays)
		A.cut_overlay(A.look_overlays) // ALLOW(sys_dx_raw_overlays): the look builder owns its overlays
		A.look_overlays = null
	var/list/added
	for(var/name in overlays)
		LAZYADD(added, name)
	for(var/name in glows)
		LAZYADD(added, name)
		LAZYADD(added, emissive_appearance(A.icon, name))
	if(added)
		A.add_overlay(added) // ALLOW(sys_dx_raw_overlays): the look builder owns its overlays
		A.look_overlays = added
	for(var/name in A.look_filters)
		if(!filters || !(name in filters))
			A.remove_filter(name)
	A.look_filters = null
	for(var/name in filters)
		A.add_filter(name, 1, filters[name])
		LAZYADD(A.look_filters, name)
	if(ismovable(A))
		var/atom/movable/M = A
		for(var/atom/movable/thing as anything in M.look_vis)
			if(!vis || !(thing in vis))
				M.vis_contents -= thing
		M.look_vis = null
		for(var/atom/movable/thing as anything in vis)
			M.vis_contents |= thing
			LAZYADD(M.look_vis, thing)
	if(flick_state)
		flick(flick_state, A)
