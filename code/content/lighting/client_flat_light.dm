// Client lighting, big sprites. The lighting plane multiplies the world per screen pixel, so a sprite taller or wider than its tile
// (a large or size-scaled character, a big simple mob) is lit by the glows of every tile its pixels cover: its head takes the
// light of the tile above and looks wrong at a corner. A big atom therefore carries a flat light: a copy of its own sprite
// (render_source, as the emissive blocker does) drawn on the glow plane above every glow, in one colour that is the light the
// floor of the turf it stands on is drawn with. Where the sprite is, the glow plane then holds that single colour instead of the
// per-pixel light.
//
// The plane chain, read from client_lighting_screen.dm: glows (BLEND_ADD sprites) and this silhouette draw on PLANE_CLIENT_GLOW, a
// hidden render target (cut to what the client sees, walls removed, softened); the lighting master ADDS that target over its black
// base (a layer filter) and multiplies the sum over the world. So the silhouette must be on the glow plane, not the lighting plane:
// on the lighting plane every glow is still added over it and a lit character comes out over-bright. On the glow plane, above the
// glows (CLIENT_GLOW_FLAT_LAYER), it replaces them under the sprite, and what the lighting plane then holds there is exactly the
// colour the silhouette has, so the character is multiplied by what the floor of its tile is multiplied by.
//
// The colour is the model of the drawn light (client_flat_light_rgb()), not the gameplay light level: get_lumcount() is a different
// curve from the glow sprite's gradient (a lit corridor read 0.6 where the floor drew 1.0), has no colour, and ignores a small
// light's reduced strength, so a character lit by it looked dimmer or glowier than the floor under it.
//
// Cheap by construction: only an atom whose sprite is bigger than a tile gets one (client_flat_light_big()); it is registered in
// REGISTRY_CLIENT_FLAT_LIT, redrawn only when the atom changes size, moves (the moved notice) or a light near it changes
// (client_flat_lights_refresh() from client_glow_apply()/client_glow_clear()/mask refresh), and the colour is only rewritten
// when the quantised colour changes. Nothing polls. Every change is logged (log_world) while lighting tracing is on (client_glow_trace_line()).

/// Level steps per channel: the colour is quantised so a slow fade does not rewrite it every light update.
#define CLIENT_FLAT_LIGHT_STEPS 32
/// A glow's strength at its distance from its centre as a fraction of its half width (0..1, 21 samples, 0.05 apart): the radial alpha of
/// the light_*.dmi sprites (a plateau to 0.3, then falling to the rim). dq_client_flat_light_profile reads the real sprite against it.
#define CLIENT_FLAT_LIGHT_PROFILE list(1, 1, 1, 1, 1, 1, 1, 0.96, 0.91, 0.86, 0.8, 0.745, 0.69, 0.627, 0.565, 0.494, 0.424, 0.353, 0.267, 0.165, 0.043)

/// Cumulative counters (tests, benchmarks).
GLOBAL_VAR_INIT(client_flat_light_makes, 0)
GLOBAL_VAR_INIT(client_flat_light_recolours, 0)
/// Flat-lit atoms redone because a light near them changed (client_flat_lights_refresh()).
GLOBAL_VAR_INIT(client_flat_light_refreshes, 0)

REGISTRY_MEMBERSHIP(/atom/movable, REGISTRY_CLIENT_FLAT_LIT)

/// The flat silhouette of a big atom: its own sprite, one colour, on the glow plane above the glows.
/atom/movable/client_flat_light
	name = "flat light"
	plane = PLANE_CLIENT_GLOW
	layer = CLIENT_GLOW_FLAT_LAYER
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	vis_flags = VIS_HIDE
	anchored = TRUE
	// RESET_TRANSFORM: render_source copies the target's transform, and an overlay applies the parent's as well; RESET_COLOR: the
	// parent's colour must not tint the silhouette. The parent's alpha is kept, so a cloaked or fading atom fades its flat light too.
	appearance_flags = RESET_TRANSFORM | RESET_COLOR
	/// The quantised colour it shows, one channel per 6 bits (red, green, blue, each 0..CLIENT_FLAT_LIGHT_STEPS), see client_flat_light_key(); -1 before the first.
	var/lit_key = -1

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

/// How strongly a glow draws at `f` of its half width from its centre: CLIENT_FLAT_LIGHT_PROFILE, interpolated; 0 at and past the rim.
/proc/client_flat_light_profile(f)
	if(f >= 1)
		return 0
	var/static/list/profile = CLIENT_FLAT_LIGHT_PROFILE
	var/at = max(f, 0) * 20
	var/low = round(at)
	return profile[low + 1] + (profile[low + 2] - profile[low + 1]) * (at - low)

