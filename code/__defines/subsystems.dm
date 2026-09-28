//! Defines for subsystems and overlays
//!
//! Lots of important stuff in here, make sure you have your brain switched on
//! when editing this file

/// Used to trigger object removal from a processing list
#define PROCESS_KILL 26


//! ## Initialization subsystem

///New should not call Initialize
#define INITIALIZATION_INSSATOMS 0
///New should call Initialize(TRUE)
#define INITIALIZATION_INNEW_MAPLOAD 1
///New should call Initialize(FALSE)
#define INITIALIZATION_INNEW_REGULAR 2

//! ### Initialization hints

///Nothing happens
#define INITIALIZE_HINT_NORMAL 0
/**
 * call LateInitialize at the end of all atom Initialization
 *
 * The item will be added to the late_loaders list, this is iterated over after
 * initialization of subsystems is complete and calls LateInitalize on the atom
 * see [this file for the LateIntialize proc](atom.html#proc/LateInitialize)
 */
#define INITIALIZE_HINT_LATELOAD 1

///Call qdel on the atom after initialization
#define INITIALIZE_HINT_QDEL 2

//! ### Map-load batches (code/controllers/subsystems/atoms_batch.dm)

/// Atoms SSatoms.CreateAtoms() initializes between yield points. A batch only yields at a
/// chunk boundary, never inside one (doc/rewrite/init_and_turfs.md sec 3.3a).
#define MATERIALIZE_CHUNK_SIZE 512

/// Deferred batch work, flushed once at the end of the batch that owns it, in this order.
/// Walls smooth once each, with their neighbours.
#define BATCH_WORK_WALL_SMOOTHING 1
/// Cables bind their power nodes in one Rust call.
#define BATCH_WORK_CABLE_BINDS 2
/// Number of BATCH_WORK_* kinds (length of a batch's work list).
#define BATCH_WORK_KINDS 2

///type and all subtypes should always immediately call Initialize in New()
#define INITIALIZE_IMMEDIATE(X) ##X/New(loc, ...){\
	..();\
	if(!(flags & ATOM_INITIALIZED)) {\
		var/previous_initialized_value = SSatoms.initialized;\
		SSatoms.initialized = INITIALIZATION_INNEW_MAPLOAD;\
		args[1] = TRUE;\
		SSatoms.InitAtom(src, FALSE, args);\
		SSatoms.initialized = previous_initialized_value;\
	}\
}

//! ### SS initialization hints
/**
 * Negative values indicate a failure or warning of some kind, positive are good.
 * 0 and 1 are unused so that TRUE and FALSE are guaranteed to be invalid values.
 */

/// Subsystem failed to initialize entirely. Print a warning, log, and disable firing.
#define SS_INIT_FAILURE -2

/// The default return value which must be overridden. Will succeed with a warning.
#define SS_INIT_NONE -1

/// Subsystem initialized successfully.
#define SS_INIT_SUCCESS 2

/// If your system doesn't need to be initialized (by being disabled or something)
#define SS_INIT_NO_NEED 3

/// Successfully initialized, BUT do not announce it to players (generally to hide game mechanics it would otherwise spoil)
#define SS_INIT_NO_MESSAGE 4

// Subsystem fire priority, from lowest to highest priority
// If the subsystem isn't listed here it's either DEFAULT or PROCESS (if it's a processing subsystem child)
#define FIRE_PRIORITY_ATC			1
#define FIRE_PRIORITY_APPRECIATE	2
#define FIRE_PRIORITY_SHUTTLES		5
#define FIRE_PRIORITY_PLANTS		5
#define FIRE_PRIORITY_ORBIT			7
#define FIRE_PRIORITY_GARBAGE		15
#define FIRE_PRIORITY_DATABASE		16
#define FIRE_PRIORITY_ALARM			20
#define FIRE_PRIORITY_AIRFLOW		30
#define FIRE_PRIORITY_AIR			35
#define FIRE_PRIORITY_BURNING		40
#define FIRE_PRIORITY_OBJ			40
#define FIRE_PRIORITY_DEFAULT		50
#define FIRE_PRIORITY_TICKER		60
#define FIRE_PRIORITY_PRIORITY_EFFECTS 90
#define FIRE_PRIORITY_TGUI			110
#define FIRE_PRIORITY_PROJECTILES	150
#define FIRE_PRIORITY_OVERLAYS		500
#define FIRE_PRIORITY_BEHAVIOURS	640
#define FIRE_PRIORITY_VG			660
#define FIRE_PRIORITY_SPEECH_CONTROLLER 900
#define FIRE_PRIORITY_DELAYED_VERBS 950
#define FIRE_PRIORITY_INPUT			1000 // This must always always be the max highest priority. Player input must never be lost.


// SS runlevels

#define RUNLEVEL_LOBBY (1<<0)
#define RUNLEVEL_SETUP (1<<1)
#define RUNLEVEL_GAME (1<<2)
#define RUNLEVEL_POSTGAME (1<<3)

#define RUNLEVELS_DEFAULT (RUNLEVEL_SETUP | RUNLEVEL_GAME | RUNLEVEL_POSTGAME)

//SSticker.current_state values
/// Game is loading
#define GAME_STATE_STARTUP 0
/// Game is loaded and in pregame lobby
#define GAME_STATE_PREGAME 1
/// Game is attempting to start the round
#define GAME_STATE_SETTING_UP 2
/// Game has round in progress
#define GAME_STATE_PLAYING 3
/// Game has round finished
#define GAME_STATE_FINISHED 4

// Used for SSticker.force_ending
/// Default, round is not being forced to end.
#define END_ROUND_AS_NORMAL 0
/// End the round now as normal
#define FORCE_END_ROUND 1
/// For admin forcing roundend, can be used to distinguish the two
#define ADMIN_FORCE_END_ROUND 2

// The change in the world's time from the subsystem's last fire in seconds.
#define DELTA_WORLD_TIME(ss) ((world.time - ss.last_fire) * 0.1)

/// The timer key used to know how long subsystem initialization takes
#define SS_INIT_TIMER_KEY "ss_init"

// Subsystem delta times or tickrates, in seconds. I.e, how many seconds in between each process() call for objects being processed by that subsystem.
// Only use these defines if you want to access some other objects processing seconds_per_tick, otherwise use the seconds_per_tick that is sent as a parameter to process()
// #define SSFLUIDS_DT (SSplumbing.wait/10)

// SCALE_PROCESS_DELTA(wait, scale)
// Converts a processing subsystem's raw wait (in deciseconds) to the scaled
// delta passed to process(). The standard pattern is:
//   - scale = 1     -> pass raw deciseconds (most subsystems)
//   - scale = 0.1   -> pass seconds (1 SECOND = 10 deciseconds, x0.1 = 1.0)
// Use this macro instead of inline arithmetic so the intent is greppable and
// so a future wait-unit change updates all call sites together.
#define SCALE_PROCESS_DELTA(wait, scale) ((wait) * (scale))
