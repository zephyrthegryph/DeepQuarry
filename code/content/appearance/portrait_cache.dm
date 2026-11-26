// The shared portrait cache: one flat picture of an atom's appearance (a mob's ID photo, its character directory card, its examine portrait, an
// owned closet's picture, the vore panel's prey), rendered off the main tick by rust-g iconforge from the appearance's own DMI states.
//
// The appearance is translated by /datum/dq_preview_flattener (code/content/client/preferences/preview_async.dm), the same translation the
// character setup preview and the Inspect panel use, which follows getFlatIcon(no_anim = TRUE) exactly. Its key is the translation itself (the
// layers, states, directions, colours and blends, hashed), so two mobs that look the same share one picture, and a mob that changes clothes
// gets a new one. An appearance the translation cannot express exactly is drawn with getFlatIcon at once (the exact-match fallback rule): it
// never looks different from before.
//
// portrait_request() answers at once when the picture is cached; otherwise it only enqueues: the appearance is translated by a kernel job one
// layer per step (/datum/portrait_translation), then the render starts (one per key, however many ask) and each asker is called back with the
// picture when it lands. Askers show a placeholder until then. Nothing waits; the render is polled four times a second. No translation, hash
// or drawing runs inside the request, whoever asks (the late-join manifest photos, the examine portrait, a closet's owner).

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
	/// "[dir]:[the appearance's ref]" -> the /datum/portrait_translation of an appearance being translated (one per appearance, however many ask). Owned.
	var/list/translations
	/// Counters for the tests and the trace: pictures served from the cache, renders started, getFlatIcon fallbacks.
	var/hits = 0
	var/renders = 0
	var/fallbacks = 0
	/// Translations finished (the tests and the trace).
	var/translated = 0

CAPABILITIES(/datum/portrait_cache)
	owns_many(nameof(portraits))
	owns_many(nameof(translations))
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
	/// The tokens (portrait_key_of() before the translation finished) of the requests this picture answers, besides its own key.
	var/list/asked_as

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
	var/datum/portrait_translation/T = cache.translations?[appearance_key]
	if(!T)
		T = new
		T.appearance = A.appearance
		T.dir = dir
		T.animated = animated
		T.token = appearance_key
		T.described = "[A] ([A.type])"
		rel_add(cache, nameof(/datum/portrait_cache::translations), T, appearance_key)
		job(T, TYPE_PROC_REF(/datum/portrait_translation, translate_step), then = TYPE_PROC_REF(/datum/portrait_translation, translation_done))
	T.add_waiter(asker, callback)
	return null

/// One appearance being translated, a layer per job step, then rendered: the work portrait_request() does not do on the asker's tick.
/datum/portrait_translation
	/// The look being translated (an immutable appearance: the mob it came from may already be gone).
	var/image/appearance
	var/dir = SOUTH
	var/animated = FALSE
	/// What portrait_key_of() answers until this lands, and what the finished picture answers to (datum/portrait/asked_as).
	var/token
	var/described
	/// list(list(handle of the asker, proc name)) called back with the portrait this becomes.
	var/list/waiters
	var/datum/dq_preview_flattener/flattener
	var/datum/dq_flatten_frame/frame
	var/steps = 0

CAPABILITIES(/datum/portrait_translation)
	owns_one(nameof(flattener))
	owns_one(nameof(frame))

/datum/portrait_translation/New()
	..()
	lifecycle_decls_init(src) // a non-atom has no materialize

/datum/portrait_translation/proc/add_waiter(datum/asker, callback)
	if(!asker || !callback)
		return
	var/handle = handle_of(asker)
	for(var/list/waiter as anything in waiters)
		if(waiter[1] == handle && waiter[2] == callback)
			return
	LAZYADD(waiters, list(list(handle, callback)))

/// One job step: opens the translation, then draws one layer of the appearance per step.
/datum/portrait_translation/proc/translate_step(datum/act/timer/A)
	steps++
	if(!frame)
		rel_set(src, nameof(flattener), new /datum/dq_preview_flattener)
		rel_set(src, nameof(frame), flattener.flatten_open(appearance, dir))
	else
		flattener.flatten_step(frame)
	return frame.done ? JOB_DONE : JOB_MORE

