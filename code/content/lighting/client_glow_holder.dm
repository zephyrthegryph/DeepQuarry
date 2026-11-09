// Client lighting, piece 3: the per-client glow holder. BYOND sends a glow only to clients that see the light's own turf, so a
// light just off screen would not spill onto the screen and its glow would pop in as the player walks. Each client holds a copy
// of every glow in reach as its own images (client.images), recomputed only when the eye crosses a chunk (CLIENT_GLOW_CHUNK turfs a side).
//   - where it stands: on the light's own turf when the eye saw that turf at the crossing, else on the reached turf the eye saw that is
//     nearest the eye, offset to the light's place. Playtesting showed an image drawn far from where it stands is culled, so the offset stays within the light's range.
//   - the reach box: the turfs seen from some eye position in the chunk. Every light whose reach overlaps it is held.
//   - a held light is a glow image, baked to its reach shape once that is ready (client_shadow.dm), and an override image that hides
//     the real glow from this client, so it is never drawn twice.
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
	/// The reach box, inclusive turf coordinates: list(x0, y0, x1, y1).
	var/list/reach
	/// "x:y" -> TRUE for the turfs the eye saw at its last chunk crossing: decides where a held glow stands.
	var/list/seen_keys
	var/eye_x = 0
	var/eye_y = 0
	/// TRUE once this viewer's first hold has been logged (the load-in timeline).
	var/first_hold_logged = FALSE
	/// TRUE: a ghost still seeing darkness: its held copies carry no shadow mask (it sees through walls, so masks buy it nothing).
	var/unmasked = FALSE
	/// TRUE: this viewer does not see darkness (a ghost with darkness off, darkvision): lights draw nothing for it, so each is only hidden.
	var/unlit = FALSE
	/// light source glow_holder_key -> list(glow image, hide image), or list(hide image) while unlit. Lazy.
	var/list/held
	/// light source glow_holder_key -> the mask shape its glow image wants. Lazy.
	var/list/held_shape
	/// light source glow_holder_key -> the mask shape its glow image is cut by now. Lazy.
	var/list/cut_shape
	/// Baked shape -> its preload image, while this client is being sent the PNG. Lazy.
	var/list/delivering
	/// Baked shape -> TRUE once this client has had time to receive its PNG. Lazy.
	var/list/delivered

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
	var/mob/viewer = client?.mob
	var/mob/observer/dead/ghost = istype(viewer, /mob/observer/dead) ? viewer : null
	var/now_unlit = viewer ? (!viewer.seedarkness || (ghost && !ghost.lighting_alpha)) : FALSE
	var/now_unmasked = !!ghost && !now_unlit
	var/new_sig = "[eye.z]:[cx]:[cy]:[hx]:[hy]:[now_unlit]:[now_unmasked]"
	if(new_sig == sig)
		return
	if(now_unlit != unlit || now_unmasked != unmasked)
		drop_all() // the entries have the other shape
		unlit = now_unlit
		unmasked = now_unmasked
	sig = new_sig
	z = eye.z
	GLOB.client_glow_holder_recomputes++
	var/ex0 = cx * CLIENT_GLOW_CHUNK + 1
	var/ey0 = cy * CLIENT_GLOW_CHUNK + 1
	var/ex1 = ex0 + CLIENT_GLOW_CHUNK - 1
	var/ey1 = ey0 + CLIENT_GLOW_CHUNK - 1
	reach = list(ex0 - hx, ey0 - hy, ex1 + hx, ey1 + hy)
	eye_x = eye.x
	eye_y = eye.y
	seen_keys = list()
	if(!unlit)
		for(var/turf/T as anything in sight_view_turfs(eye, max(hx, hy)))
			seen_keys["[T.x]:[T.y]"] = TRUE
	// Candidates: lights indexed in the glow chunks a reach could overlap the reach box from.
	var/list/keep = list()
	// One chunk further out than a reach can matter: those lights are not held, but their shapes are readied for the next crossing.
	var/c0x = round((reach[1] - CLIENT_GLOW_MAX_RANGE - 1) / CLIENT_GLOW_CHUNK) - 1
	var/c1x = round((reach[3] + CLIENT_GLOW_MAX_RANGE - 1) / CLIENT_GLOW_CHUNK) + 1
	var/c0y = round((reach[2] - CLIENT_GLOW_MAX_RANGE - 1) / CLIENT_GLOW_CHUNK) - 1
	var/c1y = round((reach[4] + CLIENT_GLOW_MAX_RANGE - 1) / CLIENT_GLOW_CHUNK) + 1
	for(var/gx in c0x to c1x)
		for(var/gy in c0y to c1y)
			for(var/datum/light_source/L as anything in GLOB.client_glow_chunks["[z],[gx],[gy]"])
				if(consider(L))
					keep[L.glow_holder_key()] = TRUE
				else if(!unlit && !unmasked && L.glow_mask_key && !L.glow_plain)
					client_glow_mask_prefetch(L.glow_mask_key)
					var/ahead = GLOB.client_glow_baker.icons[L.glow_mask_key]
					if(ahead)
						deliver(L.glow_mask_key, ahead) // on the client before the crossing that holds it
	for(var/h in LAZYCOPY(held))
		if(!keep[h])
			drop_handle(h)
	if(!first_hold_logged && client)
		first_hold_logged = TRUE
		log_world("client glow holder: [client.ckey] first hold at [time2text(world.realtime, "hh:mm:ss")], [LAZYLEN(held)] glow(s)") // the load-in timeline
	if(!(GLOB.client_glow_holder_recomputes % 64))
		log_world(client_glow_census())
	log_world("client glow holder: [client?.ckey] entered chunk [new_sig], holding [LAZYLEN(held)] glow(s)[unlit ? " (hidden only, viewer sees no darkness)" : (unmasked ? " (unmasked, ghost)" : "")], [GLOB.client_glow_holder_made] made and [GLOB.client_glow_holder_dropped] dropped so far")

