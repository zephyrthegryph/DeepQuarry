//* This file is explicitly licensed under the MIT license. *//
//* Copyright (c) 2023 Citadel Station developers.          *//

/**
 * be aware that this emits a set of disjunct nodes
 * use [jps_output_turfs()] to convert them into a proper turf path list.
 *
 * Please see [code/__HELPERS/pathfinding/jps.dm] for details on what JPS does/is.
 */
/proc/path_jps(atom/movable/actor = GLOB.generic_pathfinding_actor, turf/goal, turf/start = get_turf(actor), target_distance = 1, max_path_length = 128)
	var/datum/pathfinding/jps/instance = new(actor, start, goal, target_distance, max_path_length)
	return SSpathing.run_pathfinding(instance)

/**
 * Please see [code/__HELPERS/pathfinding/astar.dm] for details on what JPS does/is.
 */
/proc/path_astar(atom/movable/actor = GLOB.generic_pathfinding_actor, turf/goal, turf/start = get_turf(actor), target_distance = 1, max_path_length = 128)
	var/datum/pathfinding/astar/instance = new(actor, start, goal, target_distance, max_path_length)
	return SSpathing.run_pathfinding(instance)

//default_ai_pathfinding was a /datum/ai_brain helper. The modern
// brain has its own wrapper in code/modules/combat_ai/brain/pathing.dm
// (`dq_pathfind`). The legacy proc has no remaining callers and is removed.

/proc/path_for_circuit(obj/item/electronic_assembly/assembly, turf/goal, min_dist = 1, max_path = 128, list/access)
	var/datum/pathfinding/jps/instance = new(assembly, get_turf(assembly), goal, min_dist, max_path)
	instance.ss13_with_access = access.Copy()
	return jps_output_turfs(SSpathing.run_pathfinding(instance))

/proc/path_for_bot(mob/living/bot/bot, turf/goal, min_dist = 1, max_path = 128)
	var/turf/start = get_turf(bot)
	if(!istype(start) || !istype(goal) || start.z != goal.z)
		return null
	var/datum/pathfinding/jps/instance = new(bot, start, goal, min_dist, max_path)
	instance.ss13_with_access = bot.botcard.access?.Copy()
	return jps_output_turfs(SSpathing.run_pathfinding(instance))

/proc/astar_debug(mob/user, turf/target)
	if(isnull(target))
		return
	return path_astar(user, target, get_turf(user))

/proc/jps_debug(mob/user, turf/target)
	if(isnull(target))
		return
	return path_jps(user, target, get_turf(user))

/proc/old_astar_debug(mob/user, turf/target)
	if(isnull(target))
		return
	return graph_astar(get_turf(user), target, TYPE_PROC_REF(/turf, CardinalTurfsWithAccess), TYPE_PROC_REF(/turf, Distance), 0, 128, 1)

/proc/pathfinding_run_all(turf/start = get_turf(usr), turf/goal)
	var/pass_silicons_astar = path_astar(goal = goal, start = start, target_distance = 1, max_path_length = 256)
	var/pass_silicons_jps = path_jps(goal = goal, start = start, target_distance = 1, max_path_length = 256)
	// old astar has been cut because it's such horrible code it's not worth benchmarking against the other 3.
	// var/pass_old_astar = graph_astar(
	// 	start,
	// 	goal,
	// 	TYPE_PROC_REF(/turf, CardinalTurfsWithAccess),
	// 	TYPE_PROC_REF(/turf, Distance),
	// 	0,
	// 	128,
	// 	1,
	// )
	pass_silicons_astar = !!length(pass_silicons_astar)
	pass_silicons_jps = !!length(pass_silicons_jps)
	if(pass_silicons_astar != pass_silicons_jps)
		log_and_message_admins("turf pair [COORD(start)], [COORD(goal)] mismatch silicons-astar [pass_silicons_astar] silicons-jps [pass_silicons_jps]")
	else
		log_and_message_admins("turf pair [COORD(start)], [COORD(goal)] succeeded")

/proc/pathfinding_run_benchmark(times = 1000, turf/source = get_turf(usr))
	var/list/turf/nearby = RANGE_TURFS(100, source)
	for(var/i in 1 to min(times, 10000))
		var/turf/picked = pick(nearby)
		pathfinding_run_all(source, picked)
