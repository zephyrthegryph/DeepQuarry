// Client lighting, piece 2: shadow masks. Each glow is cut by an alpha mask of the turfs its light reaches (the world opacity
// layer's sight from the light's turf, code/domains/verdigris/sight/), so a glow no longer shines through walls. The mask is
// a hidden render target in the glow's vis_contents: one white tile per reached turf, its overlay list cached by shape, so
// lights with the same reach share one appearance. A mask is rebuilt only when its light is redrawn (it moved or changed) or
// when opacity changes inside its reach (a door, a wall built), found through a per-chunk index of glowing lights.


/// Cumulative mask rebuilds and reach-triggered redraws (benchmarks, the door test).
GLOBAL_VAR_INIT(client_glow_mask_builds, 0)
GLOBAL_VAR_INIT(client_glow_reconsiders, 0)
/// "z,cx,cy" -> lights glowing from that chunk (client lighting only).
GLOBAL_LIST_EMPTY(client_glow_chunks)

/// A light's shadow mask: drawn only as its glow's alpha filter source.
/obj/effect/overlay/client_glow_mask
	name = ""
	icon = null
	plane = PLANE_LIGHTING
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM | KEEP_TOGETHER
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	anchored = TRUE
	vis_flags = VIS_INHERIT_ID

/datum/light_source
	/// The mask cutting this light's glow; the reach key it last drew ("range|offsets").
	var/obj/effect/overlay/client_glow_mask/glow_mask
	var/glow_mask_key
	/// "dx,dy" -> TRUE for every turf the mask lets the glow onto (tests, debugging).
	var/list/glow_reach
	/// The chunk key this light is indexed under while it glows.
	var/glow_chunk

CAPABILITIES_PART(/datum/light_source, light_source_client_shadow)
	owns_one(nameof(glow_mask), /obj/effect/overlay/client_glow_mask)

/proc/client_glow_chunk_key(z, x, y)
	return "[z],[round((x - 1) / CLIENT_GLOW_CHUNK)],[round((y - 1) / CLIENT_GLOW_CHUNK)]"

/// The overlays of a mask of this shape (key "margin|dx,dy,dx,dy,..."): one opaque white tile (the lighting icon's
/// "transparent" state) per reached offset, placed in the glow sprite's own frame (`margin` = how far the glow reaches past
/// the light's tile). Built once per shape (client_glow_masks).
/proc/client_glow_mask_build(key)
	var/list/parts = splittext(key, "|")
	var/margin = text2num(parts[1])
	var/list/offsets = length(parts) > 1 && length(parts[2]) ? splittext(parts[2], ",") : list()
	. = list()
	for(var/i = 1, i < length(offsets), i += 2)
		var/mutable_appearance/tile = mutable_appearance(LIGHTING_ICON, "transparent")
		tile.appearance_flags = RESET_COLOR | RESET_ALPHA
		tile.pixel_x = text2num(offsets[i]) * WORLD_ICON_SIZE + margin
		tile.pixel_y = text2num(offsets[i + 1]) * WORLD_ICON_SIZE + margin
		. += tile

DECLARE_SHARED_CACHE(client_glow_masks, GLOBAL_PROC_REF(client_glow_mask_build), SC_NEVER)

/// Rebuilds this light's mask from its reach (client_glow_apply()). `glow_icon` and `margin` are the glow sprite's: the mask
/// is the same size (its base is that icon made fully transparent), so the alpha filter lines the two up.
/datum/light_source/proc/client_glow_mask_apply(range, glow_icon, margin)
	var/obj/effect/overlay/client_glow/G = glow
	var/list/offsets = list()
	var/list/reach = list()
	for(var/turf/T as anything in sight_view_turfs(source_turf, range))
		offsets += T.x - source_turf.x
		offsets += T.y - source_turf.y
		reach["[T.x - source_turf.x],[T.y - source_turf.y]"] = TRUE
	glow_reach = reach
	var/key = "[margin]|[jointext(offsets, ",")]"
	if(key == glow_mask_key && glow_mask)
		return
	GLOB.client_glow_mask_builds++
	if(!glow_mask)
		rel_set(src, nameof(glow_mask), new /obj/effect/overlay/client_glow_mask(null))
		var/obj/effect/overlay/client_glow_mask/M = glow_mask
		M.render_target = "*client_glow_mask_[handle_of(src)]"
		M.set_color(list(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0)) // the base only fixes the size
		// Soft shadow edges: the tile grid is blurred before it cuts the glow, so a shadow fades over a few pixels instead of
		// stair-stepping. A reached wall tile stays in the mask whole, so its face is lit; only its outer rim softens.
		M.add_filter("client_shadow_soft", 1, list(type = "blur", size = CLIENT_GLOW_MASK_BLUR))
		vis_add(G, M)
		G.add_filter("client_shadow", 1, list(type = "alpha", render_source = M.render_target))
	glow_mask_key = key
	var/obj/effect/overlay/client_glow_mask/M = glow_mask
	M.set_icon(glow_icon)
	M.overlays = CACHED_FAST(client_glow_masks, key)
	client_glow_index(TRUE)

/// Keeps this light in (or out of) the chunk index opacity changes look up.
/datum/light_source/proc/client_glow_index(on)
	var/key = on && source_turf ? client_glow_chunk_key(source_turf.z, source_turf.x, source_turf.y) : null
	if(key == glow_chunk)
		return
	if(glow_chunk)
		var/list/old = GLOB.client_glow_chunks[glow_chunk]
		old -= src
		if(!length(old))
			GLOB.client_glow_chunks -= glow_chunk
	glow_chunk = key
	if(key)
		var/list/members = GLOB.client_glow_chunks[key]
		if(!members)
			members = GLOB.client_glow_chunks[key] = list()
		members += src

/// The mask goes with the glow.
/datum/light_source/proc/client_glow_mask_clear()
	client_glow_index(FALSE)
	glow_mask_key = null
	glow_reach = null
	if(glow_mask)
		var/obj/effect/overlay/client_glow_mask/M = glow_mask
		rel_clear(src, nameof(glow_mask))
		spent(M)

/// Opacity changed on `T` (reconsider_lights()): every glowing light whose reach covers it redraws its mask.
/proc/client_glow_reconsider(turf/T)
	var/cx = round((T.x - 1) / CLIENT_GLOW_CHUNK)
	var/cy = round((T.y - 1) / CLIENT_GLOW_CHUNK)
	var/span = CEILING(CLIENT_GLOW_MAX_RANGE / CLIENT_GLOW_CHUNK, 1)
	for(var/dx = -span, dx <= span, dx++)
		for(var/dy = -span, dy <= span, dy++)
			for(var/datum/light_source/L as anything in GLOB.client_glow_chunks["[T.z],[cx + dx],[cy + dy]"])
				if(QDELETED(L))
					continue
				var/turf/S = L.source_turf
				if(!S || max(abs(S.x - T.x), abs(S.y - T.y)) > CEILING(L.light_range, 1))
					continue
				GLOB.client_glow_reconsiders++
				L.glow_mask_key = null
				L.force_update()
