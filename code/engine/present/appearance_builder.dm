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
	/// Names from look.variant(): each replaces the base state by "<base>-name" when the icon has it.
	var/list/variants
	/// list(name, value or null, glows) per look.part(): resolved against the icon when applied.
	var/list/parts
	/// name -> filter params (look.add_look_filter()).
	var/list/filters
	var/list/vis
	/// A one-shot flick state: played when the look is applied, not part of the key's steady state.
	var/flick_state
	/// list(range, power, color) from look.light(), or null for no light from the look.
	var/list/light_spec
	/// look.held_state(): the item_state hands draw this item with, or null (unchanged).
	var/held_state
	/// look.identity(): the name and description shown, or null (unchanged).
	var/identity_name
	var/identity_desc
	/// look.offset(): the pixel offset the holder shows, or null for none asked (x and y together).
	var/offset_x
	var/offset_y
	/// look.effect(): list(proc_ref, args...) entries run on the holder, after the look is applied, outside the output.
	var/list/effects
	/// look.watch(): own keys of the other entities this draw read (a hat's sprite, a container's contents): a change on any of them redraws the holder.
	var/list/watched
	/// look.neighbours(): the types of the neighbours this draw looked for (the watched turfs tell the holder only of those).
	var/list/neighbour_types
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
	variants = null
	parts = null
	filters = null
	vis = null
	flick_state = null
	held_state = null
	offset_x = null
	offset_y = null
	identity_name = null
	identity_desc = null
	effects = null
	watched = null
	neighbour_types = null
	touched = FALSE

/// The base icon_state. The last call wins (a capability's broken state is overridden by a type
/// that draws its own broken state after ..()). Returns `name`, so a draw that builds on the state it
/// chose can keep it: `state = look.state("[base]-open")`.
/datum/look/proc/state(name)
	icon_state = name
	touched = TRUE
	return name

/// The base icon_state this draw has chosen so far (a parent's draw, a capability), else the one `A` shows now.
/// A draw that refines the state ("[state]-busy") starts from it.
/datum/look/proc/state_so_far(atom/A)
	return isnull(icon_state) ? A.icon_state : icon_state

/// An overlay icon_state (or an image / mutable_appearance), added only `when` is true. `icon`
/// draws the state from another icon file than the holder's (one shared image per icon and state).
/datum/look/proc/overlay(name, when = TRUE, icon)
	touched = TRUE
	if(!when || isnull(name))
		return
	LAZYADD(overlays, icon ? look_image(icon, name) : name)

/// Drops a layer a capability drew (the holder's own draw() knows its sprite has no such state in
/// this state): every overlay or part named `name` added so far (a part by its name, or by name-value).
/datum/look/proc/hide(name)
	touched = TRUE
	if(overlays)
		for(var/entry in overlays.Copy())
			if(istext(entry) && entry == name)
				overlays -= entry
		if(!length(overlays))
			overlays = null
	if(parts)
		var/list/kept
		for(var/list/entry in parts)
			var/full = isnull(entry[2]) ? entry[1] : "[entry[1]]-[entry[2]]"
			if(entry[1] != name && full != name)
				LAZYADD(kept, list(entry))
		parts = kept

/**
 * The base state gets a variant: with the icon having "<base>-name" the base is replaced by it (a
 * lit or open sprite of the same thing). Variants apply in the order given; a variant the icon has no
 * state for changes nothing. Only `when` is true.
 */
/datum/look/proc/variant(name, when = TRUE)
	touched = TRUE
	if(!when || isnull(name))
		return
	LAZYADD(variants, "[name]")

/**
 * A named part drawn over the base: `value` is TRUE for a plain part ("panel"), or a value (text or
 * number) for "panel-open"; null / FALSE / "" draws nothing. It resolves when the look is applied to the
 * first state the holder's icon has of "<base>-name[-value]" then "name[-value]". A part with no state draws nothing.
 */
/datum/look/proc/part(name, value = TRUE)
	touched = TRUE
	if(isnull(name) || isnull(value) || value == 0 || value == "")
		return
	var/shown = (value == TRUE) ? null : "[value]"
	for(var/list/entry in parts)
		if(entry[1] == "[name]" && entry[2] == shown)
			return // drawn already (a type and its capabilities can both name a part)
	LAZYADD(parts, list(list("[name]", shown, FALSE)))

