// Declaration forms of the engine (doc/rewrite/final_api.html, section 1 "Declarations"; section 19 "E1, declarations").
//
// The declaration markers (CAPABILITIES, CAPABILITY_TYPE, CAPABILITY_DEF, cap_keys, STAGE_DEF, SOURCE_DEF, STATE_GRAPH, STAT) expand to nothing in
// DM (markers.dm): an author gives them no id and no constructor of their own (a marker that spans lines ends each line but the last with a backslash), and `analyze gen` reads
// them from source and writes the DM they stand for into code/engine/_generated/: ids.dm (the ids they declare, included early) and declare.dm
// (constructors, registration rows, accessors, and each type's declared_entries()). tools/analyze/src/gens/declare.rs is the generator.
//
// What stays a macro here is what DM expresses itself: the stacking vocabulary a CAPABILITY marker's stacks = names, the id arithmetic of a
// capability state key, the schema forms (the setter of a tracked var with a schema is DM code), LIST_STATE, MSG and the constants the engine
// files share.

/// Capability state key ids are CAPKEY_ID_BASE + (capability id * 32 + bit), so a bare key id in a condition is told from a value by its range.
#define CAPKEY_ID_BASE 200000
/// The id of state key `bit` (1 to 24) of capability `cap_id`: what the generated `#define COVER_OPEN CAPKEY_ID(CAP_COVER, 1)` is.
#define CAPKEY_ID(cap_id, bit) (CAPKEY_ID_BASE + ((cap_id) << 5) + (bit))
/// The capability id and the bit of a state key id.
#define CAPKEY_CAP(key_id) (((key_id) - CAPKEY_ID_BASE) >> 5)
#define CAPKEY_BIT(key_id) (((key_id) - CAPKEY_ID_BASE) & 31)

/// stacks = STACK (default): every activation runs.
#define STACK list("stack")
/// stacks = UNIQUE: only the first activation (by attach order) runs.
#define UNIQUE list("unique")
/// stacks = BEST(param): only the activation with the highest value of `param` runs; a tie goes to the first attached.
#define BEST(param) list("best", #param)

// ---- Scoped activation (section 5, X1) ----
/// Activation scope kinds.
#define SCOPE_SOURCE 1 // while the source exists, until revoke
#define SCOPE_SLOT 2 // while the item is in that slot
#define SCOPE_COND 3 // while a condition holds
#define SCOPE_RELATION 4 // while a relation names the value
#define SCOPE_TYPE 5 // type-level: lives as long as the holder

/// Hold and grant stacking policy ids (the first element of a stacks list).
#define STACKS_STACK "stack"
#define STACKS_UNIQUE "unique"
#define STACKS_BEST "best"

// ---- Declared relations (section 6) ----
/// on_other_deleted: the view drops the value.
#define OTHER_CLEAR 1
/// on_other_deleted: the holder is deleted too.
#define OTHER_DELETE_ME 2
/// links(conflict =): linking an end that takes one link and already has one. REPLACE (the default) breaks the old link, its hooks running; REFUSE keeps it
/// and the new link is not made (code/engine/declare/link_state.dm).
#define REPLACE 1
#define REFUSE 2
/// The text of one end of a sparse link: links(LINK_END(/mob/living, LK_BUCKLED_TO), LINK_END(/atom/movable, LK_BUCKLED_MOBS), sparse = TRUE, ...). A sparse end names a
/// key, not a var (a base type cannot carry a var for every pair it takes part in), so there is no `::` to write.
#define LINK_END(TYPE, KEY) ("[TYPE]::[KEY]")
/// on_destroy policies of owns_one / owns_many.
#define ON_DESTROY_DELETE 1
#define ON_DESTROY_SPILL 2
#define ON_DESTROY_PRIVATE_COPY 3
/// Handed to a successor: owns_one(nameof(cell), on_destroy = ON_DESTROY_HAND_OVER, successor = nameof(wreck), successor_var = nameof(crowbar_salvage)). With no successor it is deleted.
#define ON_DESTROY_HAND_OVER 4

// ---- Value schemas (section 4, X5) ----
/// on_invalid: what a failed write does.
#define ON_INVALID_CLAMP 1
#define ON_INVALID_REJECT 2
/// Clamp logs are rate limited per source and var: one summary line per interval.
#define SCHEMA_LOG_INTERVAL (10 SECONDS)

/**
 * A tracked var with a schema (section 4): declares the setter set_<V>() that validates the write against `schema`, normalises it
 * and publishes the change. The doc's `TRACKED(T, v, schema = ..., default = ...)`; the legacy TRACKED(T, V) of
 * code/__defines/capabilities.dm stays as it is until the migration retires it, so a var with a schema uses this name. `V` must be
 * declared on the type (the var line carries the default). A rejected write leaves the var as it was and returns FALSE.
 */
#define TRACKED_SCHEMA(T, V, SCHEMA_EXPR, opts...) ##T/proc/set_##V(value) { value = schema_write(src, #V, value); if(value == SCHEMA_REJECT) { return FALSE }; if(TRACKED_UNCHANGED(V, value)) { return FALSE }; V = value; tracked_changed(src, #V); return TRUE };SCHEMA(T, V, SCHEMA_EXPR, opts)

