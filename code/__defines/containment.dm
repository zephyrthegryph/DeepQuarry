// Containment ledger and slots (doc/rewrite/containment.md §2-3, roadmap C1).

// ---- Slot ids (a holder's slots are named by these) ----
/// The one interior slot of a closet, crate or locker.
#define CONTAINER_SLOT_INTERIOR "interior"
/// A folder's pages.
#define CONTAINER_SLOT_PAGES "pages"
/// The sealed interior of a vore belly (C7).
#define BELLY_SLOT_INTERIOR "belly"
/// A vending machine's or smartfridge's stock (C9, stock.dm).
#define CONTAINER_SLOT_STOCK "stock"
/// A machine's legacy internals: parts, circuit, coin. The machine's Destroy owns them.
#define CONTAINER_SLOT_INTERNALS "internals"

// ---- Exposure (containment.md §3.1) ----
/// Outside the holder's shell: held, worn outer layer, mounted. Sees the
/// holder's surroundings; the holder's own insulation and armour don't cover it.
#define SLOT_EXPOSURE_EXTERNAL 1
/// Inside the holder's shell: pocket, bag interior, closet, belly, machine
/// internals. Shares the holder's surroundings' air.
#define SLOT_EXPOSURE_INTERNAL 2
/// Inside, with its own interior: blocks gas from the surroundings.
#define SLOT_EXPOSURE_SEALED 3

// ---- Layers (containment.md §3.1): order among slots at the same place ----
/// Not layered.
#define SLOT_LAYER_NONE 0
#define SLOT_LAYER_UNDERSUIT 10
#define SLOT_LAYER_UNIFORM 20
#define SLOT_LAYER_SUIT 30
#define SLOT_LAYER_HARDSUIT 40
#define SLOT_LAYER_PLATE 50

// ---- Propagation paths (containment.md §3.2, roadmap C2) ----
#define PATH_EFFECT_HEAT 1
#define PATH_EFFECT_DAMAGE 2
#define PATH_EFFECT_GAS 3
#define PATH_EFFECT_RADIATION 4
/// Shares below this are dropped rather than delivered.
#define PATH_MIN_SHARE 0.001

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
/// Leave them: the holder's own Destroy() deals with them (legacy machine internals, until C6).
#define SLOT_DROP_HOLDER 4

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
