// Capabilities, tracked state and the refresh engine (doc/rewrite/dx_conventions.md).
// Runtime: code/datums/capabilities/.

// ---- cap_state bits: ALL allocated in code/__defines/cap_bits.dm (tools/ci/cap_bits_lint.py) ----

// ---- gating keywords: behind = COVER|PANEL, locked_by = LOCK ----
/// The entry is only reachable with the cover open.
#define COVER CAP_COVER_OPEN
/// The entry is only reachable with the panel open.
#define PANEL CAP_PANEL_OPEN
/// The entry refuses while locked.
#define LOCK CAP_LOCKED

// ---- layers ----
/// layer = CAP_NO_LAYER: the capability draws nothing (a DMI without that state). DM substitutes the
/// default for an explicit null argument, so null can't mean "none".
#define CAP_NO_LAYER "__none"

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

// ---- emag() modes ----
/// The emag works once: a second swipe is refused with already_say.
#define EMAG_ONCE 0
/// The emag works every time (its effect runs again).
#define EMAG_REPEATABLE 1

// ---- tool arguments ----
/// cover(open_tool = BY_HAND): opened with an empty hand. (DM substitutes a default for an explicit
/// null argument, so null can't mean "by hand".)
#define BY_HAND "by_hand"