/// Shows, updates or drops this viewer's copy of light `L`. Returns TRUE while it is held.
/datum/client_glow_holder/proc/consider(datum/light_source/L)
	if(!sig || QDELETED(L) || !L.glow || !L.glow_mask_key)
		drop(L)
		return FALSE
	var/turf/S = L.source_turf
	if(!S || S.z != z)
		drop(L)
		return FALSE
	if(unlit)
		return consider_unlit(L, S)
	var/r = CEILING(L.light_range, 1)
	if(S.x + r < reach[1] || S.x - r > reach[3] || S.y + r < reach[2] || S.y - r > reach[4])
		drop(L) // its reach never comes on screen from this chunk
		return FALSE
	var/obj/effect/overlay/client_glow/G = L.glow
	var/h = L.glow_holder_key()
	var/list/entry = LAZYACCESS(held, h)
	var/image/glow_image
	if(!entry)
		glow_image = image(G.icon, null, G.icon_state)
		glow_image.layer = G.layer
		glow_image.blend_mode = BLEND_ADD
		glow_image.appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM | KEEP_APART
		glow_image.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
		var/image/hide_image = image(null) // overrides the real glow for this viewer: never drawn twice
		hide_image.override = TRUE
		image_anchor(hide_image, G)
		entry = list(glow_image, hide_image)
		LAZYSET(held, h, entry)
		client_images_add(client, entry)
		GLOB.client_glow_holder_made++
	else
		glow_image = entry[1]
		GLOB.client_glow_holder_updated++
	var/turf/stand_on = stand_turf(L, S)
	if(glow_image.loc != stand_on)
		image_anchor(glow_image, stand_on)
	var/px = (S.x - stand_on.x) * WORLD_ICON_SIZE + G.pixel_x
	var/py = (S.y - stand_on.y) * WORLD_ICON_SIZE + G.pixel_y
	glow_image.plane = G.plane
	glow_image.color = G.color
	glow_image.alpha = G.alpha
	glow_image.pixel_x = px
	glow_image.pixel_y = py
	apply_shape(L, h, glow_image, G)
	return TRUE

/// Where light `L`'s held glow stands: its own turf if the eye saw it, else the turf of its reach the eye saw that is nearest the eye.
/datum/client_glow_holder/proc/stand_turf(datum/light_source/L, turf/S)
	if(seen_keys["[S.x]:[S.y]"] || !L.glow_reach_origin)
		return S
	var/turf/O = L.glow_reach_origin
	var/best_x
	var/best_y
	var/best = INFINITY
	for(var/key in L.glow_reach)
		var/list/xy = splittext(key, ",")
		var/x = O.x + text2num(xy[1])
		var/y = O.y + text2num(xy[2])
		if(!seen_keys["[x]:[y]"])
			continue
		var/dist = abs(x - eye_x) + abs(y - eye_y)
		if(dist < best)
			best = dist
			best_x = x
			best_y = y
	return best == INFINITY ? S : locate(best_x, best_y, S.z)

/// Gives a held glow the picture it should show: the baked cut of its shape, its previous cut while a new one bakes, or the plain sprite.
/datum/client_glow_holder/proc/apply_shape(datum/light_source/L, h, image/glow_image, obj/effect/overlay/client_glow/G)
	if(unmasked || L.glow_plain)
		LAZYREMOVE(held_shape, h)
		LAZYREMOVE(cut_shape, h)
		show_plain(glow_image, G)
		return
	var/shape = L.glow_mask_key
	if(LAZYACCESS(held_shape, h) != shape)
		LAZYSET(held_shape, h, shape)
		var/baked = client_glow_mask_icon(shape)
		if(baked && deliver(shape, baked))
			cut_with(h, glow_image, shape, baked)
			return
	var/cut = LAZYACCESS(cut_shape, h)
	if(cut == shape)
		return
	// The old cut may only stand in when the new reach is inside it: a door opening grows the reach, and the old cut would leave the door
	// tile and the room behind it dark until the new one arrives. The plain sprite is already on the client; the visibility and wall cuts bound it.
	if(!cut || copytext(cut, 1, findtext(cut, "|")) != copytext(shape, 1, findtext(shape, "|")) || client_glow_shape_grew(cut, shape))
		LAZYREMOVE(cut_shape, h)
		show_plain(glow_image, G)

