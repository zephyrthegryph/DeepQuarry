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
 *
 * This kind only ever grants UNDERSTANDING (`add_language(id, FALSE)` - the FALSE
 * is read by /mob/living/silicon's override and ignored by everyone else's single-arg
 * add_language()). It never toggles a silicon's speech synthesizer as a side effect;
 * that's GRANT_KIND_LANGUAGE_SPEECH, below - grant both kinds for the same id when a
 * source should let a silicon actually voice the language, not just understand it.
 */
/datum/grant_kind/language
	kind = GRANT_KIND_LANGUAGE

/datum/grant_kind/language/on_grant(mob/M, id, datum/source)
	M.add_language(id, FALSE)

/datum/grant_kind/language/on_revoke(mob/M, id, datum/source)
	M.remove_language(id)

GLOBAL_DATUM_INIT(grant_kind_language, /datum/grant_kind/language, new)

/**
 * GRANT_KIND_LANGUAGE_SPEECH: `id` is the same kind of language id as
 * GRANT_KIND_LANGUAGE, but this kind is "can a speech synthesizer VOICE this
 * language" - a silicon-only capability, independent of understanding it
 * (/mob/living/silicon's speech_synthesizer_langs, code/modules/mob/living/silicon/silicon.dm).
 * A module or organ that grants a language with `can_speak = FALSE` (understand-only)
 * grants just GRANT_KIND_LANGUAGE; one that also lets the synthesizer voice it grants
 * both kinds for the same id. Refcounted the same way, so two sources both granting
 * speech on the same language don't fight over who revokes it.
 */
/datum/grant_kind/language_speech
	kind = GRANT_KIND_LANGUAGE_SPEECH

/datum/grant_kind/language_speech/on_grant(mob/M, id, datum/source)
	if(!istype(M, /mob/living/silicon))
		return
	var/mob/living/silicon/S = M
	var/datum/language/L = GLOB.all_languages[id]
	if(L)
		S.speech_synthesizer_langs |= L

/datum/grant_kind/language_speech/on_revoke(mob/M, id, datum/source)
	if(!istype(M, /mob/living/silicon))
		return
	var/mob/living/silicon/S = M
	var/datum/language/L = GLOB.all_languages[id]
	if(L)
		S.speech_synthesizer_langs -= L

GLOBAL_DATUM_INIT(grant_kind_language_speech, /datum/grant_kind/language_speech, new)
