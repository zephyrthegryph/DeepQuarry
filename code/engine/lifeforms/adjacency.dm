// adjacency(KIND, dirs =, connects = PROC_REF(x), into = nameof(var), when =, changed = PROC_REF(y)): a tracked neighbour relation the engine
// keeps (doc/rewrite/final_api.html section 6 "Lifecycle forms", form 4).
//
//	CAPABILITIES(/obj/structure/catwalk)
//		adjacency(ADJ_KIND_CATWALK, into = nameof(connections), changed = PROC_REF(update_icon))
//	CAPABILITIES(/obj/structure/table)
//		adjacency(ADJ_KIND_TABLE, dirs = ADJ_CARDINAL | ADJ_DIAGONALS, connects = PROC_REF(joins_table), into = nameof(connections),
//			when = nameof(anchored))
//
// Members of one KIND (a text id) see each other. The instance is placed in the index when it initializes on a turf (a turf is placed where it
// is), moved with it, taken out while `when =` is false (re-checked when the var it names is written) and removed when it is destroyed or
// leaves the map. Every change asks the index which members' neighbour sets changed and recomputes exactly those: `connects` is a holder
// proc x(other, junction_bit) answering whether it joins that neighbour (default: every member of the kind joins), `into` gets the junction
// mask (NORTH/SOUTH/EAST/WEST/UP/DOWN as BYOND writes them, the corners at ADJ_JUNCTION_NE..SW) and is published as a tracked write, and
// `changed` runs after the mask changed. So update_neighbours() in Initialize() and on_destroy() is gone: placing, moving, anchoring and a
// neighbour's creation or destruction all reach the members it concerns.
//
// Joins across types: members of one kind see each other whatever their type, so a group of types that smooth together (walls with low
// walls, tables beside windows) share one kind and each one's `connects` picks what it joins (ADJ_KIND_SMOOTH).
//
// Map loads: while a load batch runs (SSatoms.batch_defer(), code/world/systems/atoms_batch.dm), a member whose neighbours changed is
// queued instead of recomputed (BATCH_WORK_ADJACENCY), and every queued member recomputes once when the batch closes, after every atom of
// the load (and its materials) exists. adjacency_refresh(holder, neighbours) recomputes now, for a change the index cannot see (a material).
//
// The index lives in Rust (verdigris/core/src/adjacency.rs, binds in verdigris/ffi/src/adjacency.rs): DM holds a handle per member and asks
// for the members whose sets changed. adjacency_seen(holder, KIND) is the neighbours a member sees, for code that wants them by name.

/proc/adjacency(kind, dirs = ADJ_CARDINAL, connects = null, into = null, when = null, changed = null)
	if(!istext(kind) || !length(kind))
		declare_report("adjacency(): the kind is a text id, got [kind]")
		return null
	return entry_make(ENTRY_ADJACENCY, "adjacency:[kind]", list("kind" = kind, "dirs" = dirs, "connects" = connects, "into" = into, "when" = when, "changed" = changed))

/// kind text -> the number the Rust index knows it by.
GLOBAL_LIST_EMPTY(adjacency_kind_ids)
/// handle -> the member's slot (a handle is an index into this list; a freed one is null and reused). Slots, not the members: the index keeps no reference.
GLOBAL_LIST_EMPTY(adjacency_members)
GLOBAL_LIST_EMPTY(adjacency_free)

/atom/var/tmp/adj_handle = 0 // ALLOW(base_vars, ownership): the engine's number for a member of the adjacency index (an index into GLOB.adjacency_members, not an entity)

/proc/adjacency_kind_id(kind)
	var/id = GLOB.adjacency_kind_ids[kind]
	if(!id)
		id = length(GLOB.adjacency_kind_ids) + 1
		GLOB.adjacency_kind_ids[kind] = id
	return id

/proc/adjacency_handle(atom/A)
	if(A.adj_handle)
		return A.adj_handle
	var/h
	if(length(GLOB.adjacency_free))
		h = GLOB.adjacency_free[length(GLOB.adjacency_free)]
		GLOB.adjacency_free.len--
		GLOB.adjacency_members[h] = SLOT(A)
	else
		GLOB.adjacency_members += SLOT(A)
		h = length(GLOB.adjacency_members)
	A.adj_handle = h
	return h

/// The rust dirs mask of a declaration's dirs (the BYOND corner dirs ask for the diagonals).
/proc/adjacency_rust_dirs(dirs)
	. = dirs & (NORTH|SOUTH|EAST|WEST|UP|DOWN)
	if(dirs & ADJ_DIAGONALS)
		. |= ADJ_DIAGONALS

