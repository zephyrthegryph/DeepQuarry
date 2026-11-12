// The shared portrait cache: one flat picture of an atom's appearance (a mob's ID photo, its character directory card, its examine portrait, an
// owned closet's picture, the vore panel's prey), rendered off the main tick by rust-g iconforge from the appearance's own DMI states.
//
// The appearance is translated by /datum/dq_preview_flattener (code/content/client/preferences/preview_async.dm), the same translation the
// character setup preview and the Inspect panel use, which follows getFlatIcon(no_anim = TRUE) exactly. Its key is the translation itself (the
// layers, states, directions, colours and blends, hashed), so two mobs that look the same share one picture, and a mob that changes clothes
// gets a new one. An appearance the translation cannot express exactly is drawn with getFlatIcon at once (the exact-match fallback rule): it
// never looks different from before.
//
// portrait_request() answers at once when the picture is cached; otherwise it starts the render (one per key, however many ask) and calls each
// asker back with the picture when it lands. Askers show a placeholder until then. Nothing waits; the render is polled four times a second.

/// How many pictures are kept (least recently used dropped first).
#define PORTRAIT_CACHE_MAX 256
/// A render that has not landed by then counts as failed: its askers get a getFlatIcon picture instead.
#define PORTRAIT_RENDER_TIMEOUT (10 SECONDS)

GLOBAL_DATUM_INIT(portrait_cache, /datum/portrait_cache, new)

LIFECYCLE_KEEP_UNLESS_FORCED(/datum/portrait_cache)
/// key -> /datum/portrait (ready or rendering). Owned: a dropped picture is deleted with its datum.
/datum/portrait_cache
	var/list/portraits
	/// "[dir]:[the appearance's ref]" -> the key of its picture: an appearance asked about again skips the translation (about 10 ms for a dressed
	/// human). The portrait holds the appearance, so its ref is not reused while the entry exists.
	var/list/by_appearance
	/// Keys in use order, oldest first: the cache drops from the front past PORTRAIT_CACHE_MAX.
	var/list/use_order
	/// Photos whose picture is being drawn (/datum/photo_render): owned here until each finishes, whichever photos or copies are left.
	var/list/photo_renders
	/// Counters for the tests and the trace: pictures served from the cache, renders started, getFlatIcon fallbacks.
	var/hits = 0
	var/renders = 0
	var/fallbacks = 0

CAPABILITIES(/datum/portrait_cache)
	owns_many(nameof(portraits))
	owns_many(nameof(photo_renders))

/// One picture: its key, the picture once it landed (base 64 PNG and the /icon), and who is waiting for it while it renders.
/datum/portrait
	var/key
	var/b64
	var/icon/picture
	/// One render per frame (an animated picture has several): list(job id, sheet name) each.
	var/list/jobs
	/// The frame delays of an animated picture (null: one frame).
	var/list/delays
	/// list(list(handle of the asker, proc name)) called back with this portrait when it lands.
	var/list/waiters
	var/polling = FALSE
	COOLDOWN_DECLARE(timeout_at)
	/// What the render was of, for the fallback and the trace.
	var/described
	/// The appearances that map to this picture (held, so their refs stay theirs while the cache names them).
	var/list/appearances

CAPABILITIES(/datum/portrait)
	every(0.25 SECONDS, then(PROC_REF(poll_step)), when = nameof(polling))

/datum/portrait/New()
	..()
	lifecycle_decls_init(src) // a non-atom has no materialize

