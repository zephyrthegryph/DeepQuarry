// Kernel defines (doc: doc/rewrite/kernel.md sec 1.2, 1.3, 2.1).

/// Latency classes: how a system's work is scheduled when the tick is contended.
/// L0: player input; runs first, capped, never shed. L1: simulation the player feels. L2: derived and
/// presentation work. L3: background work; the only class the kernel sheds under overload.
#define LATENCY_L0 0
#define LATENCY_L1 1
#define LATENCY_L2 2
#define LATENCY_L3 3

// ---- the step protocol: what periodic_step(dt) and a world service step return. None equals PROCESS_KILL.
// STEP_DONE (om.dm): the step is finished; stay on the cadence.
/// The step ran out of budget: the kernel resumes it on the next tick, ahead of the next cadence frame.
#define STEP_YIELD 27
/// Leave the cadence until wake_periodic() (or a change that makes should_run() true) puts it back.
#define STEP_PARK 28

// ---- cadences: CADENCE_* are the periodic pipelines (__defines/capabilities.dm).

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
