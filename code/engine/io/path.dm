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

#define PATHFINDER_TIMEOUT 50
/// A cached failure is also dropped after this long, because not every map edit bumps the navigation revision.
#define PATHFINDER_FAILURE_TTL (30 SECONDS)
/// The failure cache is emptied when it grows past this many entries.
#define PATHFINDER_FAILURE_CACHE_MAX 2048

// The synchronous search: a caller that cannot wait for a request answer (a bot step, a circuit) searches in its own stack under
// one mutex. Multi "threading" in BYOND only adds overhead, so one search runs at a time and the rest wait (stoplag) up to PATHFINDER_TIMEOUT.
/datum/system/pathing

	/// pathfinding mutex - most algorithms depend on this
	/// multi "threading" in byond just adds overhead
	/// from everything trying to re-queue their executions
	/// for this reason, much like with maploading,
	/// it's somewhat pointless to have more than one operation going
	/// at a time
	var/pathfinding_mutex = FALSE
	/// pathfinding calls blocked
	var/pathfinding_blocked = 0
	/// pathfinding cycle - this is usable because of the mutex
	/// this is used in place of a closed list in algorithms like JPS
	/// to maximize performance.
	var/tmp/pathfinding_cycle = 0
	/// Failed search key -> list(GLOB.ai_navigation_revision, world.time) when it failed (Q9).
	var/list/failed_searches
	/// Searches answered from failed_searches.
	var/failure_cache_hits = 0

/// Waits for the search mutex. Returns FALSE if it is still held after `timeout`. pathfinding_blocked
/// counts the callers waiting here; the only exit from this proc is the bottom, so it is always put back.
/datum/system/pathing/proc/wait_for_mutex(started_at, timeout = PATHFINDER_TIMEOUT)
	++pathfinding_blocked
	// Many waiters back off further, so a pile-up does not turn into a stoplag storm.
	var/backoff = pathfinding_blocked < 10 ? 1 : 3
	. = TRUE
	while(pathfinding_mutex)
		stoplag(backoff) // ALLOW(scheduler): mutex held across the search's CHECK_TICK yields
		if(ELAPSED_SINCE(src, started_at, CLOCK_WORLD) > timeout)
			. = FALSE
			break
	--pathfinding_blocked

/datum/system/pathing/proc/run_pathfinding(datum/pathfinding/instance)
	var/started_at = world.time
	if(!wait_for_mutex(started_at))
		stack_trace("pathfinder timeout; check debug logs.")
		log_runtime("pathfinder timeout of instance with debug variables [instance.debug_log_string()]")
		return null
	var/failure_key = instance.failure_cache_key()
	var/navigation_revision = GLOB.ai_navigation_revision
	if(failure_key)
		var/list/failure = LAZYACCESS(failed_searches, failure_key)
		if(failure)
			if(failure[1] == navigation_revision && ELAPSED_SINCE(src, failure[2], CLOCK_WORLD) < PATHFINDER_FAILURE_TTL)
				failure_cache_hits++
				return null
			LAZYREMOVE(failed_searches, failure_key)
	pathfinding_mutex = TRUE
	try
		. = instance.search()
	catch(var/exception/search_error)
		// A search that runtimes must not leave the mutex held: every later request would wait out
		// the timeout and get nothing. The caller still sees the original exception.
		pathfinding_mutex = FALSE
		throw search_error
	pathfinding_mutex = FALSE
	if(ELAPSED_SINCE(src, started_at, CLOCK_WORLD) > PATHFINDER_TIMEOUT)
		stack_trace("pathfinder timeout; check debug logs.")
		log_runtime("pathfinder timeout of instance with debug variables [instance.debug_log_string()]")
	if(failure_key && !length(.))
		if(LAZYLEN(failed_searches) >= PATHFINDER_FAILURE_CACHE_MAX)
			failed_searches = null
		LAZYSET(failed_searches, failure_key, list(navigation_revision, world.time))

/datum/system/pathing/proc/enqueue(datum/io/path/R)
	queue += R // ALLOW(ownership): the kernel's own queue, appended and drained by this system only
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
	return run_pathfinding(instance)

/datum/system/pathing/metrics()
	. = ..()
	.["queued"] = length(queue)
	.["searched"] = searched
	.["found"] = found
	.["dropped"] = dropped
