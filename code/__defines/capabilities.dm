// Capabilities, tracked state and the refresh engine (doc/rewrite/dx_conventions.md).
// Runtime: code/datums/capabilities/.

// ---- cap_state bits: one per boolean capability state, on /atom/var/cap_state ----
/// The cover (a hatch, the APC's front plate) is open.
#define CAP_COVER_OPEN (1<<0)
/// The maintenance panel is open.
#define CAP_PANEL_OPEN (1<<1)
/// The access lock is engaged.
#define CAP_LOCKED (1<<2)
/// Broken: every entry refuses unless it is works_broken.
#define CAP_BROKEN (1<<3)
/// Emagged.
#define CAP_EMAGGED (1<<4)
/// Wires cut or exposed state lives in the wires datum; this bit says the wires are exposed.
#define CAP_WIRES_EXPOSED (1<<5)
/// Anchored by the anchor capability (mirrors nothing: the atom's own `anchored` is the truth).
#define CAP_WELDED (1<<6)
/// Bolted (airlocks).
#define CAP_BOLTED (1<<7)

// ---- gating keywords: behind = COVER|PANEL, locked_by = LOCK ----
/// The entry is only reachable with the cover open.
#define COVER CAP_COVER_OPEN
/// The entry is only reachable with the panel open.
#define PANEL CAP_PANEL_OPEN
/// The entry refuses while locked.
#define LOCK CAP_LOCKED

// ---- change channels a capability raises ----
/// A capability's state changed (cap_state bit or its data datum).
#define CHANGE_CAPABILITY CHANGE_EXPLICIT

/**
 * Declares a tracked var: generates `set_<V>(value)`, which compares, writes, calls
 * changed(src, CHANNEL) and returns TRUE when the value changed. Declare the var normally next to
 * it. A hand-written `proc/set_<V>()` (for side effects) replaces this line. tools/ci/tracked_lint.py
 * rejects every write to V outside its setter.
 *
 *	/obj/machinery/pump
 *		var/target_pressure = ONE_ATMOSPHERE
 *	TRACKED(/obj/machinery/pump, target_pressure, CHANGE_MACHINE_SETTINGS)
 */
#define TRACKED(T, V, CHANNEL) ##T/proc/set_##V(value) { if(V == value) { return FALSE }; V = value; changed(src, CHANNEL); return TRUE }

// ---- UI helpers ----
/// Returned by a ui_<action> proc that refused (refuse() already told the user).
#define UI_REFUSED "__ui_refused"

// ---- clocks for timed_set ----
/// Real time.
#define CLOCK_WORLD 0
/// The holder's own clock (paused in stasis or suspension).
#define CLOCK_OWN 1

// ---- capability ordering (caps_ordered()) ----
#define CAP_ORDER_DRAW "draw"
#define CAP_ORDER_EXAMINE "examine"
