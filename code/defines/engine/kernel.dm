// Kernel defines (doc: doc/rewrite/kernel.md sec 1.2, 1.3, 2.1).

/// Latency classes: how a system's work is scheduled when the tick is contended.
/// L0: player input; runs first, capped, never shed. L1: simulation the player feels. L2: derived and
/// presentation work. L3: background work; the only class the kernel sheds under overload.
#define LATENCY_L0 0
#define LATENCY_L1 1
#define LATENCY_L2 2
#define LATENCY_L3 3

// ---- the step protocol: what periodic_step(dt) and a world service step return. None equals PROCESS_KILL.
/// The step is finished; stay on the cadence.
#define STEP_DONE 2
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
/// Events one client's input inbox holds before it drops its oldest coalescible input (code/engine/kernel/inbox.dm).
#define INPUT_CLIENT_MAX 64
/// The most one client's inbox ever holds. Inputs that cannot be coalesced or dropped (a Topic, a tgui action, say, a press) pass INPUT_CLIENT_MAX, but a client
/// that sends them faster than phase K serves them stops at this: the newest is refused (never a queued one), the player is told, admins are told once per burst.
#define INPUT_CLIENT_HARD_MAX 256
/// The most inputs that cannot coalesce one client may send in INPUT_RATE_WINDOW; past it the newest is refused. A person's own fastest input (a dragged tgui slider,
/// a key-repeat Topic) stays well under it.
#define INPUT_CLIENT_RATE_MAX 120
#define INPUT_RATE_WINDOW (1 SECONDS)
/// A player is told of a refusal at most this often, and an admin report opens a new burst after this long without a refusal.
#define INPUT_REFUSE_NOTICE_EVERY (5 SECONDS)
#define INPUT_REFUSE_BURST_GAP (10 SECONDS)
/// A client holding at least this many events for INPUT_NEAR_CAP_WARN has the server log a warning (at most one per INPUT_NEAR_CAP_REPEAT).
#define INPUT_CLIENT_NEAR_CAP 48
#define INPUT_NEAR_CAP_WARN (5 SECONDS)
#define INPUT_NEAR_CAP_REPEAT (60 SECONDS)
// How long an input may wait in the inbox before it is too late to be what the player meant (a /datum/input_event's max_wait). Phase K serves a quiet inbox
// within a tick (half a decisecond), so a wait this long means the server was overrun or the client flooded it, and the world the player aimed at has moved on.
/// A click or a double click: the thing under the cursor has moved or gone.
#define INPUT_MAX_WAIT_CLICK (0.4 SECONDS)
/// A drop is a deliberate gesture that may be held a moment longer.
#define INPUT_MAX_WAIT_DRAG (0.6 SECONDS)
/// Drag-over, hover, and a press: feedback about where the pointer is now, worthless once it has moved.
#define INPUT_MAX_WAIT_FEEDBACK (0.2 SECONDS)
/// A wheel notch scrolls or zooms what is under the cursor now; a late one acts on something else.
#define INPUT_MAX_WAIT_WHEEL (0.3 SECONDS)
/// Tick usage under which a click resolves on the spot; above it the click waits for phase K.
#define INPUT_CLICK_THRESHOLD 95
/// The same for every other input (a verb, a Topic, a tgui action, say).
#define INPUT_VERB_THRESHOLD 85
/// The client's mouse buttons and drag (code/engine/kernel/entry.dm): what a /datum/input_event/click/client_mouse reports.
#define INPUT_MOUSE_DOWN "mouse_down"
#define INPUT_MOUSE_UP "mouse_up"
#define INPUT_MOUSE_DRAG "mouse_drag"
/// Input-latency histogram: bins of one tick each, the last bin holds everything slower.
#define KERNEL_LATENCY_BINS 32
/// A waiter with no timeout.
#define WAITER_NO_TIMEOUT 0

// ---- the kernel tick (code/controllers/kernel/kernel.dm): phases run in this order every tick.
/// K: host systems (the input inbox first), capped at KERNEL_INPUT_CAP.
#define KERNEL_PHASE_K 1
/// S: simulation sync. Everything Rust needs from DM, pushed right before the native step. Never shed.
#define KERNEL_PHASE_S 2
/// N: native. One Rust frame: native_frame(elapsed, budget).
#define KERNEL_PHASE_N 3
/// U: urgent requests, from a reserved slice of the tick (kernel_urgent()).
#define KERNEL_PHASE_U 4
/// D: deadlines (timers, deadline wakes, timed_set reverts) and deadline-phase work items.
#define KERNEL_PHASE_D 5
/// P: the lanes: the borrow pass, then each lane's queued wakes, rings and work items, by lane share.
#define KERNEL_PHASE_P 6
/// R: leftovers, lane order (presentation).
#define KERNEL_PHASE_R 7
/// G: garbage, whatever is left, with a floor per second.
#define KERNEL_PHASE_G 8
#define KERNEL_PHASE_COUNT 8
/// Phase letters, indexed by KERNEL_PHASE_*.
#define KERNEL_PHASE_LETTERS list("K", "S", "N", "U", "D", "P", "R", "G")

