/**
 * For seeing if we can actually move between 2 given turfs while accounting for our access and the proc_caller's pass_flags
 *
 * Arguments:
 * * proc_caller: The movable, if one exists, being used for mobility checks to see what tiles it can reach
 * * ID: An ID card that decides if we can gain access to doors that would otherwise block a turf
 * * simulated_only: Do we only worry about turfs with simulated atmos, most notably things that aren't space?
*/
/turf/proc/LinkBlockedWithAccess(turf/destination_turf, proc_caller, ID)
	var/static/datum/pathfinding/whatever = new
	return !global.default_pathfinding_adjacency(src, destination_turf, GLOB.generic_pathfinding_actor, whatever)
