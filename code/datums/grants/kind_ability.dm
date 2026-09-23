/**
 * GRANT_KIND_ABILITY: `id` is an ability id (code/__defines/abilities.dm), granted
 * via grant(L, GRANT_KIND_ABILITY, id, source) / revoke(...) - see
 * code/datums/abilities/ability.dm's why_not(), which is what actually gates using
 * the ability (it reads L.has_grant(GRANT_KIND_ABILITY, id) live). Nothing needs to
 * run on grant/revoke.
 */
/datum/grant_kind/ability
	kind = GRANT_KIND_ABILITY

GLOBAL_DATUM_INIT(grant_kind_ability, /datum/grant_kind/ability, new)
