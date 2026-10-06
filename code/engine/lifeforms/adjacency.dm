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
// Map loads: while a load batch runs (SSatoms.batch_defer(), code/controllers/subsystems/atoms_batch.dm), a member whose neighbours changed is
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
/// handle -> member (a handle is an index into this list; a freed one is null and reused).
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
		GLOB.adjacency_members[h] = A
	else
		GLOB.adjacency_members += A
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

/proc/adjacency_take_out(atom/holder, datum/centry/C)
	if(!holder.adj_handle)
		return
	var/datum/entry/E = C.item
	var/list/changed = vg_adjacency_remove(adjacency_kind_id(E.args["kind"]), holder.adj_handle)
	adjacency_recompute_handles(changed, E.args["kind"])
	adjacency_write(holder, C, 0)

/proc/adjacency_recompute_handles(list/changed, kind)
	for(var/h in changed)
		var/atom/member = GLOB.adjacency_members[h]
		if(!member || QDELETED(member))
			continue
		if(SSatoms?.batch_defer(BATCH_WORK_ADJACENCY, member))
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
	var/list/seen = vg_adjacency_seen(adjacency_kind_id(E.args["kind"]), holder.adj_handle)
	for(var/i in 1 to length(seen) step 2)
		var/atom/other = GLOB.adjacency_members[seen[i]]
		var/bit = seen[i + 1]
		if(!other || QDELETED(other))
			continue
		if(connects && !call(holder, connects)(other, bit))
			continue
		mask |= bit
	adjacency_write(holder, C, mask)

/proc/adjacency_write(atom/holder, datum/centry/C, mask)
	var/datum/entry/E = C.item
	var/into = E.args["into"]
	if(into)
		if(holder.vars[into] == mask)
			return
		holder.vars[into] = mask // ALLOW(api): the engine writes an adjacency() result into its declared var and publishes it
		tracked_changed(holder, into)
	var/changed = E.args["changed"]
	if(changed && !QDELETED(holder))
		call(holder, changed)(mask)

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
		var/atom/other = GLOB.adjacency_members[seen[i]]
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
/proc/adjacency_flush_batch(list/queued)
	for(var/atom/member as anything in queued)
		if(QDELETED(member) || !member.adj_handle)
			continue
		var/datum/lifeform_plan/P = lifeform_plan_of(member)
		for(var/datum/centry/C as anything in P.adjacencies)
			adjacency_recompute(member, C)

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