/// The most of a tick one non-ticker host service (tgui, dbcore, profiler, garbage) may take in its phase, in percent.
#define KERNEL_HOST_SLICE 10
/// Share of the kernel's budget reserved for phase U.
#define KERNEL_URGENT_SHARE 0.1
/// Elapsed ticks a native frame may cover in one call (a long stall does not step the world for minutes).
#define KERNEL_NATIVE_MAX_CATCHUP NATIVE_MAX_CATCHUP
/// A work item that faults this many runs in a row is parked and admins are told.
#define KERNEL_FAULT_PARK 5
/// A spread member sweep (work_item.spread) that fell behind catches up by at most this many passes' share per pass,
/// so a stall is paid back over several ticks instead of in one.
#define KERNEL_SPREAD_CATCHUP 4

/// Opens a request (code/engine/kernel/requests.dm): open_request(owner, /datum/prompt/x, PROC_REF(done), valid = PROC_REF(ok), field = v, ...).
/// Not spelled request(): BYOND's preprocessor takes a function-like macro name at the end of a line (`var/datum/request/request`,
/// `circuit = /obj/item/circuitboard/request`) for a call and eats the next line.
/// How long a request stays open when its opener gave no timeout: it ends REQ_TIMED_OUT, never pinning its owner for the rest of the round.
#define REQUEST_DEFAULT_TIMEOUT (10 MINUTES)
/// timeout = REQUEST_NO_TIMEOUT: the request stays open until it is answered or its owner or answerer goes. Say why where it is used.
#define REQUEST_NO_TIMEOUT -1
#define open_request(owner, request_type, handler, fields...) request_open(owner, request_type, handler, list(fields))

// ---- chunked jobs (code/engine/kernel/jobs.dm): what a job step returns.
/// The step has more to do: it runs again, this tick if its budget allows, else the next.
#define JOB_MORE 1
/// The step is finished: the job's then() handler runs and the job ends.
#define JOB_DONE 2

// ---- work items: interval 0 runs every tick.
#define WORK_EVERY_TICK 0

/// Garbage gets at least KERNEL_GARBAGE_FLOOR percent of a tick once every KERNEL_GARBAGE_FLOOR_PERIOD, whatever else ran.
#define KERNEL_GARBAGE_FLOOR 2
#define KERNEL_GARBAGE_FLOOR_PERIOD (1 SECONDS)

/// An absolute tick usage no test world reaches (the boot ticks a test runs in are thousands of percent).
#define WORK_TEST_LIMIT 1e9

// ---- request re-checks (code/engine/kernel/requests.dm, request_recheck())
// open_request(..., ask_flags = ASK_ALIVE | ASK_CAPABLE, asker = M, subject = S, rights = R_X, usable_state = "physical"): re-checked when the answer arrives,
// before the handler runs; a failure ends the request cancelled (the handler sees no answer). Roles: the answerer sees the window; the asker started it
// (default: the answerer); the subject is what it is about (default: the owner, when it is an atom).

/// The answerer and the asker are alive.
#define ASK_ALIVE (1<<0)
/// The answerer and the asker are conscious.
#define ASK_CONSCIOUS (1<<1)
/// The answerer is next to the asker (next to the subject when they are the same mob).
#define ASK_ADJACENT (1<<2)
/// The subject is still in the asker's hands.
#define ASK_HELD (1<<3)
/// The subject is still somewhere on the asker (held, worn, in a bag).
#define ASK_CARRIED (1<<4)
/// Neither the answerer nor the asker is incapacitated.
#define ASK_CAPABLE (1<<5)
/// The subject is next to the answerer.
#define ASK_NEAR_SUBJECT (1<<6)
/// Neither the answerer nor the asker is restrained (cuffed, buckled in restraints).
#define ASK_RESTRAINED (1<<7)
/// The common "someone offers you something" set: both alive, awake and adjacent.
#define ASK_FACE_TO_FACE (ASK_CONSCIOUS | ASK_ADJACENT)

/// The answerer is directly inside the subject (a tunnel, a closet, a vehicle).
#define ASK_INSIDE (1<<8)


// The rate limiters of a client's inputs: a list of this size, indexed by these (client/Click() in code/engine/kernel/entry.dm and client/Topic()).
#define LIMITER_SIZE 12
#define CURRENT_SECOND 1
#define SECOND_COUNT 2
#define CURRENT_MINUTE 3
#define MINUTE_COUNT 4
#define ADMINSWARNED_AT 5
