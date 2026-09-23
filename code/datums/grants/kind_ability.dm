/**
 * GRANT_KIND_ABILITY: `id` is an ability id (code/__defines/abilities.dm), granted
 * via grant(L, GRANT_KIND_ABILITY, id, source) / revoke(...) - see
 * code/datums/abilities/ability.dm's has_ability()/ability_sources() wrappers and
 * why_not(), which is what actually gates using the ability. Nothing needs to run on
 * grant/revoke: the ability's own why_not() reads has_grant() live.
 */
/datum/grant_kind/ability
	kind = GRANT_KIND_ABILITY

GLOBAL_DATUM_INIT(grant_kind_ability, /datum/grant_kind/ability, new)