/proc/adjacency_init(atom/holder, datum/lifeform_plan/P)
	if(!isatom(holder))
		declare_report("adjacency() on [holder.type]: only atoms have neighbours")
		return
	if(ismovable(holder))
		var/atom/movable/AM = holder
		AM.lifeform_moves |= LIFEFORM_MOVES_ADJACENCY
	for(var/datum/centry/C as anything in P.adjacencies)
		adjacency_place(holder, C)

/proc/adjacency_teardown(atom/holder, datum/lifeform_plan/P)
	if(!holder.adj_handle)
		return
	for(var/datum/centry/C as anything in P.adjacencies)
		adjacency_take_out(holder, C)
	GLOB.adjacency_members[holder.adj_handle] = null
	GLOB.adjacency_free += holder.adj_handle
	holder.adj_handle = 0

/// Puts `holder` where it is now (or takes it out when it is off the map or its when = is false), and recomputes what changed.
/proc/adjacency_place(atom/holder, datum/centry/C)
	var/datum/entry/E = C.item
	var/turf/T = isturf(holder) ? holder : (isturf(holder.loc) ? holder.loc : null)
	var/on = !!T
	if(on && C.whens && !op_whens_hold(holder, C.whens))
		on = FALSE
	if(on && !isnull(E.args["when"]) && !condition_holds(holder, E.args["when"]))
		on = FALSE
	if(!on)
		adjacency_take_out(holder, C)
		return
	var/h = adjacency_handle(holder)
	var/list/changed = vg_adjacency_place(adjacency_kind_id(E.args["kind"]), h, T.x, T.y, T.z, adjacency_rust_dirs(E.args["dirs"]))
	adjacency_recompute_handles(changed, E.args["kind"])

GLOBAL_VAR_INIT(dq_adjacency_trace, 0)
/// Test/debug tracing (GLOB.dq_adjacency_trace): the references of the holder and of what shares its tile after each step of leaving the index.
#define DQ_ADJACENCY_TRACE(holder, what) if(GLOB.dq_adjacency_trace) { log_world("ADJACENCY_TRACE: [holder.type] [what]: holder refs=[refcount(holder)], tile mates refs=[dq_adjacency_mate_refs(holder)]") }

/proc/dq_adjacency_mate_refs(atom/holder)
	var/list/out = list()
	if(isturf(holder.loc))
		for(var/atom/movable/AM in holder.loc)
			if(AM != holder)
				out += "[AM.type]=[refcount(AM)]"
	return jointext(out, ",")

/// The adjacency handle of the turf ChangeTurf() is replacing in place, or 0 (a handle is a number, not a reference). Its successor is placed in the index within the same call, so the neighbours its removal
/// touches are not recomputed twice (once without the turf, once with its successor): they wait in `adjacency_pending` and recompute once with the
/// successor in place.
GLOBAL_VAR_INIT(adjacency_replacing, 0)
/// While a replacement runs: kind -> list of the member handles of the neighbours whose recompute waits for the successor.
GLOBAL_LIST(adjacency_pending)

/// The successor of the replaced turf is in place: the neighbours that nothing recomputed meanwhile recompute now.
/proc/adjacency_replacement_done()
	var/list/pending = GLOB.adjacency_pending
	GLOB.adjacency_pending = null
	GLOB.adjacency_replacing = 0
	for(var/kind in pending)
		adjacency_recompute_handles(pending[kind], kind)

/proc/adjacency_take_out(atom/holder, datum/centry/C)
	if(!holder.adj_handle)
		return
	var/datum/entry/E = C.item
	var/list/changed = vg_adjacency_remove(adjacency_kind_id(E.args["kind"]), holder.adj_handle)
	DQ_ADJACENCY_TRACE(holder, "removed from the index")
	if(GLOB.adjacency_replacing && holder.adj_handle == GLOB.adjacency_replacing && GLOB.adjacency_pending)
		var/list/waiting = GLOB.adjacency_pending[E.args["kind"]]
		if(!waiting)
			waiting = GLOB.adjacency_pending[E.args["kind"]] = list()
		waiting |= changed
		adjacency_write(holder, C, 0)
		return
	adjacency_recompute_handles(changed, E.args["kind"])
	DQ_ADJACENCY_TRACE(holder, "neighbours recomputed")
	adjacency_write(holder, C, 0)
	DQ_ADJACENCY_TRACE(holder, "mask cleared")

