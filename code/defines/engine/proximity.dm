/// Edge of one client-proximity cell, in turfs. A cell with a client eye in it, and the eight around it, hold RELEVANCE_NEAR on the tracked things in them.
#define PROXIMITY_CELL_SIZE 8
/// The filed value of a tracked thing that is carried.
#define PROXIMITY_CARRIED "carried"
#define PROXIMITY_CELL_COORD(v) (round(((v) - 1) / PROXIMITY_CELL_SIZE))
#define PROXIMITY_CELL_KEY(z, cx, cy) ((((z) * 256) + (cy)) * 256 + (cx))
/// Milliseconds of members held or released a tick for the cells a client's step woke or let go (reconcile_run()), and the cell that takes this long (ms) is traced.
#define PROXIMITY_RECONCILE_BUDGET_MS 3
#define PROXIMITY_RECONCILE_SLOW_MS 5
