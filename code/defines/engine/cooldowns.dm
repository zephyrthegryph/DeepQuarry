//// COOLDOWNS
// A rate limit is a time compared: the var holds when the cooldown ends (object_model_core.md §16).
// A cooldown that needs no var on the type (rare, on a target) still gets a var: timers are not cooldowns.

/*
 * Cooldown system based on storing world.time on a variable, plus the cooldown time.
 * Better performance over timer cooldowns, lower control. Same functionality.
*/

/// Charging-only APC_REPORT lines are written at most this often per APC (apc.dm on_apc_report()).
#define APC_REPORT_LOG_INTERVAL (30 SECONDS)
/// Type-level every() runs of at least this interval start at a spread phase (type_every_phase()); the first run falls between this share of the interval and the whole of it.
#define TYPE_EVERY_PHASE_MIN (2 SECONDS)
#define TYPE_EVERY_PHASE_FLOOR 0.25

#define COOLDOWN_DECLARE(cd_index) var/##cd_index = 0

#define STATIC_COOLDOWN_DECLARE(cd_index) var/static/##cd_index = 0

#define COOLDOWN_TMP_DECLARE(cd_index) var/tmp/##cd_index = 0

#define COOLDOWN_START(cd_source, cd_index, cd_time) (cd_source.cd_index = TIME_NOW(CLOCK_WORLD) + (cd_time))

//Returns true if the cooldown has run its course, false otherwise
#define COOLDOWN_FINISHED(cd_source, cd_index) (cd_source.cd_index < TIME_NOW(CLOCK_WORLD))

#define COOLDOWN_RESET(cd_source, cd_index) cd_source.cd_index = 0

#define COOLDOWN_STARTED(cd_source, cd_index) (cd_source.cd_index != 0)

#define COOLDOWN_TIMELEFT(cd_source, cd_index) (max(0, cd_source.cd_index - TIME_NOW(CLOCK_WORLD)))

/// Pushes the end out to at least `cd_time` from now; never shortens a cooldown that runs longer.
#define COOLDOWN_EXTEND(cd_source, cd_index, cd_time) (cd_source.cd_index = max(cd_source.cd_index, TIME_NOW(CLOCK_WORLD) + (cd_time)))

/// TRUE while the end is still ahead (`end > now`): over the moment `now` reaches it, where COOLDOWN_FINISHED (`end < now`) holds one more tick.
#define COOLDOWN_RUNNING(cd_source, cd_index) (cd_source.cd_index > TIME_NOW(CLOCK_WORLD))

/// TRUE once the end is reached or past (`end <= now`), a never-started 0 included: the exact opposite of COOLDOWN_RUNNING.
#define COOLDOWN_LAPSED(cd_source, cd_index) (cd_source.cd_index <= TIME_NOW(CLOCK_WORLD))

// The _OWN family counts on the owner's own clock (timer_clock(): bio for a living mob, machine for machinery), which slows with the domain's
// rate and stops in stasis, exactly like after() timers on that datum (CLOCK_OWN, code/defines/engine/capabilities.dm). A var is read with the family
// it was started with.
#define COOLDOWN_START_OWN(cd_source, cd_index, cd_time) (cd_source.cd_index = TIME_NOW(CLOCK_OWN, cd_source) + (cd_time))
#define COOLDOWN_EXTEND_OWN(cd_source, cd_index, cd_time) (cd_source.cd_index = max(cd_source.cd_index, TIME_NOW(CLOCK_OWN, cd_source) + (cd_time)))
#define COOLDOWN_FINISHED_OWN(cd_source, cd_index) (cd_source.cd_index < TIME_NOW(CLOCK_OWN, cd_source))
#define COOLDOWN_RUNNING_OWN(cd_source, cd_index) (cd_source.cd_index > TIME_NOW(CLOCK_OWN, cd_source))
#define COOLDOWN_LAPSED_OWN(cd_source, cd_index) (cd_source.cd_index <= TIME_NOW(CLOCK_OWN, cd_source))
#define COOLDOWN_TIMELEFT_OWN(cd_source, cd_index) (max(0, cd_source.cd_index - TIME_NOW(CLOCK_OWN, cd_source)))

// A time kept as a start ("how long since": a last hit, a time of death, a start) is STAMP/ELAPSED (code/defines/engine/time_now.dm).

// Keyed cooldowns: for keys that are data (an ability id), where a var per key would be dozens. One lazy table (key -> end time) on the
// holder that prunes its lapsed entries each time one starts; the key is the only place a cooldown name is a value (doc/rewrite/final_api.html section 3).
/// Declares the table var; it stays null until a key starts.
#define COOLDOWN_KEYED_DECLARE(cd_index) var/list/##cd_index
/// Starts `cd_key` for `cd_time` from now.
#define COOLDOWN_KEYED_START(cd_source, cd_index, cd_key, cd_time) (cd_source.cd_index = cooldown_keyed_started(cd_source.cd_index, cd_key, cd_time))
/// TRUE when `cd_key` was never started or its end is behind us (the same `<` as COOLDOWN_FINISHED).
#define COOLDOWN_KEYED_FINISHED(cd_source, cd_index, cd_key) ((cd_source.cd_index?[cd_key] || 0) < TIME_NOW(CLOCK_WORLD))
/// TRUE while `cd_key` runs (`end > now`), the strict form of !COOLDOWN_KEYED_FINISHED.
#define COOLDOWN_KEYED_RUNNING(cd_source, cd_index, cd_key) ((cd_source.cd_index?[cd_key] || 0) > TIME_NOW(CLOCK_WORLD))
/// The end time of `cd_key`, 0 when it never started or has been pruned.
#define COOLDOWN_KEYED_END(cd_source, cd_index, cd_key) (cd_source.cd_index?[cd_key] || 0)

