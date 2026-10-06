//* This file is explicitly licensed under the MIT license. *//
//* Copyright (c) 2023 Citadel Station developers.          *//

/// visualization; obviously slow as hell
// #define ASTAR_DEBUGGING

#ifdef ASTAR_DEBUGGING

#warn ASTAR pathfinding visualizations enabled
/// visualization delay
GLOBAL_VAR_INIT(astar_visualization_delay, 0.05 SECONDS)
/// how long to persist the visuals
GLOBAL_VAR_INIT(astar_visualization_persist, 3 SECONDS)
#define ASTAR_VISUAL_COLOR_CLOSED "#ff4444"
#define ASTAR_VISUAL_COLOR_OUT_OF_BOUNDS "#555555"
#define ASTAR_VISUAL_COLOR_OPEN "#4444ff"
#define ASTAR_VISUAL_COLOR_CURRENT "#ffff00"
#define ASTAR_VISUAL_COLOR_FOUND "#00ff00"

#define ASTAR_TRACE_COLOR_REDIRECTED "#7777ff"

/proc/astar_wipe_colors_after(list/turf/turfs, time)
	after(null, time, /proc/astar_wipe_colors_now, with = list(turfs))

/proc/astar_wipe_colors_now(list/turf/turfs)
	for(var/turf/T in turfs)
		T.color = null
		T.maptext = null
		T.overlays.len = 0

/proc/get_astar_scan_overlay(dir, forwards, color)
	var/image/I = new
	I.icon = icon('icons/screen/debug/pathfinding.dmi', "jps_scan", dir)
	I.appearance_flags = KEEP_APART | RESET_ALPHA | RESET_COLOR | RESET_TRANSFORM
	I.plane = OBJ_PLANE
	I.color = color
	if(dir & NORTH)
		I.pixel_y = forwards? 16 : -16
	else if(dir & SOUTH)
		I.pixel_y = forwards? -16 : 16
	if(dir & EAST)
		I.pixel_x = forwards? 16 : -16
	else if(dir & WEST)
		I.pixel_x = forwards? -16 : 16
	return I

#endif

/// this is almost a megabyte
#define ASTAR_SANE_NODE_LIMIT 15000

// Search nodes are plain lists local to one search (LC-refs: nothing keeps a turf or a
// parent node past the search): list(pos, prev, score, weight, depth, cost).
#define ASTAR_NODE_POS 1
#define ASTAR_NODE_PREV 2
#define ASTAR_NODE_SCORE 3
#define ASTAR_NODE_WEIGHT 4
#define ASTAR_NODE_DEPTH 5
#define ASTAR_NODE_COST 6
#define ASTAR_NODE_NEW(pos, prev, score, weight, depth, cost) list(pos, prev, score, weight, depth, cost)

/proc/cmp_astar_node(list/A, list/B)
	return A[ASTAR_NODE_SCORE] - B[ASTAR_NODE_SCORE]

#define ASTAR_HEURISTIC_CALL(TURF) (isnull(context)? call(heuristic_call)(TURF, goal) : call(context, heuristic_call)(TURF, goal))
#define ASTAR_ADJACENCY_CALL(A, B) (isnull(context)? call(adjacency_call)(A, B, actor, src) : call(context, adjacency_call)(A, B, actor, src))
#define ASTAR_HEURISTIC_WEIGHT 1.2
#ifdef ASTAR_DEBUGGING
	#define ASTAR_HELL_DEFINE(TURF, DIR) \
		if(!isnull(TURF)) { \
			if(ASTAR_ADJACENCY_CALL(current, considering)) { \
				considering_cost = top[ASTAR_NODE_COST] + considering.path_weight; \
				considering_score = ASTAR_HEURISTIC_CALL(considering) * ASTAR_HEURISTIC_WEIGHT + considering_cost; \
				considering_node = node_by_turf[considering]; \
				if(isnull(considering_node)) { \
					considering_node = ASTAR_NODE_NEW(considering, top, considering_score, considering_cost, top[ASTAR_NODE_DEPTH] + 1, considering_cost); \
					open.enqueue(considering_node); \
					node_by_turf[considering] = considering_node; \
					turfs_got_colored[considering] = TRUE; \
					after(considering, debug_t, TYPE_PROC_REF(/atom, set_base_color), with = list(ASTAR_VISUAL_COLOR_OPEN)); \
					considering.maptext = MAPTEXT("[top[ASTAR_NODE_DEPTH] + 1], [considering_cost], [considering_score]"); \
					considering.overlays += get_astar_scan_overlay(DIR); \
				} \
				else { \
					if(considering_node[ASTAR_NODE_COST] > considering_cost) { \
						considering_node[ASTAR_NODE_COST] = considering_cost; \
						considering_node[ASTAR_NODE_DEPTH] = top[ASTAR_NODE_DEPTH] + 1; \
						considering.maptext = MAPTEXT("X [top[ASTAR_NODE_DEPTH] + 1], [considering_cost], [considering_score]"); \
						considering.overlays += get_astar_scan_overlay(DIR, TRUE, ASTAR_TRACE_COLOR_REDIRECTED); \
						considering_node[ASTAR_NODE_PREV] = top; \
					} \
				} \
			} \
		}
