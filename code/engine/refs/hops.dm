// The hop kinds that are not vars (doc/rewrite/final_api.html section 7, "Hop kinds"). A reactive read may cross a declared relation, `loc`
// (the container hop), or one of these pseudo segments:
//
//   "turf"  the turf a thing stands on, through any nesting (get_turf(x)); a turf's turf is itself
//   "area"  the area a thing is in (get_area(x)); an area's area is itself
//
// The read walk (tools/analyze/src/sem/reads.rs, pseudo_hop) keeps the root of `get_turf(src)` / `get_area(src)` and records the segment.
// At run time every consumer that walks a hop path resolves a segment through hop_step() (reader to far end) and hop_sources() (far end back
// to its readers), and the movement choke point publishes the segment when it changes (hop_moved(), from loc_changed()).

/// What `at` reaches through `segment`: a relation var's value, the container for `loc`, the turf or the area for the pseudo segments. Null
/// where `at` has no such var (the container hop reaches whatever the thing lies in, which may not have it).
/proc/hop_step(datum/at, segment)
	if(!isdatum(at))
		return null
	if(segment == HOP_TURF)
		return isatom(at) ? get_step(at, 0) : null
	if(segment == HOP_AREA)
		if(!isatom(at))
			return null
		if(isarea(at))
			return at
		var/turf/T = get_step(at, 0)
		return T?.loc
	if(!(segment in at.vars))
		return null
	return at.vars[segment]

/// The entities that reach `at` through `segment` (the reverse of hop_step()): what is in it for `loc`, everything standing on it at any depth
/// (and the turf itself) for "turf", everything in it for "area", and the sources whose relation var names it.
/proc/hop_sources(datum/at, segment)
	RETURN_TYPE(/list)
	. = list()
	if(!isdatum(at))
		return
	if(segment == "loc")
		if(isatom(at))
			. += contents_of(at)
	else if(segment == HOP_TURF)
		if(isturf(at))
			. += at
			. += hop_nested_contents(at)
	else if(segment == HOP_AREA)
		if(isarea(at))
			. += at
			for(var/turf/T as anything in contents_of(at, /turf))
				. += T
				. += hop_nested_contents(T)
	BOOT_PHASE_BEGIN(bp_rel)
	var/list/named_by = rel_sources_via(at, segment)
	BOOT_PHASE_END(bp_rel, "hop_sources: rel_sources of [segment]", at)
	for(var/datum/source as anything in named_by)
		. |= list(source)

/// Everything inside `A` at any depth (not `A` itself).
/proc/hop_nested_contents(atom/A)
	RETURN_TYPE(/list)
	. = list()
	var/list/frontier = contents_of(A)
	while(length(frontier))
		var/list/next = list()
		for(var/atom/movable/AM as anything in frontier)
			. += AM
			if(length(AM.contents))
				next += contents_of(AM)
		frontier = next

/// TRUE when something reads the pseudo segment `segment` of anything: a stat input, a derived() hop, an on_change() path, a generated read.
/// Asked on every move, so it is a few list lookups; the registries are filled while the world boots.
/proc/hop_segment_read(segment)
	if(!GLOB.hop_segments_built && (length(GLOB.generated_read_names) || length(GLOB.generated_plans)))
		GLOB.hop_segments_built = TRUE
		for(var/name in list(HOP_TURF, HOP_AREA))
			if(name in GLOB.generated_read_names)
				GLOB.hop_segments_read[name] = TRUE
		for(var/type in GLOB.generated_plans)
			var/list/plan = GLOB.generated_plans[type]
			for(var/name in list(HOP_TURF, HOP_AREA))
				if(plan[name] & PLAN_DRAW)
					GLOB.hop_segments_read[name] = TRUE
	return GLOB.stat_input_keys?[segment] || GLOB.derived_read_vars?[segment] || GLOB.hop_segments_read[segment]

/// Pseudo segments some generated read or draw crosses, by name (built from the generated tables on the first move after they exist).
GLOBAL_LIST_EMPTY(hop_segments_read)
GLOBAL_VAR_INIT(hop_segments_built, FALSE)