/// The same schema for a var that is not tracked and is declared on its own line (a row column, a request field). The schema's source
/// text is kept for the range text of the generated UI types.
#define SCHEMA(T, V, SCHEMA_EXPR, opts...) ##T/proc/__schema_##V() { return list(#V, SCHEMA_EXPR, list(opts), #SCHEMA_EXPR); };/datum/schema_decl##T/__##V/spec() { return list(T, ##T/proc/__schema_##V); }

/// A write the schema refused (the setter's value after schema_write()).
/// ui_shape(field | field = schema, ...): the window's data fields; read from source by `analyze gen ui_types`, an empty entry at runtime (part.dm).
#define ui_shape(fields...) entry_make("ui_shape", null)
#define SCHEMA_REJECT "\[schema rejected]"

// ---- Messages (section 13) ----
/// A declared message: MSG(cover/closed) is the /datum/msg/cover/closed type that MSG_DEF(cover/closed, ...) declares. A cap_keys() reason, a
/// requirement's because = and a stage's text name messages this way.
#define MSG(path) /datum/msg/##path


// ---- constants and small macros the engine files share (they must precede every user of a declaration form) ----
// Rule names a report carries. Tests assert on them.
#define RULE_NOT_AN_ENTRY "not_an_entry"
#define RULE_CAP_CONFLICT "capability_conflict"
#define RULE_UNKNOWN_KEY "unknown_key"
#define RULE_RELATION_KIND "relation_kind"
#define RULE_CONFIGURE "configure"
#define RULE_WITHOUT "without"
#define RULE_GRAPH "state_graph"

// The lifecycle hooks a capability definition can have (its `holder_hooks` bits, which is also what ENGINE_HOOK_* asks of the lifecycle):
// on_holder_preinit before the parent's init code reads the holder, on_holder_init after, on_holder_destroy in the destroy transaction.
#define HOLDER_HOOK_PREINIT (1<<0)
#define HOLDER_HOOK_INIT (1<<1)
#define HOLDER_HOOK_DESTROY (1<<2)
#define ENGINE_HOOK_PREINIT HOLDER_HOOK_PREINIT
#define ENGINE_HOOK_INIT HOLDER_HOOK_INIT
#define ENGINE_HOOK_DESTROY HOLDER_HOOK_DESTROY
/// The type has contributions, contributes_to entries or a formula stat: its stats compute at init (stat_holder_init).
#define ENGINE_HOOK_STATS (1<<3)
/// The type has after_init() entries: they are armed when the instance's init is complete (after_init.dm).
#define ENGINE_HOOK_AFTER_INIT (1<<4)
/// A slot() entry of the type has starts =: its contents are made in the engine init (slot_starts_init()).
#define ENGINE_HOOK_SLOT_STARTS (1<<5)
/// The type declares entries of a condition-scoped kind (an entry engine with cond_scoped = TRUE, such as heat_link()): each is an activation
/// of the holder that lives while its when() conditions hold (cond_scope.dm).
#define ENGINE_HOOK_COND_SCOPED (1<<6)


#define ALLOC_LAZY 1
#define ALLOC_EAGER 2
#define KIND_LIST 1
#define KIND_SET 2
#define KIND_MAP 3
#define OWNS_NONE 1
#define OWNS_ROWS 2
#define SHARE_NONE 1
#define SHARE_COW_TABLE 2

/// Declares a per-instance list: LIST_STATE(/datum/mind, objectives), LIST_STATE(/obj, req_access, empty_differs = TRUE).
#define LIST_STATE(T, V, opts...) /datum/list_state_decl##T/__##V/spec() { return list(T, #V, list(opts)); }

#define SCHEMA_BOOL "bool"
#define SCHEMA_INT "int"
#define SCHEMA_NUM "num"
#define SCHEMA_ENUM "enum"
#define SCHEMA_FLAGS "flags"
#define SCHEMA_TEXT "text"
#define SCHEMA_REF "ref"
#define SCHEMA_PATH "path"
#define SCHEMA_LIST "list_of"
#define SCHEMA_MAP "map_of"
#define SCHEMA_ROW "row"

/// A closed list of rules for sanitize =: naming one is the declaration, not a call to remember.
#define SANITIZE_NONE 0
#define SANITIZE_PLAIN 1
#define SANITIZE_NAME 2

/// A graph edge that leaves from any stage.
#define ANY_STAGE (-1)
/// The slot a state graph keeps the parts it took in (a put_in() of a build stage): a type that builds declares the slot relation for it.
#define SLOT_CONSTRUCTION "construction"

// Entry kinds owned by E1. A kind is a text so explain_type() dumps read as the declaration does.
#define ENTRY_BLOCK "block"
#define ENTRY_CAPABILITY "capability"
#define ENTRY_REF_ONE "ref_one"
#define ENTRY_REF_MANY "ref_many"
#define ENTRY_OWNS_ONE "owns_one"
#define ENTRY_OWNS_MANY "owns_many"
#define ENTRY_LINK "link"
#define ENTRY_SLOT "slot"
#define ENTRY_WHEN "when"
#define ENTRY_EXTEND "extend"
#define ENTRY_CONFIGURE "configure"
#define ENTRY_WITHOUT "without"
#define ENTRY_WHILE_SLOTTED "while_slotted"
#define ENTRY_REL_GRANTS "rel_grants"
#define ENTRY_MEMBERSHIP "membership"
#define ENTRY_CAP_KEYS "cap_keys"
#define ENTRY_STATE_GRAPH "state_graph"
#define ENTRY_LIST_STATE "list_state"
