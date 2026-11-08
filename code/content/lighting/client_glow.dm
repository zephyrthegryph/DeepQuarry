// Client-rendered lighting, piece 1: glows. With the mode on, every light source is one soft gradient sprite on the lighting
// plane, blended additively over its black backdrop; the plane master multiplies the result over the world, so the client's
// GPU does the blending and the server only sends where each glow sits, its colour, size and strength. The DM lighting
// corners and turf underlays are not touched in this mode: no lighting object is made, and a light skips its corner work.
// Off by default: until the shadow masks land a glow shines through walls (later pieces: masks, gameplay light, culling).

/// TRUE while lights draw as client glows instead of the DM corner and underlay lighting (client_lighting_set()).
GLOBAL_VAR_INIT(client_lighting, FALSE)

/// One light source's glow.
/obj/effect/overlay/client_glow
	name = ""
	icon = 'icons/effects/light_overlays/light_32.dmi'
	icon_state = "light"
	plane = PLANE_LIGHTING
	layer = BACKGROUND_LAYER + 22 // above the lighting plane's black backdrop (BACKGROUND_LAYER + 21)
	blend_mode = BLEND_ADD
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM | KEEP_APART
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	anchored = TRUE
	vis_flags = NONE

/datum/light_source
	/// The glow this light shows while client lighting is on; null otherwise.
	var/obj/effect/overlay/client_glow/glow

CAPABILITIES_PART(/datum/light_source, light_source_client_glow)
	owns_one(nameof(glow), /obj/effect/overlay/client_glow)

/// Places, sizes and tints this light's glow (client lighting): the work update_corners() does in this mode.
/datum/light_source/proc/client_glow_apply()
	if(!glow)
		rel_set(src, nameof(glow), new /obj/effect/overlay/client_glow(null))
	var/obj/effect/overlay/client_glow/G = glow
	var/range = clamp(CEILING(light_range, 0.5), 1, 6)
	var/pixel_bounds = ((range - 1) * 64) + 32
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
	G.set_icon(glow_icons["[pixel_bounds]"])
	var/offset = (pixel_bounds - 32) * 0.5
	G.set_pixel_x(-offset + (pixel_turf ? (pixel_turf.x - source_turf.x) * WORLD_ICON_SIZE : 0))
	G.set_pixel_y(-offset + (pixel_turf ? (pixel_turf.y - source_turf.y) * WORLD_ICON_SIZE : 0))
	G.set_color(light_color)
	G.set_alpha(clamp(round(255 * min(light_power, 1)), 0, 255))
	if(G.loc != source_turf)
		G.abstract_move(source_turf)
	client_glow_mask_apply(CEILING(range, 1), G.icon, offset) // the shadow mask (client_shadow.dm)
	applied = TRUE

/// This light stops glowing (it went off, moved into nullspace or left client lighting).
/datum/light_source/proc/client_glow_clear()
	client_glow_mask_clear()
	if(glow)
		var/obj/effect/overlay/client_glow/G = glow
		rel_clear(src, nameof(glow))
		spent(G)

/// Switches client lighting on or off live: every lighting object goes (on) or comes back (off), and every light redraws.
/// One pass with no yield (an admin switch): a yield would leave half the map in each mode, and the test clock never resumes it.
/proc/client_lighting_set(on)
	on = !!on
	if(GLOB.client_lighting == on)
		return
	GLOB.client_lighting = on
	log_world("client lighting: [on ? "on" : "off"]")
	if(!SSlighting.is_initialized())
		return
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
