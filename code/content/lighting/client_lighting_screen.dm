// Client lighting, piece 4: the screen side, run by every client in client lighting mode (compare mode, an admin view that adds a second engine, is client_lighting_compare.dm).
//
// The dark base. The lighting plane master multiplies its plane over the world. The DM engine darkens through BYOND itself (a
// dark dynamic turf is at luminosity 0, so BYOND draws it black) and through its underlays; client lighting shows every
// dynamic turf (luminosity 1) and its glows add onto the plane, so without a base an unlit turf multiplies by nothing (fully
// bright) and a glow's dim edge multiplies the world darker than that. So in client mode every client is shown a black base on
// the lighting plane, under the glows (client_glow_screen()), and a turf outside dynamic lighting (space, a fullbright area),
// which the DM engine leaves bright by drawing nothing, carries a white tile on the plane over the base (client_glow_white()).
//
// The glow plane. Every glow draws on PLANE_CLIENT_GLOW, a hidden render target whose master is alpha-cut by PLANE_CLIENT_VISIBLE, so light on a turf this client does not see is gone.
// PLANE_CLIENT_VISIBLE is one white tile as every area's overlay: BYOND draws an area's overlays only on the turfs it shows this client, so the client builds its own visibility map.
// The lighting plane master adds that plane over its black base with a layer filter. A second hidden plane, PLANE_CLIENT_SPREAD, holds a relay of the glow plane, blooms it about a tile
// and keeps only the opaque tiles (PLANE_CLIENT_WALLS, a white underlay on each opaque turf set on opacity changes), and the master adds that too: a wall is lit only from floor this client can see.
// All of this was seen working in an isolated client rig. A relay must stand at screen_loc "1,1": at "CENTER" it draws shifted by about half a view. No server work when a player moves.
//

/// The glow plane's master: renders the plane only as a hidden render target.
/atom/movable/screen/plane_master/client_glow
	plane = PLANE_CLIENT_GLOW
	render_target = CLIENT_GLOW_RENDER_TARGET
	blend_mode = BLEND_OVERLAY
	alpha = 255 // the base plane master is alpha 0, and a hidden render target at alpha 0 renders empty: the world goes black (client rig)
	appearance_flags = PLANE_MASTER | NO_CLIENT_COLOR

/// The plane of "turfs this client sees": renders only as the glow plane's alpha source.
/atom/movable/screen/plane_master/client_visible
	plane = PLANE_CLIENT_VISIBLE
	render_target = CLIENT_VISIBLE_RENDER_TARGET
	blend_mode = BLEND_OVERLAY
	alpha = 255 // the base plane master is alpha 0, and a hidden render target at alpha 0 renders empty: the world goes black (client rig)
	appearance_flags = PLANE_MASTER | NO_CLIENT_COLOR

/// The plane of opaque tiles: renders only as the wall spread's alpha source.
/atom/movable/screen/plane_master/client_walls
	plane = PLANE_CLIENT_WALLS
	render_target = CLIENT_WALLS_RENDER_TARGET
	blend_mode = BLEND_OVERLAY
	alpha = 255 // the base plane master is alpha 0, and a hidden render target at alpha 0 renders empty: the world goes black (client rig)
	appearance_flags = PLANE_MASTER | NO_CLIENT_COLOR

/// The bloomed glow plane cut to opaque tiles, added to the lighting plane by its master's filter.
/atom/movable/screen/plane_master/client_spread
	plane = PLANE_CLIENT_SPREAD
	render_target = CLIENT_SPREAD_RENDER_TARGET
	blend_mode = BLEND_OVERLAY
	alpha = 255 // the base plane master is alpha 0, and a hidden render target at alpha 0 renders empty: the world goes black (client rig)
	appearance_flags = PLANE_MASTER | NO_CLIENT_COLOR

