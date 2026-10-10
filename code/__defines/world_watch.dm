// Rust world subscriptions on the OM scheduler (code/engine/time/world_watches.dm,
// doc/rewrite/object_model_core.md §4.8). The numeric registry (WORLD_REASON_*,
// WORLD_WAKE_STRIDE) is generated from the Rust sources into verdigris/_bindings.dm.

// --- Comparisons for conditions and rate watches.
#define WORLD_CMP_ABOVE 0
#define WORLD_CMP_BELOW 1

// --- Probe channels (the test Probe component, verdigris/ffi/src/sched.rs). A channel's
// reason bit is (1 << id).
#define CH_PROBE_PRESSURE 0
#define CH_PROBE_TEMPERATURE 1
#define CH_BIT(ch) (1 << (ch))

// --- Gas domain channels (verdigris/domains/gas/src/cell.rs, the same for turf gas and
// main-owned mixtures).
#define CH_GAS_PRESSURE 0
#define CH_GAS_TEMPERATURE 1
#define CH_GAS_MOLES 2
#define CH_GAS_OXYGEN 3
#define CH_GAS_PLASMA 4
#define CH_GAS_CARBON_DIOXIDE 5

// --- Watch handles: what a watch names, as list(code, cell). `code` is a component kind
// (VG_KIND_*, cells are vg_entity values) or VG_GAS_HANDLES (cells are gas arena ids).
#define WORLD_HANDLE(code, cell) list(code, cell)
/// The watch handle of a gas mixture (a turf's air, a tank, a canister).
#define WORLD_GAS_HANDLE(mixture) list(VG_GAS_HANDLES, (mixture).arena_id())

// --- DM-owned facts are not published into Rust. Game facts (areas, doors, powernets, chunks, ...) are OM change channels: CHANGE_* in om.dm.

// --- Conditions for world_watch_when(). Transient lists, consumed at registration; nothing is kept.
#define WORLD_COND_THRESHOLD 1
#define WORLD_COND_BAND 2
#define WORLD_COND_DIFFERENCE 3

/// `handle`'s channel `ch` rises to `value` or above. Hysteresis is the channel's.
#define COND_ABOVE(handle, ch, value) list(WORLD_COND_THRESHOLD, handle, ch, WORLD_CMP_ABOVE, value, -1, FALSE)
/// COND_ABOVE with the hysteresis given here (in the channel's unit) instead of the channel's.
#define COND_ABOVE_H(handle, ch, value, hysteresis) list(WORLD_COND_THRESHOLD, handle, ch, WORLD_CMP_ABOVE, value, hysteresis, FALSE)
/// COND_BELOW with the hysteresis given here instead of the channel's.
#define COND_BELOW_H(handle, ch, value, hysteresis) list(WORLD_COND_THRESHOLD, handle, ch, WORLD_CMP_BELOW, value, hysteresis, FALSE)
/// `handle`'s channel `ch` falls to `value` or below.
#define COND_BELOW(handle, ch, value) list(WORLD_COND_THRESHOLD, handle, ch, WORLD_CMP_BELOW, value, -1, FALSE)
/// Like COND_ABOVE, but also wakes when the value leaves the condition.
#define COND_ABOVE_EDGES(handle, ch, value) list(WORLD_COND_THRESHOLD, handle, ch, WORLD_CMP_ABOVE, value, -1, TRUE)
/// `handle`'s channel `ch` moves into a different band of the increasing list `levels`
/// (and once at registration, to report the starting band).
#define COND_BAND(handle, ch, levels) list(WORLD_COND_BAND, handle, ch, levels, -1)
/// `|a - b|` on channel `ch` rises to `value` or above (a firedoor's pressure difference).
#define COND_DIFFERENCE(handle_a, handle_b, ch, value) list(WORLD_COND_DIFFERENCE, handle_a, handle_b, ch, WORLD_CMP_ABOVE, value, -1, TRUE)
