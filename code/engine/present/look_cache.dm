// The appearance cache (doc/rewrite/look.md section 6). A look is finished work: when two atoms of a type hold the same inputs, the second one's
// draw builds exactly what the first one's did. The cache keys a finished look by the inputs its draw reads (the type, the vars the generated
// plan names for its draw, and the base vars no look has set); a draw that finds the key assigns the held look and never runs draw(), the
// builder or change_key().
//
// What may be cached is decided from declarations, never by running the draw twice:
//   - the type's plan names only vars of the holder itself (no hop: a draw that reads its turf, area or container is keyed by state the key cannot see),
//     and every one of them holds text, a number, a path, a file or null (a datum, a list or a runtime icon is state the key cannot see);
//   - the holder is not a mob or an area and has no capability engine state (a watched atom or a flash);
//   - the finished look is plain data: overlays are icon_state names, and it has no effect, flick, underlay, vis_contents or watched atom.
// Anything else draws as it always did (counted as a bypass). Test builds verify every hit against a fresh draw (look_cache_verify()); a mismatch
// is a draw that reads something its plan does not name.

/// TRUE: the cache serves hits. FALSE: every draw builds its look (the before of the cost measurement).
GLOBAL_VAR_INIT(look_cache_on, TRUE)
/// Key -> the finished /datum/look. Bounded (LOOK_CACHE_MAX); a full cache is emptied and counted.
GLOBAL_ALIST_EMPTY(look_cache)
#define LOOK_CACHE_MAX 40000
/// What the type cache holds for a type the cache never serves.
#define LOOK_CACHE_NEVER "never"
/// Draws served by the cache (no look built), draws that built and stored a look, draws that built one the cache could not hold (the holder or the look
/// is not cacheable), and the times the cache was emptied for size.
GLOBAL_VAR_INIT(look_cache_hits, 0)
GLOBAL_VAR_INIT(look_cache_misses, 0)
GLOBAL_VAR_INIT(look_cache_bypassed, 0)
GLOBAL_VAR_INIT(look_cache_flushed, 0)
/// Looks built by the builder (refresh_look_draw() runs draw()): the cache's hit path adds none.
GLOBAL_VAR_INIT(look_builds, 0)
#if defined(UNIT_TESTS)
/// TRUE: a hit is checked against a fresh draw (a stale hit stack_traces). The hit-path test turns it off to count builds.
GLOBAL_VAR_INIT(look_cache_verify, TRUE)
GLOBAL_VAR_INIT(look_cache_drift_expected, FALSE)
#endif

/// Type path -> the holder vars its key names (a list), or LOOK_CACHE_NEVER for a type the cache never serves.
DECLARE_SHARED_CACHE(look_cache_vars_of, GLOBAL_PROC_REF(look_cache_vars_build), SC_NEVER)

/// `sample` is the first atom of the type to be keyed: its vars say which names the plan names are the holder's own.
/proc/look_cache_vars_build(atom/sample)
	var/type = sample.type
	if(ispath(type, /mob) || ispath(type, /area))
		return LOOK_CACHE_NEVER
	var/list/plan = plan_of(type)
	if(!length(plan) || plan_type_fallback(type))
		return LOOK_CACHE_NEVER
	var/list/names = list()
	var/list/vars_of = sample.vars
	for(var/key in plan)
		if(key == "rx" || key == "type")
			continue
		if((plan[key] & PLAN_DRAW_HOP) || findtext(key, "."))
			return LOOK_CACHE_NEVER // a draw that reads a neighbour is keyed by state the key cannot see
		if(!(key in vars_of))
			return LOOK_CACHE_NEVER // a name the holder does not own (a runtime key)
		names += key
	return sortTim(names, GLOBAL_PROC_REF(cmp_text_asc))

