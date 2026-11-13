// Client lighting, big sprites. The lighting plane multiplies the world per screen pixel, so a sprite taller or wider than its tile
// (a large or size-scaled character, a big simple mob) is lit by the glows of every tile its pixels cover: its head takes the
// light of the tile above and looks wrong at a corner. A big atom therefore carries a flat light: a copy of its own sprite
// (render_source, as the emissive blocker does) drawn on the glow plane above every glow, in one grey that is the light level
// of the turf it stands on. Where the sprite is, the glow plane then holds that single level instead of the per-pixel light.
// It must be on the glow plane, not the lighting plane: the lighting master ADDS the glow plane over its own content (a layer
// filter), so a silhouette in the lighting plane is only added to by every glow and a lit character comes out over-bright.
//
// Cheap by construction: only an atom whose sprite is bigger than a tile gets one (client_flat_light_big()); it is registered in
// REGISTRY_CLIENT_FLAT_LIT, redrawn only when the atom changes size, moves (the moved notice) or a light near it changes
// (client_flat_lights_refresh() from client_glow_apply()/client_glow_clear()/mask refresh), and the colour is only rewritten
// when the quantised level changes. Nothing polls. Every change is logged (log_world) while lighting tracing is on (client_glow_trace_line()).

/// Level steps: the grey is quantised so a slow fade does not rewrite the colour every light update.
#define CLIENT_FLAT_LIGHT_STEPS 32

/// Cumulative counters (tests, benchmarks).
GLOBAL_VAR_INIT(client_flat_light_makes, 0)
GLOBAL_VAR_INIT(client_flat_light_recolours, 0)
/// Flat-lit atoms redone because a light near them changed (client_flat_lights_refresh()).
GLOBAL_VAR_INIT(client_flat_light_refreshes, 0)

REGISTRY_MEMBERSHIP(/atom/movable, REGISTRY_CLIENT_FLAT_LIT)

/// The flat silhouette of a big atom: its own sprite, one grey, on the glow plane above the glows.
/atom/movable/client_flat_light
	name = "flat light"
	plane = PLANE_CLIENT_GLOW
	layer = CLIENT_GLOW_FLAT_LAYER
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	vis_flags = VIS_HIDE
	anchored = TRUE
	// RESET_TRANSFORM: render_source copies the target's transform, and an overlay applies the parent's as well; RESET_COLOR: the
	// parent's colour must not tint the grey. The parent's alpha is kept, so a cloaked or fading atom fades its flat light too.
	appearance_flags = RESET_TRANSFORM | RESET_COLOR
	/// The quantised light level (0..CLIENT_FLAT_LIGHT_STEPS) its colour shows; -1 before the first.
	var/lit_level = -1

CAPABILITIES(/atom/movable/client_flat_light)
	param(nameof(render_source), pos = 1)

/atom/movable/client_flat_light/singularity_act()
	return

/atom/movable/client_flat_light/singularity_pull()
	return

/atom/movable/client_flat_light/onTransitZ()
	return

/atom/movable/client_flat_light/forceMove(atom/destination, direction, movetime, no_tp=FALSE, harderforce = FALSE)
	if(harderforce)
		return ..(destination, direction, movetime)

/// A big atom follows its turf's light as it moves (granted by client_flat_light_update()).
CAPABILITY_TYPE(client_flat_light, CAP_CLIENT_FLAT_LIGHT, /datum/capability/client_flat_light, key = NONE)
/datum/capability/client_flat_light

/datum/capability/client_flat_light/entries()
	return list(on_notice(/datum/notice/moved, then(CAP_PROC(flat_light_moved))))

/datum/capability/client_flat_light/proc/flat_light_moved(datum/act/A)
	client_flat_light_update(A.holder)

/// The pixel size of `A`'s sprite along its larger side: the declared icon width and height times the scale it is drawn at.
/proc/client_flat_light_extent(atom/movable/A)
	var/scale_x = A.get_icon_scale_x()
	var/scale_y = A.get_icon_scale_y()
	var/height = motion_of(A).icon_height
	if(ismob(A))
		var/mob/M = A
		scale_x *= M.size_multiplier
		scale_y *= M.size_multiplier
	if(ishuman(A))
		var/mob/living/carbon/human/H = A
		scale_x *= H.species.icon_scale_x
		scale_y *= H.species.icon_scale_y
		height = max(height, H.species.icon_height)
	return max(A.icon_expected_width * abs(scale_x), height * abs(scale_y))

/// TRUE when `A`'s sprite is bigger than one tile.
/proc/client_flat_light_big(atom/movable/A)
	return client_flat_light_extent(A) > WORLD_ICON_SIZE + 0.5

