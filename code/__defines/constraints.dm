// Constraints (doc/rewrite/rules.md §3): declared P2 predicates attached to a
// slot, a holder or an item. Code: code/datums/properties/constraints.dm and
// code/datums/properties/equip_slots.dm.

// ---- Constraint kinds: what an item declares ----
/// A holder's contents (storage, holsters): /obj/item/proc/hold_constraint().
/// Evaluated with the inserted thing as PRED_TARGET and the mover as PRED_ACTOR.
#define CONSTRAINT_HOLD "hold"
/// What a worn suit takes in its suit-storage slot: suit_storage_constraint().
/// null means the suit has no suit storage.
#define CONSTRAINT_SUIT_STORAGE "suit_storage"
/// Who an item fits (species body types): fit_constraint(). Checked for every
/// equip slot except pockets and suit storage. PRED_ACTOR is the wearer.
#define CONSTRAINT_FIT "fit"
/// What an item needs of its wearer in any equip slot: equip_constraint().
#define CONSTRAINT_EQUIP "equip"

// ---- Clauses added for constraints ----
#define PRED_OP_TYPE "type"
#define PRED_OP_FITS "fits"

/// The subject is one of `types` or a subtype (compiled to a typecache).
#define REQ_TYPE(subject, types) list(PRED_OP_TYPE, subject, types)
#define REQ_NOT_TYPE(subject, types) REQ_NOT(REQ_TYPE(subject, types))
/// PRED_TARGET (an item) fits PRED_ACTOR's body type. `bodytypes` is the
/// legacy species list: body types that fit, or "exclude" followed by the ones
/// that don't. Actors that aren't humans with a species always pass.
#define REQ_FITS_BODYTYPES(bodytypes) list(PRED_OP_FITS, bodytypes)

// ---- Holder shorthands (hold_constraint(), suit_storage_constraint()) ----
#define HOLD_ONLY(types) REQ_BECAUSE(REQ_TYPE(PRED_TARGET, types), "it doesn't take that")
#define HOLD_NOT(types) REQ_BECAUSE(REQ_NOT_TYPE(PRED_TARGET, types), "it doesn't take that")
#define HOLD_MAX_SIZE(size) REQ_AT_MOST(PRED_TARGET, PROP_SIZE_CLASS, SIZE_CLASS(size))

// ---- Reads ----
/// The compiled constraint of `kind` on item `I`, or null if it declares none.
#define CONSTRAINT(I, kind) dq_constraint(I, kind)
