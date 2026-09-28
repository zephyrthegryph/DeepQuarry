// Declarative lifecycle (doc/rewrite/declarative_lifecycle.md).
//
// One line next to a type replaces the generic work an Initialize() override or an
// on_destroy() hook used to do by hand. Every macro below adds one entry to the type's
// /datum/lifecycle_decls table (code/datums/lifecycle/declarations.dm), built once per type
// on first use and shared by every instance. The lifecycle runs the table:
//
//   init         (end of /atom/Initialize(), and table_initialize()): instance state that
//                subtype Initialize() code may read right after `. = ..()`:
//                  1. owned children   DECLARE_DEFAULT_CHILD
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

/// 1. Owned child created at init. VAR must also carry a DECLARE_REF of kind OWNED, OWNED_LIST,
/// HELD, SPILL or SPILL_LIST (that line says how it is destroyed). DEFAULT is a type path, a
/// list of type paths (or `list(type = count)`) for a list var, or the name of a var holding the
/// type (e.g. "cell_type"). The var itself wins: holding a path (`var/obj/item/cell/cell =
/// /obj/item/cell/high`) creates that path; holding an instance creates nothing. Children are
/// created with `new type(src)`.
#define DECLARE_DEFAULT_CHILD(PATH, VAR, DEFAULT) _LIFECYCLE_DECL(PATH, add_child(VAR, DEFAULT))

/// 2. A gas mixture created at init in VAR (declare VAR OWNED). VOLUME: litres, or a var name.
/// GASES: list(GAS_O2 = kPa, ...) at TEMP kelvin (moles = P*V / (R*T)).
#define DECLARE_GAS(PATH, VAR, VOLUME, TEMP, GASES) _LIFECYCLE_DECL(PATH, set_gas(VAR, VOLUME, TEMP, GASES))

/// 3. Starting reagents at init: create_reagents(VOLUME) then add CONTENTS
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

/// 4. Appearance by state, as layers. Each line adds one layer keyed by STATE_VAR (the row is
/// picked by "[value]"), or a static layer when STATE_VAR is null. ROWS: list("key" =
/// list(APPEARANCE_ICON_STATE = "x", APPEARANCE_OVERLAYS = list("state", ...), APPEARANCE_COLOR =
/// "#rrggbb", APPEARANCE_ICON = 'x.dmi'), ...); the "*" row is the layer's fallback, and a layer with
/// no matching row adds nothing. Later layers win for icon_state/colour/icon, overlays add up.
/// The combined result is built once per (type, combination) and shared: the wall_overlay_images
/// pattern, generic. Applied at init and by the base /atom/update_icon() (a declared type needs no
/// update_icon() override, or one that calls ..()). The declaration owns the overlays it adds and
/// swaps them on a state change; it never touches other overlays. A subtype's layer on the same var
/// replaces the parent's.
#define DECLARE_APPEARANCE(PATH, STATE_VAR, ROWS) _LIFECYCLE_DECL(PATH, set_appearance(STATE_VAR, ROWS))
#define APPEARANCE_ICON_STATE "icon_state"
#define APPEARANCE_OVERLAYS "overlays"
#define APPEARANCE_COLOR "color"
#define APPEARANCE_ICON "icon"
/// The fallback row key.
#define APPEARANCE_ANY "*"

/// 5. Registry membership (code/__defines/registries.dm). The same as REGISTRY_MEMBERSHIP() for an
/// ordinary registry; for a conditional one it also joins at materialize (was an unconditional
/// registry_join() in Initialize()). Leaving is automatic either way.
#define DECLARE_REGISTRY(PATH, ID) REGISTRY_MEMBERSHIP(PATH, ID); _LIFECYCLE_DECL(PATH, add_registry(ID))

/// 6. Membership in a world service: at materialize `JOIN` (a TYPE_PROC_REF on the service) is
/// called on GLOB.<SERVICE> with src; at dematerialize `LEAVE` (or nothing if null). SERVICE is
/// the GLOB var name as a string.
#define DECLARE_SERVICE_MEMBER(PATH, SERVICE, JOIN, LEAVE) _LIFECYCLE_DECL(PATH, add_service(SERVICE, JOIN, LEAVE))

/// 7. A Rust (or other external) binding: BINDER is a /datum/decl_binder type. bind_list() runs at
/// materialize (all of an SSatoms batch at once, at the end of the batch); unbind() runs in
/// destroy phase 1 and on dematerialize.
#define DECLARE_BIND(PATH, BINDER) _LIFECYCLE_DECL(PATH, add_binder(BINDER))

/// 8a. An OM behaviour attached at materialize (om_attach). The OM teardown detaches it.
#define DECLARE_BEHAVIOUR(PATH, BEHAVIOUR) _LIFECYCLE_DECL(PATH, add_behaviour(BEHAVIOUR))
/// 8b. Periodic work (om_task_periodic(src, PIPELINE)) started at materialize, stopped at
/// dematerialize. The type implements periodic_step().
#define DECLARE_PERIODIC(PATH, PIPELINE) _LIFECYCLE_DECL(PATH, set_periodic(PIPELINE))
/// 8c. om_after(src, DELAY, PROC) at materialize. DELAY: a time, or a var name. PROC: PROC_REF(x).
#define DECLARE_START_TIMER(PATH, DELAY, PROC) _LIFECYCLE_DECL(PATH, add_timer(DELAY, PROC))

// /datum/lifecycle_decls/var/work bits.
#define DECL_WORK_INIT (1<<0)
#define DECL_WORK_MATERIALIZE (1<<1)
#define DECL_WORK_UNBIND (1<<2)
#define DECL_WORK_APPEARANCE (1<<3)
