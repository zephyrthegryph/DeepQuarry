// Declaration forms of the engine (doc/rewrite/final_api.html, section 1 "Declarations"; section 19 "E1, declarations").
//
// These are the DM-compilable spellings of the final forms. The design writes a declaration over several lines and lets a
// generator read it from source (E5); DM cannot continue a macro call across lines, so a multi-line list ends each line but
// the last with a backslash, exactly as DECLARE_LOOT and DECLARE_INTERACTIONS already do. The generator, when it lands,
// replaces the macros below with generated tables and leaves the call sites unchanged.
//
//	CAPABILITIES(/obj/machinery/power/apc,
//		powered_by(/datum/system/power, role = POWER_ROLE_LOAD),
//		owns_one(nameof(cell), /obj/item/cell, starts = nameof(cell_type)),
//		extend("cover.open", wait(4 SECONDS)))
// (each line but the last of a real declaration ends in a backslash; it is left out of this example because a backslash at the end of a
// line comment continues the comment)
//
// Everything a declaration names is an entry (code/engine/declare/entries.dm): a flyweight datum interned by signature.
// A type's entries are one list, built once per type from its parent's compiled table plus its own list
// (code/engine/declare/table.dm).

/**
 * One composition root per type. T's entry list: capability constructors, relation entries, extend/configure/without,
 * when(), while_slotted(), contributes() and every other entry. A second CAPABILITIES line for the same type is a DM
 * "duplicate definition" error naming the file and line (the macro defines T's declared_entries()), which is the build error
 * the design asks for. `__FILE__:__LINE__` of the closing line is kept as the origin of every entry of the list.
 */
#define CAPABILITIES(T, entries...) ##T/declared_entries(list/into) { ..(into); into += entry_block(__FILE__, __LINE__, T); into += list(entries); }

/**
 * The paired relation of the design, `link(/obj/machinery/power/apc::hacker, /mob/living/silicon/ai::hacked_apcs)`, spelled link_pair():
 * `link` is a BYOND keyword (the output method `usr << link(url)`), so it can be neither a proc nor a macro. DM evaluates a bare
 * `/type::var` to the var's initial value, so the macro keeps each end as the text it was written as ("/type::var") and the table
 * builder resolves the type and the var. An end that is a list var says so: link_pair(A::a, B::b, b_many = TRUE).
 */
#define link_pair(A, B, args...) entry_link(#A, #B, args)

/// The id of state key `bit` (1 to 24) of capability `cap_id`: what a cap_keys() constant is, `#define COVER_OPEN CAPKEY_ID(CAP_COVER, 1)`.
#define CAPKEY_ID(cap_id, bit) (((cap_id) << 8) | (bit))
/// The capability id and the bit of a state key id.
#define CAPKEY_CAP(key_id) ((key_id) >> 8)
#define CAPKEY_BIT(key_id) ((key_id) & 255)

// ---- Capability definitions (section 11) ----

/**
 * A capability with code of its own: its params are vars on its /datum/capability subtype (the defaults), and `name` becomes the global
 * constructor whose parameters are the params, so `name("a", power = 45)` is checked by DM itself: the first parameter is the one `key`
 * names (the selector), a param left out keeps the datum's default. DM gives a proc named arguments only when it declares them, which is why
 * the parameter list is written here once, as bare names, and everything else (the key, the stacking policy, the op prefix) is data.
 *
 *	CAPABILITY_TYPE(mirror_plating, CAP_MIRROR_PLATING, /datum/capability/mirror_plating, NONE, BEST(reflect_chance), reflect_chance)
 *	/datum/capability/mirror_plating
 *		var/reflect_chance = 30
 *
 * `key` is the name of the param that is the selector (a text), or NONE. `stacks` is STACK, UNIQUE or BEST(param).
 */
