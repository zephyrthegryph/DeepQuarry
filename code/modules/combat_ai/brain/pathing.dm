// A* pathfinding integration for the brain.
//
// The legacy ai_holder stores the cached path on itself; we do the same on
// the brain. A search is a /datum/io/path request served by the path system (code/engine/io/path.dm), which runs the same
// /datum/pathfinding/astar the legacy holder used; the brain never waits for it. ID-card access is
// honoured so doors a mob can open are walked through instead of avoided.
//
// Behaviors that want smart movement call brain.smart_step_toward(target).
// Dumb behaviors keep using step_to() and pay nothing for the pathing infra.

/// Backoff after a failed A*: first retry after MIN, doubling per consecutive
/// failure up to MAX. Without this an unreachable goal costs one pathfind per
/// 250ms fast tick for every mob chasing it.
#define DQ_PATH_BACKOFF_MIN (1 SECOND)
#define DQ_PATH_BACKOFF_MAX (8 SECONDS)

/datum/ai_brain
	/// Cached A* path. List of turfs from current position to path_goal.
	var/list/planned_path = null
	/// Turf the cached path was computed to. Recomputed when target moves far.
	var/tmp/turf/path_goal
	/// Consecutive failed step attempts. After 3 we recompute.
	var/failed_steps = 0
	/// How far the goal can drift before recompute. Keeps us from recomputing
	/// every tick when chasing a moving target.
	var/path_recompute_tolerance = 2
	var/path_navigation_revision = 0
	/// world.time before which a failed A* toward (roughly) the same goal is
	/// not retried. Zero when the last pathfind succeeded.
	EXPIRY_DECLARE(next_path_attempt_at)
	/// Current failure backoff (deciseconds); grows with consecutive failures.
	var/path_fail_backoff = 0
	/// TRUE while a /datum/io/path request for this brain is open: only one is, and the brain steps directly meanwhile.
	var/path_pending = FALSE

/datum/ai_brain/proc/clear_path()
	planned_path = null
	rel_clear(src, nameof(path_goal))
	failed_steps = 0

/// Asks the path system for a path from the holder to `goal`. The answer arrives in have_path().
/datum/ai_brain/proc/request_path(turf/goal, min_dist = 1, max_path = 128)
	var/turf/start = get_turf(holder)
	if(!start || !goal)
		return FALSE
	var/obj/item/card/id/potential_id = holder.GetIdCard()
	path_pending = TRUE
	open_request(src, /datum/io/path, PROC_REF(have_path), start = start, goal = goal, mover = holder, target_distance = min_dist, max_path_length = max_path * 2, access = potential_id?.access?.Copy())
	return TRUE

/// The path system's answer (or its refusal): the cached path, or the failure backoff.
/datum/ai_brain/proc/have_path(datum/act/request/A)
	path_pending = FALSE
	var/datum/io/path/R = A.request
	var/turf/target_turf = R.goal
	if(!holder || QDELETED(holder))
		return
	planned_path = A.answer ? R.path : null
	rel_set(src, nameof(path_goal), target_turf)
	path_navigation_revision = GLOB.ai_navigation_revision
	failed_steps = 0
	if(!length(planned_path))
		path_fail_backoff = path_fail_backoff ? min(path_fail_backoff * 2, DQ_PATH_BACKOFF_MAX) : DQ_PATH_BACKOFF_MIN
		EXPIRY_SET(src, next_path_attempt_at, path_fail_backoff, CLOCK_WORLD)
		dqai_log("[holder] brain: A* to [target_turf] failed, backing off [path_fail_backoff]ds")
		return
	path_fail_backoff = 0
	next_path_attempt_at = 0

/// One smart step toward an atom. Re-uses a cached path when the goal is
/// close to the previous goal; recomputes otherwise. Returns TRUE if the mob
/// moved this call, FALSE if the path is exhausted or movement failed.
/datum/ai_brain/proc/smart_step_toward(atom/target, get_to = 1)
	if(!target || !holder)
		clear_path()
		return FALSE
	var/turf/target_turf = get_turf(target)
	if(!target_turf || target_turf.z != holder.z)
		clear_path()
		return FALSE

	// A pack of several members shares one flow field per goal (pack/flowfield.dm): a member the field covers steps along it and never searches.
	if(pack?.shares_paths())
		if(get_to > 0 && get_dist(holder, target_turf) <= get_to)
			return FALSE
		var/turf/shared_next = pack.flow_step(src, target_turf)
		if(shared_next)
			holder.face_atom(shared_next)
			var/turf/shared_from = get_turf(holder)
			act_step(shared_next)
			if(get_turf(holder) != shared_from)
				failed_steps = 0
				return TRUE

	// Recompute if no cached path, goal moved too far, or we keep failing.
	var/need_recompute = !length(planned_path)
	if(!need_recompute && path_goal() && get_dist(path_goal(), target_turf) > path_recompute_tolerance)
		need_recompute = TRUE
	if(!need_recompute && failed_steps >= 3)
		need_recompute = TRUE
	if(!need_recompute && path_navigation_revision != GLOB.ai_navigation_revision)
		need_recompute = TRUE
	if(need_recompute)
		// A recent A* to this same goal (same nav revision, goal hasn't
		// drifted) came back empty: honour the backoff instead of recomputing
		// on every fast tick. A moved goal or a map change retries at once.
		if(next_path_attempt_at && BEFORE(src, next_path_attempt_at, CLOCK_WORLD) \
			&& path_goal() && get_dist(path_goal(), target_turf) <= path_recompute_tolerance \
			&& path_navigation_revision == GLOB.ai_navigation_revision)
			return FALSE
		if(path_pending)
			return FALSE
		// The answer lands in have_path(): at once when the path system has the tick to search in (the request is already
		// answered when it returns), else a few ticks later, and until then the caller steps directly.
		request_path(target_turf, get_to)
		if(path_pending || !length(planned_path))
			return FALSE

	// Strip any path entries we've already reached (mob moved by other means).
	while(length(planned_path) && planned_path[1] == get_turf(holder))
		planned_path.Cut(1, 2)
	if(!length(planned_path))
		clear_path()
		return FALSE

	var/turf/next = planned_path[1]
	if(get_dist(holder, next) > 1)
		// Path desynced — recompute next tick.
		failed_steps++
		return FALSE
	holder.face_atom(next)
	var/old_loc = get_turf(holder)
	act_step(next)
	if(get_turf(holder) != old_loc)
		planned_path.Cut(1, 2)
		failed_steps = 0
		return TRUE
	failed_steps++
	return FALSE

/// the path_goal this refers to (a relation view: null once it is deleted).
/datum/ai_brain/proc/path_goal() as /turf
	return path_goal
