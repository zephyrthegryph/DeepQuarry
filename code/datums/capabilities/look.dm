// The look builder (doc/rewrite/dx_conventions.md §3). draw(look) calls look.state()/overlay()/
// gauge()/glow(); the builder produces a change key, so an identical result costs a string compare
// and churns no overlays. One builder is reused for every draw (draws never sleep).

/datum/look
	var/icon_state
	var/list/overlays
	var/list/glows
	/// Anything was set: a type that draws nothing keeps its mapped icon_state.
	var/touched = FALSE

GLOBAL_DATUM_INIT(look_builder, /datum/look, new)

/datum/look/proc/reset()
	icon_state = null
	overlays = null
	glows = null
	touched = FALSE

/// The base icon_state. The last call wins (a capability's broken state is overridden by a type
/// that draws its own broken state after ..()).
/datum/look/proc/state(name)
	icon_state = name
	touched = TRUE

/// An overlay icon_state, added only `when` is true. Order is list order. `icon` draws the state
/// from another icon file than the holder's (one shared image per icon and state).
/datum/look/proc/overlay(name, when = TRUE, icon)
	touched = TRUE
	if(!when || isnull(name))
		return
	LAZYADD(overlays, icon ? look_image(icon, name) : name)

/// Drops a layer a capability drew (the holder's own draw() knows its sprite has no such state in
/// this state): every overlay or glow named `name` added so far.
/datum/look/proc/hide(name)
	touched = TRUE
	if(overlays)
		overlays -= name
		if(!length(overlays))
			overlays = null
	if(glows)
		glows -= name
		if(!length(glows))
			glows = null

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

/// The change key: equal keys draw equally.
/datum/look/proc/change_key()
	var/list/names = list()
	for(var/entry in overlays)
		if(istype(entry, /image))
			var/image/I = entry
			names += "[I.icon]:[I.icon_state]"
		else
			names += entry
	return "[icon_state]|[jointext(names, ",")]|[jointext(glows || list(), ",")]"

/// The shared image for an overlay drawn from another icon file (look.overlay(icon =)).
/proc/look_image(icon, name)
	var/static/list/cache = list()
	var/key = "[icon]:[name]"
	var/image/I = cache[key]
	if(!I)
		I = image(icon = icon, icon_state = name)
		cache[key] = I
	return I

/// Applies the look to A: sets icon_state and swaps the overlays the previous look added.
/datum/look/proc/apply_to(atom/A)
	if(!isnull(icon_state))
		A.icon_state = icon_state
	if(A.look_overlays)
		A.cut_overlay(A.look_overlays)
		A.look_overlays = null
	var/list/added
	for(var/name in overlays)
		LAZYADD(added, name)
	for(var/name in glows)
		LAZYADD(added, name)
		LAZYADD(added, emissive_appearance(A.icon, name))
	if(added)
		A.add_overlay(added)
		A.look_overlays = added
