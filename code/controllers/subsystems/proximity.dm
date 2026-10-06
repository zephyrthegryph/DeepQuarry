// Client proximity (doc/rewrite/framework_gaps.md F2, final_api.html section 3).
//
// Cosmetic and ambient periodics that only matter when a player could see them park while nobody is near: a thing that opts in (`proximity_tracked`) holds
// STAT_RELEVANCE = RELEVANCE_NEAR while its cell, or one of the eight around it, has a client eye in it. every(..., when = STAT_RELEVANCE) parks on
// that stat. Work that changes simulation state must not opt in: it keeps running everywhere.
//
// The tracker keeps a grid of /datum/proximity_cell (PROXIMITY_CELL_SIZE turfs a side, per z-level). A client's eye is counted into the cell of
// get_turf(client.eye) and moves between cells when the mob moves (mob Moved), the client logs in or out, or the once-a-second sweep finds its eye
// (an AI camera, an observer, a remote view) elsewhere. A cell that gains its first occupied neighbour holds relevance on its members, with the cell
// as the hold's source; one that loses its last releases it. A tracked thing found in a cell that is already near holds at once when it joins, and
// releases from the cell it leaves. A tracked thing carried (not on a turf) stays relevant: whoever carries it is near by definition of the carry.

/datum/proximity_cell
	var/id
	var/z
	var/cx
	var/cy
	/// Client eyes counted in this cell.
	var/eyes = 0
	/// Cells within one step of this one (itself included) that hold an eye: the cell is near while this is above zero.
	var/near = 0
	/// Tracked things in this cell.
	var/list/members

SYSTEM_DEF(proximity)
	name = "Proximity"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	init_stage = INITSTAGE_MAIN
	/// Cell id -> /datum/proximity_cell, for cells that hold an eye, a member or a near count.
	VAR_PRIVATE/list/cells = list()
	/// The /datum/proximity_eye records counted into a cell.
	VAR_PRIVATE/list/eyes = list()
	/// Tracked thing -> the cell id it is filed under, or PROXIMITY_CARRIED while it is not on a turf.
	VAR_PRIVATE/list/filed = list()
	/// The source a carried tracked thing holds its relevance under.
	var/datum/proximity_carried/carried

/datum/proximity_carried

/// One client's eye, counted into a cell. Tests make them without a client.
/datum/proximity_eye
	var/client/client
	var/cell_id

/datum/system/proximity/initialize()
	carried = new
	return ..()

/datum/system/proximity/reactions()
	. = ..()
	. += every(1 SECOND, PROC_REF(sweep), lane = LANE_BACKGROUND)

/// The once-a-second pass: moves every counted eye whose cell changed without a mob step (a camera, a remote view, an eye swap).
/datum/system/proximity/proc/sweep(dt)
	for(var/datum/proximity_eye/R as anything in eyes.Copy())
		var/client/C = R.client
		if(!C || QDELETED(C))
			eye_place(R, null)
			continue
		eye_place(R, get_turf(C.eye))

/// The cell for `id`, made on demand.
/datum/system/proximity/proc/cell_of(id, z, cx, cy)
	var/datum/proximity_cell/P = cells["[id]"]
	if(!P)
		P = new
		P.id = id
		P.z = z
		P.cx = cx
		P.cy = cy
		cells["[id]"] = P
	return P

/// A cell nothing refers to any more goes.
/datum/system/proximity/proc/cell_prune(datum/proximity_cell/P)
	if(P.eyes || P.near || length(P.members))
		return
	cells -= "[P.id]"

/// The cell id of a location, or null off the map.
/datum/system/proximity/proc/id_of(atom/location)
	var/turf/T = get_turf(location)
	if(!T)
		return null
	return PROXIMITY_CELL_KEY(T.z, PROXIMITY_CELL_COORD(T.x), PROXIMITY_CELL_COORD(T.y))

/// Adds `step` to the near count of the nine cells around (cx, cy) on z; a cell going near holds relevance on its members, one going far releases it.
/datum/system/proximity/proc/spread(z, cx, cy, step)
	for(var/dx in -1 to 1)
		for(var/dy in -1 to 1)
			var/nx = cx + dx
			var/ny = cy + dy
			if(nx < 0 || ny < 0 || nx > 255 || ny > 255)
				continue
			var/id = PROXIMITY_CELL_KEY(z, nx, ny)
			var/datum/proximity_cell/P = step > 0 ? cell_of(id, z, nx, ny) : cells["[id]"]
			if(!P)
				continue
			var/was = P.near
			P.near += step
			if(!was && P.near > 0)
				for(var/atom/movable/M as anything in P.members)
					hold(M, STAT_RELEVANCE, RELEVANCE_NEAR, P)
			else if(was > 0 && P.near <= 0)
				P.near = 0
				for(var/atom/movable/M as anything in P.members)
					release(M, STAT_RELEVANCE, P)
				cell_prune(P)