/// A gauge overlay: "[name][step]" for level (0..1) quantised to 0..levels. Null level: nothing.
/datum/look/proc/gauge(name, level, levels = 4)
	touched = TRUE
	if(isnull(level))
		return
	var/step = clamp(round(level * levels), 0, levels)
	LAZYADD(overlays, "[name][step]")

/**
 * Draws a part that glows in the dark: the part `name` (with a `value`, the part of that value), emissive. A
 * part of that name already added (look.part()) is upgraded, so a glow never needs the part beside it. `value` is
 * TRUE (or any value) to do it, FALSE or null not to.
 */
/datum/look/proc/glow(name, value = TRUE, when = TRUE)
	touched = TRUE
	if(!when || isnull(name) || isnull(value) || value == 0 || value == "")
		return
	var/wanted = (value == TRUE) ? null : "[value]"
	for(var/list/entry in parts)
		if(entry[1] == name && (isnull(wanted) || entry[2] == wanted))
			entry[3] = TRUE
			return
	LAZYADD(parts, list(list("[name]", wanted, TRUE)))

/**
 * An effect of this look that is not drawing: `proc_ref(args...)` runs on the holder once the look has been applied (the look changed), outside
 * the output, so it may write state, start a sound loop or call another entity. Draw stays pure (it only names the effect); a
 * state-bound effect (a value that must follow a var even when the look does not change) is on_change(). Effects are part of the change
 * key, so a draw that stops naming one does not leave it behind, and one that names a different value runs again. Only `when` is true.
 *	look.effect(PROC_REF(add_eyes), has_eye_glow)
 */
/datum/look/proc/effect(proc_ref, ...)
	touched = TRUE
	if(isnull(proc_ref))
		return
	LAZYADD(effects, list(args.Copy()))

/// effect() only `when` is true: the condition first, so `look.effect_if(vore_eyes, PROC_REF(add_eyes))` reads like the legacy `if(vore_eyes) add_eyes()`.
/datum/look/proc/effect_if(when, proc_ref, ...)
	touched = TRUE
	if(!when || isnull(proc_ref))
		return
	LAZYADD(effects, list(args.Copy(2)))

/**
 * This draw read `thing` (a hat's item_state, a container's contents, a part's look): a change published on `thing` redraws the holder, as a
 * change of the holder's own state does. The subscription follows the draw, so a draw that stops reading `thing` stops hearing it. The thing
 * publishes through its tracked vars or changed(); a plain var it writes is not heard. Null reads nothing.
 */
/datum/look/proc/watch(datum/thing)
	if(!isdatum(thing) || QDELETED(thing))
		return
	LAZYOR(watched, OWN_KEY(thing))

/**
 * What stands on the turfs `dirs` away from `holder`: the movables of `type` there (a list, empty when none), and the draw hears about them. It watches
 * each of those turfs (a mover of `type` entering or leaving one redraws the holder) and each neighbour found (its own tracked changes: dir,
 * anchored, a tracked look var). `dirs` is one direction or a list of them. A holder that moves does not re-point the subscription until it draws again.
 *	var/obj/machinery/other = look.neighbours(src, dir, /obj/machinery/reagent_refinery)[1]
 */
/datum/look/proc/neighbours(atom/holder, dirs = GLOB.cardinal, type = /atom/movable)
	touched = TRUE
	. = list()
	var/turf/here = get_turf(holder)
	if(!here)
		return
	LAZYOR(neighbour_types, type)
	for(var/dir_away in (islist(dirs) ? dirs : list(dirs)))
		var/turf/T = get_step(here, dir_away)
		if(!T)
			continue
		watch(T)
		for(var/atom/movable/AM as anything in contents_of(T, type))
			. += AM
			watch(AM)

/// The first atom of `type` on the turf `dir` away from `holder` (neighbours() for one direction), or null.
/datum/look/proc/neighbour(atom/holder, dir_away, type = /atom/movable)
	var/list/found = neighbours(holder, dir_away, type)
	return length(found) ? found[1] : null

