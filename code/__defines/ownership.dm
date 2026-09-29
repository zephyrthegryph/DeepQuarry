// Ownership (doc/rewrite/ownership.md): own, shared, proto, relations.
//
// Every object-typed var is exactly one kind. Most need no declaration: the first own_set() /
// own_add() on a var makes it an implicit owns(policy = OWN_DELETE), the first rel_link() an
// implicit plain relation, and a var typed as a registry type is implicitly shared (ownership.md §7).
// Declare only the exceptions (a SPILL / CONTAINED / KEEP / conditional policy, pairs, keyed links,
// hooks, protos, untyped shared vars, annotations) in two per-type list overrides, built once per
// type like capabilities() (type_list()):
//
//	/obj/machinery/sleeper/ownership()
//		. = ..()
//		. += owns(nameof(beaker), policy = OWN_SPILL)
//	/obj/machinery/sleeper/relations()
//		. = ..()
//		. += rel_one(nameof(console), back = nameof(/obj/machinery/sleep_console::sleeper))
//
// Bodies are pure: no instance reads. Var names are always nameof(): nameof(var) for the type's own
// var, nameof(/type::var) for a partner's, so the compiler checks every name.

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
/// owns(nameof(v), policy = OWN_NONE, <annotations>): annotates the var without giving it a kind.
#define OWN_NONE 0
/// Destroyed with the owner.
#define OWN_DELETE 1
/// A movable goes to the owner's drop location; a non-movable is deleted.
#define OWN_SPILL 2
/// A movable in the owner's contents: the ledger slot policy decides. Asserts loc == holder.
#define OWN_CONTAINED 3
/// Released at teardown, not destroyed or moved: the value outlives the owner (a mind's body).
#define OWN_KEEP 4

// ---- what a relation does when the entity at its other end is deleted (other_deleted =) ----
/// The view drops the dead entity (the default).
#define CLEAR 0
/// The holder is deleted too (a throw record whose thrown thing is gone).
#define DELETE_ME 1

// ---- relation shapes (entry[OWNE_ARG] for OWNK_REL) ----
/// One-sided view.
#define RELS_PLAIN 0
/// Two-sided: the partner's var (OWNE_PARTNER) names us back (1:1 or a list of members).
#define RELS_PAIR 1
/// Symmetric membership: both ends list each other in the same var.
#define RELS_SYMMETRIC 2

// ---- table entry layout: list(kind, arg, partner, extra, is_list, watch, other_deleted, on_unlink) ----
#define OWNE_KIND 1
/// OWN: policy, or a proc name (policy_proc). REL: shape. PROTO/SHARED: null.
#define OWNE_ARG 2
/// REL pair/symmetric (back =): the partner var name. OWN with if_var: the flag var.
#define OWNE_PARTNER 3
/// REL keyed: list(target type, our key var). OWN with if_var: the else policy.
#define OWNE_EXTRA 4
/// REL: TRUE when the view is a list (1:N side, symmetric membership).
#define OWNE_LIST 5
/// REL: the target var names the holder's reactive procs read (watch =), or null. While linked,
/// a changed() of the target marks the holder changed too.
#define OWNE_WATCH 6
/// REL: CLEAR or DELETE_ME (other_deleted =).
#define OWNE_OTHER_DELETED 7
/// REL: the holder proc name (on_unlink = PROC_REF(x)) called with the other end when a link goes, or null.
#define OWNE_ON_UNLINK 8

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

/// own_key(D) with the cached key read inline (D must be a typed datum var): the hot paths call it
/// for every link, and nearly every call is a hit.
#define OWN_KEY(D) (D.own_key_text || own_key(D))

/// Reports an ownership violation (a runtime, so a test fails; captured in tests of the checks).
#define OWN_REPORT(msg) dq_lifecycle_report("OWN: [msg]")
