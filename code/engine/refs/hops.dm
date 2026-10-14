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
	for(var/list/pair as anything in rel_sources(at))
		if(pair[2] == segment)
			. |= list(pair[1])

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
	if(!GLOB.hop_segments_built && (length(GLOB.generated_read_names) || length(GLOB.generated_draw_reads)))
		GLOB.hop_segments_built = TRUE
		for(var/name in list(HOP_TURF, HOP_AREA))
			if(name in GLOB.generated_read_names)
				GLOB.hop_segments_read[name] = TRUE
		for(var/type in GLOB.generated_draw_reads)
			var/list/reads = GLOB.generated_draw_reads[type]
			for(var/name in list(HOP_TURF, HOP_AREA))
				if(name in reads)
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
	var/list/moved = list(mover)
	if(length(mover.contents))
		moved += hop_nested_contents(mover)
	for(var/atom/movable/AM as anything in moved)
		if(QDELETED(AM))
			continue
		if(turf_changed && (GLOB.stat_input_keys?[HOP_TURF] || GLOB.derived_read_vars?[HOP_TURF] || READERS(AM, HOP_TURF)))
			own_field_changed(AM, HOP_TURF)
		if(area_changed && (GLOB.stat_input_keys?[HOP_AREA] || GLOB.derived_read_vars?[HOP_AREA] || READERS(AM, HOP_AREA)))
			own_field_changed(AM, HOP_AREA)

/// TRUE when `segment` is a hop E's reads can start with: a var of E, or (on an atom) a pseudo segment.
/proc/hop_segment_known(datum/E, segment)
	if(segment in E.vars)
		return TRUE
	return isatom(E) && (segment == HOP_TURF || segment == HOP_AREA)

// ---- draws that read a hop chain away ----

/// var name -> the hop chains some type's draw reads it through, built from generated_draw_hop_reads on first use. A read path is "<hop>.<link>...<var>"
/// (`loc.cell.charge`): the chain is every segment before the var, in order from the reader. Each link is also a var some draw reads one hop shorter
/// (`loc.cell`), so a change of a link republishes through its own publisher and lands here as a var of its own.
/// Each entry is list(chain, read) where chain is the list of segments from the reader to the entity that holds the var.
GLOBAL_LIST_EMPTY(draw_hop_vars)
GLOBAL_VAR_INIT(draw_hop_vars_built, FALSE)

/// The chains some draw reads `var_name` through, or null: asked by every publish of a var, so after the first call it is one list lookup.
/proc/draw_hop_reads_var(var_name)
	if(!GLOB.draw_hop_vars_built)
		if(!length(GLOB.generated_draw_hop_reads))
			return null
		GLOB.draw_hop_vars_built = TRUE
		for(var/type in GLOB.generated_draw_hop_reads)
			for(var/read in GLOB.generated_draw_hop_reads[type])
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
	var/list/table = GLOB.generated_draw_hop_reads
	var/path = D.type
	while(path)
		var/list/reads = table["[path]"]
		if(reads)
			return reads
		var/datum/typed = path
		path = initial(typed.parent_type)
	return null

/// `var_name` of E changed: every draw that reads it through a hop chain (an item drawing its holder's state, a light drawing its area's switch, a
/// flash drawing the charge of the cell in the robot that carries it) is marked for a redraw. The chain is walked back from E one segment at a
/// time with hop_sources(); E itself is not marked: its own draw hears its own vars.
/proc/draw_hop_published(datum/E, var_name)
	var/list/entries = draw_hop_reads_var(var_name)
	if(!entries)
		return
	for(var/list/entry as anything in entries)
		var/list/chain = entry[1]
		var/read = entry[2]
		var/list/frontier = list(E)
		for(var/i = length(chain), i >= 1, i--)
			var/list/next = list()
			for(var/datum/at as anything in frontier)
				next |= hop_sources(at, chain[i])
			frontier = next
			if(!length(frontier))
				break
		for(var/datum/reader as anything in frontier)
			if(reader == E || QDELING(reader))
				continue
			var/list/reads = draw_hop_reads_of(reader)
			if(reads && (read in reads))
				refresh_mark(reader, DEP_DRAW)
