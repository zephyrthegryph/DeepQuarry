// Holder-provided clocks (doc/medical_frameworks.md §1). A clock maps world time to clock time
// piecewise linearly; its speed changes only at events, and it rebases at each change.

/// A clock speed that stops time: events park and nothing settles.
#define CLOCK_SPEED_STOPPED 0
/// GLOB.world_clock: speed 1, never deleted.
#define CLOCK_KIND_WORLD 1
/// A /datum/body's clock (speed 1 - BF_STASIS; built in K2).
#define CLOCK_KIND_BODY 2
/// A holder atom's clock (freezers, cryobags, the MMI cradle): its `clock_speed`.
#define CLOCK_KIND_HOLDER 3

/// "No handle". Clock handles are positive integers from one global serial, so a stale
/// handle can never cancel an event on another clock or a newer event on the same clock.
#define CLOCK_NO_HANDLE 0
/// Deciseconds of world time as seconds (a clock reading is in clock seconds).
#define CLOCK_SECONDS(ds) ((ds) / (1 SECONDS))
/// Probability for an event with chance `p_nominal` per nominal Life cycle, over `seconds`.
#define PROB_OVER(p_nominal, seconds) (100 * (1 - (1 - (p_nominal) / 100) ** ((seconds) / LIFE_NOMINAL_SECONDS)))

/// The world time clocks read. Unit tests pin it with GLOB.clock_time_override so the clock
/// arithmetic can be checked without waiting; it is always null in play.
#define CLOCK_WORLD_TIME (isnull(GLOB.clock_time_override) ? world.time : GLOB.clock_time_override)

/// Event record slots in /datum/clock/var/events[handle].
#define CLOCK_EVENT_AT 1
#define CLOCK_EVENT_TARGET 2
#define CLOCK_EVENT_PROC 3
#define CLOCK_EVENT_ARG 4
