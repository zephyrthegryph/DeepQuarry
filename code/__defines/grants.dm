// Grant kind ids for the generic grant system (code/datums/grants/, doc/rewrite/grants.md).
// A kind is a registered /datum/grant_kind singleton; new kinds get the next free id.
#define GRANT_KIND_ABILITY         1
#define GRANT_KIND_LANGUAGE        2
#define GRANT_KIND_FACTORS         3
/// Same id-space as GRANT_KIND_LANGUAGE (a language id): whether a silicon's speech
/// synthesizer can VOICE that language, independent of understanding it. See
/// code/datums/grants/kind_language.dm.
#define GRANT_KIND_LANGUAGE_SPEECH 4
// Reserved for DQ Medical (W6): GRANT_KIND_TRAIT, GRANT_KIND_GENE. Take the next free
// ids (5, 6, ...) and register a /datum/grant_kind the same way ability/language/factors
// do (code/datums/grants/kind_ability.dm is the simplest example) - see doc/rewrite/grants.md.
