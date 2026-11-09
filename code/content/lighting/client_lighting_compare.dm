// Client lighting, piece 4: the screen side and compare mode.
//
// The dark base. The lighting plane master multiplies its plane over the world. The DM engine darkens through BYOND itself (a
// dark dynamic turf is at luminosity 0, so BYOND draws it black) and through its underlays; client lighting shows every
// dynamic turf (luminosity 1) and its glows add onto the plane, so without a base an unlit turf multiplies by nothing (fully
// bright) and a glow's dim edge multiplies the world darker than that. So in client mode every client is shown a black base on
// the lighting plane, under the glows (client_glow_screen()), and a turf outside dynamic lighting (space, a fullbright area),
// which the DM engine leaves bright by drawing nothing, carries a white tile on the plane over the base (client_glow_white()).
//
// The glow plane. Every glow draws on PLANE_CLIENT_GLOW, a hidden render target over its own black base. Its master carries two filters: an
// alpha cut by PLANE_CLIENT_VISIBLE, so light on a turf this client does not see is gone, and a bloom that carries the remaining floor light about a tile onto the
// walls beside it, so a wall is lit only from a side this client can see. A relay draws the result on the lighting plane, over the black base. PLANE_CLIENT_VISIBLE is
// one white tile as every area's overlay: BYOND draws an area's overlays only on the turfs it shows this client, so the client builds its own visibility map, with no
// server work when a player moves. The white tiles stay on the lighting plane, above the relay, so they neither bloom nor get cut.
//
// Compare mode. The server runs both engines at once, the DM corner lighting (a lighting object on every dynamic turf, as the
// classic engine had before lazy objects, since turfs stay at luminosity 1 for the glows) and the client glows, and each client
// picks which one it sees, live:
//   - glows (and the white tiles) draw on their own plane, PLANE_CLIENT_GLOW, whose master is a hidden render target
//     (CLIENT_GLOW_RENDER_TARGET): a client shown nothing more never sees a glow, so it sees the DM lighting alone;
//   - a client on the client view also gets a black base on the glow plane and a relay on PLANE_LIGHTING, above the DM
//     underlays, that draws the glow plane there: opaque, so it covers the DM underlays, and the lighting master multiplies it
//     over the world as it would the DM lighting.
// It costs both engines, so it is admin-only and off by default; normal client mode runs one engine.

/// TRUE while both engines run and each client picks one (client_lighting_compare_set()). Implies GLOB.client_lighting.
GLOBAL_VAR_INIT(client_lighting_compare, FALSE)

/// What a client's screen shows of client lighting (client.lighting_screen).
#define CLIENT_GLOW_SCREEN_NONE 0
#define CLIENT_GLOW_SCREEN_BASE 1
#define CLIENT_GLOW_SCREEN_COMPARE_DM 2
#define CLIENT_GLOW_SCREEN_COMPARE_GLOW 3

/// The glow plane's master: renders the plane only as a hidden render target.
/atom/movable/screen/plane_master/client_glow
	plane = PLANE_CLIENT_GLOW
	render_target = CLIENT_GLOW_RENDER_TARGET
	blend_mode = BLEND_OVERLAY
	appearance_flags = PLANE_MASTER | NO_CLIENT_COLOR

/// The plane of "turfs this client sees": renders only as the glow plane's alpha source.
/atom/movable/screen/plane_master/client_visible
	plane = PLANE_CLIENT_VISIBLE
	render_target = CLIENT_VISIBLE_RENDER_TARGET
	blend_mode = BLEND_OVERLAY
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

/atom/movable/screen/client_glow_base/compare
	plane = PLANE_CLIENT_GLOW

