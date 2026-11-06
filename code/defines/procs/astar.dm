//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/*
A Star pathfinding algorithm
Returns a list of tiles forming a path from A to B, taking dense objects as well as walls, and the orientation of
windows along the route into account.
Use:
your_list = AStar(start location, end location, adjacent turf proc, distance proc)
For the adjacent turf proc i wrote:
/turf/proc/AdjacentTurfs
And for the distance one i wrote:
/turf/proc/Distance
So an example use might be:

src.path_list = AStar(src.loc, target.loc, /turf/proc/AdjacentTurfs, /turf/proc/Distance)

Note: The path is returned starting at the END node, so i wrote reverselist to reverse it for ease of use.

src.path_list = reverselist(src.pathlist)

Then to start on the path, all you need to do it:
Step_to(src, src.path_list[1])
src.path_list -= src.path_list[1] or equivilent to remove that node from the list.

Optional extras to add on (in order):
MaxNodes: The maximum number of nodes the returned path can be (0 = infinite)
Maxnodedepth: The maximum number of nodes to search (default: 30, 0 = infinite)
Mintargetdist: Minimum distance to the target before path returns, could be used to get
near a target, but not right to it - for an AI mob with a gun, for example.
Minnodedist: Minimum number of nodes to return in the path, could be used to give a path a minimum
length to avoid portals or something i guess?? Not that they're counted right now but w/e.
*/

// Modified to provide ID argument - supplied to 'adjacent' proc, defaults to null
// Used for checking if route exists through a door which can be opened

// Also added 'exclude' turf to avoid travelling over; defaults to null


/datum/PriorityQueue
	var/list/queue
	var/comparison_function

/datum/PriorityQueue/New(compare)
	queue = list()
	comparison_function = compare

/datum/PriorityQueue/proc/IsEmpty()
	return !queue.len

/datum/PriorityQueue/proc/Enqueue(data)
	// Indexed append, not Add(): the entry is a search node list.
	queue.len++
	queue[queue.len] = data
	var/index = queue.len

	//From what I can tell, this automagically sorts the added data into the correct location.
	while(index > 2 && call(comparison_function)(queue[index / 2], queue[index]) > 0)
		queue.Swap(index, index / 2)
		index /= 2

/datum/PriorityQueue/proc/Dequeue()
	if(!queue.len)
		return 0
	return Remove(1)

/datum/PriorityQueue/proc/Remove(index)
	if(index > queue.len)
		return 0

	var/thing = queue[index]
	queue.Swap(index, queue.len)
	queue.Cut(queue.len)
	if(index < queue.len)
		FixQueue(index)
	return thing

/datum/PriorityQueue/proc/FixQueue(index)
	var/child = 2 * index
	var/item = queue[index]

	while(child <= queue.len)
		if(child < queue.len && call(comparison_function)(queue[child], queue[child + 1]) > 0)
			child++
		if(call(comparison_function)(item, queue[child]) > 0)
			queue[index] = queue[child]
			index = child
		else
			break
		child = 2 * index
	queue[index] = item

/datum/PriorityQueue/proc/List()
	return queue.Copy()

/datum/PriorityQueue/proc/Length()
	return queue.len

/datum/PriorityQueue/proc/RemoveItem(data)
	var/index = queue.Find(data)
	if(index)
		return Remove(index)

// Search nodes are plain lists local to one search (LC-refs: no datum holds a position or a
// parent reference past the search): list(position, parent node, best estimate, estimate,
// nodes traversed).
#define ASTAR_PATHNO_POS 1
#define ASTAR_PATHNO_PREV 2
#define ASTAR_PATHNO_BEST 3
#define ASTAR_PATHNO_EST 4
#define ASTAR_PATHNO_DEPTH 5
#define ASTAR_PATHNO_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)

/proc/PathWeightCompare(list/a, list/b)
	return a[ASTAR_PATHNO_EST] - b[ASTAR_PATHNO_EST]

/proc/AStar(start, end, adjacent, dist, max_nodes, max_node_depth = 30, min_target_dist = 0, min_node_dist, id, datum/exclude)
	var/datum/PriorityQueue/open = new /datum/PriorityQueue(/proc/PathWeightCompare)
	var/list/closed = list()
	var/list/path
	var/list/path_node_by_position = list()
	start = get_turf(start)
	if(!start)
		return 0

	open.Enqueue(ASTAR_PATHNO_NEW(start, null, 0, call(start, dist)(end), 0))

	while(!open.IsEmpty() && !path)
		var/list/current = open.Dequeue()
		closed.Add(current[ASTAR_PATHNO_POS])

		if(current[ASTAR_PATHNO_POS] == end || call(current[ASTAR_PATHNO_POS], dist)(end) <= min_target_dist)
			path = new /list(current[ASTAR_PATHNO_DEPTH] + 1)
			path[path.len] = current[ASTAR_PATHNO_POS]
			var/index = path.len - 1

			while(current[ASTAR_PATHNO_PREV])
				current = current[ASTAR_PATHNO_PREV]
				path[index--] = current[ASTAR_PATHNO_POS]
			break

		if(min_node_dist && max_node_depth)
			if(call(current[ASTAR_PATHNO_POS], min_node_dist)(end) + current[ASTAR_PATHNO_DEPTH] >= max_node_depth)
				continue

		if(max_node_depth)
			if(current[ASTAR_PATHNO_DEPTH] >= max_node_depth)
				continue

		for(var/datum/datum in call(current[ASTAR_PATHNO_POS], adjacent)(id))
			if(datum == exclude)
				continue

			var/best_estimated_cost = current[ASTAR_PATHNO_EST] + call(current[ASTAR_PATHNO_POS], dist)(datum)

			//handle removal of sub-par positions
			if(datum in path_node_by_position)
				var/list/target = path_node_by_position[datum]
				if(target[ASTAR_PATHNO_BEST])
					if(best_estimated_cost + call(datum, dist)(end) < target[ASTAR_PATHNO_BEST])
						open.RemoveItem(target)
					else
						continue

			var/list/next_node = ASTAR_PATHNO_NEW(datum, current, best_estimated_cost, call(datum, dist)(end), current[ASTAR_PATHNO_DEPTH] + 1)
			path_node_by_position[datum] = next_node
			open.Enqueue(next_node)

			if(max_nodes && open.Length() > max_nodes)
				open.Remove(open.Length())

	return path

#undef ASTAR_PATHNO_POS
#undef ASTAR_PATHNO_PREV
#undef ASTAR_PATHNO_BEST
#undef ASTAR_PATHNO_EST
#undef ASTAR_PATHNO_DEPTH
#undef ASTAR_PATHNO_NEW