/// While a bulk change holds the recomputes (adjacency_hold_begin()): the member slots, in the order first asked, and slot -> TRUE (a slot is a number,
/// so the set is an alist beside the ordered list). Each member recomputes once when
/// the hold drains (adjacency_hold_drain()), instead of once per neighbour that changed: an explosion crater changes most turfs next to each other,
/// and every changed turf asked its 4-8 neighbours again (14 k recomputes for 2.3 k changed turfs in the supermatter bench).
GLOBAL_LIST(adjacency_held)
GLOBAL_ALIST(adjacency_held_seen)
/// Where adjacency_hold_drain() resumes in the held list.
GLOBAL_VAR_INIT(adjacency_held_index, 1)
/// Recomputes held and members recomputed by drains since boot (diagnostics: their ratio is the work the hold saved).
GLOBAL_VAR_INIT(adjacency_held_asks, 0)
GLOBAL_VAR_INIT(adjacency_held_runs, 0)

/// Starts holding neighbour recomputes for a bulk change (an explosion's resolve). The holder calls adjacency_hold_drain() until it returns TRUE.
/proc/adjacency_hold_begin()
	if(!GLOB.adjacency_held)
		GLOB.adjacency_held = list()
		GLOB.adjacency_held_seen = alist()
		GLOB.adjacency_held_index = 1

/// Recomputes each held member once, oldest first; a recompute asked while draining joins the list. With `tick_checked`, stops when the tick is
/// over budget and returns FALSE (call again); returns TRUE when the hold is drained and closed.
/proc/adjacency_hold_drain(tick_checked = TRUE)
	var/list/held = GLOB.adjacency_held
	if(!held)
		return TRUE
	while(GLOB.adjacency_held_index <= length(held))
		var/atom/member = slot_datum(held[GLOB.adjacency_held_index++])
		if(member && !QDELETED(member) && member.adj_handle)
			GLOB.adjacency_held_runs++
			var/datum/lifeform_plan/MP = lifeform_plan_of(member)
			for(var/datum/centry/MC as anything in MP.adjacencies)
				adjacency_recompute(member, MC)
		if(tick_checked && TICK_CHECK)
			return FALSE
	log_world("ADJACENCY_HOLD: drained [length(held)] member(s); [GLOB.adjacency_held_asks] recompute(s) held, [GLOB.adjacency_held_runs] run since boot")
	GLOB.adjacency_held = null
	GLOB.adjacency_held_seen = null
	GLOB.adjacency_held_index = 1
	return TRUE

/proc/adjacency_recompute_handles(list/changed, kind)
	var/list/waiting = GLOB.adjacency_pending?[kind]
	var/list/held = GLOB.adjacency_held
	for(var/h in changed)
		if(waiting)
			waiting -= h // recomputed here, with the successor in place
		if(held)
			var/member_slot = GLOB.adjacency_members[h]
			if(member_slot)
				GLOB.adjacency_held_asks++
				if(!GLOB.adjacency_held_seen[member_slot])
					GLOB.adjacency_held_seen[member_slot] = TRUE
					held += member_slot
			continue
		var/atom/member = slot_datum(GLOB.adjacency_members[h])
		if(!member || QDELETED(member))
			continue
		if(materialization_host().batch_defer(BATCH_WORK_ADJACENCY, member))
			continue // a load batch runs: recomputed once when it closes
		var/datum/lifeform_plan/MP = lifeform_plan_of(member)
		for(var/datum/centry/MC as anything in MP.adjacencies)
			var/datum/entry/ME = MC.item
			if(ME.args["kind"] == kind)
				adjacency_recompute(member, MC)

/// The mask `holder` has now in the entry's kind: each neighbour it sees that it connects to.
/proc/adjacency_recompute(atom/holder, datum/centry/C)
	var/datum/entry/E = C.item
	var/connects = E.args["connects"]
	var/mask = 0
	DQ_ADJACENCY_TRACE(holder, "recompute begins")
	var/list/seen = vg_adjacency_seen(adjacency_kind_id(E.args["kind"]), holder.adj_handle)
	DQ_ADJACENCY_TRACE(holder, "recompute: neighbours read")
	for(var/i in 1 to length(seen) step 2)
		var/atom/other = slot_datum(GLOB.adjacency_members[seen[i]])
		var/bit = seen[i + 1]
		if(!other || QDELETED(other))
			continue
		if(connects && !call(holder, connects)(other, bit))
			continue
		mask |= bit
	DQ_ADJACENCY_TRACE(holder, "recompute: mask joined")
	adjacency_write(holder, C, mask)
	DQ_ADJACENCY_TRACE(holder, "recompute: mask written")

/proc/adjacency_write(atom/holder, datum/centry/C, mask)
	var/datum/entry/E = C.item
	var/into = E.args["into"]
	if(into)
		if(holder.vars[into] == mask)
			return
		holder.vars[into] = mask // ALLOW(api): the engine writes an adjacency() result into its declared var and publishes it
		DQ_ADJACENCY_TRACE(holder, "write: var set")
		tracked_changed(holder, into)
		DQ_ADJACENCY_TRACE(holder, "write: change published")
	var/changed = E.args["changed"]
	if(changed && !QDELETED(holder))
		call(holder, changed)(mask)
		DQ_ADJACENCY_TRACE(holder, "write: changed proc ran")

