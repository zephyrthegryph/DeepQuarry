// Declarative lifecycle (doc/rewrite/declarative_lifecycle.md).
//
// One line next to a type replaces the generic work an Initialize() override or an
// on_destroy() hook used to do by hand. Every macro below adds one entry to the type's
// /datum/lifecycle_decls table (code/datums/lifecycle/declarations.dm), built once per type
// on first use and shared by every instance. The lifecycle runs the table:
//
//   init         (end of /atom/Initialize(), and table_initialize()): instance state that
//                subtype Initialize() code may read right after `. = ..()`:
//                  1. owned children   DECLARE_DEFAULT_CHILD (now owns(starts =): code/datums/ownership/table.dm)
//                  2. gas contents     DECLARE_GAS
//                  3. reagents         DECLARE_REAGENTS
//                  4. appearance       DECLARE_APPEARANCE
//   materialize  (/atom/on_materialize(), after registries, rules and OM start):
//                  5. registries       DECLARE_REGISTRY (conditional ones are joined here)
//                  6. service members  DECLARE_SERVICE_MEMBER
//                  7. binds            DECLARE_BIND (batched per SSatoms batch)
//                  8. behaviours       DECLARE_BEHAVIOUR, DECLARE_PERIODIC, DECLARE_START_TIMER
//   dematerialize (/atom/on_dematerialize()): 8..5 in reverse (periodic stop, service leave;
//                registries, behaviours and timers are already left by the core).
//   destroy      phase 1 (unbind): DECLARE_BIND release. Phase 4 deletes the children
//                (their DECLARE_REF kind). Phase 6: DESTROY_EFFECTS data, including
//                drop_contents and a debris list.
//
// Every declaration is evaluated once per type: arguments must be constants (numbers, paths,
// strings, lists of those). Where an amount can differ per instance (a mapped volume) pass the
// var's name as a string and it is read from the instance when applied.

/// Adds one entry to PATH's declaration table. Internal: use the named macros below.
#define _LIFECYCLE_DECL(PATH, CALL) ##PATH/declare_lifecycle(datum/lifecycle_decls/decls) { ..(); decls.##CALL; }

/// 1. Owned child created at init. LEGACY: the foundation form is the relation's starting occupant,
///	rel_one(nameof(cell), /obj/item/cell, kind = RELK_OWNED, policy = OWN_SPILL, starts = nameof(cell_type))
/// in relations() (doc/rewrite/state_and_relations.md section 2); this macro is a thin wrapper over it
/// that adds only the `starts` annotation (the var keeps whatever kind/policy ownership() or relations()
/// give it, else the first own_set() learns OWN_DELETE). DEFAULT is a type path, a list of type paths (or
/// `list(type = count)`) for a list var, or the name of a var holding the type (e.g. "cell_type"). The var
/// itself wins: holding a path (`var/obj/item/cell/cell = /obj/item/cell/high`) creates that path; holding
/// an instance creates nothing (a null DEFAULT names the var itself: whatever path it holds is made). Children
/// are created with `new type(src)`.
#define DECLARE_DEFAULT_CHILD(PATH, VAR, DEFAULT) ##PATH/relations() { . = ..(); . += owns(VAR, policy = OWN_NONE, starts = (isnull(DEFAULT) ? VAR : DEFAULT)); }

/// 2. LEGACY: the foundation form is `gas_store(nameof(var), volume, temp, gases)` in capabilities()
/// (code/datums/capabilities/library/gas_store.dm; doc/rewrite/lifecycle.md section 9).
/// A gas mixture created at init in VAR (declare VAR OWNED). VOLUME: litres, or a var name.
/// GASES: list(GAS_O2 = kPa, ...) at TEMP kelvin (moles = P*V / (R*T)).
#define DECLARE_GAS(PATH, VAR, VOLUME, TEMP, GASES) _LIFECYCLE_DECL(PATH, set_gas(VAR, VOLUME, TEMP, GASES))