/// The portrait of `A` facing `dir`: a /datum/portrait whose b64/picture are set when it is ready (now, from the cache or the getFlatIcon
/// fallback) or null while it renders, in which case `asker`'s `callback` (a proc name: callback(datum/portrait/P)) is called when it lands.
/proc/portrait_request(atom/A, dir = SOUTH, datum/asker = null, callback = null, animated = FALSE)
	RETURN_TYPE(/datum/portrait)
	if(!A)
		return null
	var/datum/portrait_cache/cache = GLOB.portrait_cache
	var/appearance_key = "[dir]:[animated ? "a:" : ""][ref(A.appearance)]"
	var/known_key = cache.by_appearance?[appearance_key]
	var/datum/portrait/known = known_key ? cache.portraits?[known_key] : null
	if(known)
		return portrait_serve(cache, known, asker, callback)
	var/datum/dq_preview_flattener/flattener = new
	var/list/flat = flattener.flatten(A, dir)
	// An animated picture (getFlatIcon without no_anim): every frame is rendered, when every animated state in it has the same frames.
	var/list/animation = (animated && flat && !flattener.unsupported) ? portrait_animation(flat[1], flattener) : null
	if(!flat || flattener.unsupported)
		// The exact-match rule: what the translation cannot express is drawn the old way, now, and not cached (no key names it).
		cache.set_fallbacks(cache.fallbacks + 1)
		var/datum/portrait/sync = new
		sync.picture = animated ? getFlatIcon(A, defdir = dir) : getFlatIcon(A, defdir = dir, no_anim = TRUE)
		sync.set_b64(icon2base64(sync.picture))
		log_world("PORTRAIT: [A] ([A.type]) drawn with getFlatIcon ([flattener.unsupported || "nothing to render"]).")
		return sync
	var/key = "[dir]:[md5(json_encode(flat[1]))][animation ? ":anim" : ""]"
	var/datum/portrait/P = cache.portraits?[key]
	if(P)
		cache.set_by_appearance_at(appearance_key, key)
		P.add_appearances(list(A.appearance))
		return portrait_serve(cache, P, asker, callback)
	cache.set_renders(cache.renders + 1)
	P = new
	P.set_key(key)
	P.described = "[A] ([A.type])"
	P.jobs = list()
	if(animation)
		P.delays = animation
		for(var/frame in 1 to length(animation))
			P.jobs += list(dq_preview_start_job(portrait_frame_tree(flat[1], frame), "portrait"))
	else
		P.jobs += list(dq_preview_start_job(flat[1], "portrait"))
	P.add_waiter(asker, callback)
	P.set_appearances(list(A.appearance))
	cache.set_by_appearance_at(appearance_key, key)
	COOLDOWN_START(P, timeout_at, PORTRAIT_RENDER_TIMEOUT)
	rel_add(cache, nameof(/datum/portrait_cache::portraits), P, key)
	cache.add_use_order(key)
	while(length(cache.use_order) > PORTRAIT_CACHE_MAX)
		var/oldest = cache.use_order[1]
		cache.cut_use_order(1, 2)
		var/datum/portrait/dropped = cache.portraits[oldest]
		if(dropped && dropped != P)
			portrait_forget_appearances(cache, oldest)
			own_remove(cache, nameof(/datum/portrait_cache::portraits), dropped)
	P.set_polling(TRUE)
	return null

/// The key of the picture `A`'s current look renders to (or has), once it was asked for; null before.
/proc/portrait_key_of(atom/A, dir = SOUTH, animated = FALSE)
	var/appearance_key = "[dir]:[animated ? "a:" : ""][ref(A.appearance)]"
	return GLOB.portrait_cache.by_appearance?[appearance_key]

/// `P` from the cache: ready (returned), or still rendering (the asker waits for it; null).
/proc/portrait_serve(datum/portrait_cache/cache, datum/portrait/P, datum/asker, callback)
	cache.remove_use_order(P.key)
	cache.add_use_order(P.key)
	if(P.b64)
		cache.set_hits(cache.hits + 1)
		return P
	P.add_waiter(asker, callback)
	return null

/// `asker` is called back with this portrait when it lands: once, however many times it asked.
/datum/portrait/proc/add_waiter(datum/asker, callback)
	if(!asker || !callback)
		return
	var/handle = handle_of(asker)
	for(var/list/waiter as anything in waiters)
		if(waiter[1] == handle && waiter[2] == callback)
			return
	LAZYADD(waiters, list(list(handle, callback)))

/// Drops the appearance shortcuts to the picture `key` (it left the cache).
/proc/portrait_forget_appearances(datum/portrait_cache/cache, key)
	for(var/appearance_key in cache.by_appearance?.Copy())
		if(cache.by_appearance[appearance_key] == key)
			cache.remove_by_appearance(appearance_key)

