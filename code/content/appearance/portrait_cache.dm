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
	/// Counters for the tests and the trace: pictures served from the cache, renders started, getFlatIcon fallbacks.
	var/hits = 0
	var/renders = 0
	var/fallbacks = 0

CAPABILITIES(/datum/portrait_cache)
	owns_many(nameof(portraits))

/// One picture: its key, the picture once it landed (base 64 PNG and the /icon), and who is waiting for it while it renders.
/datum/portrait
	var/key
	var/b64
	var/icon/picture
	var/job_id
	var/sheet_name
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
/proc/portrait_request(atom/A, dir = SOUTH, datum/asker = null, callback = null)
	RETURN_TYPE(/datum/portrait)
	if(!A)
		return null
	var/datum/portrait_cache/cache = GLOB.portrait_cache
	var/appearance_key = "[dir]:[ref(A.appearance)]"
	var/known_key = cache.by_appearance?[appearance_key]
	var/datum/portrait/known = known_key ? cache.portraits?[known_key] : null
	if(known)
		return portrait_serve(cache, known, asker, callback)
	var/datum/dq_preview_flattener/flattener = new
	var/list/flat = flattener.flatten(A, dir)
	if(!flat || flattener.unsupported)
		// The exact-match rule: what the translation cannot express is drawn the old way, now, and not cached (no key names it).
		cache.fallbacks++
		var/datum/portrait/sync = new
		sync.picture = getFlatIcon(A, defdir = dir, no_anim = TRUE)
		sync.b64 = icon2base64(sync.picture)
		log_world("PORTRAIT: [A] ([A.type]) drawn with getFlatIcon ([flattener.unsupported || "nothing to render"]).")
		return sync
	var/key = "[dir]:[md5(json_encode(flat[1]))]"
	var/datum/portrait/P = cache.portraits?[key]
	if(P)
		LAZYSET(cache.by_appearance, appearance_key, key)
		P.appearances += list(A.appearance)
		return portrait_serve(cache, P, asker, callback)
	cache.renders++
	P = new
	P.key = key
	P.described = "[A] ([A.type])"
	var/list/started = dq_preview_start_job(flat[1], "portrait")
	P.job_id = started[1]
	P.sheet_name = started[2]
	P.add_waiter(asker, callback)
	P.appearances = list(A.appearance)
	LAZYSET(cache.by_appearance, appearance_key, key)
	COOLDOWN_START(P, timeout_at, PORTRAIT_RENDER_TIMEOUT)
	rel_add(cache, nameof(/datum/portrait_cache::portraits), P, key)
	LAZYADD(cache.use_order, key)
	while(length(cache.use_order) > PORTRAIT_CACHE_MAX)
		var/oldest = cache.use_order[1]
		cache.use_order.Cut(1, 2)
		var/datum/portrait/dropped = cache.portraits[oldest]
		if(dropped && dropped != P)
			portrait_forget_appearances(cache, oldest)
			own_remove(cache, nameof(/datum/portrait_cache::portraits), dropped)
	P.set_polling(TRUE)
	return null

/// `P` from the cache: ready (returned), or still rendering (the asker waits for it; null).
/proc/portrait_serve(datum/portrait_cache/cache, datum/portrait/P, datum/asker, callback)
	cache.use_order -= P.key
	cache.use_order += P.key
	if(P.b64)
		cache.hits++
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
			cache.by_appearance -= appearance_key

/// One poll of the render: the picture lands, or the render failed or timed out (the askers then get nothing and ask again later).
/datum/portrait/proc/poll_step(datum/act/timer/tick)
	var/output = rustg_iconforge_check(job_id)
	var/timed_out = ELAPSED(src, timeout_at, CLOCK_WORLD) > 0
	if(output == RUSTG_JOB_NO_RESULTS_YET && !timed_out)
		return
	set_polling(FALSE)
	var/png_path = output == RUSTG_JOB_NO_RESULTS_YET ? null : dq_preview_job_png(sheet_name, output)
	if(!png_path)
		log_world("PORTRAIT: render of [described] failed or timed out ([output]); dropped, the next request renders it again.")
		var/datum/portrait_cache/cache = GLOB.portrait_cache
		cache.use_order -= key
		portrait_forget_appearances(cache, key)
		own_remove(cache, nameof(/datum/portrait_cache::portraits), src)
		return
	picture = icon(file(png_path))
	b64 = icon2base64(picture)
	fdel(png_path)
	var/list/called = waiters
	waiters = null
	for(var/list/waiter as anything in called)
		var/datum/asker = handle_get(waiter[1])
		if(asker && !QDELETED(asker))
			call(asker, waiter[2])(src)

#undef PORTRAIT_CACHE_MAX
#undef PORTRAIT_RENDER_TIMEOUT
