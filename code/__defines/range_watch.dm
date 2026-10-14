// The range watcher (code/datums/range_watch.dm, code/datums/connect_range.dm): what happens on the turfs around an atom.

/// Something entered a turf in range: the listener's proc is called as x(turf, arrived, old_loc).
#define RANGE_ENTERED "range_entered"
/// Something left a turf in range: x(turf, gone, new_loc).
#define RANGE_EXITED "range_exited"
/// Something was created on a turf in range: x(turf, created, mapload).
#define RANGE_INITIALIZED "range_initialized"

/// Watchers are kept in a grid of 2^N-turf buckets per z-level; a turf looks at its own bucket only.
#define RANGE_BUCKET_SHIFT 3
/// A watcher remembers each bucket it is in as one number: z * 1000000 + bucket x * 1000 + bucket y (a bucket coordinate stays under 1000: 8000 turfs a side).
#define RANGE_BUCKET_KEY(z, bx, by) ((z) * 1000000 + (bx) * 1000 + (by))

/// Tells the watchers around turf `src` that `kind` happened. A turf with nobody watching the world costs one global read.
#define RANGE_WATCH(location, kind, thing, other) if(GLOB.range_watch_count && isturf(location)) { range_watch_notify(location, kind, thing, other) }
