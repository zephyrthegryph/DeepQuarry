// Sparse slots and cooldown tables: the declaration markers and accessors (procs in code/engine/declare/sparse_slots.dm).

/// Declares a sparse slot `name` on T (a value type with type =, documentation). The slot is read and written by sparse_get() / sparse_set().
#define sparse(T, name, params...)
/// Declares cooldown names on the type whose CAPABILITIES block holds it.
#define cooldowns(names...)
#define sparse_get(D, name) _sparse_get(D, #name)
/// The slot's value, or `default` when unset.
#define sparse_get_or(D, name, default) _sparse_get(D, #name, default)
#define sparse_set(D, name, value) _sparse_set(D, #name, value)
/// Writes the slot; a value equal to `default` clears it (a counter back at 0).
#define sparse_set_or(D, name, value, default) _sparse_set(D, #name, value, default)
#define sparse_has(D, name) (!isnull((D).sparse_slots?[#name]))
#define cooldown_start(D, name, duration) _cooldown_start(D, #name, duration)
#define cooldown_ready(D, name) ((D).cooldown_table?[#name] < world.time)
#define cooldown_end(D, name) ((D).cooldown_table?[#name] || 0)
#define cooldown_left(D, name) max(0, ((D).cooldown_table?[#name] || 0) - world.time)
#define cooldown_started(D, name) (!!((D).cooldown_table?[#name]))
#define cooldown_reset(D, name) _cooldown_set(D, #name, 0)
/// Sets the end time directly (an absolute world.time), for a cooldown pushed out by a computed amount.
#define cooldown_set_end(D, name, at) _cooldown_set(D, #name, at)

// Stamps: "how long since" on a base type (doc/rewrite/final_api.html section 3). A stamp lives in the same lazy table as the cooldowns
// (a name -> a point on a clock), so an instance that never stamps pays nothing.
/// Declares stamp names on the type whose CAPABILITIES block holds it.
#define stamps(names...)
/// Records "now" on `clock` (CLOCK_WORLD or CLOCK_OWN) as the stamp `name` of D.
#define stamp_now(D, name, clock) _stamp_set(D, #name, TIME_NOW(clock, D))
/// Records a raw point on D's clock as the stamp (tests, a stamp moved by a computed amount).
#define stamp_set(D, name, point) _stamp_set(D, #name, point)
/// Deciseconds since the stamp on `clock`. A never-stamped name reads as a stamp at 0, as the var it replaces did.
#define stamp_elapsed(D, name, clock) (TIME_NOW(clock, D) - ((D).cooldown_table?[#name] || 0))
/// The stored point, or null when never stamped.
#define stamp_point(D, name) ((D).cooldown_table?[#name])
#define stamp_has(D, name) (!isnull((D).cooldown_table?[#name]))
#define stamp_clear(D, name) _stamp_clear(D, #name)