/// The light the floor of `T` is drawn with: list(red, green, blue), 0..1 each, worked out the way the screen draws it. A turf outside dynamic
/// lighting carries a white tile (full light). Otherwise the glows whose baked reach covers the turf add, each as the colour of its light times its
/// drawn alpha (strength, small-light scale) times the sprite's falloff at the turf's centre, and the lighting plane clamps the sum. The turf's own
/// gameplay light level (get_lumcount()) is another curve and is not used.
/proc/client_flat_light_rgb(turf/T)
	if(!T.has_dynamic_lighting())
		return list(1, 1, 1)
	var/red = 0
	var/green = 0
	var/blue = 0
	for(var/datum/light_source/L as anything in GLOB.client_glow_chunks[client_glow_chunk_id(T.z, CLIENT_GLOW_CHUNK_OF(T.x), CLIENT_GLOW_CHUNK_OF(T.y))])
		if(QDELETED(L))
			continue
		var/obj/effect/overlay/client_glow/G = L.glow
		var/turf/S = L.source_turf
		if(!G || !S || S.z != T.z)
			continue
		var/dx = T.x - S.x
		var/dy = T.y - S.y
		if(!L.glow_plain && !L.glow_reach?["[dx],[dy]"]) // a plain (carried) glow is drawn uncut: the visibility cut is all that bounds it
			continue
		var/strength = client_flat_light_profile(sqrt(dx * dx + dy * dy) * WORLD_ICON_SIZE / (WORLD_ICON_SIZE / 2 - G.pixel_x)) * G.alpha / 255 // pixel_x is minus the sprite's margin
		if(strength <= 0)
			continue
		var/list/tint = istext(G.color) ? rgb2num(G.color) : null
		if(length(tint) < 3)
			tint = list(255, 255, 255)
		red += strength * tint[1] / 255
		green += strength * tint[2] / 255
		blue += strength * tint[3] / 255
	return list(min(red, 1), min(green, 1), min(blue, 1))

/// How bright `T` looks to a player now, 0..1: under client lighting the strongest channel of the light its floor is drawn with (client_flat_light_rgb()),
/// else the gameplay light level. The darksight overlay (a radial BLEND_ADD glow centred on the player, hud_used.dsoverlay) eases in by how dark this says the
/// turf is; fed the gameplay level, which reads a lit corridor at 0.6 where the floor draws 1.0, it added a halo that peaked on the player's own character.
/proc/client_darksight_brightness(turf/T)
	if(!GLOB.client_lighting || !SSlighting.is_initialized())
		return T.get_lumcount()
	var/list/rgb = client_flat_light_rgb(T)
	return max(rgb[1], rgb[2], rgb[3])

/// The quantised colour of `rgb` (client_flat_light_rgb()) as one number: red, green and blue steps, 6 bits each.
/proc/client_flat_light_key(list/rgb)
	return round(rgb[1] * CLIENT_FLAT_LIGHT_STEPS) | (round(rgb[2] * CLIENT_FLAT_LIGHT_STEPS) << 6) | (round(rgb[3] * CLIENT_FLAT_LIGHT_STEPS) << 12)

/// The colour matrix that turns every pixel of the silhouette into the colour of `key`, alpha kept.
/proc/client_flat_light_color(key)
	var/red = (key & 63) / CLIENT_FLAT_LIGHT_STEPS
	var/green = ((key >> 6) & 63) / CLIENT_FLAT_LIGHT_STEPS
	var/blue = ((key >> 12) & 63) / CLIENT_FLAT_LIGHT_STEPS
	return list(0,0,0, 0,0,0, 0,0,0, red,green,blue)

/// Gives `A` its flat light when client lighting is on, its sprite is bigger than a tile and it stands on a turf; takes it away
/// when any of that stops being true; and sets its colour to the light its turf is drawn with now.
/proc/client_flat_light_update(atom/movable/A)
	if(QDELETED(A))
		return
	var/turf/T = A.loc
	if(!GLOB.client_lighting || !SSlighting.is_initialized() || !isturf(T) || !client_flat_light_big(A))
		client_flat_light_drop(A)
		return
	var/list/rgb = client_flat_light_rgb(T)
	var/key = client_flat_light_key(rgb)
	if(!A.flat_light)
		if(isnull(A.render_target))
			A.render_target = ref(A) // the name the emissive blocker uses too
		rel_set(A, nameof(/atom/movable::flat_light), new /atom/movable/client_flat_light(null, A.render_target))
		A.flat_light_overlay_add()
		registry_join(REGISTRY_CLIENT_FLAT_LIT, A)
		grant(A, /datum/capability/client_flat_light, A)
		GLOB.client_flat_light_makes++
		if(client_glow_trace_line())
			log_world("client flat light: [A] ([A.type]) is [round(client_flat_light_extent(A))] px, plane [A.flat_light.plane] layer [A.flat_light.layer], lit as the floor of its turf [T.x],[T.y],[T.z]")
	var/atom/movable/client_flat_light/F = A.flat_light
	if(F.lit_key == key)
		return
	F.set_lit_key(key)
	F.set_color(client_flat_light_color(key))
	GLOB.client_flat_light_recolours++
	if(client_glow_trace_line())
		log_world("client flat light: [A] now rgb [round(rgb[1] * CLIENT_FLAT_LIGHT_STEPS)],[round(rgb[2] * CLIENT_FLAT_LIGHT_STEPS)],[round(rgb[3] * CLIENT_FLAT_LIGHT_STEPS)] of [CLIENT_FLAT_LIGHT_STEPS] at [T.x],[T.y],[T.z] (the floor's drawn light; the gameplay light level there is [round(T.get_lumcount(), 0.01)])")

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

/// A light near the flat-lit atoms changed (it glows, moved, resized, went dark or its mask changed): each flat-lit atom within its reach takes the new light of its turf.
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