/// A mob's glowing eyes: the "<state>-eyes" sprite of its icon, above the lighting plane (so it glows in the dark), tinted `color` when given.
/// What add_eyes()/remove_eyes() hung on the mob; the draw only says whether they show.
/datum/look/proc/eyes(atom/holder, state, color, when = TRUE)
	touched = TRUE
	if(!when || isnull(state))
		return
	LAZYADD(overlays, look_overlay_image(holder.icon, "[state]-eyes", plane = PLANE_LIGHTING_ABOVE, color = color, appearance_flags = holder.appearance_flags))

/// Another icon file for the base state.
/datum/look/proc/set_icon(file)
	icon = file
	touched = TRUE

// ---- part names and the per-icon state cache ----

/// icon file text -> assoc set of its icon_states. An icon's states never change in a round, so each
/// file is read once; a look resolving parts costs list lookups, not icon_states() calls.
GLOBAL_LIST_EMPTY(look_icon_states)
/// "[type]" -> the part names a look asked for that the type's icon has no state for (filled in test builds).
GLOBAL_LIST_EMPTY(look_missing_parts)

/// The set of state names `icon` (a file) has.
/proc/look_states_of(icon)
	RETURN_TYPE(/list)
	var/key = isfile(icon) ? "[icon]" : null
	var/list/found = key ? GLOB.look_icon_states[key] : null
	if(found)
		return found
	found = list()
	if(icon)
		for(var/state in icon_states(icon))
			found[state] = TRUE
	if(key)
		GLOB.look_icon_states[key] = found
	return found

/// Whether `icon` has a state named `state`.
/proc/look_icon_has_state(icon, state)
	return !!look_states_of(icon)[state]

/**
 * The state of part `name` (with `value`) in `icon` for base state `base`: the first of
 * "<base>-name[-value]", "name[-value]" that exists. Null when the icon has none. Names are exact:
 * tools/dq_icons/rename_states.py --standard moves legacy states to the standard names.
 */
/proc/look_resolve_part(icon, base, name, value)
	var/list/states = look_states_of(icon)
	var/full = isnull(value) ? "[name]" : "[name]-[value]"
	if(base && states["[base]-[full]"])
		return "[base]-[full]"
	if(states[full])
		return full
	return null

/**
 * The standard parts of `A`'s look that its icon has no state for (from the capabilities' look_parts()),
 * less what A says it knowingly lacks (look_lacks()). What the unit test lists.
 */
/proc/look_missing_standard_parts(atom/A)
	. = list()
	var/list/lacks = A.look_lacks()
	var/base = initial(A.icon_state)
	for(var/datum/capability/C as anything in caps_all(A))
		for(var/part_name in C.look_parts())
			if(part_name in lacks)
				continue
			if(!look_resolve_part(A.icon, base, part_name, null))
				. |= part_name

/// The standard part names this atom's type knowingly has no sprite for (an allowlist for the
/// missing-parts test). Override to declare them.
/atom/proc/look_lacks()
	return null

/// TRUE for a type whose standard parts the unit test enforces (types opt in as their sprites are named).
/proc/look_checked(atom/holder)
	return FALSE

/// The standard part names this capability draws (its layer). Null draws none.
/datum/capability/proc/look_parts()
	if(!layer_name || layer_name == CAP_NO_LAYER)
		return null
	return list(layer_name)

/// The shared image for an overlay drawn from another icon file (look.overlay(icon =)).
/proc/look_image(icon, name)
	var/static/list/cache = list() // ALLOW(cache): images shared by icon file and name, built once on first use and never written after
	var/key = "[icon]:[name]"
	var/image/I = cache[key]
	if(!I)
		I = image(icon = icon, icon_state = name)
		cache[key] = I
	return I

