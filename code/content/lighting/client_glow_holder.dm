// Client lighting, piece 3: the per-client glow holder. BYOND sends a glow only to clients that see the light's own turf, so a
// light just off screen would not spill onto the screen and its glow would pop in as the player walks. Each client holds a copy
// of such a glow as its own images (client.images), anchored on a turf it is sure to see and offset to the light's true place:
// an image on a map turf scrolls and glides with the world, so stepping changes nothing.
//
// The geometry is per eye chunk (CLIENT_GLOW_CHUNK turfs a side), so the images change only when the eye crosses a chunk:
//   - the safe box: the turfs seen from every eye position in the chunk (the views' intersection). A light standing in it is
//     always on screen and keeps its normal glow; nothing is copied.
//   - the reach box: the turfs seen from some eye position in the chunk (the views' union). A light outside the safe box whose
//     reach overlaps it is held: a glow image on the safe-box turf nearest it along the line from the chunk's middle, a mask
//     image of its own (below), and an override image that hides the real glow from this client, so a light that steps on
//     screen inside the chunk is never drawn twice.
// The mask: the glow's alpha filter reads its shadow mask as a render target, and a render target renders only when its object
// is drawn for that client. The real mask stands on the light's turf, which this client may not see, so each held light gets a
// mask image of its own, with a render target unique to this holder and light, which the glow image's filter names.
//
// Events only: the eye crossing a chunk or changing view (interest_eye_update()), a light glowing, moving or changing
// (client_glow_apply()), its mask rebuilding (client_glow_mask_apply()), going out (client_glow_clear()), client lighting
// switching off and the client leaving.

/// Holder bookkeeping (benchmarks, tests): images made, images changed in place, images dropped, eye-chunk recomputes.
GLOBAL_VAR_INIT(client_glow_holder_made, 0)
GLOBAL_VAR_INIT(client_glow_holder_updated, 0)
GLOBAL_VAR_INIT(client_glow_holder_dropped, 0)
GLOBAL_VAR_INIT(client_glow_holder_recomputes, 0)

/// One viewer's held glows. A client owns one (client.glow_holder); tests and benchmarks make one with no client.
/datum/client_glow_holder
	/// The client shown the images (null: a test or benchmark viewer, its images are only kept here).
	var/client/client
	/// The eye's chunk signature "z:cx:cy:hx:hy"; equal text, nothing to do.
	var/sig
	var/z = 0
	/// The safe box and the reach box, inclusive turf coordinates: list(x0, y0, x1, y1).
	var/list/safe
	var/list/reach
	/// light source glow_holder_key -> list(glow image, mask image, hide image). Lazy.
	var/list/held

/client
	/// This client's held off-screen glows (client lighting only).
	var/datum/client_glow_holder/glow_holder

CAPABILITIES_PART(/client, client_glow_holder)
	owns_one(nameof(glow_holder), /datum/client_glow_holder)

/datum/light_source
	/// This light's key in the holders' held lists, taken once while it is alive (a dying datum's handle cannot be looked up again).
	var/glow_holder_key

SCHEMA(/datum/light_source, glow_holder_key, schema_text())

/datum/light_source/proc/glow_holder_key()
	if(!glow_holder_key)
		glow_holder_key = handle_text(handle_of(src))
	return glow_holder_key

/// Every live holder (REGISTRY_CLIENT_GLOW_HOLDERS): a light event walks them, one per connected client plus test and benchmark viewers.
REGISTRY_MEMBERSHIP(/datum/client_glow_holder, REGISTRY_CLIENT_GLOW_HOLDERS)

/client/interest_eye_moved(turf/at_eye)
	..()
	client_glow_holder_eye(src, at_eye) // held off-screen glows follow the eye's glow chunk
	client_glow_screen_sync(src) // the lighting screen objects (client_lighting_compare.dm); one comparison when in step

/client/interest_eye_left()
	..()
	client_glow_holder_gone(src)

/datum/client_glow_holder/New()
	..()
	join_registries()

/datum/client_glow_holder/on_destroy(force)
	drop_all()
	client = null
	..()

/// Half the view in turfs on each axis: list(hx, hy). `view` is a number or "WxH".
/proc/client_glow_view_halves(view)
	if(istext(view))
		var/list/size = splittext(view, "x")
		return list(round(text2num(size[1]) / 2), round(text2num(size[length(size)]) / 2))
	var/n = isnum(view) ? view : world.view
	if(istext(n))
		return client_glow_view_halves(n)
	return list(n, n)

/// The client's eye moved or its view changed (interest_eye_update()): its holder follows when the eye's chunk did.
/proc/client_glow_holder_eye(client/C, turf/at_eye)
	if(!GLOB.client_lighting || !C || QDELETED(C))
		return
	if(!C.glow_holder)
		if(!at_eye)
			return
		var/datum/client_glow_holder/H = new
		H.client = C
		rel_set(C, nameof(C.glow_holder), H)
	var/list/halves = client_glow_view_halves(C.view)
	C.glow_holder.view_at(at_eye, halves[1], halves[2])