/// Draws the glow plane on the lighting plane, over the DM underlays, for a client on the compare client view. Its
/// render_source is set when it is made (client_glow_screen_objects()): a render_source declared on the type stops the native
/// compiler (doc/rewrite/native_render_source_initializer_repro.md).
/atom/movable/screen/client_glow_relay
	name = ""
	screen_loc = "CENTER"
	plane = PLANE_LIGHTING
	layer = BACKGROUND_LAYER + 30
	blend_mode = BLEND_OVERLAY
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/// The glow plane on the lighting plane in normal play: over the black base, under the white tiles.
/atom/movable/screen/client_glow_relay/normal
	layer = BACKGROUND_LAYER + 22

/// The shared screen objects (a screen object may sit on many screens); made on first use.
GLOBAL_DATUM(client_glow_plane_master, /atom/movable/screen/plane_master/client_glow)
GLOBAL_DATUM(client_glow_base, /atom/movable/screen/client_glow_base)
GLOBAL_DATUM(client_glow_compare_base, /atom/movable/screen/client_glow_base/compare)
GLOBAL_DATUM(client_glow_relay, /atom/movable/screen/client_glow_relay)
GLOBAL_DATUM(client_glow_normal_relay, /atom/movable/screen/client_glow_relay/normal)
GLOBAL_DATUM(client_visible_plane_master, /atom/movable/screen/plane_master/client_visible)

CAPABILITIES_PART(/datum/controller/global_vars, client_glow_screens)
	owns_one(nameof(client_glow_plane_master), /atom/movable/screen/plane_master/client_glow)
	owns_one(nameof(client_glow_base), /atom/movable/screen/client_glow_base)
	owns_one(nameof(client_glow_compare_base), /atom/movable/screen/client_glow_base/compare)
	owns_one(nameof(client_glow_relay), /atom/movable/screen/client_glow_relay)
	owns_one(nameof(client_glow_normal_relay), /atom/movable/screen/client_glow_relay/normal)
	owns_one(nameof(client_visible_plane_master), /atom/movable/screen/plane_master/client_visible)

/client
	/// Compare mode: TRUE when this client sees the DM lighting, FALSE the client glows.
	var/tmp/lighting_compare_dm = FALSE
	/// What this client's screen shows of client lighting now (CLIENT_GLOW_SCREEN_*).
	var/tmp/lighting_screen = CLIENT_GLOW_SCREEN_NONE

/// Every shared screen object: list(master, base, compare base, relay, normal relay, visibility master).
/proc/client_glow_screen_objects()
	if(!GLOB.client_glow_plane_master)
		rel_set(GLOB, nameof(GLOB.client_glow_plane_master), new /atom/movable/screen/plane_master/client_glow)
		rel_set(GLOB, nameof(GLOB.client_glow_base), new /atom/movable/screen/client_glow_base)
		rel_set(GLOB, nameof(GLOB.client_glow_compare_base), new /atom/movable/screen/client_glow_base/compare)
		var/atom/movable/screen/client_glow_relay/R = new
		R.render_source = CLIENT_GLOW_RENDER_TARGET
		rel_set(GLOB, nameof(GLOB.client_glow_relay), R)
		var/atom/movable/screen/client_glow_relay/normal/N = new
		N.render_source = CLIENT_GLOW_RENDER_TARGET
		rel_set(GLOB, nameof(GLOB.client_glow_normal_relay), N)
		rel_set(GLOB, nameof(GLOB.client_visible_plane_master), new /atom/movable/screen/plane_master/client_visible)
		var/atom/movable/screen/plane_master/client_glow/M = GLOB.client_glow_plane_master
		M.add_filter("client_visible_cut", 1, list(type = "alpha", render_source = CLIENT_VISIBLE_RENDER_TARGET))
		M.add_filter("client_wall_spread", 2, list(type = "bloom", threshold = "#000000", size = CLIENT_GLOW_SPREAD_SIZE, offset = CLIENT_GLOW_SPREAD_OFFSET, alpha = CLIENT_GLOW_SPREAD_ALPHA))
	return list(GLOB.client_glow_plane_master, GLOB.client_glow_base, GLOB.client_glow_compare_base, GLOB.client_glow_relay, GLOB.client_glow_normal_relay, GLOB.client_visible_plane_master)

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
			return list(all[2], all[1], all[3], all[5], all[6])
		if(CLIENT_GLOW_SCREEN_COMPARE_DM)
			return list(all[1])
		if(CLIENT_GLOW_SCREEN_COMPARE_GLOW)
			return list(all[1], all[3], all[4], all[6])
	return list()

