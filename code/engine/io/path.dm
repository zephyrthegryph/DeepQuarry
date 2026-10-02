// Paths as requests (doc/rewrite/final_api.html, section 2 "Chunked work and paths"; section 19 "E6").
//
//     open_request(bot, /datum/io/path, PROC_REF(have_path), start = get_turf(bot), goal = target_turf)
//
// /datum/io/path is a request kind served by the path system (SSpathing): each request is its own record, so the caller never
// takes a mutex and never spin-waits, and a bot's AI can be a non-sleeping every() step that reads A.request.path in its handler.
// The path system runs one search at a time on a detached worker (a search yields inside CHECK_TICK; only the kernel and the
// request layer may suspend, and this is that layer), oldest request first, dropping any whose owner has gone. A search that
// finds nothing ends REQ_NO_RESULT. The answer is the path, a list of turfs. The combat AI's brain asks for its paths this way
// (code/modules/combat_ai/brain/pathing.dm) and steps directly until the answer arrives.

/datum/io/path
	/// Where the search starts and what it wants to reach.
	var/turf/start
	var/turf/goal
	/// The mover whose size and access the search honours; null: a generic one.
	var/atom/movable/mover
	/// How close counts as there, and the longest path worth finding.
	var/target_distance = 1
	var/max_path_length = 128
	/// The access the mover carries, or null.
	var/list/access
	/// The answer: the turfs of the path, in order.
	var/list/path

/datum/io/path/begin()
	if(!istype(start) || !istype(goal) || start.z != goal.z)
		fail_transport("no path between those places")
		return
	SSpathing.enqueue(src)

SYSTEM_DEF(pathing)
	name = "Pathing"
	phase = KERNEL_PHASE_P
	latency_class = LATENCY_L1
	/// Open path requests, oldest first.
	var/list/queue = list()
	/// TRUE while the worker is searching.
	var/working = FALSE
	var/searched = 0
	var/found = 0
	var/dropped = 0

/datum/system/pathing/proc/enqueue(datum/io/path/R)
	queue += R
	if(!working)
		work()

/// The worker: searches the queued requests one after another, then rests until the next one.
/datum/system/pathing/proc/work()
	set waitfor = FALSE // ALLOW(scheduler): the path system's worker: a search yields inside CHECK_TICK, off every kernel phase
	working = TRUE
	while(length(queue))
		var/datum/io/path/R = queue[1]
		queue.Cut(1, 2)
		if(!R || !R.is_open() || QDELETED(R.owner))
			dropped++
			continue
		searched++
		var/list/found_path = search(R)
		if(!R.is_open())
			dropped++
			continue
		if(!length(found_path))
			request_end(R, REQ_NO_RESULT, null)
		else
			found++
			R.path = found_path
			request_end(R, REQ_ANSWERED, found_path)
		CHECK_TICK
	working = FALSE

/// One request's search through the pathfinder.
/datum/system/pathing/proc/search(datum/io/path/R)
	var/datum/pathfinding/astar/instance = new(R.mover || GLOB.generic_pathfinding_actor, R.start, R.goal, R.target_distance, R.max_path_length)
	if(R.access)
		instance.ss13_with_access = R.access.Copy()
	return om_pathfinder().run_pathfinding(instance)

/datum/system/pathing/metrics()
	. = ..()
	.["queued"] = length(queue)
	.["searched"] = searched
	.["found"] = found
	.["dropped"] = dropped
