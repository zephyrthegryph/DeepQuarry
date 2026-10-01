// Capabilities, tracked state and the refresh engine (doc/rewrite/dx_conventions.md).
// Runtime: code/datums/capabilities/.

// ---- cap_state bits: ALL allocated in code/__defines/cap_bits.dm (tools/ci/cap_bits_lint.py) ----
// ---- storage categories (L1: the one allocation of HOLDS_* bits) ----
// A cap_storage() holder's `holds` is a mask of these; an item's `storage_class` says which it is.
// can_hold rule (storage.dm): HOLDS_ANY takes anything that fits; otherwise an item fits when
// (holds & HOLDS_TOOLS) and it has tool qualities, or (item.storage_class & holds) != 0.
// DM bitfields are safe to 24 bits.
/// Anything with a tool quality (no storage_class needed).
#define HOLDS_TOOLS (1<<0)
/// Cable, flashlights, meters, circuit boards, engineering consumables.
#define HOLDS_ENGINEERING (1<<1)
/// Medicine, bandages, scanners, pill bottles.
#define HOLDS_MEDICAL (1<<2)
/// Food and drink.
#define HOLDS_FOOD (1<<3)
/// Magazines, casings, cells for weapons.
#define HOLDS_AMMO (1<<4)
/// Small weapons (knives, batons, holstered guns).
#define HOLDS_WEAPONS (1<<5)
/// Paper, pens, folders, stamps, photos.
#define HOLDS_PAPERWORK (1<<6)
/// Clothing and accessories.
#define HOLDS_CLOTHING (1<<7)
/// Seeds and plant produce.
#define HOLDS_BOTANY (1<<8)
/// Ore, sheets and raw materials.
#define HOLDS_MINING (1<<9)
/// Beakers, bottles, vials and other reagent containers.
#define HOLDS_CHEMISTRY (1<<10)
/// Science samples, slimes cores, disks.
#define HOLDS_SCIENCE (1<<11)
/// Cuffs, flashes, evidence bags.
#define HOLDS_SECURITY (1<<12)
/// Cleaning supplies.
#define HOLDS_JANITORIAL (1<<13)
/// Cigarettes, lighters, matches.
#define HOLDS_SMOKABLES (1<<14)
/// ID cards, cash, coins.
#define HOLDS_CARDS (1<<15)
/// Power cells.
#define HOLDS_CELLS (1<<16)
/// Every category, and anything with no category at all: only size and space limit it.
#define HOLDS_ANY ((1<<24) - 1)

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
 * changed(src, CHANNEL, "V") and returns TRUE when the value changed. Declare the var normally next
 * to it. A hand-written `proc/set_<V>()` (for side effects) replaces this line and passes the var
 * name too: changed(src, CHANNEL, nameof(V)). tools/ci/tracked_lint.py rejects every write to V
 * outside its setter. A type that declares its dependencies (derived()) re-derives only the outputs
 * that read V when it changes.
 *
 *	/obj/machinery/pump
 *		var/target_pressure = ONE_ATMOSPHERE
 *	TRACKED(/obj/machinery/pump, target_pressure, CHANGE_MACHINE_SETTINGS)
 */
/// TRUE for a GLOBAL_PROC_REF() (a /proc/ path), FALSE for a type proc ref: holder_call() and dispatch_call() pass a
/// global proc the holder as an argument instead of calling it on the holder.
#define IS_GLOBAL_PROC_REF(P) (copytext("[P]", 1, 7) == "/proc/")

#define TRACKED(T, V, CHANNEL) ##T/proc/set_##V(value) { if(V == value) { return FALSE }; V = value; changed(src, CHANNEL, #V); return TRUE };SETTER(T, V)

/**
 * Registers a hand-written `T/proc/set_<V>(value)` as V's setter (a setter with side effects):
 * admin var edits go through it, and tools/ci/tracked_lint.py treats V as tracked (writes only in the
 * setter). Only registered setters are called by VV: a proc that merely happens to be named set_<x>
 * (a verb, another signature) never is.
 */
#define SETTER(T, V) ##T/proc/__setter_##V() { return TRUE }

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

// ---- periodic cadences (periodic_cadence = CADENCE_*; periodic_step(delta) gets the interval in ds) ----
/// Every 2 seconds.
#define CADENCE_SLOW /datum/cadence/slow
/// Every second.
#define CADENCE_SECOND /datum/cadence/second
/// Every 0.2 seconds (continuous lanes need a reason).
#define CADENCE_FAST /datum/cadence/fast

/// The reagents capability's key (reagents(), code/datums/capabilities/library/reagents.dm): refine(CAP_REAGENTS,
/// starts = ...) adds to the inherited contents, without(., CAP_REAGENTS) drops the holder.
#define CAP_REAGENTS /datum/capability/reagents

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
/// A light fixture of an area (powered_by(POWERED_BY_AREA, role = POWER_ROLE_LIGHTING)): members_of(area, role).
#define POWER_ROLE_LIGHTING "lighting"
/// A computer console of an area.
#define POWER_ROLE_COMPUTER "computer"
/// powered_by(POWERED_BY_AREA, ...): the holder is a MEMBER relation of the area it stands in, not of a system.
#define POWERED_BY_AREA "area"
/// cell_bay(): at or below this charge (percent) cap_cell_charged() refuses.
#define CELL_BAY_LOW_PERCENT 15
/// cap_wall_mount(): pixels from the turf centre into the wall.
#define WALL_MOUNT_OFFSET 26
/// Every minute.
#define CADENCE_MINUTE /datum/cadence/minute