/// The client's eye is counted in the cell of get_turf(client.eye): call it after anything that can have moved it.
/datum/system/proximity/proc/eye_update(client/C)
	var/datum/proximity_eye/R = C.proximity_eye
	if(!R)
		R = new
		R.client = C
		C.proximity_eye = R
	eye_place(R, get_turf(C.eye))

/// The client left: its eye stops counting.
/datum/system/proximity/proc/eye_remove(client/C)
	var/datum/proximity_eye/R = C.proximity_eye
	if(!R)
		return
	eye_place(R, null)
	C.proximity_eye = null
	R.client = null

/// Counts the eye record `R` into the cell of `T` (none when null), leaving the cell it was in.
/datum/system/proximity/proc/eye_place(datum/proximity_eye/R, turf/T)
	var/id = T ? PROXIMITY_CELL_KEY(T.z, PROXIMITY_CELL_COORD(T.x), PROXIMITY_CELL_COORD(T.y)) : null
	if(id == R.cell_id)
		return
	if(!isnull(R.cell_id))
		var/datum/proximity_cell/old = cells["[R.cell_id]"]
		R.cell_id = null
		if(old)
			old.eyes--
			if(old.eyes <= 0)
				old.eyes = 0
				spread(old.z, old.cx, old.cy, -1)
				cell_prune(old)
	if(isnull(id))
		eyes -= R
		return
	var/datum/proximity_cell/P = cell_of(id, T.z, PROXIMITY_CELL_COORD(T.x), PROXIMITY_CELL_COORD(T.y))
	R.cell_id = id
	eyes |= R
	P.eyes++
	if(P.eyes == 1)
		spread(P.z, P.cx, P.cy, 1)

/// A tracked thing is in the world at `M`.loc (Initialize, Moved): files it in its cell and holds or releases relevance to match.
/datum/system/proximity/proc/member_update(atom/movable/M)
	var/on_turf = isturf(M.loc)
	var/id = on_turf ? id_of(M) : null
	if(filed[M] == (on_turf ? id : (M.loc ? PROXIMITY_CARRIED : null)))
		return
	member_leave(M)
	if(!on_turf)
		if(M.loc)
			hold(M, STAT_RELEVANCE, RELEVANCE_NEAR, carried)
			filed[M] = PROXIMITY_CARRIED
		return
	if(isnull(id))
		return
	var/turf/T = M.loc
	var/datum/proximity_cell/P = cell_of(id, T.z, PROXIMITY_CELL_COORD(T.x), PROXIMITY_CELL_COORD(T.y))
	LAZYADD(P.members, M)
	filed[M] = id
	if(P.near > 0)
		hold(M, STAT_RELEVANCE, RELEVANCE_NEAR, P)

/// A tracked thing leaves its cell (a move, its deletion).
/datum/system/proximity/proc/member_leave(atom/movable/M)
	var/where = filed[M]
	if(isnull(where))
		return
	filed -= M
	if(where == PROXIMITY_CARRIED)
		release(M, STAT_RELEVANCE, carried)
		return
	var/datum/proximity_cell/P = cells["[where]"]
	if(!P)
		return
	LAZYREMOVE(P.members, M)
	release(M, STAT_RELEVANCE, P)
	cell_prune(P)

/// How many cells the tracker holds (tests, the admin view).
/datum/system/proximity/proc/cell_count()
	return length(cells)


/// Opt a type in with `proximity_tracked = TRUE`: it holds RELEVANCE_NEAR while a client eye is within a cell of it.
/atom/movable
	/// TRUE: the tracker files this thing in its cell and holds STAT_RELEVANCE on it while a client is near (cosmetic or ambient periodics only).
	var/proximity_tracked = FALSE // ALLOW(base_vars): the movable base checks this one flag in Initialize and Moved to skip every untracked thing at no cost

/client
	/// This client's eye, counted into the cell grid.
	var/tmp/datum/proximity_eye/proximity_eye

/atom/movable/on_destroy(force)
	. = ..()
	if(proximity_tracked)
		SSproximity.member_leave(src)