/datum/client_glow_holder/proc/show_plain(image/glow_image, obj/effect/overlay/client_glow/G)
	glow_image.icon = G.icon
	glow_image.icon_state = G.icon_state

/// Shows a held glow baked to `shape`.
/datum/client_glow_holder/proc/cut_with(h, image/glow_image, shape, baked)
	glow_image.icon = baked
	glow_image.icon_state = null
	LAZYSET(cut_shape, h, shape)

/// TRUE once this client can draw `baked`. An image whose icon the client has not received draws nothing until it arrives, so a new PNG goes
/// to the client first on a black (invisible under BLEND_ADD) preload image, and the held glows swap to it afterwards (client_glow_delivered()).
/datum/client_glow_holder/proc/deliver(shape, baked)
	if(!client || LAZYACCESS(delivered, shape))
		return TRUE
	if(LAZYACCESS(delivering, shape))
		return FALSE
	var/turf/eye = locate(eye_x, eye_y, z)
	if(!eye)
		return TRUE
	var/image/preload = image(baked)
	preload.color = "#000000" // adds nothing, however many are stacked: a faint copy would show as a patch around the eye
	preload.plane = PLANE_LIGHTING
	preload.layer = CLIENT_GLOW_LAYER
	preload.blend_mode = BLEND_ADD
	preload.appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM | KEEP_APART
	preload.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	image_anchor(preload, eye)
	LAZYSET(delivering, shape, preload)
	client_images_add(client, list(preload))
	after(src, CLIENT_GLOW_ICON_DELIVERY, PROC_REF(client_glow_delivered), with = list(shape, baked))
	return FALSE

/datum/client_glow_holder/proc/client_glow_delivered(shape, baked)
	var/image/preload = LAZYACCESS(delivering, shape)
	LAZYREMOVE(delivering, shape)
	if(preload && client)
		client_images_remove(client, list(preload))
	LAZYSET(delivered, shape, TRUE)
	if(length(delivered) > CLIENT_GLOW_MASK_CACHE_MAX)
		delivered.Cut(1, 2)
	shape_ready(shape, baked)

/// A shape finished baking: every held glow waiting on it shows it, once this client has the picture.
/datum/client_glow_holder/proc/shape_ready(shape, baked)
	var/waited_on = FALSE
	for(var/h in held_shape)
		if(held_shape[h] == shape && LAZYACCESS(cut_shape, h) != shape)
			waited_on = TRUE
			break
	if(!waited_on || !deliver(shape, baked))
		return
	for(var/h in held_shape)
		if(held_shape[h] != shape || LAZYACCESS(cut_shape, h) == shape)
			continue
		var/list/entry = LAZYACCESS(held, h)
		if(length(entry) == 2)
			cut_with(h, entry[1], shape, baked)

/// A viewer that sees no darkness: every light its view can reach is hidden from it with a plain override image, so its client
/// never draws the glows (a ghost sees through walls, so otherwise all of them, for no visible light).
/datum/client_glow_holder/proc/consider_unlit(datum/light_source/L, turf/S)
	var/r = CEILING(L.light_range, 1)
	if(S.x + r < reach[1] || S.x - r > reach[3] || S.y + r < reach[2] || S.y - r > reach[4])
		drop(L)
		return FALSE
	var/h = L.glow_holder_key()
	if(LAZYACCESS(held, h))
		return TRUE
	var/image/hide_image = image(null)
	hide_image.override = TRUE
	image_anchor(hide_image, L.glow)
	var/list/entry = list(hide_image)
	LAZYSET(held, h, entry)
	client_images_add(client, entry)
	GLOB.client_glow_holder_made++
	return TRUE

/// This viewer stops holding light `L`.
/datum/client_glow_holder/proc/drop(datum/light_source/L)
	if(L.glow_holder_key)
		drop_handle(L.glow_holder_key)

/datum/client_glow_holder/proc/drop_handle(h)
	var/list/entry = LAZYACCESS(held, h)
	if(!entry)
		return
	LAZYREMOVE(held, h)
	LAZYREMOVE(held_shape, h)
	LAZYREMOVE(cut_shape, h)
	client_images_remove(client, entry)
	GLOB.client_glow_holder_dropped++

/datum/client_glow_holder/proc/drop_all()
	for(var/h in LAZYCOPY(held))
		drop_handle(h)

/// This viewer's copy of light `L` (tests): list(glow image, hide image), or null.
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

/// (Tests, benchmarks.) A viewer eye about ten turfs from `L` on x, in L's row: its reach comes on screen from that eye's chunk.
/proc/client_glow_test_eye(turf/L)
	var/x = L.x > 20 ? L.x - 10 : L.x + 10
	return locate(x, L.y, L.z)