/// A fresh overlay image for look.overlay() with its placement and tint set in one call (a draw() writes nothing, so an overlay raised, tinted, put on
/// another plane or turned is built here): `icon_state` of `icon`, or the appearance of `of` (an atom drawn into the look, a scanner's patient).
/proc/look_overlay_image(icon, icon_state, layer = FLOAT_LAYER, plane = FLOAT_PLANE, alpha = 255, pixel_x = 0, pixel_y = 0, pixel_w = 0, pixel_z = 0, color = null, dir = null, matrix/transform = null, list/filters = null, atom/of = null, appearance_flags = null, invisibility = null)
	var/image/I = of ? image(of) : image(icon = icon, icon_state = icon_state)
	I.layer = layer
	I.plane = plane
	I.alpha = alpha
	I.pixel_x = pixel_x
	I.pixel_y = pixel_y
	I.pixel_w = pixel_w
	I.pixel_z = pixel_z
	if(!isnull(color))
		I.color = color
	if(!isnull(dir))
		I.dir = dir
	if(transform)
		I.transform = transform
	if(length(filters))
		I.filters = filters
	if(!isnull(appearance_flags))
		I.appearance_flags = appearance_flags
	if(!isnull(invisibility))
		I.invisibility = invisibility
	return I

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

/// The holder's pixel offset (a wall bin sits in the wall it faces, a mob stands a little low): x and y together, part of the key. A draw that stops
/// naming it gives the holder its mapped offset back.
/datum/look/proc/offset(x = 0, y = 0)
	offset_x = x
	offset_y = y
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
	LAZYADD(vis, thing) // ALLOW(ownership): vis is the look's per-draw scratch list of shown atoms, rebuilt on every draw; it is not a relation

/// The atom's light while this look holds (the APC's screen glow, a lit airlock). A look that stops
/// setting it turns the light off: draw() never calls set_light() itself (that would be a side effect).
/datum/look/proc/light(range, power = 1, color)
	touched = TRUE
	if(!range || !power)
		return
	light_spec = list(range, power, color)

/// The holder's light is off while this look shows (set_light(0)), even when its type starts lit.
/datum/look/proc/light_off()
	touched = TRUE
	light_spec = list(0, 0, null)

/// A one-shot animation state, played when this look is applied.
/// The state hands draw this item with (its item_state). The holder's hands are redrawn when it changes. A draw that does
/// not call it leaves the item_state as it is (a reskin or a script may have set it).
/datum/look/proc/held_state(state)
	held_state = state
	touched = TRUE

/// What the thing is called and how it is described. Null leaves either as it is (so a name call and a desc call compose); a draw that does not call it changes
/// neither (a player's rename stays).
/datum/look/proc/identity(name = null, desc = null)
	if(!isnull(name))
		identity_name = name
	if(!isnull(desc))
		identity_desc = desc
	touched = TRUE

/datum/look/proc/play_flick(name)
	flick_state = name
	touched = TRUE

/// The change key: equal keys draw equally (the flick is part of it, so a new flick re-applies).
/datum/look/proc/change_key()
	var/list/parts = list(icon_state, "[icon]", color, alpha, transform ? jointext(list(transform.a, transform.b, transform.c, transform.d, transform.e, transform.f), ",") : null, dir, plane, layer, isnull(offset_x) ? null : "[offset_x],[offset_y]", flick_state, light_spec ? jointext(light_spec, ",") : null, held_state, identity_name, identity_desc)
	var/list/overlay_keys = list()
	for(var/entry in overlays)
		overlay_keys += look_part_key(entry)
	parts += jointext(overlay_keys, ",")
	if(variants)
		parts += "variants:[jointext(variants, ",")]"
	for(var/list/entry in src.parts)
		parts += "part:[entry[1]]:[entry[2]]:[entry[3]]"
	if(filters)
		for(var/name in filters)
			parts += "[name]=[json_encode(filters[name])]"
	for(var/list/entry in effects)
		var/list/bits = list()
		for(var/bit in entry)
			bits += "[bit]"
		parts += "fx:[jointext(bits, ":")]"
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
		return "{[I.icon]:[I.icon_state]:[I.color]:[I.alpha]:[I.layer]:[I.plane]:[I.dir]:[I.pixel_x],[I.pixel_y],[I.pixel_w],[I.pixel_z]:[I.blend_mode]}"
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
#define LOOK_SET_OFFSET (1<<9)

