// Ownership (doc/rewrite/ownership.md): own, shared, proto, relations.
//
// Every object-typed var is exactly one kind. Most need no declaration: the first own_set() /
// own_add() on a var makes it an implicit OWN(DELETE), the first rel_set() / rel_add() an implicit
// REF, and a var typed as a registry type is implicitly SHARED (ownership.md §7). Declare only the
// exceptions: a SPILL / CONTAINED / conditional policy, pairs, keyed links, protos, untyped
// shared vars. Each declaration overrides declared_ownership() and adds one entry on top of
// ..(); own_table_of() (code/datums/ownership/table.dm) caches the result per type.
// VAR is written bare: nameof(PATH::VAR) makes the compiler check it exists.

// ---- kinds (the key of a table entry) ----
/// Owned child(ren). Shape (one / list / assoc values) comes from the value.
#define OWNK_OWN 1
/// A registered immortal singleton or DEF (REGISTRY_TYPE). Never cleared.
#define OWNK_SHARED 2
/// A shared prototype, or a private copy owned by the holder (copy-on-write).
#define OWNK_PROTO 3
/// A light relation edge: a framework-maintained view var (1:1, or a list for 1:N).
#define OWNK_REL 4

// ---- teardown policies (OWNK_OWN) ----
/// Destroyed with the owner.
#define OWN_DELETE 1
/// A movable goes to the owner's drop location; a non-movable is deleted.
#define OWN_SPILL 2
/// A movable in the owner's contents: the ledger slot policy decides. Asserts loc == holder.
#define OWN_CONTAINED 3

// ---- REF shapes (entry[OWNE_OPT] for OWNK_REL) ----
/// One-sided view.
#define RELS_PLAIN 0
/// Two-sided: the partner's var (OWNE_PARTNER) names us back (1:1 or a list of members).
#define RELS_PAIR 1
/// Symmetric membership: both ends list each other in the same var.
#define RELS_SYMMETRIC 2

// ---- table entry layout: list(kind, arg, partner, extra, is_list) ----
#define OWNE_KIND 1
/// OWN: policy, or a proc path (conditional policy). REF: shape. PROTO/SHARED: null.
#define OWNE_ARG 2
/// REF pair/member: the partner var name. OWN_IF: the flag var.
#define OWNE_PARTNER 3
/// REF keyed: list(target type, our key var, their key var). OWN_IF: the else policy.
#define OWNE_EXTRA 4
/// REF: TRUE when the view is a list (1:N side, symmetric membership).
#define OWNE_LIST 5

/// PATH owns VAR's value(s), torn down by POLICY (OWN_DELETE / OWN_SPILL / OWN_CONTAINED).
#define OWN(PATH, VAR, POLICY) ##PATH/declared_ownership() { return own_declare(..(), nameof(PATH::VAR), list(OWNK_OWN, POLICY, null, null, FALSE)); }
/// PATH owns VAR's value(s); POLICY_PROC (a proc path on PATH) returns the policy at teardown.
#define OWN_POLICY(PATH, VAR, POLICY_PROC) ##PATH/declared_ownership() { return own_declare(..(), nameof(PATH::VAR), list(OWNK_OWN, POLICY_PROC, null, null, FALSE)); }
/// POLICY while FLAG (a var on PATH) is true, else ELSE_POLICY.
#define OWN_IF(PATH, VAR, POLICY, FLAG, ELSE_POLICY) ##PATH/declared_ownership() { return own_declare(..(), nameof(PATH::VAR), list(OWNK_OWN, POLICY, nameof(PATH::FLAG), ELSE_POLICY, FALSE)); }

/// VAR holds a registered singleton (an untyped var; typed registry vars are implicit).
#define SHARED(PATH, VAR) ##PATH/declared_ownership() { return own_declare(..(), nameof(PATH::VAR), list(OWNK_SHARED, null, null, null, FALSE)); }
/// VAR holds a registered prototype or a private copy the holder owns.
#define PROTO(PATH, VAR) ##PATH/declared_ownership() { return own_declare(..(), nameof(PATH::VAR), list(OWNK_PROTO, null, null, null, FALSE)); }

