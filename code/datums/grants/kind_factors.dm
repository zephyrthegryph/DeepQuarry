/**
 * GRANT_KIND_FACTORS: `id` is the source's own factor table (an alist of
 * BF_id -> value, same shape as /datum/modifier/var/factors - see
 * code/modules/body/factors.dm's header). There's no separate "name" for a factor
 * grant: the table itself IS what's granted, so grant(L, GRANT_KIND_FACTORS,
 * my_factors, src) / revoke(...) is how an organ, implant or item that isn't
 * already one of factors.dm's built-in sources (affliction/reagent/modifier/
 * species/trait/form/worn item) folds a static factor table into body factors.
 *
 * on_grant()/on_revoke() only need to invalidate: recompute_factors() (this file's
 * accumulate_grant_factors()) does the actual folding, reading the live grant list
 * every time it rebuilds - so it doesn't matter that two sources granting the exact
 * same table only "apply" once by refcount, the recompute loop still visits every
 * currently-granted table once per rebuild.
 */
/datum/grant_kind/factors
	kind = GRANT_KIND_FACTORS

/datum/grant_kind/factors/on_grant(mob/M, id, datum/source)
	if(isliving(M))
		var/mob/living/L = M
		L.invalidate_factors()
		L.life_wake(LIFE_SYS_ALL, "grant: factors changed")

/datum/grant_kind/factors/on_revoke(mob/M, id, datum/source)
	on_grant(M, id, source)

GLOBAL_DATUM_INIT(grant_kind_factors, /datum/grant_kind/factors, new)

/// Fold every currently-granted GRANT_KIND_FACTORS table into `acc` (recompute_factors(),
/// code/modules/body/factors.dm). Each granted id IS a factor table (see this file's
/// header); who's granting it doesn't matter once any source has, so this folds each
/// distinct table once regardless of how many sources currently grant it - same as
/// every other factors.dm source (an active modifier folds once, not once per grantor).
/datum/body/proc/accumulate_grant_factors(list/acc)
	var/list/tables = owner.grants?[GRANT_KIND_FACTORS]
	if(!length(tables))
		return acc
	for(var/alist/table as anything in tables)
		acc = body_factor_accumulate(acc, table)
	return acc