/// Applies the look to A. Only what the look set is touched; what it set last time and not now is
/// taken back: overlays, filters and vis_contents are removed, and a base property (icon, color,
/// alpha, ...) goes back to its type default.
/datum/look/proc/apply_to(atom/A)
	var/datum/rx_state/cache = rx_of(A)
	var/was = cache.look_set_bits
	var/now = 0
	var/old_icon = A.icon
	var/old_state = A.icon_state
	if(!isnull(icon))
		A.icon = icon
		now |= LOOK_SET_ICON
	else if(was & LOOK_SET_ICON)
		A.icon = initial(A.icon)
	// The base state, then variants ("<base>-lit") the icon has: only what the look asked is touched.
	var/base = icon_state
	if(isnull(base))
		base = (was & LOOK_SET_ICON_STATE) ? initial(A.icon_state) : A.icon_state
	var/resolved = base
	for(var/name in variants)
		var/candidate = "[resolved]-[name]"
		if(look_icon_has_state(A.icon, candidate))
			resolved = candidate
	if(!isnull(icon_state) || resolved != base)
		A.icon_state = resolved
		now |= LOOK_SET_ICON_STATE
	else if(was & LOOK_SET_ICON_STATE)
		A.icon_state = initial(A.icon_state)
	if(ismovable(A) && (A.icon != old_icon || A.icon_state != old_state))
		A.look_changed_sprite(old_icon, old_state)
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
		A.look_set_dir(dir)
		now |= LOOK_SET_DIR
	else if(was & LOOK_SET_DIR)
		A.look_set_dir(initial(A.dir))
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
	if(!isnull(offset_x))
		A.pixel_x = offset_x
		A.pixel_y = offset_y
		now |= LOOK_SET_OFFSET
	else if(was & LOOK_SET_OFFSET)
		A.pixel_x = initial(A.pixel_x)
		A.pixel_y = initial(A.pixel_y)
	if(light_spec)
		if(!light_spec[1])
			A.look_apply_light(0) // light_off(): the range only, so the power and colour stay for the next light
		else if(light_spec[3])
			A.look_apply_light(light_spec[1], light_spec[2], light_spec[3])
		else
			A.look_apply_light(light_spec[1], light_spec[2])
		now |= LOOK_SET_LIGHT
	else if(was & LOOK_SET_LIGHT)
		A.look_apply_light(0)
	cache.look_set_bits = now
	if(!isnull(identity_name))
		A.name = identity_name
	if(!isnull(identity_desc))
		A.desc = identity_desc
	if(!isnull(held_state))
		A.look_apply_held_state(held_state)
	if(cache.look_overlays)
		A.cut_overlay(cache.look_overlays)
		cache.look_overlays = null
	var/list/added
	for(var/name in overlays)
		LAZYADD(added, name)
	for(var/list/entry in parts)
		var/state = look_resolve_part(A.icon, resolved, entry[1], entry[2])
		if(!state)
#ifdef UNIT_TESTS
			LAZYINITLIST(GLOB.look_missing_parts["[A.type]"])
			GLOB.look_missing_parts["[A.type]"] |= (entry[2] ? "[entry[1]]-[entry[2]]" : entry[1])
#endif
			continue
		LAZYADD(added, state)
		if(entry[3])
			LAZYADD(added, emissive_appearance(A.icon, state))
	if(added)
		A.add_overlay(added)
		cache.look_overlays = added
	for(var/name in cache.look_filters)
		if(!filters || !(name in filters))
			A.look_remove_filter(name)
	cache.look_filters = null
	for(var/name in filters)
		A.look_add_filter(name, 1, filters[name])
		LAZYADD(cache.look_filters, name)
	if(ismovable(A))
		var/atom/movable/M = A
		for(var/atom/movable/thing as anything in cache.look_vis)
			if(!vis || !(thing in vis))
				M.vis_contents -= thing
		cache.look_vis = null
		for(var/atom/movable/thing as anything in vis)
			M.vis_contents |= thing
			LAZYADD(cache.look_vis, thing)
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
#undef LOOK_SET_OFFSET


// ---- transient visuals: look_flash() ----