/// One poll of the render: the picture lands, or the render failed or timed out (the askers then get nothing and ask again later).
/datum/portrait/proc/poll_step(datum/act/timer/tick)
	var/timed_out = ELAPSED(src, timeout_at, CLOCK_WORLD) > 0
	var/list/outputs = list()
	for(var/list/job as anything in jobs)
		var/output = rustg_iconforge_check(job[1])
		if(output == RUSTG_JOB_NO_RESULTS_YET && !timed_out)
			return
		outputs += output
	set_polling(FALSE)
	var/list/pngs = list()
	for(var/i in 1 to length(jobs))
		var/list/job = jobs[i]
		var/png_path = outputs[i] == RUSTG_JOB_NO_RESULTS_YET ? null : dq_preview_job_png(job[2], outputs[i])
		if(!png_path)
			log_world("PORTRAIT: render of [described] failed or timed out ([outputs[i]]); dropped, the next request renders it again.")
			for(var/path in pngs)
				fdel(path)
			var/datum/portrait_cache/cache = GLOB.portrait_cache
			cache.remove_use_order(key)
			portrait_forget_appearances(cache, key)
			own_remove(cache, nameof(/datum/portrait_cache::portraits), src)
			return
		pngs += png_path
	if(length(pngs) == 1)
		picture = icon(file(pngs[1]))
	else
		// As getFlatIcon's animated result: one state, its frames with their delays.
		picture = new /icon()
		for(var/i in 1 to length(pngs))
			picture.Insert(icon(file(pngs[i])), icon_state = "", frame = i, delay = delays[i])
	set_b64(icon2base64(picture))
	for(var/path in pngs)
		fdel(path)
	var/list/called = waiters
	waiters = null
	for(var/list/waiter as anything in called)
		var/datum/asker = handle_get(waiter[1])
		if(asker && !QDELETED(asker))
			call(asker, waiter[2])(src)

/// The frame delays of the animated picture `tree` (a flattener translation): null when nothing in it animates, the delays when every
/// animated state in it has the same ones. Two states with different frames (which getFlatIcon blends frame by frame its own way) set the
/// flattener's `unsupported`: that picture is drawn the old way.
/proc/portrait_animation(list/tree, datum/dq_preview_flattener/flattener)
	var/list/found = list()
	portrait_collect_delays(tree, found, flattener)
	var/list/delays
	for(var/list/state_delays as anything in found)
		if(!delays)
			delays = state_delays
		else if(json_encode(delays) != json_encode(state_delays))
			flattener.unsupported = "animated states with different frames"
			return null
	return delays

/proc/portrait_collect_delays(list/sprite, list/found, datum/dq_preview_flattener/flattener)
	if(!islist(sprite))
		return
	if(sprite["icon_file"])
		var/list/state = portrait_state_metadata(sprite["icon_file"], sprite["icon_state"])
		var/list/state_delays = state?["delay"]
		if(length(state_delays) > 1)
			if(state["rewind"] || state["loop_count"])
				flattener.unsupported = "an animation that rewinds or stops"
			found += list(state_delays)
	for(var/list/transform as anything in sprite["transform"])
		if(transform["icon"])
			portrait_collect_delays(transform["icon"], found, flattener)

/proc/portrait_state_metadata(icon_file, icon_state)
	var/list/metadata = icon_metadata(icon_file)
	for(var/list/state as anything in metadata?["states"])
		if(state["name"] == icon_state)
			return state
	return null

/// `sprite` at frame `frame`: every animated state in it shows that frame (a copy; the translation is not changed).
/proc/portrait_frame_tree(list/sprite, frame)
	var/list/copy = sprite.Copy()
	if(copy["icon_file"] && length(portrait_state_metadata(copy["icon_file"], copy["icon_state"])?["delay"]) > 1)
		copy["frame"] = frame
	var/list/transforms = list()
	for(var/list/transform as anything in copy["transform"])
		if(transform["icon"])
			var/list/inner = transform.Copy()
			inner["icon"] = portrait_frame_tree(transform["icon"], frame)
			transforms += list(inner)
		else
			transforms += list(transform)
	copy["transform"] = transforms
	return copy

#undef PORTRAIT_CACHE_MAX
#undef PORTRAIT_RENDER_TIMEOUT

// ---- Consumers declared in the library ----

/// The colour matrix tool's item pictures come from the shared portrait cache (its trial colour on): null until they land, then the window
/// draws again (picture_landed).
/datum/tgui_input_colormatrix/flat_picture(atom/A)
	return portrait_request(A, SOUTH, src, PROC_REF(picture_landed))?.picture
