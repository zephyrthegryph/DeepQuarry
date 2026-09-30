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

// ---- the kernel tick (code/controllers/kernel/kernel.dm): phases run in this order every tick.
/// K: hosted input subsystems (input, verb_manager), capped at KERNEL_INPUT_CAP.
#define KERNEL_PHASE_K 1
/// N: native. One Rust frame: native_frame(elapsed, budget).
#define KERNEL_PHASE_N 2
/// U: urgent requests, from a reserved slice of the tick (request_urgent()).
#define KERNEL_PHASE_U 3
/// D: deadlines (timers, deadline wakes, timed_set reverts) and deadline-phase work items.
#define KERNEL_PHASE_D 4
/// P: the lanes: the borrow pass, then each lane's queued wakes, rings and work items, by lane share.
#define KERNEL_PHASE_P 5
/// R: leftovers, lane order.
#define KERNEL_PHASE_R 6
/// G: garbage (hosted), whatever is left, with a floor per second.
#define KERNEL_PHASE_G 7
#define KERNEL_PHASE_COUNT 7
/// Phase letters, indexed by KERNEL_PHASE_*.
#define KERNEL_PHASE_LETTERS list("K", "N", "U", "D", "P", "R", "G")

/// Share of the tick's remaining budget the kernel takes; the MC's other subsystems get the rest.
#define KERNEL_TICK_SHARE 0.6
/// Share of the kernel's budget reserved for phase U.
#define KERNEL_URGENT_SHARE 0.1
/// Elapsed ticks a native frame may cover in one call (a long stall does not step the world for minutes).
#define KERNEL_NATIVE_MAX_CATCHUP NATIVE_MAX_CATCHUP
/// A work item that faults this many runs in a row is parked and admins are told.
#define KERNEL_FAULT_PARK 5

// ---- work items: interval 0 runs every tick.
#define WORK_EVERY_TICK 0

/// Garbage gets at least KERNEL_GARBAGE_FLOOR percent of a tick once every KERNEL_GARBAGE_FLOOR_PERIOD, whatever else ran.
#define KERNEL_GARBAGE_FLOOR 2
#define KERNEL_GARBAGE_FLOOR_PERIOD (1 SECONDS)

/// An absolute tick usage no test world reaches (the boot ticks a test runs in are thousands of percent).
#define WORK_TEST_LIMIT 1e9
