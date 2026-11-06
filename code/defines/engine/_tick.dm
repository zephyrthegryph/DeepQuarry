#define MAPTICK_LAST_INTERNAL_TICK_USAGE (world.map_cpu)

/// The tick a BYOND-side cost has recently taken (SendMaps), in percent of a tick: the peak of world.map_cpu,
/// decaying slowly, measured by the tick meter. Nothing subtracts it from the MC's budget; see verb_manager.dm.
#define TICK_BYOND_RESERVE (km_meter().byond_reserve())

#define TICK_LIMIT_RUNNING 80
/// Tick limit used to resume things in stoplag
#define TICK_LIMIT_TO_RUN 70
/// Tick limit for MC while running
#define TICK_LIMIT_MC 70
#define TICK_LIMIT_MC_INIT_DEFAULT 98

/// Busy-waits until tick usage reaches the target percentage. For the VERB_STRESS_TEST debug build only.
#define CONSUME_UNTIL(target_usage) while(TICK_USAGE < (target_usage)) { }

/// for general usage of tick_usage
#define TICK_USAGE world.tick_usage
/// to be used where the result isn't checked
#define TICK_USAGE_REAL world.tick_usage

/// Returns true if tick_usage is above the limit
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
/// runs stoplag if tick_usage is above the limit
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )

/// Checks if a sleeping proc is running before or after the master controller
#define RUNNING_BEFORE_MASTER ( Kernel.last_run != null && Kernel.last_run != world.time )
/// Returns true if a verb ought to yield to the MC (IE: queue up to be processed by a subsystem)
#define VERB_SHOULD_YIELD ( TICK_CHECK || RUNNING_BEFORE_MASTER )

/// Returns true if tick usage is above 95, for high priority usage
#define TICK_CHECK_HIGH_PRIORITY ( TICK_USAGE > 95 )
/// runs stoplag if tick_usage is above 95, for high priority usage
#define CHECK_TICK_HIGH_PRIORITY ( TICK_CHECK_HIGH_PRIORITY? stoplag() : 0 )