/// The cache key of `A`'s next draw, or null when A is not cacheable now.
/proc/look_cache_key(atom/A)
	if(!GLOB.look_cache_on)
		return null
	var/list/names = CACHED_KEY(look_cache_vars_of, A.type, A)
	if(!islist(names) || capability_data(A)?[/datum/cap_engine_state])
		return null
	var/list/vars_of = A.vars
	var/list/parts = list("[A.type]")
	for(var/name in names)
		var/value = vars_of[name]
		if(!(isnull(value) || isnum(value) || istext(value) || ispath(value) || (isfile(value) && length("[value]"))))
			return null // (a file with no name is an icon made at runtime: every one would share the key)
		parts += "[value]"
	// The base vars no look has set are inputs too (the draw may read them, and an unset one is the mapped value); one a look set is the draw's own output.
	if(!(isnull(A.icon) || istext(A.icon) || (isfile(A.icon) && length("[A.icon]"))))
		return null
	var/was = A.rx?.look_set_bits || 0
	parts += (was & LOOK_SET_ICON) ? "~" : "[A.icon]"
	parts += (was & LOOK_SET_ICON_STATE) ? "~" : A.icon_state
	parts += (was & LOOK_SET_COLOR) ? "~" : A.color
	parts += (was & LOOK_SET_ALPHA) ? "~" : A.alpha
	parts += (was & LOOK_SET_DIR) ? "~" : A.dir
	parts += (was & LOOK_SET_PLANE) ? "~" : A.plane
	parts += (was & LOOK_SET_LAYER) ? "~" : A.layer
	parts += (was & LOOK_SET_INVISIBILITY) ? "~" : A.invisibility
	parts += (was & LOOK_SET_OFFSET) ? "~" : "[A.pixel_x],[A.pixel_y]"
	return jointext(parts, "|")

/// Whether the finished look in `L` may be held: plain data that builds the same for any holder with the same key.
/proc/look_cache_storable(datum/look/L)
	if(!L.touched || L.watched || L.watched_worn || L.watched_looks || L.effects || L.flick_state || L.vis || L.underlays)
		return FALSE
	for(var/entry in L.overlays)
		if(!istext(entry))
			return FALSE
	return TRUE

/// A copy of the builder's finished look, as the cache holds it.
/proc/look_cache_copy(datum/look/L, key)
	var/datum/look/C = new
	C.icon_state = L.icon_state
	C.icon = L.icon
	C.color = L.color
	C.alpha = L.alpha
	C.invisibility = L.invisibility
	if(L.transform)
		C.transform = matrix(L.transform)
	C.dir = L.dir
	C.plane = L.plane
	C.layer = L.layer
	C.overlays = L.overlays ? L.overlays.Copy() : null
	C.variants = L.variants ? L.variants.Copy() : null
	C.parts = L.parts ? L.parts.Copy() : null
	C.filters = L.filters ? L.filters.Copy() : null
	C.light_spec = L.light_spec ? L.light_spec.Copy() : null
	C.held_state = L.held_state
	C.identity_name = L.identity_name
	C.identity_desc = L.identity_desc
	C.offset_x = L.offset_x
	C.offset_y = L.offset_y
	C.touched = TRUE
	C.made_key = key
	return C

/// Holds `L` (just built, look key `look_key`) under `cache_key`.
/proc/look_cache_store(cache_key, datum/look/L, look_key)
	var/list/held = GLOB.look_cache
	if(length(held) >= LOOK_CACHE_MAX)
		held.Cut()
		GLOB.look_cache_flushed++
	held[cache_key] = look_cache_copy(L, look_key)

/// Serves `A` its draw from the cache entry `hit`: nothing is built. Returns the look key, as refresh_look() does.
/proc/look_cache_serve(atom/A, datum/look/hit)
	GLOB.look_cache_hits++
	var/datum/rx_state/S = rx_of(A)
	if(hit.made_key == S.look_key)
		refresh_look_count(A, "same")
	else
		refresh_look_count(A, isnull(S.look_key) ? "first" : "changed")
		var/atom/outer = GLOB.refresh_applying
		GLOB.refresh_applying = A
		hit.apply_to(A)
		GLOB.refresh_applying = outer
		S.look_key = hit.made_key
	return hit.made_key

