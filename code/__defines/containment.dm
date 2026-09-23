// Containment ledger and slots (doc/rewrite/containment.md §2-3, roadmap C1).

// ---- Slot ids (a holder's slots are named by these) ----
/// The one interior slot of a closet, crate or locker.
#define CONTAINER_SLOT_INTERIOR "interior"
/// Inside a legacy /obj/item/storage (until C4).
#define CONTAINER_SLOT_STORAGE "storage"
/// A folder's pages.
#define CONTAINER_SLOT_PAGES "pages"

// ---- Exposure (containment.md §3.1) ----
#define SLOT_EXPOSURE_EXTERNAL 1
#define SLOT_EXPOSURE_INTERNAL 2

// ---- Capacity models ----
/// No limit.
#define SLOT_CAPACITY_NONE 0
/// Each thing costs 1.
#define SLOT_CAPACITY_COUNT 1
/// Each thing costs its size class (PROP_SIZE_CLASS).
#define SLOT_CAPACITY_SIZE 2
/// Each thing costs its mass in kg (PROP_MASS).
#define SLOT_CAPACITY_MASS 3
/// Each thing costs what the slot definition's cost() says.
#define SLOT_CAPACITY_UNITS 4

// ---- Drop policies: what the base Destroy() does with a slot's contents ----
/// Move them to the holder's drop location. Deleted if there is none.
#define SLOT_DROP_SPILL 1
/// Delete them with the holder.
#define SLOT_DROP_DELETE 2
/// Move them into the holder's own container's default slot, else spill.
#define SLOT_DROP_TRANSFER 3

// ---- Entry records (the ledger's per-thing list) ----
#define LEDGER_E_SLOT 1
#define LEDGER_E_SERIAL 2
#define LEDGER_E_COST 3
/// Snapshot of the thing's contribution to the aggregates: measure values in
/// the ledger's measure order, then tag words.
#define LEDGER_E_SNAPSHOT 4
#define LEDGER_E_LEN 4

/// Separates a slot id from the serial in an entry id: "interior#12".
#define LEDGER_ENTRY_SEPARATOR "#"
