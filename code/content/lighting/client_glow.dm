// Client-rendered lighting, piece 1: glows. With the mode on, every light source is one soft gradient sprite on the lighting
// plane, blended additively over its black backdrop; the plane master multiplies the result over the world, so the client's
// GPU does the blending and the server only sends where each glow sits, its colour, size and strength. The DM lighting
// corners and turf underlays are not touched in this mode: no lighting object is made, and a light skips its corner work.
// The default lighting of a running server. Glows draw on a hidden plane that is cut to what this client sees, spread onto walls and relayed to the lighting plane (client_lighting_screen.dm).

/// TRUE while lights draw as client glows instead of the DM corner and underlay lighting. The lighting system sets it at boot
/// (a test sets it through client_lighting_set()); a unit-test world stays on the DM engine unless the test asks.
GLOBAL_VAR_INIT(client_lighting, FALSE)

/// Per-event lighting diagnostics (a chunk crossing, a delivery ack, a flat light recolour, a settle, a flush) are written only while the lighting_trace config flag is on
/// (profiling and play-testing): they run on every crossing and light change, and a log line each is a server cost. Warnings and anomalies (images taken off a client,
/// a stale or timed-out delivery, a drop-all and its reason) are always written. Use as `if(client_glow_trace_line())` around the log_world(); the lines written are counted.
GLOBAL_VAR_INIT(client_glow_trace_lines, 0)

/proc/client_glow_trace_line()
	if(!CONFIG_GET(flag/lighting_trace))
		return FALSE
	GLOB.client_glow_trace_lines++
	return TRUE

/// One light source's glow.
/obj/effect/overlay/client_glow
	name = ""
	icon = 'icons/effects/light_overlays/light_32.dmi'
	icon_state = "light"
	plane = PLANE_LIGHTING
	// An ordinary layer, as the DM lighting's turf underlays use: the black base is a screen object on BACKGROUND_LAYER, and a map
	// object on BACKGROUND_LAYER does not reliably draw over a screen one.
	layer = CLIENT_GLOW_LAYER
	blend_mode = BLEND_ADD
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM | KEEP_APART
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	anchored = TRUE
	vis_flags = VIS_HIDE // not drawn through a turf in vis_contents: open space would show the deck below's glow, uncut (client rig)

/datum/light_source
	/// The glow this light shows while client lighting is on; null otherwise.
	var/obj/effect/overlay/client_glow/glow
	/// TRUE once this light has changed turf while glowing.
	var/glow_has_moved = FALSE
	/// "x:y:z" where this light stood when its settle check was scheduled; null while none is pending (client_glow_settle_check()).
	var/glow_settle_at
	/// TRUE: viewers draw this light's plain glow, with no baked cut (client_glow_note_moving()).
	var/glow_plain = FALSE

CAPABILITIES_PART(/datum/light_source, light_source_client_glow)
	owns_one(nameof(glow), /obj/effect/overlay/client_glow)

/// The glow sprite that is `pixel_bounds` pixels across.
/proc/client_glow_icon(pixel_bounds)
	var/static/list/glow_icons = list(
		"32" = 'icons/effects/light_overlays/light_32.dmi',
		"96" = 'icons/effects/light_overlays/light_96.dmi',
		"160" = 'icons/effects/light_overlays/light_160.dmi',
		"224" = 'icons/effects/light_overlays/light_224.dmi',
		"288" = 'icons/effects/light_overlays/light_288.dmi',
		"352" = 'icons/effects/light_overlays/light_352.dmi',
		"64" = 'icons/effects/light_overlays/light_64.dmi',
		"128" = 'icons/effects/light_overlays/light_128.dmi',
		"192" = 'icons/effects/light_overlays/light_192.dmi',
		"256" = 'icons/effects/light_overlays/light_256.dmi',
		"320" = 'icons/effects/light_overlays/light_320.dmi',
	)
	return glow_icons["[pixel_bounds]"]

/// Places, sizes and tints this light's glow (client lighting): the work update_corners() does in this mode.
/datum/light_source/proc/client_glow_apply()
	if(!glow)
		rel_set(src, nameof(glow), new /obj/effect/overlay/client_glow(null))
	var/turf/was_at = glow_reach_origin // where its light last reached from, for the flat lights it leaves
	var/was_range = glow_mask_range
	var/obj/effect/overlay/client_glow/G = glow
	var/range = clamp(CEILING(light_range, 0.5), 1, 6)
	var/pixel_bounds = ((range - 1) * 64) + 32
	G.set_icon(client_glow_icon(pixel_bounds))
	var/offset = (pixel_bounds - 32) * 0.5
	// A wall-mounted device's pixel offset rounds its pixel_turf onto the wall: centred there its glow, and an unbaked or uncut glow above all, falls on both sides of the wall.
	// The baked cut is measured from source_turf, so the sprite stands there too: centred a tile away, the cut would land a tile off.
	G.set_pixel_x(-offset)
	G.set_pixel_y(-offset)
	G.set_color(light_color)
	G.set_plane(client_glow_plane())
	client_glow_note_moving()
	G.set_alpha(clamp(round(255 * min(light_power, 1) * (range <= CLIENT_GLOW_SMALL_RANGE ? CLIENT_GLOW_SMALL_SCALE : 1)), 0, 255)) // a device's small glow reads far stronger than the corner lighting's at the same power
	if(G.loc != source_turf)
		G.abstract_move(source_turf)
	client_glow_mask_apply(CEILING(range, 1), offset) // the shadow mask (client_shadow.dm)
	applied = TRUE
	client_glow_holders_consider(src) // viewers holding an off-screen copy follow (client_glow_holder.dm)
	client_flat_lights_refresh(src, was_at, was_range) // big sprites near it, or near where it was, take the new light of their turf (client_flat_light.dm)