#else
	#define ASTAR_HELL_DEFINE(TURF, DIR) \
		if(!isnull(TURF)) { \
			if(ASTAR_ADJACENCY_CALL(current, considering)) { \
				considering_cost = top[ASTAR_NODE_COST] + considering.path_weight; \
				considering_score = ASTAR_HEURISTIC_CALL(considering) * ASTAR_HEURISTIC_WEIGHT + considering_cost; \
				considering_node = node_by_turf[considering]; \
				if(isnull(considering_node)) { \
					considering_node = ASTAR_NODE_NEW(considering, top, considering_score, considering_cost, top[ASTAR_NODE_DEPTH] + 1, considering_cost); \
					open.enqueue(considering_node); \
					node_by_turf[considering] = considering_node; \
				} \
				else { \
					if(considering_node[ASTAR_NODE_COST] > considering_cost) { \
						considering_node[ASTAR_NODE_COST] = considering_cost; \
						considering_node[ASTAR_NODE_DEPTH] = top[ASTAR_NODE_DEPTH] + 1; \
						considering_node[ASTAR_NODE_PREV] = top; \
					} \
				} \
			} \
		}
#endif

/**
 * AStar
 * * Non uniform grids
 * * Slower than JPS
 * * Inherently cardinals-only
 * * Node limit is manhattan, so 128 is a lot less than BYOND's get_dist(128).
 */
/datum/pathfinding/astar
#ifdef ASTAR_DEBUGGING
	/// Replay time (deciseconds) of the search visualisation: each step lands this long after the search started.
	var/debug_t = 0
#endif