/// The translation is done: the picture is served from the cache, rendered (a job of its own), or (what the translation cannot express) drawn
/// the old way, and every asker is called back (now, or when the render lands).
/datum/portrait_translation/proc/translation_done(datum/act/timer/A)
	var/datum/portrait_cache/cache = GLOB.portrait_cache
	cache.set_translated(cache.translated + 1)
	var/list/asked = waiters
	waiters = null
	var/list/flat = frame.result
	var/datum/portrait/P
	if(!flat || flattener.unsupported)
		P = fallback_portrait(cache, flattener.unsupported || "nothing to render")
	else
		P = portrait_for_translation(cache, flat)
	LAZYADD(P.asked_as, token)
	if(P.key)
		cache.set_by_appearance_at(token, P.key)
	for(var/list/waiter as anything in asked)
		if(P.b64)
			var/datum/asker = handle_get(waiter[1])
			if(asker && !QDELETED(asker))
				call(asker, waiter[2])(P)
		else
			P.add_waiter_entry(waiter)
	own_remove(cache, nameof(/datum/portrait_cache::translations), src)

/// What the translation cannot express is drawn the old way (the exact-match rule), and not cached (no key names it). It is drawn here, in a job
/// step of its own, never inside the request.
/datum/portrait_translation/proc/fallback_portrait(datum/portrait_cache/cache, why)
	cache.set_fallbacks(cache.fallbacks + 1)
	var/datum/portrait/P = new
	P.picture = animated ? getFlatIcon(appearance, defdir = dir) : getFlatIcon(appearance, defdir = dir, no_anim = TRUE)
	P.set_b64(icon2base64(P.picture))
	log_world("PORTRAIT: [described] drawn with getFlatIcon ([why]) after [steps] steps.")
	return P

/// The portrait of a finished translation: the cached one of its look, or a new one rendering off the tick.
/datum/portrait_translation/proc/portrait_for_translation(datum/portrait_cache/cache, list/flat)
	// An animated picture (getFlatIcon without no_anim): every frame is rendered, when every animated state in it has the same frames.
	var/list/animation = animated ? portrait_animation(flat[1], flattener) : null
	if(flattener.unsupported)
		return fallback_portrait(cache, flattener.unsupported)
	var/key = "[dir]:[md5(json_encode(flat[1]))][animation ? ":anim" : ""]"
	var/datum/portrait/P = cache.portraits?[key]
	if(P)
		P.add_appearances(list(appearance))
		cache.remove_use_order(key)
		cache.add_use_order(key)
		if(P.b64)
			cache.set_hits(cache.hits + 1)
		return P
	cache.set_renders(cache.renders + 1)
	P = new
	P.set_key(key)
	P.described = described
	P.jobs = list()
	if(animation)
		P.delays = animation
		for(var/frame_number in 1 to length(animation))
			P.jobs += list(dq_preview_start_job(portrait_frame_tree(flat[1], frame_number), "portrait"))
	else
		P.jobs += list(dq_preview_start_job(flat[1], "portrait"))
	P.set_appearances(list(appearance))
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
	return P

/// The key of the picture `A`'s current look renders to (or has), once it was asked for; the request's token while it is still being translated; null before.
/proc/portrait_key_of(atom/A, dir = SOUTH, animated = FALSE)
	var/appearance_key = "[dir]:[animated ? "a:" : ""][ref(A.appearance)]"
	// Until the translation lands the key is not known: the token stands for it (datum/portrait/proc/answers()).
	return GLOB.portrait_cache.by_appearance?[appearance_key] || (GLOB.portrait_cache.translations?[appearance_key] ? appearance_key : null)

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

/// A waiter entry from a translation, kept once per asker and proc.
/datum/portrait/proc/add_waiter_entry(list/waiter)
	for(var/list/known as anything in waiters)
		if(known[1] == waiter[1] && known[2] == waiter[2])
			return
	LAZYADD(waiters, list(waiter))

/// Is `asked` (a key or a portrait_key_of() token) this picture?
/datum/portrait/proc/answers(asked)
	return !isnull(asked) && (asked == key || (asked in asked_as))

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
