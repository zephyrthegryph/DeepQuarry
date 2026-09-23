// SSreactor (doc/rewrite/reactor.md): wake dispatch, timers, the continuous lane,
// DM-owned keys and rate models. The numeric registry (REACT_REASON_*, REACT_WAKE_STRIDE,
// REACT_DOMAIN_*) is generated from the Rust sources into verdigris/_bindings.dm.
//
// A subscriber implements /datum/proc/on_react(reason, source, source_kind). Every macro
// that subscribes returns a token for REACT_CANCEL. The base /datum/Destroy() calls
// REACT_CLEAR, so a subscriber never has to.

// --- Lanes (rust_core.md §7). Urgent drains in full; normal and background share the budget.
#define REACT_LANE_URGENT 0
#define REACT_LANE_NORMAL 1
#define REACT_LANE_BACKGROUND 2

// --- Comparisons for conditions and rate watches.
#define REACT_CMP_ABOVE 0
#define REACT_CMP_BELOW 1

// --- Probe domain channels (verdigris/ffi/src/reactor.rs). A channel's reason bit is (1 << id).
#define CH_PROBE_PRESSURE 0
#define CH_PROBE_TEMPERATURE 1
#define CH_BIT(ch) (1 << (ch))

// --- Rust entity handles: a domain and a cell in one exact number (domain < 16, cell < 2^20).
#define REACT_HANDLE(domain, cell) ((domain) * 1048576 + (cell))
#define REACT_HANDLE_DOMAIN(handle) round((handle) / 1048576)
#define REACT_HANDLE_CELL(handle) ((handle) % 1048576)

// --- DM-owned key kinds (§4). A key is (kind, id); the id is a registry id, never a string.
/// Keys used only by the reactor's own tests.
#define REACT_KEY_TEST 1
/// An area's power channels changed. Id: the area's REACT_ID.
#define REACT_KEY_AREA_POWER 2
/// A door's mode (bolts, emergency access, ...) changed. Id: the door's REACT_ID.
#define REACT_KEY_DOOR_MODE 3

/// Reason classes for the wake metrics (REACT_CLASS_EVERY counts continuous-lane runs,
/// which call react_every() instead of on_react()).
#define REACT_CLASS_CHANGED 1
#define REACT_CLASS_CONDITION 2
#define REACT_CLASS_TIMER 3
#define REACT_CLASS_KEY 4
#define REACT_CLASS_RATE 5
#define REACT_CLASS_EVERY 6
#define REACT_CLASS_COUNT 6

// --- Conditions for REACT_WHEN. Transient lists, consumed at registration; nothing is kept.
#define REACT_COND_THRESHOLD 1
#define REACT_COND_BAND 2
#define REACT_COND_DIFFERENCE 3

/// `handle`'s channel `ch` rises to `value` or above. Hysteresis is the channel's.
#define COND_ABOVE(handle, ch, value) list(REACT_COND_THRESHOLD, handle, ch, REACT_CMP_ABOVE, value, -1, FALSE)
/// `handle`'s channel `ch` falls to `value` or below.
#define COND_BELOW(handle, ch, value) list(REACT_COND_THRESHOLD, handle, ch, REACT_CMP_BELOW, value, -1, FALSE)
/// Like COND_ABOVE, but also wakes when the value leaves the condition.
#define COND_ABOVE_EDGES(handle, ch, value) list(REACT_COND_THRESHOLD, handle, ch, REACT_CMP_ABOVE, value, -1, TRUE)
/// `handle`'s channel `ch` moves into a different band of the increasing list `levels`
/// (and once at registration, to report the starting band).
#define COND_BAND(handle, ch, levels) list(REACT_COND_BAND, handle, ch, levels, -1)
/// `|a - b|` on channel `ch` rises to `value` or above (a firedoor's pressure difference).
#define COND_DIFFERENCE(handle_a, handle_b, ch, value) list(REACT_COND_DIFFERENCE, handle_a, handle_b, ch, REACT_CMP_ABOVE, value, -1, TRUE)

// --- The API (reactor.md §1).

/// The datum's registry index, assigning one if it has none. Use it to build key ids.
#define REACT_ID(D) ((D).reactor_id || SSreactor.assign_id(D))
/// Wake on a change of any channel in `mask` of a Rust entity.
#define REACT_ON(D, handle, mask) SSreactor.on_change(D, handle, mask)
/// Wake when a condition (COND_*) becomes true.
#define REACT_WHEN(D, condition) SSreactor.when(D, condition)
/// One-shot timer: wake at the first tick at or after world.time `time`.
#define REACT_AT(D, time) SSreactor.at(D, time)
/// Declared continuous work: D.react_every(seconds) every `period`, until cancelled.
/// `why` says why this cannot be a watch or a timer; the profiler lists it.
#define REACT_EVERY(D, period, why) SSreactor.every(D, period, why)
/// DM-owned state under key (kind, id) changed; `mask` says which parts.
#define REACT_PUBLISH(kind, id, mask) vg_react_publish(kind, id, mask)
/// Wake when key (kind, id) is published with any bit of `mask`.
#define REACT_ON_KEY(D, kind, id, mask) SSreactor.on_key(D, kind, id, mask)
/// Drop one subscription, timer or continuous declaration.
#define REACT_CANCEL(D, token) SSreactor.cancel(D, token)
/// Drop everything D subscribed to. The base /datum/Destroy() calls this.
#define REACT_CLEAR(D) if((D).reactor_id) { SSreactor.clear(D) }

// --- Rate models (§5). Rates are per second; the wheel runs in ticks.
#define REACT_PER_TICK(per_second) ((per_second) * world.tick_lag / 10)
/// A quantity changing at `per_second` from `v0`, clamped to [lo, hi] (null: unbounded).
#define RATE_LINEAR(v0, per_second, lo, hi) vg_rate_linear(v0, REACT_PER_TICK(per_second), lo, hi)
/// A quantity relaxing toward `target` with rate constant `k_per_second`.
#define RATE_RELAX(v0, target, k_per_second) vg_rate_relax(v0, target, REACT_PER_TICK(k_per_second))
/// A store with named inflow/outflow terms (RATE_SET_TERM).
#define RATE_SUM(v0, lo, hi) vg_rate_sum(v0, lo, hi)
#define RATE_READ(model) vg_rate_read(model)
#define RATE_SET(model, value) vg_rate_set(model, value)
#define RATE_SET_RATE(model, per_second) vg_rate_set_rate(model, REACT_PER_TICK(per_second))
#define RATE_SET_TERM(model, term, per_second) vg_rate_set_term(model, term, REACT_PER_TICK(per_second))
#define RATE_REMOVE(model) vg_rate_remove(model)
/// Wake D at the exact tick the model enters `cmp level` (at once if it already holds).
#define REACT_RATE(D, model, cmp, level) SSreactor.on_rate(D, model, cmp, level)
