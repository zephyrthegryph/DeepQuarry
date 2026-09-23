// Containment ledger and slots (doc/rewrite/containment.md §2-3, roadmap C1).

// ---- Slot ids (a holder's slots are named by these) ----
/// The one interior slot of a closet, crate or locker.
#define CONTAINER_SLOT_INTERIOR "interior"
/// Inside a legacy /obj/item/storage (until C4).
#define CONTAINER_SLOT_STORAGE "storage"
/// A folder's pages.
#define CONTAINER_SLOT_PAGES "pages"
/// The sealed interior of a vore belly (C7).
#define BELLY_SLOT_INTERIOR "belly"
/// A vending machine's or smartfridge's stock (C9, stock.dm).
#define CONTAINER_SLOT_STOCK "stock"
/// A machine's legacy internals: parts, circuit, coin. The machine's Destroy owns them.
#define CONTAINER_SLOT_INTERNALS "internals"
/// A storage item's interior (/obj/item/storage, C4).
#define CONTAINER_SLOT_STORAGE "storage"

// ---- Occupant machines (C8, containment.md §10) ----
/// The sealed occupant slot of a cryopod-family despawner.
#define OCCUPANT_SLOT_CRYOPOD "cryopod_occupant"
/// The sealed occupant slot of a resleeving pod.
#define OCCUPANT_SLOT_RESLEEVER "resleever_occupant"
/// The sealed occupant slot of an implant chair.
#define OCCUPANT_SLOT_IMPLANT_CHAIR "implant_chair_occupant"
/// The sealed occupant slot of a gibber.
#define OCCUPANT_SLOT_GIBBER "gibber_occupant"
/// The sealed occupant slot of a cyborg recharge station.
#define OCCUPANT_SLOT_RECHARGE_STATION "recharge_occupant"
/// The sealed occupant slot of a DNA modifier scanner.
#define OCCUPANT_SLOT_DNA_SCANNER "dna_scanner_occupant"
/// The sealed occupant slot of a suit storage unit.
#define OCCUPANT_SLOT_SUIT_STORAGE "suit_storage_occupant"
/// A mecha's sealed pilot slot.
#define MECHA_SLOT_PILOT "mecha_pilot"
/// A mecha's external hardpoint slot for attached equipment.
#define MECHA_SLOT_EQUIPMENT "mecha_equipment"
/// A mecha's internal cargo compartment slot.
#define MECHA_SLOT_CARGO "mecha_cargo"

// ---- Body slots (C3, code/modules/body/slots.dm): a mob's slots, per body plan ----
/// Everything inside a mob that isn't equipment: organs, implants, bellies,
/// held abilities. The default slot, so legacy moves into a mob land here.
#define SLOT_ID_BODY "body"
#define SLOT_ID_HAND_L "hand_l"
#define SLOT_ID_HAND_R "hand_r"
#define SLOT_ID_BACK "back"
#define SLOT_ID_BELT "belt"
#define SLOT_ID_POCKET_L "pocket_l"
#define SLOT_ID_POCKET_R "pocket_r"
#define SLOT_ID_UNIFORM "uniform"
#define SLOT_ID_SUIT "suit"
#define SLOT_ID_SUIT_STORAGE "suit_storage"
#define SLOT_ID_HEAD "head"
#define SLOT_ID_MASK "mask"
#define SLOT_ID_EYES "eyes"
#define SLOT_ID_EAR_L "ear_l"
#define SLOT_ID_EAR_R "ear_r"
#define SLOT_ID_GLOVES "gloves"
#define SLOT_ID_SHOES "shoes"
#define SLOT_ID_ID "id"
#define SLOT_ID_HANDCUFFED "handcuffed"
#define SLOT_ID_LEGCUFFED "legcuffed"
/// A cyborg's three active module slots.
#define SLOT_ID_MODULE_1 "module_1"
#define SLOT_ID_MODULE_2 "module_2"
#define SLOT_ID_MODULE_3 "module_3"
/// Module slot `n` (1-3), computed.
#define SLOT_ID_MODULE(n) "module_[n]"

// ---- Body slot roles (/datum/slot_def/body/var/roles) ----
/// Worn: its item's worn_factors apply (not hands, pockets or restraints).
#define BODY_SLOT_WORN (1<<0)
/// Its clothing's armour covers the body parts in body_parts_covered.
#define BODY_SLOT_ARMOR (1<<1)
/// Its clothing's conductivity and thermal protection count.
#define BODY_SLOT_INSULATION (1<<2)

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
/// The thing's `slot_key()` at insert time, for a keyed slot (J4). Null for
/// an unkeyed slot, or a keyed slot whose thing has no key right now.
#define LEDGER_E_KEY 5
#define LEDGER_E_LEN 5

/// Separates a slot id from the serial in an entry id: "interior#12".
#define LEDGER_ENTRY_SEPARATOR "#"

// ---- slot_remove() flags (J2) ----
/// Skip the removal refusal, the acceptance refusal and both pre signals.
/// The commit bookkeeping (note_exit/note_enter, COMSIG_SLOT_*, on_slotted/
/// on_unslotted) still runs. Used to spill or transfer a holder's contents
/// while it is being destroyed (ledger_apply_drop_policies()), where the
/// move must not be refusable.
#define LEDGER_MOVE_FORCED (1<<0)