/// The black base the glows add onto (on the lighting plane in client mode, on the glow plane in compare mode).
/atom/movable/screen/client_glow_base
	name = ""
	icon = 'icons/mob/screen_gen.dmi'
	icon_state = "flash"
	screen_loc = "WEST,SOUTH to EAST,NORTH"
	plane = PLANE_LIGHTING
	layer = BACKGROUND_LAYER + 21 // under the white tiles and the glows (CLIENT_GLOW_WHITE_LAYER, CLIENT_GLOW_LAYER)
	color = "#000"
	blend_mode = BLEND_OVERLAY
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT


/// The glow plane copied onto the spread plane. Its render_source is set when it is made (client_glow_screen_objects()): a render_source declared on the type stops
/// the native compiler (doc/rewrite/native_render_source_initializer_repro.md).
/atom/movable/screen/client_glow_spread_relay
	name = ""
	screen_loc = "1,1" // at "CENTER" a render_source relay draws shifted by about half a view (client rig)
	plane = PLANE_CLIENT_SPREAD
	layer = 1
	blend_mode = BLEND_OVERLAY
	appearance_flags = NONE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/// The shared screen objects (a screen object may sit on many screens); made on first use.
GLOBAL_DATUM(client_glow_plane_master, /atom/movable/screen/plane_master/client_glow)
GLOBAL_DATUM(client_glow_base, /atom/movable/screen/client_glow_base)
GLOBAL_DATUM(client_walls_plane_master, /atom/movable/screen/plane_master/client_walls)
GLOBAL_DATUM(client_spread_plane_master, /atom/movable/screen/plane_master/client_spread)
GLOBAL_DATUM(client_glow_spread_relay, /atom/movable/screen/client_glow_spread_relay)
GLOBAL_DATUM(client_visible_plane_master, /atom/movable/screen/plane_master/client_visible)

CAPABILITIES_PART(/datum/controller/global_vars, client_glow_screens)
	owns_one(nameof(client_glow_plane_master), /atom/movable/screen/plane_master/client_glow)
	owns_one(nameof(client_glow_base), /atom/movable/screen/client_glow_base)
	owns_one(nameof(client_walls_plane_master), /atom/movable/screen/plane_master/client_walls)
	owns_one(nameof(client_spread_plane_master), /atom/movable/screen/plane_master/client_spread)
	owns_one(nameof(client_glow_spread_relay), /atom/movable/screen/client_glow_spread_relay)
	owns_one(nameof(client_visible_plane_master), /atom/movable/screen/plane_master/client_visible)

/client
	/// What this client's screen shows of client lighting now (CLIENT_GLOW_SCREEN_*).
	var/tmp/lighting_screen = CLIENT_GLOW_SCREEN_NONE

/// Every shared screen object: list(glow master, base, compare base, compare relay, visibility master, walls master, spread master, spread relay).
/proc/client_glow_screen_objects()
	if(!GLOB.client_glow_plane_master)
		rel_set(GLOB, nameof(GLOB.client_glow_plane_master), new /atom/movable/screen/plane_master/client_glow)
		rel_set(GLOB, nameof(GLOB.client_glow_base), new /atom/movable/screen/client_glow_base)
		client_glow_compare_make()
		rel_set(GLOB, nameof(GLOB.client_visible_plane_master), new /atom/movable/screen/plane_master/client_visible)
		rel_set(GLOB, nameof(GLOB.client_walls_plane_master), new /atom/movable/screen/plane_master/client_walls)
		rel_set(GLOB, nameof(GLOB.client_spread_plane_master), new /atom/movable/screen/plane_master/client_spread)
		var/atom/movable/screen/client_glow_spread_relay/S = new
		S.render_source = CLIENT_GLOW_RENDER_TARGET
		rel_set(GLOB, nameof(GLOB.client_glow_spread_relay), S)
		GLOB.client_glow_plane_master.add_filter("client_visible_cut", 1, list(type = "alpha", render_source = CLIENT_VISIBLE_RENDER_TARGET))
		// Opaque tiles leave the glow plane before anything spreads: a soft edge of a few pixels on the far side of a wall is enough for the bloom to light the whole wall (client rig).
		GLOB.client_glow_plane_master.add_filter("client_glow_no_walls", 2, list(type = "alpha", render_source = CLIENT_WALLS_RENDER_TARGET, flags = MASK_INVERSE))
		GLOB.client_glow_plane_master.add_filter("client_glow_soften", 3, list(type = "blur", size = CLIENT_GLOW_SOFTEN_SIZE))
		GLOB.client_spread_plane_master.add_filter("client_wall_spread", 1, list(type = "bloom", threshold = "#000000", size = CLIENT_GLOW_SPREAD_SIZE, offset = CLIENT_GLOW_SPREAD_OFFSET, alpha = CLIENT_GLOW_SPREAD_ALPHA))
		GLOB.client_spread_plane_master.add_filter("client_walls_only", 2, list(type = "alpha", render_source = CLIENT_WALLS_RENDER_TARGET))
	return list(GLOB.client_glow_plane_master, GLOB.client_glow_base, GLOB.client_glow_compare_base, GLOB.client_glow_relay, GLOB.client_visible_plane_master, GLOB.client_walls_plane_master, GLOB.client_spread_plane_master, GLOB.client_glow_spread_relay)

