// Declarative lifecycle (doc/rewrite/declarative_lifecycle.md).
//
// One line next to a type replaces the generic work an Initialize() override or an
// on_destroy() hook used to do by hand. Every macro below adds one entry to the type's
// /datum/lifecycle_decls table (code/datums/lifecycle/declarations.dm), built once per type
// on first use and shared by every instance. The lifecycle runs the table:
//
//   init         (end of /atom/Initialize(), and table_initialize()): instance state that
//                subtype Initialize() code may read right after `. = ..()`:
//                  (starting occupants: owns_one / owns_many with starts =, made first)
//                  1. gas contents     DECLARE_GAS
//                  (reagents: reagents() in CAPABILITIES, code/library/reagents/reagents.dm)
//                  3. appearance       DECLARE_APPEARANCE
//   materialize  (/atom/on_materialize(), after registries, rules and OM start):
//                  4. registries       DECLARE_REGISTRY (conditional ones are joined here)
//                  5. service members  DECLARE_SERVICE_MEMBER
//                  6. binds            DECLARE_BIND (batched per SSatoms batch)
//   dematerialize (/atom/on_dematerialize()): 6..4 in reverse (service leave;
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

/// 1. LEGACY: the foundation form is `gas_store(nameof(var), volume, temp, gases)` in capabilities()
/// (code/datums/capabilities/library/gas_store.dm; doc/rewrite/lifecycle.md section 9).
/// A gas mixture created at init in VAR (declare VAR OWNED). VOLUME: litres, or a var name.
/// GASES: list(GAS_O2 = kPa, ...) at TEMP kelvin (moles = P*V / (R*T)).
#define DECLARE_GAS(PATH, VAR, VOLUME, TEMP, GASES) _LIFECYCLE_DECL(PATH, set_gas(VAR, VOLUME, TEMP, GASES))


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

#define VERB_DECL_ALWAYS 1
#define VERB_DECL_LOGIN 2
#define VERB_DECL_HIDE 3

// /datum/lifecycle_decls/var/work bits.
#define DECL_WORK_INIT (1<<0)
#define DECL_WORK_MATERIALIZE (1<<1)
#define DECL_WORK_UNBIND (1<<2)
#define DECL_WORK_APPEARANCE (1<<3)
/// Legacy declared-verb table work (kept while the verb store consumes it).
#define DECL_WORK_VERBS (1<<5)
