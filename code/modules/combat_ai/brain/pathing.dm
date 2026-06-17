// A* pathfinding integration for the brain.
//
// The legacy ai_holder stores the cached path on itself; we do the same on
// the brain. SSpathfinder is reused via dq_pathfind(), which wraps the same
// /datum/pathfinding/astar instance the legacy holder used. ID-card access is
// honoured so doors a mob can open are walked through instead of avoided.
//
// Behaviors that want smart movement call brain.smart_step_toward(target).
// Dumb behaviors keep using step_to() and pay nothing for the pathing infra.

/datum/ai_brain
	/// Cached A* path. List of turfs from current position to path_goal.
	var/list/cached_path = null
	/// Turf the cached path was computed to. Recomputed when target moves far.
	var/turf/path_goal = null
	/// Consecutive failed step attempts. After 3 we recompute.
	var/failed_steps = 0
	/// How far the goal can drift before recompute. Keeps us from recomputing
	/// every tick when chasing a moving target.
	var/path_recompute_tolerance = 2

/datum/ai_brain/proc/clear_path()
	cached_path = null
	path_goal = null
	failed_steps = 0

/proc/dq_pathfind(mob/living/actor, turf/goal, min_dist = 1, max_path = 64)
	if(!actor || !goal)
		return null
	// Never stoplag-wait on the global pathfinder. A search yields via CHECK_TICK
	// while holding pathfinding_mutex, so waiting on it serializes the whole AI
	// tick behind one mob — the "only one mob moves at a time, ~1 step/second"
	// stall. If the pathfinder is mid-search, skip A* this tick; the caller falls
	// back to a cheap step and retries next tick. One short A* runs per free tick
	// instead of a stoplag pileup.
	if(SSpathfinder.pathfinding_mutex)
		return null
	var/datum/pathfinding/astar/instance = new(actor, get_turf(actor), goal, min_dist, max_path * 2)
	var/obj/item/card/id/potential_id = actor.GetIdCard()
	if(!isnull(potential_id))
		instance.ss13_with_access = potential_id.access?.Copy()
	return SSpathfinder.run_pathfinding(instance)

/// One smart step toward an atom. Re-uses a cached path when the goal is
/// close to the previous goal; recomputes otherwise. Returns TRUE if the mob
/// moved this call, FALSE if the path is exhausted or movement failed.
/datum/ai_brain/proc/smart_step_toward(atom/target, get_to = 1)
	if(!target || !holder || holder.anchored) // anchored mobs can't path-move (Move() ignores anchored)
		clear_path()
		return FALSE
	if(world.time < holder.next_move) // honor the AI move cooldown (dq_ai_move_delay)
		return FALSE
	var/turf/target_turf = get_turf(target)
	if(!target_turf || target_turf.z != holder.z)
		clear_path()
		return FALSE

	// Recompute if no cached path, goal moved too far, or we keep failing.
	var/need_recompute = !length(cached_path)
	if(!need_recompute && path_goal && get_dist(path_goal, target_turf) > path_recompute_tolerance)
		need_recompute = TRUE
	if(!need_recompute && failed_steps >= 3)
		need_recompute = TRUE
	if(need_recompute)
		cached_path = dq_pathfind(holder, target_turf, get_to)
		path_goal = target_turf
		failed_steps = 0
		if(!length(cached_path))
			return FALSE

	// Strip any path entries we've already reached (mob moved by other means).
	while(length(cached_path) && cached_path[1] == get_turf(holder))
		cached_path.Cut(1, 2)
	if(!length(cached_path))
		clear_path()
		return FALSE

	var/turf/next = cached_path[1]
	if(get_dist(holder, next) > 1)
		// Path desynced — recompute next tick.
		failed_steps++
		return FALSE
	holder.face_atom(next)
	var/old_loc = get_turf(holder)
	dq_set_move_glide(holder) // glide one tile per tick so pathed movement animates smoothly too
	// `next` is guaranteed adjacent (checked above), so a direct step beats step_to()
	// — the latter re-runs BYOND's internal A* for what is only a one-tile move.
	step(holder, get_dir(holder, next))
	if(get_turf(holder) != old_loc)
		holder.setMoveCooldown(dq_ai_move_delay(holder)) // start the move cooldown
		cached_path.Cut(1, 2)
		failed_steps = 0
		return TRUE
	failed_steps++
	return FALSE