/// 3. LEGACY: the foundation form is `reagents(volume, starts = list(...))` in capabilities(), with
/// `refine(CAP_REAGENTS, starts = ...)` on subtypes and `without(., CAP_REAGENTS)` for DECLARE_NO_REAGENTS
/// (code/datums/capabilities/library/reagents.dm; doc/rewrite/lifecycle.md section 9). Never mix the forms in a chain.
/// Starting reagents at init: create_reagents(VOLUME) then add CONTENTS
/// (list(REAGENT_ID_X = amount, ...), or null for an empty holder). VOLUME: a number, a var
/// name ("volume"), or null to keep the parent's. CONTENTS ADD to the parent's declared contents,
/// the way the old `. = ..(); reagents.add_reagent(...)` chain added to the parent's; the
/// declaration table is shared by the type, the per-instance reagent datums exist only in the
/// holder (empty holders already share one empty list).
#define DECLARE_REAGENTS(PATH, VOLUME, CONTENTS) _LIFECYCLE_DECL(PATH, set_reagents(VOLUME, CONTENTS, null, FALSE))
/// A holder of VOLUME holding the reagent named by the instance var ID_VAR, AMOUNT units
/// (a number, or the name of an instance var); both read per atom at init.
#define DECLARE_REAGENT_FROM_VAR(PATH, VOLUME, ID_VAR, AMOUNT) _LIFECYCLE_DECL(PATH, set_reagent_var(VOLUME, ID_VAR, AMOUNT))
/// DECLARE_REAGENTS, then `color = reagents.get_color()` (pills, patches).
#define DECLARE_REAGENTS_TINTED(PATH, VOLUME, CONTENTS) _LIFECYCLE_DECL(PATH, set_reagents(VOLUME, CONTENTS, null, TRUE))
/// DECLARE_REAGENTS with a /datum/reagents subtype for the holder.
#define DECLARE_REAGENTS_TYPED(PATH, VOLUME, CONTENTS, HOLDER) _LIFECYCLE_DECL(PATH, set_reagents(VOLUME, CONTENTS, HOLDER, FALSE))
/// Drops every inherited reagent declaration (holder and contents); a later line may declare anew.
#define DECLARE_NO_REAGENTS(PATH) _LIFECYCLE_DECL(PATH, clear_reagents())

/// 4. Appearance by state, as layers (doc/rewrite/systems.md section 1; the other appearance
/// declarations and the runtime: code/__defines/sys_appearance.dm, code/datums/sys/appearance.dm).
/// Each line adds one layer keyed by STATE_VAR (a var or a no-argument proc; the row is picked by
/// "[value]"), or a static layer when STATE_VAR is null. ROWS: list("key" =
/// list(APPEARANCE_ICON_STATE = "x", APPEARANCE_OVERLAYS = list("state", ...), APPEARANCE_COLOR =
/// "#rrggbb", APPEARANCE_ICON = 'x.dmi'), ...); the "*" row is the layer's fallback, and a layer with
/// no matching row adds nothing. Later layers win for icon_state/colour/icon, overlays add up.
/// The combined result is built once per (type, combination) and shared. Applied at init and by the
/// base /atom/update_icon(); when STATE_VAR is a declared field its setter refreshes it (no manual
/// update_icon()). The declaration owns the overlays it adds and swaps them on a state change; it
/// never touches other overlays. A subtype's layer on the same var replaces the parent's.
#define DECLARE_APPEARANCE(PATH, STATE_VAR, ROWS) _LIFECYCLE_DECL(PATH, set_appearance(STATE_VAR, ROWS))
#define APPEARANCE_ICON_STATE "icon_state"
#define APPEARANCE_OVERLAYS "overlays"
#define APPEARANCE_COLOR "color"
#define APPEARANCE_ICON "icon"
/// The fallback row key.
#define APPEARANCE_ANY "*"

/// 5. LEGACY: the foundation form is `membership(joins = REGISTRY_X)` in capabilities()
/// (code/datums/capabilities/library/membership.dm).
/// Registry membership (code/__defines/registries.dm). The same as REGISTRY_MEMBERSHIP() for an
/// ordinary registry; for a conditional one it also joins at materialize (was an unconditional
/// registry_join() in Initialize()). Leaving is automatic either way.
#define DECLARE_REGISTRY(PATH, ID) REGISTRY_MEMBERSHIP(PATH, ID); _LIFECYCLE_DECL(PATH, add_registry(ID))

