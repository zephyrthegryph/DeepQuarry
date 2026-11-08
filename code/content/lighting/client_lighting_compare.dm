// Client lighting, piece 4: the screen side and compare mode.
//
// The dark base. The lighting plane master multiplies its plane over the world. The DM engine darkens through BYOND itself (a
// dark dynamic turf is at luminosity 0, so BYOND draws it black) and through its underlays; client lighting shows every
// dynamic turf (luminosity 1) and its glows add onto the plane, so without a base an unlit turf multiplies by nothing (fully
// bright) and a glow's dim edge multiplies the world darker than that. So in client mode every client is shown a black base on
// the lighting plane, under the glows (client_glow_screen()), and a turf outside dynamic lighting (space, a fullbright area),
// which the DM engine leaves bright by drawing nothing, carries a white tile on the plane over the base (client_glow_white()).
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
/// Turfs given a white tile by the last pass (tests, logs).
GLOBAL_VAR_INIT(client_glow_whites, 0)

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

/// The black base the glows add onto (on the lighting plane in client mode, on the glow plane in compare mode).
/atom/movable/screen/client_glow_base
	name = ""
	icon = 'icons/mob/screen_gen.dmi'
	icon_state = "flash"
	screen_loc = "WEST,SOUTH to EAST,NORTH"
	plane = PLANE_LIGHTING
	layer = BACKGROUND_LAYER + 21 // under the white tiles and the glows (BACKGROUND_LAYER + 22)
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

/// The shared screen objects (a screen object may sit on many screens); made on first use.
GLOBAL_DATUM(client_glow_plane_master, /atom/movable/screen/plane_master/client_glow)
GLOBAL_DATUM(client_glow_base, /atom/movable/screen/client_glow_base)
GLOBAL_DATUM(client_glow_compare_base, /atom/movable/screen/client_glow_base/compare)
GLOBAL_DATUM(client_glow_relay, /atom/movable/screen/client_glow_relay)

CAPABILITIES_PART(/datum/controller/global_vars, client_glow_screens)
	owns_one(nameof(client_glow_plane_master), /atom/movable/screen/plane_master/client_glow)
	owns_one(nameof(client_glow_base), /atom/movable/screen/client_glow_base)
	owns_one(nameof(client_glow_compare_base), /atom/movable/screen/client_glow_base/compare)
	owns_one(nameof(client_glow_relay), /atom/movable/screen/client_glow_relay)

/client
	/// Compare mode: TRUE when this client sees the DM lighting, FALSE the client glows.
	var/tmp/lighting_compare_dm = FALSE
	/// What this client's screen shows of client lighting now (CLIENT_GLOW_SCREEN_*).
	var/tmp/lighting_screen = CLIENT_GLOW_SCREEN_NONE

/// Every shared screen object: list(master, base, compare base, relay).
/proc/client_glow_screen_objects()
	if(!GLOB.client_glow_plane_master)
		rel_set(GLOB, nameof(GLOB.client_glow_plane_master), new /atom/movable/screen/plane_master/client_glow)
		rel_set(GLOB, nameof(GLOB.client_glow_base), new /atom/movable/screen/client_glow_base)
		rel_set(GLOB, nameof(GLOB.client_glow_compare_base), new /atom/movable/screen/client_glow_base/compare)
		var/atom/movable/screen/client_glow_relay/R = new
		R.render_source = CLIENT_GLOW_RENDER_TARGET
		rel_set(GLOB, nameof(GLOB.client_glow_relay), R)
	return list(GLOB.client_glow_plane_master, GLOB.client_glow_base, GLOB.client_glow_compare_base, GLOB.client_glow_relay)

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
			return list(all[2])
		if(CLIENT_GLOW_SCREEN_COMPARE_DM)
			return list(all[1])
		if(CLIENT_GLOW_SCREEN_COMPARE_GLOW)
			return list(all[1], all[3], all[4])
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

/// The plane a glow and a white tile draw on now.
/proc/client_glow_plane()
	return GLOB.client_lighting_compare ? PLANE_CLIENT_GLOW : PLANE_LIGHTING

/// The white tile on `plane`: one shared appearance per plane, so a turf's underlay costs no appearance of its own.
/proc/client_glow_white_build(plane_text)
	var/mutable_appearance/white = mutable_appearance(LIGHTING_ICON, "transparent", BACKGROUND_LAYER + 21.5, text2num(plane_text), 255, RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM)
	return white

DECLARE_SHARED_CACHE(client_glow_white_tiles, GLOBAL_PROC_REF(client_glow_white_build), SC_NEVER)

/// This turf, outside dynamic lighting inside a dynamic area, keeps (or loses) its white tile on the plane the glows use now
/// (a turf in an area outside dynamic lighting is covered by the area's tile).
/turf/proc/client_glow_white(on)
	underlays -= CACHED_FAST(client_glow_white_tiles, "[PLANE_LIGHTING]")
	underlays -= CACHED_FAST(client_glow_white_tiles, "[PLANE_CLIENT_GLOW]")
	var/area/A = loc
	if(on && !IS_DYNAMIC_LIGHTING(src) && IS_DYNAMIC_LIGHTING(A))
		underlays += CACHED_FAST(client_glow_white_tiles, "[client_glow_plane()]")
		return TRUE
	return FALSE

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
/// its overlay; inside a dynamic area, a turf outside dynamic lighting as its underlay. GLOB.client_glow_whites counts both.
/proc/client_glow_whites_set(on)
	var/n = 0
	var/start = REALTIMEOFDAY
	for(var/area/A in world)
		if(!A.dynamic_lighting)
			A.set_client_glow_white_plane(on ? client_glow_plane() : 0) // its draw() adds or drops the white tile
			n++
			continue
		for(var/turf/T as anything in contents_of(A, /turf))
			if(!IS_DYNAMIC_LIGHTING(T) && T.client_glow_white(on))
				n++
	GLOB.client_glow_whites = n
	log_world("client lighting: [n] area(s) and turf(s) outside dynamic lighting [on ? "carry" : "dropped"] a white tile ([(REALTIMEOFDAY - start) * 100] ms)")

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