/// The client left: its held glows go.
/proc/client_glow_holder_gone(client/C)
	if(!C?.glow_holder)
		return
	var/datum/client_glow_holder/H = C.glow_holder
	rel_clear(C, nameof(C.glow_holder))
	spent(H)

/// The viewer sees from `eye` with view halves (hx, hy). Recomputes only when the eye's chunk or the view changed.
/datum/client_glow_holder/proc/view_at(turf/eye, hx, hy)
	if(!eye)
		sig = null
		drop_all()
		return
	var/cx = round((eye.x - 1) / CLIENT_GLOW_CHUNK)
	var/cy = round((eye.y - 1) / CLIENT_GLOW_CHUNK)
	var/new_sig = "[eye.z]:[cx]:[cy]:[hx]:[hy]"
	if(new_sig == sig)
		return
	sig = new_sig
	z = eye.z
	GLOB.client_glow_holder_recomputes++
	var/ex0 = cx * CLIENT_GLOW_CHUNK + 1
	var/ey0 = cy * CLIENT_GLOW_CHUNK + 1
	var/ex1 = ex0 + CLIENT_GLOW_CHUNK - 1
	var/ey1 = ey0 + CLIENT_GLOW_CHUNK - 1
	reach = list(ex0 - hx, ey0 - hy, ex1 + hx, ey1 + hy)
	var/sx0 = ex1 - hx
	var/sx1 = ex0 + hx
	var/sy0 = ey1 - hy
	var/sy1 = ey0 + hy
	if(sx0 > sx1) // a view narrower than a chunk: no turf is seen from all of it; the chunk's middle stands in
		sx0 = sx1 = round((ex0 + ex1) / 2)
	if(sy0 > sy1)
		sy0 = sy1 = round((ey0 + ey1) / 2)
	safe = list(max(1, sx0), max(1, sy0), min(world.maxx, sx1), min(world.maxy, sy1))
	// Candidates: lights indexed in the glow chunks a reach could overlap the reach box from.
	var/list/keep = list()
	var/c0x = round((reach[1] - CLIENT_GLOW_MAX_RANGE - 1) / CLIENT_GLOW_CHUNK)
	var/c1x = round((reach[3] + CLIENT_GLOW_MAX_RANGE - 1) / CLIENT_GLOW_CHUNK)
	var/c0y = round((reach[2] - CLIENT_GLOW_MAX_RANGE - 1) / CLIENT_GLOW_CHUNK)
	var/c1y = round((reach[4] + CLIENT_GLOW_MAX_RANGE - 1) / CLIENT_GLOW_CHUNK)
	for(var/gx in c0x to c1x)
		for(var/gy in c0y to c1y)
			for(var/datum/light_source/L as anything in GLOB.client_glow_chunks["[z],[gx],[gy]"])
				if(consider(L))
					keep[L.glow_holder_key()] = TRUE
	for(var/h in LAZYCOPY(held))
		if(!keep[h])
			drop_handle(h)
	log_world("client glow holder: [client?.ckey] entered chunk [new_sig], holding [LAZYLEN(held)] glow(s), [GLOB.client_glow_holder_made] made and [GLOB.client_glow_holder_dropped] dropped so far")

/// Shows, updates or drops this viewer's copy of light `L`. Returns TRUE while it is held.
/datum/client_glow_holder/proc/consider(datum/light_source/L)
	if(!sig || QDELETED(L) || !L.glow || !L.glow_mask_key)
		drop(L)
		return FALSE
	var/turf/S = L.source_turf
	if(!S || S.z != z)
		drop(L)
		return FALSE
	if(S.x >= safe[1] && S.x <= safe[3] && S.y >= safe[2] && S.y <= safe[4])
		drop(L) // always on screen from this chunk: the normal glow shows
		return FALSE
	var/r = CEILING(L.light_range, 1)
	if(S.x + r < reach[1] || S.x - r > reach[3] || S.y + r < reach[2] || S.y - r > reach[4])
		drop(L) // its reach never comes on screen from this chunk
		return FALSE
	var/turf/A = anchor_for(S)
	if(!A)
		drop(L)
		return FALSE
	var/obj/effect/overlay/client_glow/G = L.glow
	var/h = L.glow_holder_key()
	var/list/entry = LAZYACCESS(held, h)
	var/image/glow_image
	var/image/mask_image
	if(!entry)
		var/mask_name = "*cglow_mask_[handle_text(handle_of(L))]_[handle_text(handle_of(src))]"
		mask_image = image(G.icon, null, G.icon_state) // the glow's own state, so the mask is the glow's size and the alpha filter lines them up
		mask_image.plane = PLANE_LIGHTING
		mask_image.appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM | KEEP_TOGETHER
		mask_image.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
		mask_image.color = list(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0) // the base only fixes the size
		mask_image.render_target = mask_name
		mask_image.filters = filter(type = "blur", size = CLIENT_GLOW_MASK_BLUR)
		glow_image = image(G.icon, null, G.icon_state)
		glow_image.layer = G.layer
		glow_image.blend_mode = BLEND_ADD
		glow_image.appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM | KEEP_APART
		glow_image.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
		glow_image.filters = filter(type = "alpha", render_source = mask_name)
		var/image/hide_image = image(null) // overrides the real glow for this viewer: never drawn twice
		hide_image.override = TRUE
		image_anchor(hide_image, G)
		image_anchor(glow_image, A)
		image_anchor(mask_image, A)
		entry = list(glow_image, mask_image, hide_image)
		LAZYSET(held, h, entry)
		client_images_add(client, entry)
		GLOB.client_glow_holder_made++
	else
		glow_image = entry[1]
		mask_image = entry[2]
		GLOB.client_glow_holder_updated++
	var/px = (S.x - A.x) * WORLD_ICON_SIZE + G.pixel_x
	var/py = (S.y - A.y) * WORLD_ICON_SIZE + G.pixel_y
	if(glow_image.loc != A) // re-anchored: shown again so the client image index follows the new turf
		client_images_remove(client, entry)
		image_anchor(glow_image, A)
		image_anchor(mask_image, A)
		client_images_add(client, entry)
	glow_image.icon = G.icon
	glow_image.plane = G.plane
	mask_image.plane = G.plane
	glow_image.color = G.color
	glow_image.alpha = G.alpha
	glow_image.pixel_x = px
	glow_image.pixel_y = py
	mask_image.icon = G.icon
	mask_image.pixel_x = px
	mask_image.pixel_y = py
	mask_image.overlays = CACHED_FAST(client_glow_masks, L.glow_mask_key)
	return TRUE

