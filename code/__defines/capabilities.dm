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
 * Declares a tracked var: generates `set_<V>(value)`, which compares, writes and returns TRUE when the value
 * changed; a change publishes the key "V" (publish_change(src, nameof(V))) only when READERS(src, "V") says someone
 * reads it (an on_change / on_cross reaction, a generated read, an observer), and re-derives the outputs that read
 * V. Declare the var normally next to it. A hand-written `proc/set_<V>()` (for side effects) replaces this line,
 * calls tracked_changed(src, nameof(V)) and registers itself with SETTER(T, V). tools/ci/tracked_lint.py rejects
 * every write to V outside its setter.
 *
 *	/obj/machinery/pump
 *		var/target_pressure = ONE_ATMOSPHERE
 *	TRACKED(/obj/machinery/pump, target_pressure)
 */
/// TRUE for a GLOBAL_PROC_REF() (a /proc/ path), FALSE for a type proc ref: holder_call() and dispatch_call() pass a
/// global proc the holder as an argument instead of calling it on the holder.
#define IS_GLOBAL_PROC_REF(P) (copytext("[P]", 1, 7) == "/proc/")

#define TRACKED(T, V) ##T/proc/set_##V(value) { if(V == value) { return FALSE }; V = value; tracked_changed(src, #V); return TRUE };SETTER(T, V)

/**
 * BRIDGE (removed with S4): TRACKED() that also raises the OM channel CHANNEL, for a var an OM stage `wake_on` or an
 * om_watch() still listens to by channel (the machine pipeline wakes on CHANGE_MACHINE_SETTINGS). Everything else
 * uses TRACKED(T, V). When the last channel consumer of V is gone, drop the third argument.
 */
#define TRACKED_BRIDGED(T, V, CHANNEL) ##T/proc/set_##V(value) { if(V == value) { return FALSE }; V = value; changed(src, CHANNEL, #V); return TRUE };SETTER(T, V)

/**
 * Registers a hand-written `T/proc/set_<V>(value)` as V's setter (a setter with side effects):
 * admin var edits go through it, and tools/ci/tracked_lint.py treats V as tracked (writes only in the
 * setter). Only registered setters are called by VV: a proc that merely happens to be named set_<x>
 * (a verb, another signature) never is.
 */
#define SETTER(T, V) ##T/proc/__setter_##V() { return TRUE }

/**
 * Names the change key that covers V: V is written only by producers that publish KEY (a bit field set through a
 * helper, a value a subsystem rewrites). tools/ci/derived_reads_lint.py generates KEY for a presentation reaction
 * that reads V, and accepts V as published. `__published_<V>()` returns the key (tests check producers with it).
 */
#define PUBLISHED_BY(T, V, KEY) ##T/proc/__published_##V() { return KEY }

/**
 * One-line capability declaration: `CAPABILITY(/obj/item/reagent_containers/food/snacks/donut, reagents(20, starts =
 * list(REAGENT_ID_NUTRIMENT = 3)))`. Expands to a declared_capabilities() override that adds ENTRY after ..(),
 * collected into the type's capabilities table after its capabilities() list (caps_build()). Any capability
 * constructor, bundle or refine() works; several lines on one type add in file order. Use it for data-only
 * subtypes; a type with logic keeps a capabilities() override (both may coexist).
 */
#define CAPABILITY(T, ENTRY) ##T/declared_capabilities(list/into) { ..(); into += ENTRY; }

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

// ---- what a type derives (type_derive_flags(), cached per type) ----
#define TYPE_DERIVES_CAPS (1<<0)
#define TYPE_DERIVES_LOOK (1<<1)
#define TYPE_DERIVES_VERBS (1<<2)
/// Not yet known: the type's first refresh fills in LOOK and VERBS.
#define TYPE_DERIVES_PENDING (1<<3)
/// type_verbs() lists something.
#define TYPE_DERIVES_TYPE_VERBS (1<<4)
/// The type declares its dependencies (derived()): its instances join the relation index at init.
#define TYPE_DERIVES_DEPS (1<<5)
/// The type overrides a refresh side effect (on_state_changed() or push_to_rust()), or its probe could not rule it out:
/// a refresh of it does work even when it draws and hides nothing, so its refreshes are never skipped.
#define TYPE_DERIVES_SIDE (1<<6)

// ---- periodic cadences (periodic_cadence = CADENCE_*; periodic_step(delta) gets the interval in ds) ----
/// Every 2 seconds.
#define CADENCE_SLOW /datum/cadence/slow
/// Every second.
#define CADENCE_SECOND /datum/cadence/second
/// Every 0.2 seconds (continuous lanes need a reason).
#define CADENCE_FAST /datum/cadence/fast

/// /datum/capability/condition `blocks`: the condition refuses every other capability entry of its holder.
#define ALL_ENTRIES "all_entries"

// ---- power_channels() / powered_by() / cell_bay() / cap_wall_mount() ----
/// power_channels(): channel indices (Rust's channel order).
#define POWER_CHANNEL_EQUIPMENT 0
#define POWER_CHANNEL_LIGHTING 1
#define POWER_CHANNEL_ENVIRON 2
/// powered_by(/datum/system/power, role =): what the holder is to the power system.
#define POWER_ROLE_AREA_SUPPLY "area_supply"
#define POWER_ROLE_PRODUCER "producer"
#define POWER_ROLE_STORAGE "storage"
#define POWER_ROLE_CONSUMER "consumer"
/// The power capability's tracked "powered" state (G8): a machine's NOPOWER, written only by set_powered()
/// (power_change()); published to its readers on a change. The draw mode is the tracked var nameof(use_power).
#define MACHINE_KEY_POWERED "machine_powered"
/// The integrity state (G8): published by atom_break() / atom_fix(), the only writers of a machine's BROKEN.
#define INTEGRITY_KEY_BROKEN "integrity_broken"
/// cell_bay(): at or below this charge (percent) cap_cell_charged() refuses.
#define CELL_BAY_LOW_PERCENT 15
/// cap_wall_mount(): pixels from the turf centre into the wall.
#define WALL_MOUNT_OFFSET 26
/// Every minute.
#define CADENCE_MINUTE /datum/cadence/minute