/// The quantised light level of the turf `T`, 0..CLIENT_FLAT_LIGHT_STEPS.
/proc/client_flat_light_level(turf/T)
	return round(T.get_lumcount() * CLIENT_FLAT_LIGHT_STEPS)

/// The colour that turns every pixel of the silhouette into the grey of `level`, alpha kept.
/proc/client_flat_light_color(level)
	var/grey = level / CLIENT_FLAT_LIGHT_STEPS
	return list(0,0,0, 0,0,0, 0,0,0, grey,grey,grey)

/// Gives `A` its flat light when client lighting is on, its sprite is bigger than a tile and it stands on a turf; takes it away
/// when any of that stops being true; and sets its grey to the turf's current level.
/proc/client_flat_light_update(atom/movable/A)
	if(QDELETED(A))
		return
	var/turf/T = A.loc
	if(!GLOB.client_lighting || !SSlighting.is_initialized() || !isturf(T) || !client_flat_light_big(A))
		client_flat_light_drop(A)
		return
	var/level = client_flat_light_level(T)
	if(!A.flat_light)
		if(isnull(A.render_target))
			A.render_target = ref(A) // the name the emissive blocker uses too
		rel_set(A, nameof(/atom/movable::flat_light), new /atom/movable/client_flat_light(null, A.render_target))
		A.flat_light_overlay_add()
		registry_join(REGISTRY_CLIENT_FLAT_LIT, A)
		grant(A, /datum/capability/client_flat_light, A)
		GLOB.client_flat_light_makes++
		if(client_glow_trace_line())
			log_world("client flat light: [A] ([A.type]) is [round(client_flat_light_extent(A))] px, lit as its turf [T.x],[T.y],[T.z] (level [level]/[CLIENT_FLAT_LIGHT_STEPS])")
	var/atom/movable/client_flat_light/F = A.flat_light
	if(F.lit_level == level)
		return
	F.set_lit_level(level)
	F.set_color(client_flat_light_color(level))
	GLOB.client_flat_light_recolours++
	if(client_glow_trace_line())
		log_world("client flat light: [A] now level [level]/[CLIENT_FLAT_LIGHT_STEPS] at [T.x],[T.y],[T.z]")

/// Takes `A`'s flat light away (a no-op without one).
/proc/client_flat_light_drop(atom/movable/A)
	if(!A.flat_light)
		return
	A.flat_light_overlay_cut()
	rel_clear(A, nameof(/atom/movable::flat_light))
	registry_leave(REGISTRY_CLIENT_FLAT_LIT, A)
	revoke(A, /datum/capability/client_flat_light, A)
	if(client_glow_trace_line())
		log_world("client flat light: [A] ([A.type]) lost its flat light")

/// A light near the flat-lit atoms changed (it glows, moved, resized, went dark or its mask changed): each flat-lit atom within its reach takes its turf's new level.
/// The registry holds only big atoms, so this walks a handful, not the world; of those only the ones standing within the light's reach box (CLIENT_GLOW_RADIUS about
/// its turf, on its level) can have a different level. `was_at` and `was_range` are where and how far it reached before this change (a move or a resize leaves the
/// atoms of the old reach to be redone too); null for a change that left them as they were.
/proc/client_flat_lights_refresh(datum/light_source/L, turf/was_at = null, was_range = 0)
	if(!REGISTRY_COUNT(REGISTRY_CLIENT_FLAT_LIT))
		return
	var/r = CLIENT_GLOW_RADIUS(L)
	var/turf/at = L.source_turf || L.glow_reach_origin
	var/list/near = at ? glow_reach_box(at, max(r, was_range)) : null
	var/list/before = was_at && was_at != at ? glow_reach_box(was_at, max(r, was_range)) : null
	if(!near && !before)
		return
	for(var/atom/movable/A as anything in REGISTRY_COPY(REGISTRY_CLIENT_FLAT_LIT))
		var/turf/T = A.loc
		if(!isturf(T))
			continue
		if((near && at.z == T.z && !CLIENT_GLOW_CLEAR_OF(T.x, T.y, 0, near)) || (before && was_at.z == T.z && !CLIENT_GLOW_CLEAR_OF(T.x, T.y, 0, before)))
			GLOB.client_flat_light_refreshes++
			client_flat_light_update(A)

/// Client lighting went on (every big living mob takes a flat light) or off (every flat light goes).
/proc/client_flat_lights_switched(on)
	if(!on)
		for(var/atom/movable/A as anything in REGISTRY_COPY(REGISTRY_CLIENT_FLAT_LIT))
			client_flat_light_drop(A)
		return
	for(var/mob/living/M as anything in REGISTRY_COPY(REGISTRY_LIVING_MOBS))
		client_flat_light_update(M)

#undef CLIENT_FLAT_LIGHT_STEPS