/// A movable moved from `old_loc` (Moved(), doMove() into nullspace): its turf and area, and those of everything inside it, may have changed.
/// Each changed segment is published on each thing whose reads cross it, through the one path a relation write takes (own_field_changed()).
/// Nothing runs while nothing reads the segments.
/proc/hop_moved(atom/movable/mover, atom/old_loc)
	var/turf_read = hop_segment_read(HOP_TURF)
	var/area_read = hop_segment_read(HOP_AREA)
	if(!turf_read && !area_read)
		return
	var/turf/old_turf = old_loc ? get_step(old_loc, 0) : null
	var/turf/new_turf = get_step(mover, 0)
	if(old_turf == new_turf)
		return
	var/turf_changed = turf_read
	var/area_changed = area_read && (old_turf?.loc != new_turf?.loc)
	if(!turf_changed && !area_changed)
		return
	if(!length(mover.contents))
		if(turf_changed && hop_reads(mover, HOP_TURF))
			own_field_changed(mover, HOP_TURF)
		if(area_changed && hop_reads(mover, HOP_AREA))
			own_field_changed(mover, HOP_AREA)
		return
	var/list/moved = list(mover) + hop_nested_contents(mover)
	// Which of them read the hops is kept on the mover: it changes only with what it carries (the handles of `moved`, in order: a thing put in,
	// taken out, deleted or reordered changes them) or with a reader of a hop coming or going anywhere (hop_reader_epoch). So a step asks each
	// thing nothing; the answers are rebuilt when either changes. The handles are numbers, so the cache holds no reference to what it describes.
	var/datum/rx_state/S = rx_of(mover)
	var/list/gens = handle_gens
	var/list/handles = list()
	for(var/atom/movable/AM as anything in moved)
		var/id = AM.handle_slot
		handles += id ? id + SLOT_SPAN * gens[id] : 0
	if(S.hop_cache_epoch != GLOB.hop_reader_epoch || !(S.hop_cache_handles ~= handles))
		hop_cache_build(S, moved, handles)
	else
		GLOB.hop_cache_hits++
		if(GLOB.hop_cache_verify)
			hop_cache_verify(moved, S)
	if(turf_changed)
		for(var/i in S.hop_cache_turf)
			var/atom/movable/AM = moved[i]
			if(!QDELETED(AM))
				own_field_changed(AM, HOP_TURF)
	if(area_changed)
		for(var/i in S.hop_cache_area)
			var/atom/movable/AM = moved[i]
			if(!QDELETED(AM))
				own_field_changed(AM, HOP_AREA)

/// Does a change of the hop `segment` (turf or area) on AM reach a reader? Per thing, not per world: a stat somewhere reading the turf hop does not
/// make each organ of a walking human a reader of it.
/proc/hop_reads(atom/movable/AM, segment)
	return GLOB.derived_read_vars?[segment] || stat_type_reads_key(AM, segment) || READERS(AM, segment)

/// The positions in `moved` of the things that read `segment`: what hop_moved() publishes it on.
/proc/hop_reader_positions(list/moved, segment)
	. = list()
	for(var/i in 1 to length(moved))
		var/atom/movable/AM = moved[i]
		if(!QDELETED(AM) && hop_reads(AM, segment))
			. += i

/// Asks each of `moved` again and keeps the answers on the mover's state S. Kept only once the tables that decide them are built (before that a
/// reader probe answers TRUE without caching) and every thing has a handle (a thing given one now changes its handle from 0, so the next step rebuilds).
/proc/hop_cache_build(datum/rx_state/S, list/moved, list/handles)
	GLOB.hop_cache_builds++
	S.hop_cache_turf = hop_reader_positions(moved, HOP_TURF)
	S.hop_cache_area = hop_reader_positions(moved, HOP_AREA)
	var/ready = islist(GLOB.stat_type_index) && islist(GLOB.change_index_by_type) && islist(GLOB.rx_tables) && GLOB.plan_reader_keys
	for(var/atom/movable/AM as anything in moved)
		if(!AM.handle_slot)
			handle_of(AM)
			ready = FALSE
	S.hop_cache_handles = ready ? handles : null
	S.hop_cache_epoch = ready ? GLOB.hop_reader_epoch : 0

/// Test builds (GLOB.hop_cache_verify, set by dq_hop_cache_parity): the kept answers against the full walk, so a cache that misses a change shows.
/proc/hop_cache_verify(list/moved, datum/rx_state/S)
	var/list/turf_full = hop_reader_positions(moved, HOP_TURF)
	var/list/area_full = hop_reader_positions(moved, HOP_AREA)
	if(!(turf_full ~= S.hop_cache_turf) || !(area_full ~= S.hop_cache_area))
		GLOB.hop_cache_mismatches++

/// Something that decides whether a thing reads a hop changed (an observer of the turf or area key came or went, an on_change() hop path
/// registered): every mover's kept answers are rebuilt on its next step. A null key: it may be any.
/proc/hop_readers_changed(key)
	if(isnull(key) || key == HOP_TURF || key == HOP_AREA)
		GLOB.hop_reader_epoch++

