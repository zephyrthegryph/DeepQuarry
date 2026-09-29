// Kernel defines (doc: systems design sec 1.2, 1.3, 2.1).

/// Latency classes: how a system's work is scheduled when the tick is contended.
/// L0: player input; runs first, capped, never shed. L1: simulation the player feels. L2: derived and
/// presentation work. L3: background work; the only class the kernel sheds under overload.
#define LATENCY_L0 0
#define LATENCY_L1 1
#define LATENCY_L2 2
#define LATENCY_L3 3

// ---- cadences (code/controllers/kernel/cadence.dm): typepaths of the standard /datum/cadence singletons.
#define CADENCE_TICK /datum/cadence/tick
#define CADENCE_FAST /datum/cadence/fast
#define CADENCE_SECOND /datum/cadence/second
#define CADENCE_SLOW /datum/cadence/slow
#define CADENCE_LIFE /datum/cadence/life
#define CADENCE_MINUTE /datum/cadence/minute

// ---- latency and shedding (code/controllers/kernel/latency.dm)
/// Consecutive overrun ticks (tick usage over 100) before L3 work is shed.
#define KERNEL_SHED_STREAK 3
/// Consecutive ticks with no overrun before shedding ends.
#define KERNEL_SHED_RECOVER 5
/// While shedding, L3 work still runs once per this many deciseconds (its floor), then catches up.
#define KERNEL_SHED_FLOOR (1 SECONDS)
/// Phase K (input) budget, percent of a tick. Use over it is counted as an overrun.
#define KERNEL_INPUT_CAP 15
/// Clicks the kernel queue holds; the oldest is dropped past it and counted.
#define KERNEL_CLICK_QUEUE_MAX 64
/// Input-latency histogram: bins of one tick each, the last bin holds everything slower.
#define KERNEL_LATENCY_BINS 32
/// A waiter with no timeout.
#define WAITER_NO_TIMEOUT 0
