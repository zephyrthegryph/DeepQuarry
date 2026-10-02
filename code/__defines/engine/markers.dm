// Engine declaration markers (doc/rewrite/final_api.html, section 1 "Declarations"; section 22 "Base declarations").
//
// These are GENERATOR MARKERS, not working macros: each expands to nothing, so a declaration written in the final
// syntax compiles (and is skipped) today. E1 (the table builder), E3 (stats), E4 (actions) and E5 (the generators on the
// analysis engine) read these lines from source and emit the real vars, ids and types into code/engine/_generated/.
// Until an engine lands, the declaration is documentation that the test-only capabilities under code/tests/engine/ and
// the contracts under code/contracts/ already carry in the final form.
//
// Only markers whose names are free on master are defined here. TRACKED(), SYSTEM_DEF() and MSG_DEF() already exist as
// legacy forms with other shapes (code/__defines/capabilities.dm, MC.dm, messages.dm); a final-form line that uses one of
// those is written inside a comment until its engine replaces the legacy macro (doc/rewrite/engine_contracts.md,
// "Name clashes").

/// One composition root per type: registers T's entry list with the table builder.
#define CAPABILITIES(T, entries...)
/// A capability whose body returns entries: CAPABILITY_DEF(name, CAP_X, key =, stacks =, param = default, ...).
#define CAPABILITY_DEF(name, cap_id, params...)
/// A capability with code of its own: CAPABILITY_TYPE(name, CAP_X, /datum/capability/x, key =, stacks =, params...).
#define CAPABILITY_TYPE(name, cap_id, cap_type, params...)
/// A capability's state keys: ids, accessors, reasons and read registration.
#define cap_keys(cap_id, keys...)
/// A world action: generates /datum/act/<name>, act_<name>() and the past-tense notice (section 8).
#define ACTION(name, fields...)
/// A composed stat: declares the var, its base and the id STAT_<NAME> (section 5).
#define STAT(T, name, rule, params...)
/// A value schema on a var that is not tracked (section 4, X5).
#define SCHEMA(T, var, schema, params...)
/// A reactive read of private system state, declared in code/contracts/accessors (section 7).
#define SYSTEM_ACCESSOR(system, name, key)
/// A build stage id (section 12): defines STAGE_<GROUP>_<NAME>.
#define STAGE_DEF(group, name)
/// A named, reusable state graph of stages (section 12).
#define STATE_GRAPH(graph, entries...)
/// A resource and its adapter (section 9, X2).
#define RESOURCE_DEF(res, params...)
/// A flyweight source (section 5): SOURCE_DEF(ai_control) is SRC_AI_CONTROL.
#define SOURCE_DEF(name)
/// A list of entries or parts under a name, kept in its own file (section 11).
#define BUNDLE(name, entries...)