/// A carried light, a mob's own light and anything that has changed turf since it first glowed draw uncut: their shape changes as they go, and
/// a bake per step would be a storm. The visibility cut on the glow plane still removes what they spill on tiles this client cannot see.
/datum/light_source/proc/client_glow_note_moving()
	if(glow_reach_origin && glow_reach_origin != source_turf)
		glow_has_moved = TRUE
		if(!glow_settle_at)
			glow_settle_at = client_glow_settle_key()
			after(src, CLIENT_GLOW_SETTLE_TIME, PROC_REF(client_glow_settle_check), clock = CLOCK_WORLD)
	glow_plain = glow_has_moved || top_atom != source_atom || ismob(source_atom)

/datum/light_source/proc/client_glow_settle_key()
	return source_turf ? "[source_turf.x]:[source_turf.y]:[source_turf.z]" : "none"

/// A light that has stood on one turf for a whole settle period goes back to its baked cut; one still moving checks again.
/datum/light_source/proc/client_glow_settle_check()
	var/now = client_glow_settle_key()
	if(now != glow_settle_at)
		glow_settle_at = now
		after(src, CLIENT_GLOW_SETTLE_TIME, PROC_REF(client_glow_settle_check), clock = CLOCK_WORLD)
		return
	glow_settle_at = null
	glow_has_moved = FALSE
	if(!glow)
		return
	client_glow_note_moving()
	if(client_glow_trace_line())
		log_world("client glow: light at [now] settled, [glow_plain ? "still carried, stays plain" : "back to its baked cut"]")
	client_glow_holders_consider(src)

/// This light stops glowing (it went off, moved into nullspace or left client lighting).
/datum/light_source/proc/client_glow_clear()
	var/turf/was_at = glow_reach_origin
	var/was_range = glow_mask_range
	if(glow_holder_key)
		GLOB.client_glow_dirty_lights -= glow_holder_key
	client_glow_holders_drop(src)
	client_glow_mask_clear()
	if(glow)
		var/obj/effect/overlay/client_glow/G = glow
		rel_clear(src, nameof(glow))
		spent(G)
	client_flat_lights_refresh(src, was_at, was_range)

/// Switches client lighting on or off live: every lighting object goes (on) or comes back (off), and every light redraws.
/// One pass with no yield (an admin switch): a yield would leave half the map in each mode, and the test clock never resumes it.
/proc/client_lighting_set(on)
	on = !!on
	if(GLOB.client_lighting == on)
		return
	if(!on && GLOB.client_lighting_compare)
		client_lighting_compare_set(FALSE) // compare mode runs on client lighting
	GLOB.client_lighting = on
	client_glow_holders_switched(on)
	client_flat_lights_switched(on)
	log_world("client lighting: [on ? "on" : "off"]")
	client_glow_screens_sync() // the black base on every client's lighting plane (client_lighting_screen.dm)
	lighting_smooth_apply() // the smoothing mode follows the engine on or off
	if(!SSlighting.is_initialized())
		return
	client_glow_whites_set(on) // turfs outside dynamic lighting stay bright over the base
	var/list/all_turfs = block(locate(1, 1, 1), locate(world.maxx, world.maxy, world.maxz))
	if(on)
		for(var/turf/T as anything in all_turfs)
			if(T.lighting_object)
				T.lighting_clear_overlay()
			if(T.has_dynamic_lighting())
				T.set_luminosity(1, TRUE) // BYOND shows every turf; the lighting plane does the darkness
	for(var/datum/light_source/L)
		// A spent source not yet destroyed must not be queued again: light_step() steps back over a deleted queue entry,
		// so a requeued one would spin it forever.
		if(QDELETED(L))
			continue
		if(on)
			L.remove_lum()
		else
			L.client_glow_clear()
		L.force_update()
	if(!on)
		for(var/turf/T as anything in all_turfs)
			T.lighting_build_overlay() // create_all_lighting_objects() without its yields

ADMIN_VERB(toggle_client_lighting, R_DEBUG|R_SERVER, "Toggle Client Lighting", "Switch every light between client-rendered glows and the DM lighting, live.", ADMIN_CATEGORY_DEBUG_GAME)
	client_lighting_set(!GLOB.client_lighting)
	message_admins("[key_name_admin(user)] turned client lighting [GLOB.client_lighting ? "on" : "off"].")