/datum/rx_state
	/// hop_moved()'s cache on a mover: the handles of what it moved with, in order, and the positions among them that read the turf and the area.
	var/list/hop_cache_handles
	var/list/hop_cache_turf
	var/list/hop_cache_area
	var/hop_cache_epoch = 0

GLOBAL_VAR_INIT(hop_reader_epoch, 1)
GLOBAL_VAR_INIT(hop_cache_hits, 0)
GLOBAL_VAR_INIT(hop_cache_builds, 0)
GLOBAL_VAR_INIT(hop_cache_verify, FALSE)
GLOBAL_VAR_INIT(hop_cache_mismatches, 0)

/// TRUE when `segment` is a hop E's reads can start with: a var of E, or (on an atom) a pseudo segment.
/proc/hop_segment_known(datum/E, segment)
	if(segment in E.vars)
		return TRUE
	return isatom(E) && (segment == HOP_TURF || segment == HOP_AREA)

// ---- draws that read a hop chain away ----

/// var name -> the hop chains some type's draw reads it through, built from the plans (PLAN_DRAW_HOP) on first use. A read path is "<hop>.<link>...<var>"
/// (`loc.cell.charge`): the chain is every segment before the var, in order from the reader. Each link is also a var some draw reads one hop shorter
/// (`loc.cell`), so a change of a link republishes through its own publisher and lands here as a var of its own.
/// Each entry is list(chain, read) where chain is the list of segments from the reader to the entity that holds the var.
GLOBAL_LIST_EMPTY(draw_hop_vars)
GLOBAL_VAR_INIT(draw_hop_vars_built, FALSE)

/// The chains some draw reads `var_name` through, or null: asked by every publish of a var, so after the first call it is one list lookup.
/proc/draw_hop_reads_var(var_name)
	if(!GLOB.draw_hop_vars_built)
		if(!length(GLOB.generated_plans))
			return null
		GLOB.draw_hop_vars_built = TRUE
		for(var/type_text in GLOB.generated_plans)
			var/type = text2path(type_text)
			if(!type)
				continue // a test-only type in a production build
			for(var/read in plan_keys(type, PLAN_DRAW_HOP))
				var/list/segments = splittext(read, ".")
				if(length(segments) < 2)
					continue
				var/name = segments[length(segments)]
				segments.len--
				var/list/entries = GLOB.draw_hop_vars[name]
				if(!entries)
					entries = list()
					GLOB.draw_hop_vars[name] = entries
				entries += list(list(segments, read))
	return GLOB.draw_hop_vars[var_name]

/// What the draw of D's type (the nearest type with a draw) reads through a hop chain, as "<hop>.<link>...<var>", or null.
/proc/draw_hop_reads_of(datum/D)
	return plan_keys(D.type, PLAN_DRAW_HOP) // the change graph's plan (code/engine/change/plan.dm)

/// `var_name` of E changed: every draw that reads it through a hop chain (an item drawing its holder's state, a light drawing its area's switch, a
/// flash drawing the charge of the cell in the robot that carries it) is marked for a redraw. The chain is walked back from E one segment at a
/// time with hop_sources(); E itself is not marked: its own draw hears its own vars. Inside draw_hop_batch_begin()/end() the vars are collected
/// and walked at the end, once per chain for all of them.
/proc/draw_hop_published(datum/E, var_name)
	if(!draw_hop_reads_var(var_name))
		return
	if(GLOB.draw_hop_batch_depth)
		var/list/pending = GLOB.draw_hop_batch_pending
		var/list/names = pending[E]
		if(!names)
			names = pending[E] = list()
		names[var_name] = TRUE
		return
	draw_hop_publish_vars(E, list(var_name))

GLOBAL_VAR_INIT(draw_hop_batch_depth, 0)

/// The handles of the materialized movables whose type's draw reads a var one area hop away ("area.<var>": a vendor drawing its area's power):
/// what an area's var change marks, instead of a walk of the area. Kept by hop_area_reader_join()/leave() on materialize and dematerialize.
GLOBAL_LIST_EMPTY(area_hop_readers)
/// type -> TRUE or FALSE: whether the type's draw reads a var one area hop away.
GLOBAL_LIST_EMPTY(area_hop_reader_types)

/// Whether `type`'s draw reads a var through the area hop alone ("area.<var>"), from the change plan; cached per type.
/proc/draws_through_area_hop(type)
	var/cached = GLOB.area_hop_reader_types[type]
	if(!isnull(cached))
		return cached
	. = FALSE
	for(var/read in plan_keys(type, PLAN_DRAW_HOP))
		var/list/segments = splittext(read, ".")
		if(length(segments) == 2 && segments[1] == HOP_AREA)
			. = TRUE
			break
	GLOB.area_hop_reader_types[type] = .

