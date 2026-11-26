// Client lighting, piece 5: compare mode. The screen side of client lighting that every client runs (the dark base, the glow plane, the walls spread, the white
// tiles) is client_lighting_screen.dm; this is only what compare mode adds.
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

/// The black base on the glow plane under a compare-view client's relay.
/atom/movable/screen/client_glow_base/compare
	plane = PLANE_CLIENT_GLOW

/// Draws the glow plane on the lighting plane, over the DM underlays, for a client on the compare client view. Its render_source is set when it is made
/// (client_glow_compare_make()): a render_source declared on the type stops the native compiler (doc/rewrite/native_render_source_initializer_repro.md).
/atom/movable/screen/client_glow_compare_relay
	name = ""
	screen_loc = "1,1" // at "CENTER" a render_source relay draws shifted by about half a view (client rig)
	plane = PLANE_LIGHTING
	layer = BACKGROUND_LAYER + 30
	blend_mode = BLEND_OVERLAY
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

GLOBAL_DATUM(client_glow_compare_base, /atom/movable/screen/client_glow_base/compare)
GLOBAL_DATUM(client_glow_relay, /atom/movable/screen/client_glow_compare_relay)

CAPABILITIES_PART(/datum/controller/global_vars, client_glow_compare_screens)
	owns_one(nameof(client_glow_compare_base), /atom/movable/screen/client_glow_base/compare)
	owns_one(nameof(client_glow_relay), /atom/movable/screen/client_glow_compare_relay)

/client
	/// Compare mode: TRUE when this client sees the DM lighting, FALSE the client glows.
	var/tmp/lighting_compare_dm = FALSE

/// Makes the compare view's two shared screen objects (client_glow_screen_objects()).
/proc/client_glow_compare_make()
	rel_set(GLOB, nameof(GLOB.client_glow_compare_base), new /atom/movable/screen/client_glow_base/compare)
	var/atom/movable/screen/client_glow_compare_relay/R = new
	R.render_source = CLIENT_GLOW_RENDER_TARGET
	rel_set(GLOB, nameof(GLOB.client_glow_relay), R)

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
	for(var/atom/movable/screen/plane_master/lighting/M in world)
		client_glow_master_compose(M)
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
