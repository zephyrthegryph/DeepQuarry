/**
 * GRANT_KIND_LANGUAGE: `id` is a language name/id (a GLOB.all_languages key,
 * code/modules/mob/language/language.dm). Refcounted so overlapping sources (an
 * implant and a software module both granting the same language, say) don't step
 * on each other: the language is added on the first grant and removed only once
 * every source has revoked it.
 *
 * `add_language()`/`remove_language()` stay the low-level, unconditional primitives
 * (species defaults, one-shot narrative grants with no source to track) - use them
 * directly for a language that's never individually revoked. Use
 * grant(L, GRANT_KIND_LANGUAGE, id, source) instead whenever an item, implant,
 * organ or modifier can independently add and later remove the same language.
 */
/datum/grant_kind/language
	kind = GRANT_KIND_LANGUAGE

/datum/grant_kind/language/on_grant(mob/M, id, datum/source)
	M.add_language(id)

/datum/grant_kind/language/on_revoke(mob/M, id, datum/source)
	M.remove_language(id)

GLOBAL_DATUM_INIT(grant_kind_language, /datum/grant_kind/language, new)