/// A member moved: it is re-placed in each kind (a move off the map takes it out).
/proc/adjacency_moved(atom/movable/holder, atom/old_loc)
	var/datum/lifeform_plan/P = lifeform_plan_of(holder)
	for(var/datum/centry/C as anything in P.adjacencies)
		adjacency_place(holder, C)

/// The var a `when =` names was written: the member is placed or taken out.
/proc/adjacency_when_changed(atom/holder, datum/centry/C)
	adjacency_place(holder, C)

/// The members `holder` sees in `kind` (connected or not), as list(member = junction bit).
/proc/adjacency_seen(atom/holder, kind)
	. = list()
	if(!holder.adj_handle)
		return
	var/list/seen = vg_adjacency_seen(adjacency_kind_id(kind), holder.adj_handle)
	for(var/i in 1 to length(seen) step 2)
		var/atom/other = slot_datum(GLOB.adjacency_members[seen[i]])
		if(other)
			.[other] = seen[i + 1]

/// Recomputes every adjacency() entry of `holder` now (a change the index cannot see: a material, a flip); with `neighbours`, the members it
/// sees as well. The old update_connections(propagate) callers land here.
/proc/adjacency_refresh(atom/holder, neighbours = FALSE)
	if(!holder?.adj_handle || QDELETED(holder))
		return
	var/datum/lifeform_plan/P = lifeform_plan_of(holder)
	for(var/datum/centry/C as anything in P.adjacencies)
		adjacency_recompute(holder, C)
		if(!neighbours)
			continue
		var/datum/entry/E = C.item
		for(var/atom/other as anything in adjacency_seen(holder, E.args["kind"]))
			if(QDELETED(other))
				continue
			var/datum/lifeform_plan/OP = lifeform_plan_of(other)
			for(var/datum/centry/OC as anything in OP.adjacencies)
				var/datum/entry/OE = OC.item
				if(OE.args["kind"] == E.args["kind"])
					adjacency_recompute(other, OC)

/// A load batch closed (BATCH_WORK_ADJACENCY): each member it queued recomputes once.
/// Each member joins its neighbours as one construction step (silent construction, refresh.dm): what its joins write (its connections, the
/// icon_state and dir its look settles on) is published once when the step ends, only where a reader follows it, and its draw is queued once.
/proc/adjacency_flush_batch(list/queued)
	for(var/atom/member as anything in queued)
		if(QDELETED(member) || !member.adj_handle)
			continue
		var/reopened = GLOB.silent_construction && !(member.datum_flags & DF_CONSTRUCTING)
		if(reopened)
			member.datum_flags |= DF_CONSTRUCTING
		var/datum/lifeform_plan/P = lifeform_plan_of(member)
		for(var/datum/centry/C as anything in P.adjacencies)
			adjacency_recompute(member, C)
		if(reopened)
			GLOB.adjacency_joins_constructed++
			construction_birth(member)

/// Load-batch members whose joins ran as a construction step (adjacency_flush_batch()).
GLOBAL_VAR_INIT(adjacency_joins_constructed, 0)

/// The BYOND directions a junction mask names: each face it holds, and each corner (NORTHEAST..SOUTHWEST) for the corner bits.
/proc/adjacency_mask_dirs(mask)
	. = list()
	for(var/dir in list(NORTH, SOUTH, EAST, WEST))
		if(mask & dir)
			. += dir
	if(mask & ADJ_JUNCTION_NE)
		. += NORTHEAST
	if(mask & ADJ_JUNCTION_NW)
		. += NORTHWEST
	if(mask & ADJ_JUNCTION_SE)
		. += SOUTHEAST
	if(mask & ADJ_JUNCTION_SW)
		. += SOUTHWEST

/// The member of `kind` that `holder` sees on the face or corner `bit` (a BYOND direction or an ADJ_JUNCTION_* bit), or null.
/proc/adjacency_member_at(atom/holder, kind, bit)
	switch(bit)
		if(NORTHEAST)
			bit = ADJ_JUNCTION_NE
		if(NORTHWEST)
			bit = ADJ_JUNCTION_NW
		if(SOUTHEAST)
			bit = ADJ_JUNCTION_SE
		if(SOUTHWEST)
			bit = ADJ_JUNCTION_SW
	var/list/seen = adjacency_seen(holder, kind)
	for(var/atom/other as anything in seen)
		if(seen[other] == bit)
			return other
	return null
