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
//
// `analyze gen` reads these from source and writes the DM they stand for into code/engine/_generated/ (E1: ids.dm and declare.dm; E5:
// reads.dm and system_accessors.dm). SCHEMA is a real macro (code/__defines/engine/declare.dm): a tracked var's setter is DM code.

/// One composition root per type: registers T's entry list with the table builder. `analyze gen declare` writes T's declared_entries().
/// A block: the marker line is a header (an override of /datum/proc/__capabilities() on T, which nothing calls) and the entries are its indented statements, one per line, no
/// trailing commas and no backslashes; an entry may span lines inside its own parentheses. The entry names are the part and entry
/// constructors (`op`, `extend`, `configure`, `needs`, `then`, ... in code/engine and code/library), so the compiler and DreamChecker check
/// them like any call. `analyze` reads the block from source; nothing runs it.
///
///     CAPABILITIES(/obj/machinery/thing)
///         op("press", hand(), then(PROC_REF(pressed)))
///         extend("ui_open", needs(req_is(STAT_OPERABLE)))
///
///         section(controls, "The window and its buttons.")
///         interface("Thing")
///         op("eject", ui_act(), then(PROC_REF(eject)))
#define CAPABILITIES(T) ##T/__capabilities()
/// STATIC_ENTRY(kind) names an entry constructor (`loot`, `map_resolver`) whose entries a CAPABILITIES block may carry but that are read without an
/// instance of the type: `analyze gen declare` leaves them out of declared_entries() and writes them into declared_static_blocks(), which the
/// static_entries system compiles at world setup (code/engine/declare/static_entries.dm). The kind's /datum/entry_engine sets static_kind = TRUE.
#define STATIC_ENTRY(kind)
/// A capability whose body returns entries: CAPABILITY_DEF(name, CAP_X, key =, stacks =, param = default, ...).
#define CAPABILITY_DEF(name, cap_id, params...)
/// A capability with code of its own: CAPABILITY_TYPE(name, CAP_X, /datum/capability/x, key =, stacks =, param = default, ...).
#define CAPABILITY_TYPE(name, cap_id, cap_type, params...)
/// A capability's state keys: ids, accessors, reasons and read registration.
#define cap_keys(cap_id, keys...)
/// A build stage id (section 12): STAGE_DEF(group, name) is STAGE_<GROUP>_<NAME>.
#define STAGE_DEF(group, name)
/// A named, reusable state graph of stages (section 12): STATE_GRAPH(GRAPH_X, start(STAGE_X), stage(...), dismantle(...)).
/// A block, like CAPABILITIES: the entries (`start(...)`, `stage(...)`, `dismantle(...)`) are the indented statements under the header.
#define STATE_GRAPH(graph) /proc/__state_graph_##graph()
/// A flyweight source (section 5): SOURCE_DEF(ai_control) is SRC_AI_CONTROL.
#define SOURCE_DEF(name)
/// A world action: generates /datum/act/<name>, act_<name>() and the past-tense notice (section 8).
#define ACTION(name, fields...)
/// A composed stat: declares the var, its base and the id STAT_<NAME> (section 5).
#define STAT(T, name, rule, params...)
/// A reactive read of private system state, declared in code/contracts/accessors (section 7). An optional fourth argument, the var's type
/// path, makes the accessor typed (`/proc/name() as /type`), so a caller reads through it: `ticker_mode().name`.
#define SYSTEM_ACCESSOR(system, name, key, type...)
/// A resource and its adapter (section 9, X2).
#define RESOURCE_DEF(res, params...)
/// A section of a CAPABILITIES block (section 1): `section(name, "doc")` on its own line groups the entries after it, up to the next section or
/// the block's end. The entries stay the type's own (PROC_REF(x), nameof(v)); each carries the section's name with its file:line, which
/// Explain Type and Explain Interaction print. A section is not reuse: entries several types share are a capability or a plain proc
/// returning list(entries). Expands to nothing (the line is an empty statement of the header's proc).
#define section(name, doc...)

/// An accessor proc that stands for a producer key rather than a var: READS_AS(proc, KEY) or, through a relation,
/// READS_AS(pad_occupied, OCCUPANTS_KEY, via = nameof(pad)). Generated reads do not follow the proc; readers subscribe to KEY
/// (published with PUBLISH_CHANGE(E, KEY)). The analysis engine (tools/analyze, sem/reads) checks the accessor's own reads are covered.
#define READS_AS(proc, key, args...)
/// First line of a global helper that a condition, requirement or output calls: the helper is followed through the arguments
/// it names. READS_FROM(C) follows C; READS_FROM() says the helper reads no entity state. An unannotated global call in a handler
/// is a build error (sem/reads, unannotated_global).
#define READS_FROM(args...)