/// 6. Membership in a world service: at materialize `JOIN` (a TYPE_PROC_REF on the service) is
/// called on GLOB.<SERVICE> with src; at dematerialize `LEAVE` (or nothing if null). SERVICE is
/// the GLOB var name as a string.
#define DECLARE_SERVICE_MEMBER(PATH, SERVICE, JOIN, LEAVE) _LIFECYCLE_DECL(PATH, add_service(SERVICE, JOIN, LEAVE))

/// 7. LEGACY, test-only (no real site): a Rust binding is push_to_rust() with generated rust_push() reads and a
/// relation / lifecycle_unbind() for its lifetime (doc/rewrite/lifecycle.md section 9).
/// A Rust (or other external) binding: BINDER is a /datum/decl_binder type. bind_list() runs at
/// materialize (all of an SSatoms batch at once, at the end of the batch); unbind() runs in
/// destroy phase 1 and on dematerialize.
#define DECLARE_BIND(PATH, BINDER) _LIFECYCLE_DECL(PATH, add_binder(BINDER))

/// 8a. LEGACY: per behaviour, cap_trait() (a trait + examine line), on_notice (an after-fact) or before_op on a
/// guard key (a veto): the audit is in doc/rewrite/lifecycle.md section 9.
/// An OM behaviour attached at materialize (om_attach). The OM teardown detaches it.
#define DECLARE_BEHAVIOUR(PATH, BEHAVIOUR) _LIFECYCLE_DECL(PATH, add_behaviour(BEHAVIOUR))
/// 8b. Periodic work (om_task_periodic(src, PIPELINE)) started at materialize, stopped at
/// dematerialize. The type implements periodic_step().
#define DECLARE_PERIODIC(PATH, PIPELINE) _LIFECYCLE_DECL(PATH, set_periodic(PIPELINE))
/// 8c. LEGACY: the foundation form is `after_init(delay, PROC_REF(x))` in reactions() (armed at init;
/// code/datums/reactions/after_init.dm).
/// om_after(src, DELAY, PROC) at materialize. DELAY: a time, or a var name. PROC: PROC_REF(x).
#define DECLARE_START_TIMER(PATH, DELAY, PROC) _LIFECYCLE_DECL(PATH, add_timer(DELAY, PROC))

// Verbs a type has by what it is (code/datums/om/grant_verbs.dm, doc/rewrite/systems.md §19).
// Applied by the verb store with no per-instance store entry; a runtime GRANT_VERB_HIDE still
// hides them and GRANT_VERB grants still stack on top. VERB is a verb or proc path.
/// 4b. VERB is on every PATH instance from init.
#define DECLARE_VERB(PATH, VERB) _LIFECYCLE_DECL(PATH, add_verb_decl(VERB, VERB_DECL_ALWAYS))
/// VERB is on a PATH mob once a player has had it (applied at Login); NPC-only mobs never carry it.
/// LEGACY: a thin wrapper over the foundation form, a type_verbs() entry `type_verb(VERB, login = TRUE)`
/// (code/datums/capabilities/type_verbs.dm).
#define DECLARE_LOGIN_VERB(PATH, VERB) ##PATH/type_verbs() { . = ..(); . += type_verb(VERB, login = TRUE); }
/// VERB is on a PATH instance while its var VAR_NAME (a string) is true. Whoever changes the var
/// calls verb_store_refresh(src, VERB) after.
#define DECLARE_VERB_IF(PATH, VERB, VAR_NAME) _LIFECYCLE_DECL(PATH, add_verb_decl(VERB, VAR_NAME))
/// VERB (usually a verb the type inherits) is never on a PATH instance: replaces stripping a type verb in Initialize().
#define DECLARE_VERB_HIDE(PATH, VERB) _LIFECYCLE_DECL(PATH, add_verb_decl(VERB, VERB_DECL_HIDE))

#define VERB_DECL_ALWAYS 1
#define VERB_DECL_LOGIN 2
#define VERB_DECL_HIDE 3

// /datum/lifecycle_decls/var/work bits.
#define DECL_WORK_INIT (1<<0)
#define DECL_WORK_MATERIALIZE (1<<1)
#define DECL_WORK_UNBIND (1<<2)
#define DECL_WORK_APPEARANCE (1<<3)
/// Damage reactions / REFLECTS / EMP_DISABLE (code/datums/sys/damage_reactions.dm).
#define DECL_WORK_REACT (1<<4)
/// Declared verbs (DECLARE_VERB and friends).
#define DECL_WORK_VERBS (1<<5)
