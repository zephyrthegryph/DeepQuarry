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
/// An APC's own state or its grid supply class changed. Id: the APC's REACT_ID.
#define REACT_KEY_APC 4
	#define REACT_APC_STATE 1
	#define REACT_APC_SUPPLY 2
/// A powernet changed. Id: the powernet's REACT_ID.
#define REACT_KEY_POWERNET 5
	/// Supply or load moved (exact-rate consumers).
	#define REACT_POWERNET_RATE 1
	/// Cables, warnings or monitor-visible state.
	#define REACT_POWERNET_STATE 2
	/// Machine membership (sleeping APCs).
	#define REACT_POWERNET_TOPOLOGY 4
/// A turret's settings or power changed. Id: the turret's REACT_ID.
#define REACT_KEY_TURRET 6
/// A disposal unit's state changed. Id: the unit's REACT_ID.
#define REACT_KEY_DISPOSAL 7
/// A meteor appeared or went away. Id: always 1.
#define REACT_KEY_METEORS 8
/// A mob entered, left or moved in a 16x16 chunk. Id: MOB_CHUNK_NUMERIC_KEY (z < 256).
/// One key for every mob; the mask says whether the mover was a player.
#define REACT_KEY_MOB_CHUNK 9
	/// Any mob (sleeping turrets, calm AI brains). Subscribe with sleep_on_keys().
	#define REACT_CHUNK_ANY_MOB (1<<0)
	/// A mob with a client (looping sounds, auto-flicker lights, Q5). Subscribe with
	/// SSreactor.subscribe_player_chunks().
	#define REACT_CHUNK_PLAYER (1<<1)
/// The mask for keys with a single meaning.
#define REACT_KEY_CHANGED 1

/// Publish key (kind, D's id) only if D was ever given a registry id: a subscriber builds
/// the key with REACT_ID(D), so a datum without one has no subscribers. Saves the bind call.
#define REACT_PUBLISH_OWN(D, kind, mask) if((D).reactor_id) { REACT_PUBLISH(kind, (D).reactor_id, mask) }
/// A pipe network's leaks or topology changed. Id: the network's REACT_ID, or
/// REACT_ID_GLOBAL for a change whose network is not known yet (new construction).
#define REACT_KEY_PIPE_NETWORK 21
/// A shuttle's schedule changed (called, recalled, launching). Id: REACT_SHUTTLE_*.
#define REACT_KEY_SHUTTLE_SCHEDULE 22
#define REACT_SHUTTLE_EVAC 1
#define REACT_SHUTTLE_SUPPLY 2
/// A machine broke or was fixed (base /obj/machinery/atom_break()/atom_fix()). Id: the machine's REACT_ID.
#define REACT_KEY_MACHINE_BROKEN 23

/// Key id for global keys (registry ids start at 1, so 0 is never a datum's id).
#define REACT_ID_GLOBAL 0

// Key masks.
/// REACT_KEY_AREA_POWER: the area's power_change() ran (channels or light switch).
#define REACT_AREA_POWER_CHANGED (1<<0)
/// REACT_KEY_DOOR_MODE parts.
#define REACT_DOOR_BOLTS (1<<0)
#define REACT_DOOR_POWER (1<<1)
#define REACT_DOOR_ELECTRIFIED (1<<2)
#define REACT_DOOR_OPEN (1<<3)
/// REACT_KEY_PIPE_NETWORK: leak membership or topology changed.
#define REACT_PIPE_LEAKS (1<<0)

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
/// Declared continuous work that runs D.process(delta_deciseconds): the migration target for a
/// retired START_PROCESSING user whose work really is continuous. Idempotent (DF_ISPROCESSING);
/// process() returning PROCESS_KILL cancels it. `why` is required, as for REACT_EVERY.
#define REACT_PROCESS(D, period, why) SSreactor.start_process(D, period, why)
/// Drops D's REACT_PROCESS declaration.
#define REACT_PROCESS_STOP(D) SSreactor.stop_process(D)
/// Whether D has a live REACT_PROCESS declaration (or, for a machine, is on SSmachines).
#define REACT_PROCESSING(D) ((D).datum_flags & DF_ISPROCESSING)
/// One timer per purpose: `token = REACT_REARM(D, token, time)` cancels the old one and, for
/// a non-null time, schedules a new REACT_AT.
#define REACT_REARM(D, token, time) SSreactor.rearm(D, token, time)
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
