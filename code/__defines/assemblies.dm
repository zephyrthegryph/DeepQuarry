#define IC_COMPONENTS_BASE		20
#define IC_COMPLEXITY_BASE		60

// Idle-power economy baseline. handle_idle_power() scales its per-tick draw by
// seconds_per_tick normalized to this value, so the draw at the electronic
// assembly's REACT_PROCESS period (2s) is numerically unchanged while the rate
// decouples from the scheduler. Keep in sync with the REACT_PROCESS period
// passed in code/modules/integrated_electronics/core/assemblies.dm.
#define IC_IDLE_POWER_BASELINE_SPT	2

// Upper bound on circuits visited during a single synchronous pulse propagation.
// A wide fan-out assembly that exceeds this bails with feedback rather than
// stalling the tick. Generous enough that no normal assembly hits it.
#define IC_MAX_PULSE_CIRCUITS		300