/// A movable entered the world: if its draw reads its area's vars, an area change finds it in area_hop_readers.
/proc/hop_area_reader_join(atom/movable/AM)
	if(draws_through_area_hop(AM.type))
		GLOB.area_hop_readers[handle_text(handle_of(AM))] = TRUE

/// A movable left the world: it is no area's reader any more.
/proc/hop_area_reader_leave(atom/movable/AM)
	// Dematerialize runs inside the destroy, where handle_of() answers null: the handle is read off the slot it still holds.
	var/id = AM.handle_slot
	if(id && GLOB.area_hop_reader_types[AM.type])
		GLOB.area_hop_readers -= handle_text(id + SLOT_SPAN * handle_gens[id])
/// E -> its changed var names (assoc), while a hop batch is open.
GLOBAL_LIST_EMPTY(draw_hop_batch_pending)

/// Opens a hop batch: draw_hop_published() collects instead of walking (an area's three channel writes walk the area once, not three times).
/proc/draw_hop_batch_begin()
	GLOB.draw_hop_batch_depth++

/// Closes a hop batch; the outermost close walks what was collected.
/proc/draw_hop_batch_end()
	if(--GLOB.draw_hop_batch_depth > 0)
		return
	GLOB.draw_hop_batch_depth = 0
	var/list/pending = GLOB.draw_hop_batch_pending
	if(!length(pending))
		return
	GLOB.draw_hop_batch_pending = list()
	for(var/datum/E as anything in pending)
		if(!QDELETED(E))
			draw_hop_publish_vars(E, pending[E])

/// The walk for E's changed vars `names`: the entries are grouped by chain (every type that reads `area.power_light` adds the same chain), so
/// each chain is walked once and a reader on it is marked when its draw reads any of the group's reads.
/proc/draw_hop_publish_vars(datum/E, list/names)
	// A datum that is not an atom has no loc, turf or area to hop through, and when nothing names it through a relation view there is no source to walk
	// either (a reagent or a reagent holder being filled at construction): no reader can be reached, so the chains are not even built.
	if(!isatom(E) && !_rel_index_of(E))
		return
	// An empty turf that nothing names through a relation view (most floors at a map load) has no reader on the turf hop: its only source is itself,
	// which is skipped below. One test replaces a walk that allocates a frontier, a nested-contents list and a relation list per chain.
	var/lone_turf = FALSE
	if(isturf(E))
		var/turf/where = E
		lone_turf = !length(where.contents) && !_rel_index_of(where)
	var/list/chains = list() // chain key -> the chain
	var/list/reads_of_chain = list() // chain key -> its reads (assoc)
	for(var/name in names)
		for(var/list/entry as anything in draw_hop_reads_var(name))
			var/list/chain = entry[1]
			if(lone_turf && length(chain) == 1 && chain[1] == HOP_TURF)
				continue
			var/key = jointext(chain, "|")
			if(!chains[key])
				chains[key] = chain
				reads_of_chain[key] = list()
			var/list/group = reads_of_chain[key]
			group[entry[2]] = TRUE
	for(var/key in chains)
		var/list/chain = chains[key]
		var/list/group = reads_of_chain[key]
		// One area hop (a draw reading its own area's var): its readers are the few materialized things whose type draws through the area hop
		// (area_hop_readers), asked where they stand now, not the area's whole nested contents.
		if(isarea(E) && length(chain) == 1 && chain[1] == HOP_AREA)
			for(var/handle in GLOB.area_hop_readers)
				var/atom/movable/reader = handle_get(handle)
				if(!reader || QDELING(reader) || hop_step(reader, HOP_AREA) != E)
					continue
				var/list/reads = draw_hop_reads_of(reader)
				if(!reads)
					continue
				for(var/read in group)
					if(read in reads)
						refresh_mark(reader, DEP_DRAW)
						break
			continue
		var/list/frontier = list(E)
		for(var/i = length(chain), i >= 1, i--)
			var/list/next = list()
			BOOT_PHASE_BEGIN(bp_walk)
			for(var/datum/at as anything in frontier)
				next |= hop_sources(at, chain[i])
			BOOT_PHASE_END(bp_walk, "draw_hop_published: walk [chain[i]]", E)
			frontier = next
			if(!length(frontier))
				break
		for(var/datum/reader as anything in frontier)
			if(reader == E || QDELING(reader))
				continue
			var/list/reads = draw_hop_reads_of(reader)
			if(!reads)
				continue
			for(var/read in group)
				if(read in reads)
					refresh_mark(reader, DEP_DRAW)
					break