#if defined(UNIT_TESTS)
/// Test builds: a hit is checked against a fresh draw, which must make the same look.
/proc/look_cache_verify(atom/A, datum/look/hit)
	if(!GLOB.look_cache_verify)
		return
	var/key = refresh_look_draw(A, FALSE, null)
	if(key != hit.made_key && !GLOB.look_cache_drift_expected)
		stack_trace("LOOK CACHE DRIFT: [A.type] was served a held look that a fresh draw does not make ([refresh_key_difference(hit.made_key, key)])")
#endif

// ---- what a draw costs, by type ----

/// Type path -> list(draws, ms in all, then a count per cost bucket (look_cost_bounds)). Every draw adds to it, served or built.
GLOBAL_ALIST_EMPTY(look_cost)
/// The upper bound (ms) of each cost bucket; a draw over the last is counted in the one past it.
GLOBAL_LIST_INIT(look_cost_bounds, list(0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5))
GLOBAL_VAR_INIT(look_cost_hit_ms, 0)
GLOBAL_VAR_INIT(look_cost_built_ms, 0)
GLOBAL_VAR_INIT(look_cost_all_draws, 0)
GLOBAL_VAR_INIT(look_cost_all_ms, 0)

/// A row of look_cost, empty.
/proc/look_cost_row()
	var/list/row = list(0, 0)
	for(var/i in 1 to length(GLOB.look_cost_bounds) + 1)
		row += 0
	return row

/proc/look_cost_note(type, ms, hit)
	var/list/row = GLOB.look_cost[type]
	if(!row)
		row = look_cost_row()
		GLOB.look_cost[type] = row
	row[1]++
	row[2] += ms
	var/bucket = length(GLOB.look_cost_bounds) + 1
	for(var/i in 1 to length(GLOB.look_cost_bounds))
		if(ms <= GLOB.look_cost_bounds[i])
			bucket = i
			break
	row[2 + bucket]++
	GLOB.look_cost_all_draws++
	GLOB.look_cost_all_ms += ms
	if(hit)
		GLOB.look_cost_hit_ms += ms
	else
		GLOB.look_cost_built_ms += ms

/// The p95 draw cost of a row: the upper bound of the bucket the 95th percentile draw fell in.
/proc/look_cost_p95(list/row)
	var/target = row[1] * 0.95
	var/seen = 0
	var/last = length(GLOB.look_cost_bounds)
	for(var/i in 1 to last + 1)
		seen += row[2 + i]
		if(seen >= target)
			return i <= last ? GLOB.look_cost_bounds[i] : GLOB.look_cost_bounds[last] * 2
	return 0

/// Draw cost over every draw (mean and p95 ms) and the `top` types by time spent, as one line.
/proc/look_cost_text(top = 5)
	var/draws = GLOB.look_cost_all_draws
	var/list/all = look_cost_row()
	var/list/ranked = list()
	for(var/type in GLOB.look_cost)
		var/list/row = GLOB.look_cost[type]
		for(var/i in 3 to length(all))
			all[i] += row[i]
		ranked["[type]"] = row[2]
	all[1] = draws
	var/text = "draw cost: mean [draws ? round(GLOB.look_cost_all_ms / draws, 0.0001) : 0] ms, p95 [draws ? look_cost_p95(all) : 0] ms over [draws] draws"
	for(var/n in 1 to top)
		var/best
		for(var/name in ranked)
			if(isnull(best) || ranked[name] > ranked[best])
				best = name
		if(isnull(best))
			break
		var/list/row = GLOB.look_cost[text2path(best)]
		text += "; [best] x[row[1]] mean [round(row[2] / row[1], 0.0001)] p95 [look_cost_p95(row)] ms"
		ranked -= best
	return text

/// The cache's counters, for the look log line.
/proc/look_cache_text()
	var/served = GLOB.look_cache_hits + GLOB.look_cache_misses
	return "cache: [GLOB.look_cache_hits] hits, [GLOB.look_cache_misses] misses ([served ? round(100 * GLOB.look_cache_hits / served, 0.1) : 0]% hit rate), [GLOB.look_cache_bypassed] bypassed, [length(GLOB.look_cache)] held, flushed [GLOB.look_cache_flushed]x; looks built [GLOB.look_builds]"
