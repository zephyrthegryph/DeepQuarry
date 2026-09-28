// Body part slots (doc/medical_frameworks.md §2.2-2.3, slice O2).
//
// The limb tree is physically nested: the torso sits in its mob's
// SLOT_ID_PART_ROOT slot, each child limb in its parent's SLOT_ID_PART_CHILD
// slot, and each internal organ in its limb's SLOT_ID_PART_ORGANS slot. The
// ledger is the source of truth; code/modules/body/parts/attach.dm keeps the
// derived state (owner, the mob's organ caches) from the J6 commit hooks.

// ---- Slot ids ----
/// A humanoid mob's one root part (the torso). Declared on the humanoid plan.
// Implants use ORGAN_SLOT_IMPLANTS (the implant_site relation slot, organ_external.dm).
#define SLOT_ID_PART_ROOT "parts:root"
/// A limb's child limbs (an arm's hand). Keyed by organ_tag.
#define SLOT_ID_PART_CHILD "parts:child"
/// A limb's internal organs. Keyed by organ_tag.
#define SLOT_ID_PART_ORGANS "parts:organs"
/// Shrapnel and thrown weapons stuck in a limb (O3b/O3c move them here).
#define SLOT_ID_PART_EMBEDDED "parts:embedded"
/// Surgically placed items. A limb's default slot, so a legacy move of a
/// non-part into a limb lands here rather than among its parts.
#define SLOT_ID_PART_CAVITY "parts:cavity"
/// One splint.
#define SLOT_ID_PART_SPLINT "parts:splint"
/// One tourniquet.
#define SLOT_ID_PART_TOURNIQUET "parts:tourniquet"

/// Whether `slot_id` is one of the structural part slots whose occupant is
/// attached to the body its tree hangs from.
#define IS_PART_TREE_SLOT(slot_id) ((slot_id) == SLOT_ID_PART_ROOT || (slot_id) == SLOT_ID_PART_CHILD || (slot_id) == SLOT_ID_PART_ORGANS)

// ---- Organ slots (O-slots) ----
// Internal organs are keyed entries (key: organ_tag, O_*) in their limb's
// SLOT_ID_PART_ORGANS slot, or, for a mob with no part tree, loose in its
// SLOT_ID_BODY interior slot. The ledger is the only record: there are no
// mob-side organ lists. Read through these (code/modules/body/parts/queries.dm):
//   M.organ_in(O_HEART)         the attached organ keyed O_HEART, or null
//   INTERNAL_ORGANS(M)          a fresh list of every attached internal organ
//   ORGAN_IN(M, tag)            macro form of organ_in()
// Write through the ledger: move_into(limb, SLOT_ID_PART_ORGANS) / place_into()
// to insert, removed() / slot_remove() to take out. tools/ci/organ_slots_lint.py
// keeps the deleted lists deleted.
#define ORGAN_IN(M, tag) ((M).organ_in(tag))
#define INTERNAL_ORGANS(M) ((M).internal_organ_list())