/// VAR is a one-sided relation view: a target reference the framework clears when the target dies.
#define REL(PATH, VAR) ##PATH/declared_ownership() { return own_declare(..(), nameof(PATH::VAR), list(OWNK_REL, RELS_PLAIN, null, null, FALSE)); }
/// VAR is a one-sided list view (1:N): members leave it when they die.
#define REL_LIST(PATH, VAR) ##PATH/declared_ownership() { return own_declare(..(), nameof(PATH::VAR), list(OWNK_REL, RELS_PLAIN, null, null, TRUE)); }
/// Two-sided, single on this end: PATH.VAR names a partner whose B_VAR names PATH back (B_VAR may
/// be single or a list). Declare both ends (REL_PAIR or REL_PAIR_LIST on the partner type).
#define REL_PAIR(PATH, VAR, B_VAR) ##PATH/declared_ownership() { return own_declare(..(), nameof(PATH::VAR), list(OWNK_REL, RELS_PAIR, #B_VAR, null, FALSE)); }
/// Two-sided, a list on this end (the "many" side of a 1:N pair, or many-to-many).
#define REL_PAIR_LIST(PATH, VAR, B_VAR) ##PATH/declared_ownership() { return own_declare(..(), nameof(PATH::VAR), list(OWNK_REL, RELS_PAIR, #B_VAR, null, TRUE)); }
/// Symmetric membership: VAR is a list; linking A to B adds each to the other's VAR.
#define REL_SET(PATH, VAR) ##PATH/declared_ownership() { return own_declare(..(), nameof(PATH::VAR), list(OWNK_REL, RELS_SYMMETRIC, nameof(PATH::VAR), null, TRUE)); }
/// A one-sided view auto-linked by id: when PATH or a TARGET_PATH (declared KEYED_TARGET)
/// materializes, VAR links to the TARGET_PATH instance whose key equals our OUR_KEY.
#define REL_KEYED(PATH, VAR, OUR_KEY, TARGET_PATH) ##PATH/declared_ownership() { return own_declare(..(), nameof(PATH::VAR), list(OWNK_REL, RELS_PLAIN, null, list(TARGET_PATH, nameof(PATH::OUR_KEY)), FALSE)); }
/// REL_KEYED with a list view: every matching TARGET_PATH instance.
#define REL_KEYED_LIST(PATH, VAR, OUR_KEY, TARGET_PATH) ##PATH/declared_ownership() { return own_declare(..(), nameof(PATH::VAR), list(OWNK_REL, RELS_PLAIN, null, list(TARGET_PATH, nameof(PATH::OUR_KEY)), TRUE)); }
/// PATH instances are found by REL_KEYED sources through KEY_VAR (indexed while materialized).
#define KEYED_TARGET(PATH, KEY_VAR) ##PATH/keyed_target_var() { return nameof(PATH::KEY_VAR); }

/// Registry singletons: PATH and subtypes are shared. GETTER(D) returns the registered
/// instance D stands for (so D is registered iff GETTER(D) == D).
#define REGISTRY_TYPE(PATH, GETTER) ##PATH/registry_getter() { return GETTER; }

// ---- owned timers ----
/// NAME is a timer the entity owns: at most one pending per (entity, NAME), scheduled with
/// om_after_slot(E, "NAME", ...), read with om_timer_slot_pending()/om_timer_slot_left(),
/// cancelled with om_cancel_timer_slot(), and released by teardown with the entity's other
/// owned things. A keyed family ("NAME:key") is declared once by NAME. Timer ids are never
/// stored in vars (check_grep "stored timer handles").
#define OWN_TIMER(PATH, NAME) ##PATH/declared_timer_slots() { . = ..(); . += #NAME; }

// ---- annotations (not kinds) ----
/// Diagnostic: VAR is deliberately left set after destruction (an id the GC report reads).
#define KEEP_AFTER_DESTROY(PATH, VAR) ##PATH/declared_keep_vars() { . = ..(); LAZYADD(., nameof(PATH::VAR)); }
/// Pooling: pool_release() resets VAR to its initial value. Only on POOL_DECLAREd types.
#define POOL_RESET(PATH, VAR) ##PATH/declared_pool_reset() { . = ..(); LAZYADD(., nameof(PATH::VAR)); }

/// replace_with(): VAR is carried to the successor (om_handle_forward()). An owned value moves
/// (own_move), a relation view re-links, anything else is copied.
#define FORWARD_STATE(PATH, VAR) ##PATH/declared_forward_vars() { . = ..(); LAZYADD(., nameof(PATH::VAR)); }

/// Reports an ownership violation (a runtime, so a test fails; captured in tests of the checks).
#define OWN_REPORT(msg) dq_lifecycle_report("OWN: [msg]")
