// The pAI universal translator used to add a hardcoded list of ~20 languages
// on toggle-on and unconditionally remove that same list on toggle-off,
// regardless of whether the pai already knew any of them natively. Since
// /datum/pai_software/translator is a single GLOBAL_LIST_EMPTY(pai_software_by_key)
// singleton shared by every pAI (see code/modules/mob/living/silicon/pai/pai_service.dm), any
// per-instance state would itself have been a cross-pai clobber, so the fix
// tracks exactly which languages the translator granted on the pai mob
// itself (translator_added_languages) and only removes those.

/datum/unit_test/dq_pai_translator_does_not_strip_native_language

/datum/unit_test/dq_pai_translator_does_not_strip_native_language/Run()
	var/mob/living/silicon/pai/P = allocate(/mob/living/silicon/pai)
	var/datum/pai_software/translator/T = new

	// This pai natively knows Vox (from some other source -- a species quirk,
	// an award, whatever) before ever touching the translator module.
	P.add_language(LANGUAGE_VOX)
	TEST_ASSERT(GLOB.all_languages[LANGUAGE_VOX] in P.languages, "precondition: the pai should know Vox before the translator is touched")

	T.toggle(P) // on
	TEST_ASSERT(P.translator_on, "toggle should turn the translator on")
	TEST_ASSERT(GLOB.all_languages[LANGUAGE_UNATHI] in P.languages, "the translator should grant Unathi while on")
	TEST_ASSERT(!(LANGUAGE_VOX in P.translator_added_languages), "Vox should not be tracked as translator-granted since the pai already knew it")

	T.toggle(P) // off
	TEST_ASSERT(!P.translator_on, "toggle should turn the translator back off")
	TEST_ASSERT(!(GLOB.all_languages[LANGUAGE_UNATHI] in P.languages), "turning the translator off should remove a language it granted")
	TEST_ASSERT(GLOB.all_languages[LANGUAGE_VOX] in P.languages, "turning the translator off must not strip Vox, which the pai knew natively")

/datum/unit_test/dq_pai_translator_removes_only_what_it_granted

/datum/unit_test/dq_pai_translator_removes_only_what_it_granted/Run()
	var/mob/living/silicon/pai/P = allocate(/mob/living/silicon/pai)
	var/datum/pai_software/translator/T = new

	T.toggle(P) // on
	TEST_ASSERT(length(P.translator_added_languages) > 20, "the translator should have tracked every language it granted, got [length(P.translator_added_languages)]")

	T.toggle(P) // off
	for(var/language in T.candidate_languages)
		TEST_ASSERT(!(GLOB.all_languages[language] in P.languages), "[language] should have been removed after the translator toggled off")
	TEST_ASSERT_NULL(P.translator_added_languages, "the tracked grant list should be cleared once everything it added has been removed")