/datum/pathfinding/astar/search()
	var/turf/start = search_start()
	ASSERT(isturf(start) && isturf(search_goal()) && start.z == search_goal().z)
	if(start == search_goal())
		return list()
	// too far away
	if(get_manhattan_dist(start, search_goal()) > max_path_length)
		return null
	#ifdef ASTAR_DEBUGGING
	var/list/turf/turfs_got_colored = list()
	#endif
	// cache for sanic speed
	var/max_depth = src.max_path_length
	var/turf/goal = search_goal()
	var/target_distance = src.target_distance
	var/atom/movable/actor = search_actor()
	var/adjacency_call = src.adjacency_call
	var/heuristic_call = src.heuristic_call
	var/datum/context = search_context()
	// add operating vars
	var/turf/current
	var/turf/considering
	var/considering_score
	var/considering_cost
	var/list/considering_node
	var/list/node_by_turf = list()
	// make queue
	var/datum/priority_queue/open = new /datum/priority_queue(/proc/cmp_astar_node)
	// add initial node
	var/list/initial_node = ASTAR_NODE_NEW(start, null, ASTAR_HEURISTIC_CALL(start), 0, 0, 0)
	open.enqueue(initial_node)
	node_by_turf[start] = initial_node

	#ifdef ASTAR_DEBUGGING
	turfs_got_colored[start] = TRUE
	after(start, debug_t, TYPE_PROC_REF(/atom, set_base_color), with = list(ASTAR_VISUAL_COLOR_OPEN))
	#endif

	while(length(open.array))
		// get best node
		var/list/top = open.dequeue()
		current = top[ASTAR_NODE_POS]
		#ifdef ASTAR_DEBUGGING
		after(top[ASTAR_NODE_POS], debug_t, TYPE_PROC_REF(/atom, set_base_color), with = list(ASTAR_VISUAL_COLOR_CURRENT))
		turfs_got_colored[top[ASTAR_NODE_POS]] = TRUE
		debug_t += GLOB.astar_visualization_delay // the replay moves on a step (after(), no sleep)
		#else
		CHECK_TICK
		#endif

		// get distance and check completion
		if(get_dist(current, goal) <= target_distance && (target_distance != 1 || !require_adjacency_when_going_adjacent || current.TurfAdjacency(goal)))
			// found; build path end to start of nodes
			var/list/path_built = list()
			while(top)
				path_built += top[ASTAR_NODE_POS]
				#ifdef ASTAR_DEBUGGING
				after(top[ASTAR_NODE_POS], debug_t, TYPE_PROC_REF(/atom, set_base_color), with = list(ASTAR_VISUAL_COLOR_FOUND))
				turfs_got_colored[top] = TRUE
				#endif
				top = top[ASTAR_NODE_PREV]
			// reverse
			var/head = 1
			var/tail = length(path_built)
			while(head < tail)
				path_built.Swap(head++, tail--)
			#ifdef ASTAR_DEBUGGING
			astar_wipe_colors_after(turfs_got_colored, GLOB.astar_visualization_persist + debug_t)
			#endif
			return path_built

		// too deep, abort
		if(top[ASTAR_NODE_DEPTH] + get_dist(current, goal) > max_depth)
			#ifdef ASTAR_DEBUGGING
			after(top[ASTAR_NODE_POS], debug_t, TYPE_PROC_REF(/atom, set_base_color), with = list(ASTAR_VISUAL_COLOR_OUT_OF_BOUNDS))
			turfs_got_colored[top[ASTAR_NODE_POS]] = TRUE
			#endif
			continue

		considering = get_step(current, NORTH)
		ASTAR_HELL_DEFINE(considering, NORTH)
		considering = get_step(current, SOUTH)
		ASTAR_HELL_DEFINE(considering, SOUTH)
		considering = get_step(current, EAST)
		ASTAR_HELL_DEFINE(considering, EAST)
		considering = get_step(current, WEST)
		ASTAR_HELL_DEFINE(considering, WEST)

		#ifdef ASTAR_DEBUGGING
		after(top[ASTAR_NODE_POS], debug_t, TYPE_PROC_REF(/atom, set_base_color), with = list(ASTAR_VISUAL_COLOR_CLOSED))
		turfs_got_colored[top[ASTAR_NODE_POS]] = TRUE
		#endif

		if(length(open.array) > ASTAR_SANE_NODE_LIMIT)
			#ifdef ASTAR_DEBUGGING
			astar_wipe_colors_after(turfs_got_colored, GLOB.astar_visualization_persist + debug_t)
			#endif
			CRASH("A* hit node limit - something went horribly wrong! args: [json_encode(args)]; vars: [json_encode(vars)]")

	#ifdef ASTAR_DEBUGGING
	astar_wipe_colors_after(turfs_got_colored, GLOB.astar_visualization_persist + debug_t)
	#endif

#undef ASTAR_HELL_DEFINE
#undef ASTAR_HEURISTIC_CALL
#undef ASTAR_ADJACENCY_CALL

#undef ASTAR_SANE_NODE_LIMIT
#undef ASTAR_HEURISTIC_WEIGHT

#ifdef ASTAR_DEBUGGING
	#undef ASTAR_DEBUGGING

	#undef ASTAR_VISUAL_COLOR_CLOSED
	#undef ASTAR_VISUAL_COLOR_OPEN
	#undef ASTAR_VISUAL_COLOR_CURRENT
	#undef ASTAR_VISUAL_COLOR_FOUND
#endif

#undef ASTAR_NODE_POS
#undef ASTAR_NODE_PREV
#undef ASTAR_NODE_SCORE
#undef ASTAR_NODE_WEIGHT
#undef ASTAR_NODE_DEPTH
#undef ASTAR_NODE_COST
#undef ASTAR_NODE_NEW