#define CAPABILITY_TYPE(name, cap_id, cap_type, key, stacks, params...) /proc/##name(params) { RETURN_TYPE(cap_type); return cap_construct(cap_id, cap_type, list(params), #params); };/datum/capdef_decl/c_##name/spec() { return list(cap_id, cap_type, key, stacks, #name, #params); }
/// A capability whose body returns entries: the same declaration; the entries are the definition's `/datum/capability/def/<name>/entries()`.
#define CAPABILITY_DEF(name, cap_id, key, stacks, params...) /proc/##name(params) { RETURN_TYPE(/datum/capability/def/##name); return cap_construct(cap_id, /datum/capability/def/##name, list(params), #params); };/datum/capdef_decl/c_##name/spec() { return list(cap_id, /datum/capability/def/##name, key, stacks, #name, #params); }

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
/// on_destroy policies of owns_one / owns_many.
#define ON_DESTROY_DELETE 1
#define ON_DESTROY_SPILL 2
#define ON_DESTROY_PRIVATE_COPY 3

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
#define TRACKED_SCHEMA(T, V, SCHEMA_EXPR, opts...) ##T/proc/set_##V(value) { value = schema_write(src, #V, value); if(value == SCHEMA_REJECT) { return FALSE }; if(V == value) { return FALSE }; V = value; tracked_changed(src, #V); return TRUE };SCHEMA(T, V, SCHEMA_EXPR, opts)

/// The same schema for a var that is not tracked and is declared on its own line (a row column, a request field). The schema's source
/// text is kept for the range text of the generated UI types.
#define SCHEMA(T, V, SCHEMA_EXPR, opts...) ##T/proc/__schema_##V() { return list(#V, SCHEMA_EXPR, list(opts), #SCHEMA_EXPR); };/datum/schema_decl##T/__##V/spec() { return list(T, ##T/proc/__schema_##V); }

/// A write the schema refused (the setter's value after schema_write()).
#define SCHEMA_REJECT "\[schema rejected]"

// ---- Messages (section 13) ----
/// A declared message: MSG(cover/closed) is the /datum/msg/cover/closed type that MSG_DEF(cover/closed, ...) declares. A cap_keys() reason, a
/// requirement's because = and a stage's text name messages this way.
#define MSG(path) /datum/msg/##path

// ---- State graphs (section 12) ----
/// A named, reusable state graph of stages: STATE_GRAPH(GRAPH_X, start(STAGE_X), stage(...), dismantle(...)).
#define STATE_GRAPH(graph, entries...) /datum/graph_decl/g_##graph/spec() { return list(graph, entries); }
/// A build stage id and its text key: STAGE_DEF(door, frame, STAGE_DOOR_FRAME) (the id is the third argument until the
/// generator derives it from the first two).
#define STAGE_DEF(group, name, id) /datum/stage_def/##group##_##name/spec() { return list(id, #group, #name); }
/// A flyweight source: SOURCE_DEF(ai_control, SRC_AI_CONTROL).
#define SOURCE_DEF(name, id) /datum/source_def/##name/spec() { return list(id, #name); }

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
// on_holder_preinit before the parent's init code reads the holder, on_holder_init_ctx after, on_holder_destroy_ctx in the destroy transaction.
#define HOLDER_HOOK_PREINIT (1<<0)
#define HOLDER_HOOK_INIT (1<<1)
#define HOLDER_HOOK_DESTROY (1<<2)
#define ENGINE_HOOK_PREINIT HOLDER_HOOK_PREINIT
#define ENGINE_HOOK_INIT HOLDER_HOOK_INIT
#define ENGINE_HOOK_DESTROY HOLDER_HOOK_DESTROY


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

/// Capability state keys (section 4 "Capability state: cap_keys", section 11): cap_keys(CAP_X, OPEN = MSG(cover/closed), ...) registers the keys of one
/// capability in order, bit 1 first, at most 24. The id of a key is CAPKEY_ID(cap, bit), written as a #define beside the declaration until the
/// generator emits it.
#define cap_keys(cap_id, keys...) /datum/cap_keys_decl/k_##cap_id/spec() { return list(cap_id, list(keys)); }

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
