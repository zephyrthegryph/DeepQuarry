// Traits are a keyed stat: a trait on a datum is a hold on STAT_TRAIT_HOLDS keyed by the trait, held by its source. There is no per-datum
// trait list and no ADD_TRAIT/REMOVE_TRAIT/HAS_TRAIT macro any more (tools/ci/traits_lint.py).
//
//	add_trait(mob, TRAIT_UNLUCKY, src)       // src (a datum) or a text source key (JOB_TRAIT, ...)
//	remove_trait(mob, TRAIT_UNLUCKY, src)    // null sources: every source but ROUNDSTART_TRAIT
//	has_trait(mob, TRAIT_UNLUCKY)
//
// A datum source releases its grants when it is deleted, like any contribution. A text
// source key is a /datum/trait_source singleton (trait_source()), so it lives for the round.
// The first grant of a trait emits /datum/om/event/trait_gained, the last release
// /datum/om/event/trait_lost.

GLOBAL_LIST_EMPTY(trait_source_singletons)

/// The singleton that holds grants for a text source key (JOB_TRAIT, "adminabuse", ...).
/datum/trait_source
	var/name

/datum/trait_source/New(key)
	name = key

/// The datum holding grants for `source`: the source itself when it is a datum, else the
/// singleton for its text key.
/proc/trait_source(source)
	if(isnull(source))
		return null
	if(isdatum(source))
		return source
	var/key = "[source]"
	var/datum/trait_source/S = GLOB.trait_source_singletons[key]
	if(!S)
		S = new /datum/trait_source(key)
		GLOB.trait_source_singletons[key] = S
	return S

/// TRUE when `target` holds `trait` from any source.
/proc/has_trait(datum/target, trait)
	READS_FROM(target)
	if(!isdatum(target))
		return FALSE
	var/list/held = stat_value(target, STAT_TRAIT_HOLDS)
	return !!held && held[trait] > 0

/// TRUE when `target` holds `trait` from `source`.
/proc/has_trait_from(datum/target, trait, source)
	if(!isdatum(target))
		return FALSE
	var/datum/holder = trait_source(source)
	return holder && (holder in hold_sources(target, STAT_TRAIT_HOLDS, trait))

/// TRUE when `target` or its mind holds `trait`.
/proc/has_mind_trait(mob/target, trait)
	return has_trait(target, trait) || (target?.mind && has_trait(target.mind, trait))

/// The source datums granting `target` `trait` (a new list, empty when none).
/proc/trait_sources(datum/target, trait)
	return isdatum(target) ? hold_sources(target, STAT_TRAIT_HOLDS, trait) : list()

/// Every trait `target` holds (a new list).
/proc/trait_list(datum/target)
	. = list()
	if(!isdatum(target))
		return
	var/list/per_key = stat_value(target, STAT_TRAIT_HOLDS)
	if(!islist(per_key))
		return
	for(var/trait in per_key)
		if(per_key[trait] > 0)
			. += trait

/// Grants `target` `trait` from `source` (a datum or a text key).
/proc/add_trait(datum/target, trait, source)
	if(QDELETED(target) || isnull(trait))
		return FALSE
	var/datum/holder = trait_source(source)
	if(!holder)
		CRASH("add_trait([target], [trait]) without a source")
	var/had = has_trait(target, trait)
	if(QDELETED(holder) || !hold(target, STAT_TRAIT_HOLDS, 1, holder, key = trait))
		return FALSE
	if(!had)
		PUBLISH_LEGACY(target, /datum/notice/trait_gained, trait)
	return TRUE

/// Releases `trait` on `target` from `sources` (one source or a list). Null sources release
/// every source except ROUNDSTART_TRAIT.
/proc/remove_trait(datum/target, trait, sources)
	if(isnull(target) || isnull(trait) || !has_trait(target, trait))
		return
	var/list/holders = list()
	if(isnull(sources))
		var/datum/roundstart = trait_source(ROUNDSTART_TRAIT)
		for(var/datum/holder as anything in trait_sources(target, trait))
			if(holder != roundstart)
				holders += holder
	else
		var/list/wanted = islist(sources) ? sources : list(sources)
		for(var/source in wanted)
			holders |= trait_source(source)
	for(var/datum/holder as anything in holders)
		release(target, STAT_TRAIT_HOLDS, holder, trait)
	if(!has_trait(target, trait))
		PUBLISH_LEGACY(target, /datum/notice/trait_lost, trait)

/// Releases every trait `target` holds from `sources` (one source or a list).
/proc/remove_traits_in(datum/target, sources)
	if(isnull(target) || isnull(sources))
		return
	for(var/trait in trait_list(target))
		remove_trait(target, trait, sources)

/// Grants a list of traits from one source.
/datum/proc/add_traits(list/list_of_traits, source)
	ASSERT(islist(list_of_traits), "Invalid arguments passed to add_traits! Invoked on [src] with [list_of_traits], source being [source].")
	for(var/trait in list_of_traits)
		add_trait(src, trait, source)

/// Releases a list of traits from one source.
/datum/proc/remove_traits(list/list_of_traits, source)
	ASSERT(islist(list_of_traits), "Invalid arguments passed to remove_traits! Invoked on [src] with [list_of_traits], source being [source].")
	for(var/trait in list_of_traits)
		remove_trait(src, trait, source)
