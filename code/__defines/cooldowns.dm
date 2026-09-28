//// COOLDOWNS
// A rate limit is a time compared: the var holds when the cooldown ends (object_model_core.md §16).
// A cooldown that needs no var on the type (rare, on a target) still gets a var: timers are not cooldowns.

/*
 * Cooldown system based on storing world.time on a variable, plus the cooldown time.
 * Better performance over timer cooldowns, lower control. Same functionality.
*/

#define COOLDOWN_DECLARE(cd_index) var/##cd_index = 0

#define STATIC_COOLDOWN_DECLARE(cd_index) var/static/##cd_index = 0

#define COOLDOWN_START(cd_source, cd_index, cd_time) (cd_source.cd_index = world.time + (cd_time))

//Returns true if the cooldown has run its course, false otherwise
#define COOLDOWN_FINISHED(cd_source, cd_index) (cd_source.cd_index < world.time)

#define COOLDOWN_RESET(cd_source, cd_index) cd_source.cd_index = 0

#define COOLDOWN_STARTED(cd_source, cd_index) (cd_source.cd_index != 0)

#define COOLDOWN_TIMELEFT(cd_source, cd_index) (max(0, cd_source.cd_index - world.time))

/*
 * TIMESTAMP_VAR(name): a var that records a world.time as *data* rather than as a rate limit:
 * an expiry or deadline (a contract, a lease, a guest pass), a scheduled time a service or
 * machine acts at (a launch, a payroll, a weather shift), or a start/recorded time read back
 * for elapsed math (time of death, a scan's start, a cache's stamp). Comparing one with
 * world.time is a state check, so tools/ci/cooldown_lint.py does not count compares that read
 * a var declared this way. A "not more than once per N" belongs in COOLDOWN_DECLARE instead.
 */
#define TIMESTAMP_VAR(name) var/##name = 0
#define TIMESTAMP_TMP_VAR(name) var/tmp/##name = 0