/// The lighting master adds the glow plane and the wall spread over its black base, before its emissive masks so those still punch through; compare mode relays instead. A filter whose source is not on this screen adds nothing.
/proc/client_glow_master_compose(atom/movable/screen/plane_master/lighting/M)
	M.remove_filter("client_glow_add")
	M.remove_filter("client_spread_add")
	if(GLOB.client_lighting_compare)
		return
	M.add_filter("client_glow_add", -2, list(type = "layer", render_source = CLIENT_GLOW_RENDER_TARGET, blend_mode = BLEND_ADD))
	M.add_filter("client_spread_add", -1, list(type = "layer", render_source = CLIENT_SPREAD_RENDER_TARGET, blend_mode = BLEND_ADD))

/// The screen state a client wants now.
/proc/client_glow_screen_state(client/C)
	if(!GLOB.client_lighting)
		return CLIENT_GLOW_SCREEN_NONE
	if(!GLOB.client_lighting_compare)
		return CLIENT_GLOW_SCREEN_BASE
	return C?.lighting_compare_dm ? CLIENT_GLOW_SCREEN_COMPARE_DM : CLIENT_GLOW_SCREEN_COMPARE_GLOW

/// The screen objects a client in `state` is shown (tests read it).
/proc/client_glow_screen(state)
	var/list/all = client_glow_screen_objects()
	switch(state)
		if(CLIENT_GLOW_SCREEN_BASE)
			return list(all[2], all[1], all[5], all[6], all[7], all[8])
		if(CLIENT_GLOW_SCREEN_COMPARE_DM)
			return list(all[1])
		if(CLIENT_GLOW_SCREEN_COMPARE_GLOW)
			return list(all[1], all[3], all[4], all[5])
	return list()

/// The client's screen was emptied: the next sync puts every lighting screen object back.
/proc/client_glow_screen_forget(client/C)
	C.lighting_screen = CLIENT_GLOW_SCREEN_NONE

/// Puts this client's screen in step with the lighting mode and its compare view. Cheap when it already is (one comparison).
/proc/client_glow_screen_sync(client/C)
	if(!C)
		return
	var/want = client_glow_screen_state(C)
	if(want == C.lighting_screen)
		return
	log_world("client lighting screen: [C.ckey] [C.lighting_screen] -> [want]") // a change here while walking would blink the darkness
	client_screen_remove(C, client_glow_screen_objects())
	client_screen_add(C, client_glow_screen(want))
	C.lighting_screen = want

/proc/client_glow_screens_sync()
	for(var/client/C as anything in GLOB.clients)
		client_glow_screen_sync(C)

/// The plane a glow draws on.
/proc/client_glow_plane()
	return PLANE_CLIENT_GLOW

/// The plane a white tile draws on now: above the relay on the lighting plane, or on the glow plane under compare's opaque relay.
/proc/client_glow_white_plane()
	return GLOB.client_lighting_compare ? PLANE_CLIENT_GLOW : PLANE_LIGHTING

