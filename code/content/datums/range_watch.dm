// The range watcher's grid (doc/rewrite/final_api.html section 10, "Announcing and observing"; the cheap observer of what happens around an atom).
//
// A scanner that wants to hear about everything entering, leaving or appearing within range 10 of it used to hook three events on each of the 441
// turfs around it: about 1300 hooks per scanner, rebuilt on every step it took. A watcher is instead one entry in a grid of 8x8-turf buckets, kept per
// z-level: a range-10 watcher is in at most nine buckets and moving it is a handful of list writes. A turf that something enters, leaves or is created on
// reads its own bucket and asks each watcher in it whether the turf is in range (a square: the same rule RANGE_TURFS() had). The watcher's listener
// is called as x(turf, thing, other) (RANGE_ENTERED, RANGE_EXITED, RANGE_INITIALIZED in code/__defines/range_watch.dm).
//
// Nothing here ends by itself: the /datum/connect_range that registers a watcher ends it when it is deleted (lifecycle_prerelease) or when what it
// tracks is, and a world with no watchers pays one read of GLOB.range_watch_count per movement.

/// The grid: [z] -> [bucket x + 1] -> [bucket y + 1] -> list of the /datum/connect_range watchers whose range overlaps that bucket. Plain indexed lists (a number
/// is an index, never an assoc key), grown as watchers appear and null where nobody watches.
GLOBAL_LIST_EMPTY(range_watch_grid)
/// How many watchers are in the grid right now (the movement hot path reads this and nothing else when it is zero).
GLOBAL_VAR_INIT(range_watch_count, 0)

/// The watchers list of bucket (z, bx, by), or null when there is none; `create` makes it (and the lists on the way to it).
/proc/range_watch_cell(z, bx, by, create = FALSE)
	var/list/planes = GLOB.range_watch_grid
	if(z > length(planes))
		if(!create)
			return null
		planes.len = z
	var/list/columns = planes[z]
	if(!columns)
		if(!create)
			return null
		columns = list()
		planes[z] = columns
	if(bx + 1 > length(columns))
		if(!create)
			return null
		columns.len = bx + 1
	var/list/cells = columns[bx + 1]
	if(!cells)
		if(!create)
			return null
		cells = list()
		columns[bx + 1] = cells
	if(by + 1 > length(cells))
		if(!create)
			return null
		cells.len = by + 1
	var/list/watchers = cells[by + 1]
	if(!watchers && create)
		watchers = list()
		cells[by + 1] = watchers
	return watchers

/// Tells the watchers in range of `location` (a turf) that `kind` happened to `thing`. RANGE_WATCH() guards the call.
/proc/range_watch_notify(turf/location, kind, atom/movable/thing, other)
	var/list/bucket = range_watch_cell(location.z, location.x >> RANGE_BUCKET_SHIFT, location.y >> RANGE_BUCKET_SHIFT)
	if(!length(bucket))
		return
	for(var/datum/connect_range/watcher as anything in bucket.Copy())
		watcher.notify(location, kind, thing, other)
