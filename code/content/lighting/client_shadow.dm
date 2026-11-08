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
	/// The reach range and glow margin the mask was last built for (client_glow_mask_refresh()).
	var/glow_mask_range = 0
	var/glow_mask_margin = 0
	/// "dx,dy" -> TRUE for every turf the mask lets the glow onto (tests, debugging).
	var/list/glow_reach
	/// The turf glow_reach is measured from.
	var/turf/glow_reach_origin
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
	// The first child fixes the render target's size: the glow sprite, zeroed by its own colour. The colour must stay on this
	// child: the mask is KEEP_TOGETHER, so a colour on the mask itself applies to the whole group after it is drawn, whatever
	// RESET_COLOR the tiles carry, and a zero matrix there empties the mask and cuts every glow to nothing.
	var/mutable_appearance/sizer = mutable_appearance(client_glow_icon(margin * 2 + WORLD_ICON_SIZE), "light")
	sizer.color = list(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0)
	. = list(sizer)
	for(var/i = 1, i < length(offsets), i += 2)
		var/mutable_appearance/tile = mutable_appearance(LIGHTING_ICON, "transparent")
		tile.appearance_flags = RESET_COLOR | RESET_ALPHA
		tile.pixel_x = text2num(offsets[i]) * WORLD_ICON_SIZE + margin
		tile.pixel_y = text2num(offsets[i + 1]) * WORLD_ICON_SIZE + margin
		. += tile

DECLARE_SHARED_CACHE(client_glow_masks, GLOBAL_PROC_REF(client_glow_mask_build), SC_NEVER)

/// Recomputes this light's reach after an opacity change and rebuilds the mask only if the reach changed.
/datum/light_source/proc/client_glow_mask_refresh()
	if(!glow || !glow_mask || !source_turf)
		return
	var/obj/effect/overlay/client_glow/G = glow
	if(client_glow_mask_apply(glow_mask_range, glow_mask_margin))
		client_glow_holders_consider(src) // the held copies take the new mask

/// Rebuilds this light's mask from its reach (client_glow_apply()). `margin` is the glow sprite's: the mask
/// is the same size (client_glow_mask_build() gives it a transparent copy of that icon), so the alpha filter lines the two up. TRUE when it rebuilt.
/datum/light_source/proc/client_glow_mask_apply(range, margin)
	glow_mask_range = range
	glow_mask_margin = margin
	var/obj/effect/overlay/client_glow/G = glow
	// The reach first, as a shape key: an opacity change that leaves this light's reach as it was (most of them) stops here.
	var/list/seen = sight_view_turfs(source_turf, range)
	var/list/offsets = new /list(length(seen) * 2)
	var/i = 0
	var/sx = source_turf.x
	var/sy = source_turf.y
	for(var/turf/T as anything in seen)
		offsets[++i] = T.x - sx
		offsets[++i] = T.y - sy
	var/key = "[margin]|[jointext(offsets, ",")]"
	if(key == glow_mask_key && glow_mask && glow_reach_origin == source_turf)
		return
	// Lum watches (watched(T, WATCH_LUM)) on turfs this light lit or now lights hear about it.
	var/watching = SSwatched.client_lum_watching()
	var/list/watched_turfs = watching ? client_glow_watched_reach() : list()
	var/list/reach = list()
	for(var/turf/T as anything in seen)
		reach["[T.x - sx],[T.y - sy]"] = TRUE
		if(watching && SSwatched.client_lum_watched(T))
			watched_turfs |= T
	glow_reach = reach
	glow_reach_origin = source_turf // ALLOW(ownership): lighting engine turf cache, rewritten on every mask rebuild like source_turf; a turf relation index entry per rebuild would grow without bound
	for(var/turf/W as anything in watched_turfs)
		SSwatched.lum_changed(W)
	GLOB.client_glow_mask_builds++
	if(!glow_mask)
		rel_set(src, nameof(glow_mask), new /obj/effect/overlay/client_glow_mask(null))
		var/obj/effect/overlay/client_glow_mask/M = glow_mask
		M.render_target = "*client_glow_mask_[handle_text(handle_of(src))]" // whole number: "[h]" rounds past 1e6 and lights would share a mask
		// Soft shadow edges: the tile grid is blurred before it cuts the glow, so a shadow fades over a few pixels instead of
		// stair-stepping. A reached wall tile stays in the mask whole, so its face is lit; only its outer rim softens.
		M.add_filter("client_shadow_soft", 1, list(type = "blur", size = CLIENT_GLOW_MASK_BLUR))
		vis_add(G, M)
		G.add_filter("client_shadow", 1, list(type = "alpha", render_source = M.render_target))
	glow_mask_key = key
	var/obj/effect/overlay/client_glow_mask/M = glow_mask
	M.overlays = CACHED_FAST(client_glow_masks, key)
	client_glow_index(TRUE)
	return TRUE

/// The watched turfs (lum bands) in this light's last reach.
/datum/light_source/proc/client_glow_watched_reach()
	. = list()
	var/turf/O = glow_reach_origin
	if(!O || !glow_reach)
		return
	for(var/key in glow_reach)
		var/list/xy = splittext(key, ",")
		var/turf/T = locate(O.x + text2num(xy[1]), O.y + text2num(xy[2]), O.z)
		if(T && SSwatched.client_lum_watched(T))
			. += T

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
	for(var/turf/W as anything in client_glow_watched_reach())
		SSwatched.lum_changed(W)
	glow_mask_key = null
	glow_reach = null
	glow_reach_origin = null // ALLOW(ownership): lighting engine turf cache cleared with the mask, like source_turf
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
				L.client_glow_mask_refresh() // only the mask: the glow's place, size and tint did not change