/// Puts this client's screen in step with the lighting mode and its compare view. Cheap when it already is (one comparison).
/proc/client_glow_screen_sync(client/C)
	if(!C)
		return
	var/want = client_glow_screen_state(C)
	if(want == C.lighting_screen)
		return
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

/// Everything outside dynamic lighting gets its white tile (on) or loses it, in one pass: an area outside dynamic lighting as
/// its overlay; inside a dynamic area, a turf outside dynamic lighting as its underlay. Returns how many carry one.
/proc/client_glow_whites_set(on)
	var/n = 0
	var/start = REALTIMEOFDAY
	for(var/area/A in world)
		if(!A.dynamic_lighting)
			A.set_client_glow_white_plane(on ? client_glow_white_plane() : 0) // its draw() adds or drops the white tile
			n++
			continue
		for(var/turf/T as anything in contents_of(A, /turf))
			if(!IS_DYNAMIC_LIGHTING(T) && T.client_glow_white(on))
				n++
	log_world("client lighting: [n] area(s) and turf(s) outside dynamic lighting [on ? "carry" : "dropped"] a white tile ([(REALTIMEOFDAY - start) * 100] ms)")
	return n

/// Switches compare mode on or off live, in one pass with no yield (as client_lighting_set()). On turns client lighting on
/// first, then gives every dynamic turf its lighting object and redraws every light with both engines; off clears the
/// lighting objects and the corners' light and redraws every light as a glow alone.
/proc/client_lighting_compare_set(on)
	on = !!on
	if(GLOB.client_lighting_compare == on)
		return
	if(on && !GLOB.client_lighting)
		client_lighting_set(TRUE)
	GLOB.client_lighting_compare = on
	log_world("client lighting compare: [on ? "on" : "off"]")
	if(SSlighting.is_initialized())
		var/list/all_turfs = block(locate(1, 1, 1), locate(world.maxx, world.maxy, world.maxz))
		for(var/turf/T as anything in all_turfs)
			if(on)
				T.lighting_build_overlay()
			else if(T.lighting_object)
				T.lighting_clear_overlay()
				if(T.has_dynamic_lighting())
					T.set_luminosity(1, TRUE)
		for(var/datum/light_source/L)
			if(QDELETED(L)) // a requeued deleted source would spin light_step()
				continue
			if(!on)
				L.remove_lum()
			L.force_update()
		client_glow_whites_set(TRUE) // the white tiles move to the plane the glows use now
	client_glow_screens_sync()

ADMIN_VERB(toggle_client_lighting_compare, R_DEBUG|R_SERVER, "Toggle Lighting Compare", "Run the DM lighting and the client glows together, so each admin can switch which one they see (costs both engines).", ADMIN_CATEGORY_DEBUG_GAME)
	client_lighting_compare_set(!GLOB.client_lighting_compare)
	message_admins("[key_name_admin(user)] turned lighting compare mode [GLOB.client_lighting_compare ? "on" : "off"].")

ADMIN_VERB(switch_lighting_compare_view, R_DEBUG|R_SERVER, "Switch Lighting Compare View", "In lighting compare mode, switch between seeing the DM lighting and the client glows.", ADMIN_CATEGORY_DEBUG_GAME)
	if(!GLOB.client_lighting_compare)
		to_chat(user, span_warning("Lighting compare mode is off (Toggle Lighting Compare)."))
		return
	user.lighting_compare_dm = !user.lighting_compare_dm
	client_glow_screen_sync(user)
	to_chat(user, span_notice("You now see the [user.lighting_compare_dm ? "DM corner lighting" : "client glows"]."))