/**
 * Shows `state` on A for `duration` (an overlay, or the base icon_state with as_state = TRUE), then
 * takes it back: a transient visual needs no var and no draw() branch of its own. Re-flashing the same
 * state restarts its time.
 *	look_flash(src, "pointer_flash", 0.5 SECONDS)
 */
/proc/look_flash(atom/A, state, duration, as_state = FALSE)
	if(QDELETED(A) || !state || duration <= 0)
		return
	var/datum/cap_engine_state/engine = cap_engine_state_make(A)
	if(as_state)
		engine.look_flash_state = state
	else
		LAZYSET(engine.look_flashes, state, TRUE)
	state_changed(A)
	var/token = "[state]:[++GLOB.look_flash_seq]"
	LAZYSET(engine.look_flash_tokens, state, token)
	after(A, duration, GLOBAL_PROC_REF(look_flash_end), with = list(A, state, token, as_state), keeps_dead = TRUE)

GLOBAL_VAR_INIT(look_flash_seq, 0)

/proc/look_flash_end(atom/A, state, token, as_state)
	if(QDELETED(A))
		return
	var/datum/cap_engine_state/engine = cap_engine_state_of(A)
	if(!engine || engine.look_flash_tokens?[state] != token)
		return
	LAZYREMOVE(engine.look_flash_tokens, state)
	if(as_state)
		if(engine.look_flash_state == state)
			engine.look_flash_state = null
	else
		LAZYREMOVE(engine.look_flashes, state)
	state_changed(A)

/// A layer built in one call: a draw writes nothing, not even the members of an image it made, so a tinted, faded or re-planed
/// layer is made here and handed to look.overlay(). (mutable_appearance() takes the layer, plane, alpha and flags; this adds the colour.)
/proc/look_appearance(icon, icon_state = "", color = null, alpha = 255, layer = FLOAT_LAYER, plane = FLOAT_PLANE, appearance_flags = NONE)
	var/mutable_appearance/MA = mutable_appearance(icon, icon_state, layer, plane, alpha, appearance_flags)
	if(!isnull(color))
		MA.color = color
	return MA


/// Presentation integration hooks. The look builder owns the requested changes; downstream adapters own their transport.
/atom/proc/look_changed_sprite(old_icon, old_state)
	return

/atom/proc/look_apply_held_state(state)
	return

/atom/proc/look_apply_light(range, power, color)
	return

/atom/proc/look_remove_filter(name)
	return

/atom/proc/look_add_filter(name, priority, list/params)
	return

/// Commits a priority layer replacement chosen by an appearance adapter. Rendering owns
/// the raw overlay operations; the adapter chooses the old and new appearance values.
/proc/look_replace_priority_overlay(atom/target, mutable_appearance/old, mutable_appearance/replacement)
	target.cut_overlay(list(old), TRUE)
	target.add_overlay(list(replacement), TRUE)

// ---- keyed appearance cache: one shared image per (key), built on first use ----

DECLARE_SHARED_CACHE_EX(look_cached_images, GLOBAL_PROC_REF(build_look_cached_image), SC_NEVER, 4096, 0)

/**
 * The shared image of `state` in `icon`, tinted `color` and put on `plane` / `layer` when given, built once per `key` and reused by every holder that
 * asks for the same key (a stool's seat, a chair's armrest). The key must name everything that varies the image (icon, state, tint, plane); a
 * draw hands the result to look.overlay(). Replaces the hand-rolled "if(isnull(GLOB.x[key])) build and store" idiom, which a draw may not hold.
 *	. += look_cached_image("[icon]-[base_icon]-[material.name]", icon, base_icon, material.icon_colour)
 */
/proc/look_cached_image(key, icon, state, color, plane, layer)
	READS_FROM()
	if(!isfile(icon))
		return build_look_cached_image(icon, state, color, plane, layer) // a runtime /icon has no stable identity: built uncached
	return CACHED_KEY(look_cached_images, key, icon, state, color, plane, layer)

/proc/build_look_cached_image(icon, state, color, plane, layer)
	var/image/I = image(icon = icon, icon_state = state)
	if(!isnull(color))
		I.color = color
	if(!isnull(plane))
		I.plane = plane
	if(!isnull(layer))
		I.layer = layer
	return I
