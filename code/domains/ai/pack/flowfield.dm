// Shared paths (doc/rewrite/ai_packs.md B3): a pack that sends several members at one goal builds one bounded flow field for it instead of each member
// searching for its own path.
//
// A field is a breadth-first distance map out from the goal turf over the turfs a mob can walk (open, not blocked by a dense object or a door), out to
// FLOW_RADIUS tiles. A member reads its next step from it: the neighbour with the smallest distance. The field is keyed by the goal and
// GLOB.ai_navigation_revision (a door opening or closing invalidates it), kept for FLOW_MAX_AGE, and reused while a moving goal stays within
// FLOW_GOAL_TOLERANCE tiles of the goal it was built for. A member the field does not cover (it is beyond the radius, or walled off in the field's
// view) gets null and falls back to the individual A* path. Only packs with more than one live member use fields; a pack of one is exactly the old path
// code.

#define FLOW_RADIUS 14
#define FLOW_MAX_AGE (10 SECONDS)
#define FLOW_GOAL_TOLERANCE 2
#define FLOW_MAX_FIELDS 3

/// Flow fields built since boot (tests read this).
GLOBAL_VAR_INIT(ai_pack_flow_builds, 0)

/datum/ai_pack
	/// Built fields, newest last (the pack owns them).
	var/list/flow_fields = null
	var/flow_builds = 0

/// One built field: the goal turf it was built for, the navigation revision it was built under, its distance map (turf => steps) and when.
/datum/flow_field
	var/turf/goal
	var/revision = 0
	var/list/dist
	var/built_at = 0

CAPABILITIES(/datum/flow_field)
	ref_one(nameof(goal), /turf)

/// Can a walker go from `origin` onto `dest`: open, no dense object on it (a window excepted), no door or window edge between them.
/proc/ai_flow_passable(turf/origin, turf/dest)
	if(!dest || dest.density)
		return FALSE
	if(TurfBlockedNonWindow(dest))
		return FALSE
	return !LinkBlocked(origin, dest)

/// The distance map for `goal`: the cached field when one is current, else built now. Null when the goal has no turf.
/datum/ai_pack/proc/flow_field_for(turf/goal)
	if(!goal)
		return null
	for(var/datum/flow_field/field as anything in flow_fields)
		var/turf/built_for = field.goal
		if(built_for.z == goal.z && get_dist(built_for, goal) <= FLOW_GOAL_TOLERANCE && field.revision == GLOB.ai_navigation_revision && ELAPSED(field, built_at, CLOCK_WORLD) < FLOW_MAX_AGE)
			return field.dist
	var/list/dist = list()
	dist[goal] = 0
	var/list/frontier = list(goal)
	var/head = 1
	while(head <= length(frontier))
		var/turf/cur = frontier[head++]
		var/steps = dist[cur]
		if(steps >= FLOW_RADIUS)
			continue
		for(var/dir in GLOB.alldirs)
			var/turf/next = get_step(cur, dir)
			if(!next || !isnull(dist[next]) || !ai_flow_passable(cur, next))
				continue
			dist[next] = steps + 1
			frontier += next
	flow_builds++
	GLOB.ai_pack_flow_builds++
	var/datum/flow_field/built = new
	rel_set(built, nameof(built.goal), goal)
	built.revision = GLOB.ai_navigation_revision
	built.dist = dist
	STAMP(built, built_at, CLOCK_WORLD)
	rel_add(src, nameof(flow_fields), built)
	while(length(flow_fields) > FLOW_MAX_FIELDS)
		rel_remove(src, nameof(flow_fields), flow_fields[1])
	trace("flow field built for [goal] (revision [GLOB.ai_navigation_revision]): [length(dist)] cell(s)")
	return dist

/// The turf `B` should step onto next on the way to `goal`, read from the shared field; null when the field does not cover B or has no better turf.
/datum/ai_pack/proc/flow_step(datum/ai_brain/B, turf/goal)
	var/turf/here = get_turf(B.get_owner())
	if(!here || !goal || here.z != goal.z)
		return null
	var/list/dist = flow_field_for(goal)
	var/here_steps = dist?[here]
	if(isnull(here_steps) || here_steps == 0)
		return null
	var/turf/best = null
	var/best_steps = here_steps
	for(var/dir in GLOB.alldirs)
		var/turf/next = get_step(here, dir)
		var/steps = next ? dist[next] : null
		if(isnull(steps) || steps >= best_steps || !ai_flow_passable(here, next))
			continue
		best = next
		best_steps = steps
	return best

/// TRUE when this pack shares paths for its members (more than one is alive).
/datum/ai_pack/proc/shares_paths()
	return length(members) > 1
