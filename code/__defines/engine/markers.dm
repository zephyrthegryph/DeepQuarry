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
// E1 made CAPABILITIES, CAPABILITY_DEF/TYPE, cap_keys, SCHEMA, STAGE_DEF, STATE_GRAPH and SOURCE_DEF real macros
// (code/__defines/engine/declare.dm); the ones below still wait for their engine.

/// A world action: generates /datum/act/<name>, act_<name>() and the past-tense notice (section 8).
#define ACTION(name, fields...)
/// A composed stat: declares the var, its base and the id STAT_<NAME> (section 5).
#define STAT(T, name, rule, params...)
/// A reactive read of private system state, declared in code/contracts/accessors (section 7).
#define SYSTEM_ACCESSOR(system, name, key)
/// A resource and its adapter (section 9, X2).
#define RESOURCE_DEF(res, params...)
/// A list of entries or parts under a name, kept in its own file (section 11).
#define BUNDLE(name, entries...)

/// An accessor proc that stands for a producer key rather than a var: READS_AS(proc, KEY) or, through a relation,
/// READS_AS(pad_occupied, OCCUPANTS_KEY, via = nameof(pad)). Generated reads do not follow the proc; readers subscribe to KEY
/// (published with PUBLISH_CHANGE(E, KEY)). The analysis engine (tools/analyze, sem/reads) checks the accessor's own reads are covered.
#define READS_AS(proc, key, args...)
/// First line of a global helper that a condition, requirement or output calls: the helper is followed through the arguments
/// it names. READS_FROM(C) follows C; READS_FROM() says the helper reads no entity state. An unannotated global call in a handler
/// is a build error (sem/reads, unannotated_global).
#define READS_FROM(args...)