/// The white tile on `plane`: one shared appearance per plane, so a turf's underlay costs no appearance of its own.
/proc/client_glow_white_build(plane_text)
	var/mutable_appearance/white = mutable_appearance(LIGHTING_ICON, "transparent", CLIENT_GLOW_WHITE_LAYER, text2num(plane_text), 255, RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM)
	return white

DECLARE_SHARED_CACHE(client_glow_white_tiles, GLOBAL_PROC_REF(client_glow_white_build), SC_NEVER)

/// This turf, outside dynamic lighting inside a dynamic area, keeps (or loses) its white tile on the plane the glows use now
/// (a turf in an area outside dynamic lighting is covered by the area's tile).
/turf/proc/client_glow_white(on)
	underlays -= CACHED_FAST(client_glow_white_tiles, "[PLANE_LIGHTING]")
	underlays -= CACHED_FAST(client_glow_white_tiles, "[PLANE_CLIENT_GLOW]")
	var/area/A = loc
	if(on && !IS_DYNAMIC_LIGHTING(src) && IS_DYNAMIC_LIGHTING(A))
		underlays += CACHED_FAST(client_glow_white_tiles, "[client_glow_white_plane()]")
		return TRUE
	return FALSE

/// The white tile an opaque turf carries on the walls plane.
/proc/client_walls_tile()
	var/static/mutable_appearance/tile
	if(!tile)
		tile = mutable_appearance(LIGHTING_ICON, "transparent", CLIENT_GLOW_WHITE_LAYER, PLANE_CLIENT_WALLS, 255, RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM)
	return tile

/// This turf's opacity changed or it was just made: it is on the walls plane exactly while it is opaque. Events only.
/turf/proc/client_glow_wall_sync()
	underlays -= client_walls_tile()
	if(GLOB.client_lighting && directional_opacity == ALL_CARDINALS)
		underlays += client_walls_tile()

/// The white tile every area draws on the visibility plane: BYOND shows it only on turfs this client sees.
/proc/client_visible_tile()
	var/static/mutable_appearance/tile
	if(!tile)
		tile = mutable_appearance(LIGHTING_ICON, "transparent", CLIENT_GLOW_WHITE_LAYER, PLANE_CLIENT_VISIBLE, 255, RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM)
	return tile

/// The white tile an area outside dynamic lighting draws in client mode (its draw()), or null: BYOND draws an area's overlays on
/// every turf of the area, so the whole area stays bright for one appearance (space is most of the map's turfs).
/proc/client_glow_area_white(area/A)
	if(!A.client_glow_white_plane)
		return null
	return CACHED_FAST(client_glow_white_tiles, "[A.client_glow_white_plane]")

/area
	/// Client lighting: the plane this area's white tile is on (client_glow_whites_set()), 0 for none. Its draw() reads it.
	var/client_glow_white_plane = 0
	/// Client lighting: this area draws the visibility tile (client_glow_whites_set(), set_ambient_luminosity() for a later area). Its draw() reads it,
	/// so the setter redraws the area: an area whose nothing else changes is never redrawn otherwise.
	var/client_visible_shown = FALSE

/// Everything outside dynamic lighting gets its white tile (on) or loses it, in one pass: an area outside dynamic lighting as
/// its overlay; inside a dynamic area, a turf outside dynamic lighting as its underlay. Returns how many carry one.
/proc/client_glow_whites_set(on)
	var/n = 0
	var/start = REALTIMEOFDAY
	for(var/area/A in world)
		A.set_client_visible_shown(!!on)
		if(!A.dynamic_lighting)
			A.set_client_glow_white_plane(on ? client_glow_white_plane() : 0) // its draw() adds or drops the white tile
			n++
			continue
		for(var/turf/T as anything in contents_of(A, /turf))
			if(T.directional_opacity == ALL_CARDINALS)
				T.client_glow_wall_sync()
			if(!IS_DYNAMIC_LIGHTING(T) && T.client_glow_white(on))
				n++
	log_world("client lighting: [n] area(s) and turf(s) outside dynamic lighting [on ? "carry" : "dropped"] a white tile ([(REALTIMEOFDAY - start) * 100] ms)")
	return n

