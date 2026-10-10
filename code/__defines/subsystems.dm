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
// There is no late-load hint: work that needs the whole map load is after_init(0, then(PROC_REF(x))) in the type's CAPABILITIES
// (code/engine/actions/after_init.dm), run when the load's frame closes.

///Call qdel on the atom after initialization
#define INITIALIZE_HINT_QDEL 2

//! ### Map-load batches (code/controllers/subsystems/atoms_batch.dm)

/// Atoms SSatoms.CreateAtoms() initializes between yield points. A batch only yields at a
/// chunk boundary, never inside one (doc/rewrite/init_and_turfs.md sec 3.3a).
#define MATERIALIZE_CHUNK_SIZE 512

// The context list of one InitializeAtoms() run (SSatoms.initialize_atoms_begin()).
#define ATOM_RUN_SOURCE 1
#define ATOM_RUN_BATCH 2
#define ATOM_RUN_OUTER_CREATED 3
#define ATOM_RUN_MACHINE_OWNER 4
#define ATOM_RUN_DECL_OWNER 5
#define ATOM_RUN_FIELDS 5

/// Deferred batch work, flushed once at the end of the batch that owns it, in this order.
/// Members of the adjacency index (code/engine/lifeforms/adjacency.dm) recompute their joins once each, when every atom of the load exists.
#define BATCH_WORK_ADJACENCY 1
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

// Runlevels: the bits a system's periodic work runs in (periodic_runlevels)

#define RUNLEVEL_LOBBY (1<<0)
#define RUNLEVEL_SETUP (1<<1)
#define RUNLEVEL_GAME (1<<2)
#define RUNLEVEL_POSTGAME (1<<3)

#define RUNLEVELS_DEFAULT (RUNLEVEL_SETUP | RUNLEVEL_GAME | RUNLEVEL_POSTGAME)

//round_game_state() values
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

/// The timer key used to know how long a system's initialization takes
#define KERNEL_INIT_TIMER_KEY "kernel_init"

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
