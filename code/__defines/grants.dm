// Grant kind ids for the generic grant system (code/datums/grants/, doc/rewrite/grants.md).
// A kind is a registered /datum/grant_kind singleton; new kinds get the next free id.
#define GRANT_KIND_ABILITY   1
#define GRANT_KIND_LANGUAGE  2
#define GRANT_KIND_FACTORS   3
// Reserved for DQ Medical (W6): GRANT_KIND_TRAIT, GRANT_KIND_GENE. Take the next free
// ids (4, 5, ...) and register a /datum/grant_kind the same way ability/language/factors
// do (code/datums/grants/kind_ability.dm is the simplest example) - see doc/rewrite/grants.md.
