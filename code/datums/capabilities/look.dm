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
	/// list(range, power, color) from look.light(), or null for no light from the look.
	var/list/light_spec
	/// Anything was set: a type that draws nothing keeps its mapped appearance.
	var/touched = FALSE

GLOBAL_DATUM_INIT(look_builder, /datum/look, new)

/datum/look/proc/reset()
	light_spec = null
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

/// The atom's light while this look holds (the APC's screen glow, a lit airlock). A look that stops
/// setting it turns the light off: draw() never calls set_light() itself (that would be a side effect).
/datum/look/proc/light(range, power = 1, color)
	touched = TRUE
	if(!range || !power)
		return
	light_spec = list(range, power, color)

/// A one-shot animation state, played when this look is applied.
/datum/look/proc/play_flick(name)
	flick_state = name
	touched = TRUE

/// The change key: equal keys draw equally (the flick is part of it, so a new flick re-applies).
/datum/look/proc/change_key()
	var/list/parts = list(icon_state, "[icon]", color, alpha, transform ? jointext(list(transform.a, transform.b, transform.c, transform.d, transform.e, transform.f), ",") : null, dir, plane, layer, flick_state, light_spec ? jointext(light_spec, ",") : null)
	var/list/overlay_keys = list()
	for(var/entry in overlays)
		overlay_keys += look_part_key(entry)
	parts += jointext(overlay_keys, ",")
	parts += jointext(glows || list(), ",")
	if(filters)
		for(var/name in filters)
			parts += "[name]=[json_encode(filters[name])]"
	if(vis)
		for(var/atom/movable/thing as anything in vis)
			parts += "vis:[SHARED_CACHE_UID(thing)]"
	return jointext(parts, "|")

/// The key of one overlay entry: an icon_state as it is; an image or mutable_appearance by what it
/// shows. (Stringifying an appearance gives its type, so two different images would share one key
/// and a changed image would never be applied.)
/proc/look_part_key(entry)
	if(istext(entry))
		return entry
	if(isimage(entry) || istype(entry, /mutable_appearance))
		var/image/I = entry
		return "{[I.icon]:[I.icon_state]:[I.color]:[I.alpha]:[I.layer]:[I.plane]:[I.dir]:[I.pixel_x],[I.pixel_y]:[I.blend_mode]}"
	return "[entry]"

#define LOOK_SET_ICON (1<<0)
#define LOOK_SET_ICON_STATE (1<<1)
#define LOOK_SET_COLOR (1<<2)
#define LOOK_SET_ALPHA (1<<3)
#define LOOK_SET_TRANSFORM (1<<4)
#define LOOK_SET_DIR (1<<5)
#define LOOK_SET_PLANE (1<<6)
#define LOOK_SET_LAYER (1<<7)
#define LOOK_SET_LIGHT (1<<8)

/atom
	/// LOOK_SET_* for the base properties the last applied look set (taken back when a look stops
	/// setting them).
	var/tmp/look_set_bits = 0
	/// The filter names the last applied look added (removed on the next change).
	var/tmp/list/look_filters
	/// The vis_contents the last applied look added.
	var/tmp/list/look_vis

/// Applies the look to A. Only what the look set is touched; what it set last time and not now is
/// taken back: overlays, filters and vis_contents are removed, and a base property (icon, color,
/// alpha, ...) goes back to its type default.
/datum/look/proc/apply_to(atom/A)
	var/was = A.look_set_bits
	var/now = 0
	if(!isnull(icon))
		A.icon = icon
		now |= LOOK_SET_ICON
	else if(was & LOOK_SET_ICON)
		A.icon = initial(A.icon)
	if(!isnull(icon_state))
		A.icon_state = icon_state
		now |= LOOK_SET_ICON_STATE
	else if(was & LOOK_SET_ICON_STATE)
		A.icon_state = initial(A.icon_state)
	if(!isnull(color))
		A.color = color
		now |= LOOK_SET_COLOR
	else if(was & LOOK_SET_COLOR)
		A.color = initial(A.color)
	if(!isnull(alpha))
		A.alpha = alpha
		now |= LOOK_SET_ALPHA
	else if(was & LOOK_SET_ALPHA)
		A.alpha = initial(A.alpha)
	if(transform)
		A.transform = transform
		now |= LOOK_SET_TRANSFORM
	else if(was & LOOK_SET_TRANSFORM)
		A.transform = null
	if(!isnull(dir))
		A.dir = dir
		now |= LOOK_SET_DIR
	else if(was & LOOK_SET_DIR)
		A.dir = initial(A.dir)
	if(!isnull(plane))
		A.plane = plane
		now |= LOOK_SET_PLANE
	else if(was & LOOK_SET_PLANE)
		A.plane = initial(A.plane)
	if(!isnull(layer))
		A.layer = layer
		now |= LOOK_SET_LAYER
	else if(was & LOOK_SET_LAYER)
		A.layer = initial(A.layer)
	if(light_spec)
		if(light_spec[3])
			A.set_light(light_spec[1], light_spec[2], light_spec[3])
		else
			A.set_light(light_spec[1], light_spec[2])
		now |= LOOK_SET_LIGHT
	else if(was & LOOK_SET_LIGHT)
		A.set_light(0)
	A.look_set_bits = now
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

#undef LOOK_SET_ICON
#undef LOOK_SET_ICON_STATE
#undef LOOK_SET_COLOR
#undef LOOK_SET_ALPHA
#undef LOOK_SET_TRANSFORM
#undef LOOK_SET_DIR
#undef LOOK_SET_PLANE
#undef LOOK_SET_LAYER
#undef LOOK_SET_LIGHT
