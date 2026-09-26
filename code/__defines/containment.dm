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
/// An organ's implant site: keyed by implant type (OM relations step 2).
#define ORGAN_SLOT_IMPLANTS "implants"

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
/// The sealed occupant slot of a medical sleeper.
#define OCCUPANT_SLOT_SLEEPER "sleeper_occupant"
/// The sealed occupant slot of a cryo tube.
#define OCCUPANT_SLOT_CRYO "cryo_occupant"
/// The sealed occupant slot of an advanced medical body scanner.
#define OCCUPANT_SLOT_BODY_SCANNER "body_scanner_occupant"
/// The sealed occupant slot of a cloning pod.
#define OCCUPANT_SLOT_CLONEPOD "clonepod_occupant"
/// The sealed occupant slot of a VR pod's avatar shell.
#define OCCUPANT_SLOT_VR_POD "vr_pod_occupant"
/// The sealed occupant slot of a ballistic transport pod.
#define OCCUPANT_SLOT_TRANSPORTPOD "transportpod_occupant"
/// The sealed occupant slot of a mech passenger seat equipment item.
#define OCCUPANT_SLOT_MECHA_PASSENGER "mecha_passenger_occupant"
/// The sealed occupant slot of a mech-mounted sleeper equipment item.
#define OCCUPANT_SLOT_MECHA_SLEEPER "mecha_sleeper_occupant"
/// The sealed occupant slot of a Tyr project stasis prop.
#define OCCUPANT_SLOT_TYR_PROP "tyr_prop_occupant"
/// The sealed occupant slot of a suit cycler.
#define OCCUPANT_SLOT_SUIT_CYCLER "suit_cycler_occupant"
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

// ---- Body slot roles (/datum/om/relation/slot/body/var/roles) ----
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
/// Delete them with the holder (recursively, children first -- L1 phase 3).
#define SLOT_DROP_DELETE 2
/// A declared resolver (doc/rewrite/lifecycle.md §3's TRANSFER(resolver))
/// picks the destination: /datum/om/relation/slot/proc/drop_resolver(). The default
/// resolver is today's behaviour (the holder's own container's default
/// slot, else spill); override it for anything else -- occupant ejection,
/// mind transfer, mecha equipment to the mech's turf.
#define SLOT_DROP_TRANSFER 3
/// Deprecated (doc/rewrite/lifecycle.md §3: "SLOT_DROP_HOLDER is removed").
/// Left to the holder's own Destroy(), unmigrated. Restricted to the two
/// remaining owners outside this track's scope: body equipment/organ slots
/// (DQ Medical, O2/O4) and machine internals (stock.dm, C6). Nothing else
/// may add a new use.
#define SLOT_DROP_HOLDER 4
/// Contents fold into latent entries on a declared successor instead of
/// staying real (doc/rewrite/lifecycle.md §3's TO_LATENT): debris, wreckage.
/// /datum/om/relation/slot/proc/latent_successor(holder) names it.
#define SLOT_DROP_TO_LATENT 5
/// Moves into a slot of replace_with()'s successor (doc/rewrite/lifecycle.md
/// §3's KEEP_WITH(slot)); falls back to SPILL when nothing is replacing the
/// holder. /datum/om/relation/slot/proc/keep_with_slot() names the destination slot.
#define SLOT_DROP_KEEP_WITH 6

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
/// while it is being destroyed (dq_lifecycle_resolve_contents(), L1), where
/// the move must not be refusable.
#define LEDGER_MOVE_FORCED (1<<0)
/// L1 (doc/rewrite/lifecycle.md §3): this move is the destroy transaction
/// resolving a slot's declared policy, not an ordinary player/game move.
/// Passed to on_slotted()/on_unslotted() (J6) and holder_destroying() is
/// queryable during it, so a hook can skip re-derivation (body invalidate,
/// om_changed, HUD, factor recompute) that a moment-later qdel would waste.
/// Always combined with LEDGER_MOVE_FORCED.
#define LEDGER_MOVE_DESTROYING (1<<1)

// ---- J5: the move hook gate (atom/movable/var/move_hooks) ----
// One shared mechanism for anything that needs to react to every move of a
// specific thing, cheaply, even when it's nested arbitrarily deep in
// holders that themselves aren't hooked (a clocked item in a carried bag).
// The gate is one var test (doMove(), atoms_movable.dm): `if(move_hooks)`.
// Own-hook bits mean "call my own move_hook_before()/move_hook_after()".
// MOVE_HOOK_SUBTREE means "walk my contents; something inside is hooked",
// kept accurate by the ledger's note_enter()/note_exit() (an O(1) counter,
// not a rescan) the same way it already bubbles aggregate changes.
/// DQ Medical's clock framework (K1): a holder-provided clock following
/// this thing. Reserved here; K1 writes the handler.
#define MOVE_HOOK_CLOCK (1<<0)
/// C10 (latency policy): reserved here; C10 writes the handler. C10's
/// dq_latent_touch in note_enter stays unconditional -- only its
/// collapse-cancel uses this bit.
#define MOVE_HOOK_LATENCY (1<<1)
/// Set (by the ledger, not by hand) on any holder with a hooked descendant
/// somewhere in its slots, so a move of the holder itself knows to walk in
/// and fire that descendant's hooks too, since the descendant's own `loc`
/// doesn't change when its container moves.
#define MOVE_HOOK_SUBTREE (1<<2)