/// The safe-box turf nearest `S` along the line from the safe box's middle to it.
/datum/client_glow_holder/proc/anchor_for(turf/S)
	var/mx = (safe[1] + safe[3]) / 2
	var/my = (safe[2] + safe[4]) / 2
	var/dx = S.x - mx
	var/dy = S.y - my
	var/t = 1
	if(dx > 0)
		t = min(t, (safe[3] - mx) / dx)
	else if(dx < 0)
		t = min(t, (safe[1] - mx) / dx)
	if(dy > 0)
		t = min(t, (safe[4] - my) / dy)
	else if(dy < 0)
		t = min(t, (safe[2] - my) / dy)
	var/ax = clamp(round(mx + dx * t + 0.5), safe[1], safe[3])
	var/ay = clamp(round(my + dy * t + 0.5), safe[2], safe[4])
	return locate(ax, ay, z)

/// This viewer stops holding light `L`.
/datum/client_glow_holder/proc/drop(datum/light_source/L)
	if(L.glow_holder_key)
		drop_handle(L.glow_holder_key)

/datum/client_glow_holder/proc/drop_handle(h)
	var/list/entry = LAZYACCESS(held, h)
	if(!entry)
		return
	LAZYREMOVE(held, h)
	client_images_remove(client, entry)
	GLOB.client_glow_holder_dropped++

/datum/client_glow_holder/proc/drop_all()
	for(var/h in LAZYCOPY(held))
		drop_handle(h)

/// This viewer's copy of light `L` (tests): list(glow image, mask image, hide image), or null.
/datum/client_glow_holder/proc/entry_of(datum/light_source/L)
	return L.glow_holder_key && LAZYACCESS(held, L.glow_holder_key)

/// Every image this viewer holds (tests).
/datum/client_glow_holder/proc/images()
	. = list()
	for(var/h in held)
		. += held[h]

/// Light `L` glowed, moved, changed or rebuilt its mask: every viewer updates its copy.
/proc/client_glow_holders_consider(datum/light_source/L)
	for(var/datum/client_glow_holder/H as anything in REGISTRY_MEMBERS(REGISTRY_CLIENT_GLOW_HOLDERS))
		H.consider(L)

/// Light `L` stopped glowing: every viewer drops its copy.
/proc/client_glow_holders_drop(datum/light_source/L)
	for(var/datum/client_glow_holder/H as anything in REGISTRY_MEMBERS(REGISTRY_CLIENT_GLOW_HOLDERS))
		H.drop(L)

/// Client lighting switched: off drops every held glow; on recomputes every client's holder from its eye.
/proc/client_glow_holders_switched(on)
	for(var/datum/client_glow_holder/H as anything in REGISTRY_COPY(REGISTRY_CLIENT_GLOW_HOLDERS))
		H.sig = null
		H.drop_all()
	if(on)
		for(var/client/C as anything in GLOB.clients)
			client_glow_holder_eye(C, get_turf(C.eye || C.mob))

/// (Tests, benchmarks.) A viewer eye about ten turfs from `L` on x, in L's row: from that eye's chunk the light stands off the safe box but its reach
/// comes on screen.
/proc/client_glow_test_eye(turf/L)
	var/x = L.x > 20 ? L.x - 10 : L.x + 10
	return locate(x, L.y, L.z)
