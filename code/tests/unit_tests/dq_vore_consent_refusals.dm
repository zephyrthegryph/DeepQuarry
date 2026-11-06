// Supplement the existing devour/digest order coverage with the remaining consent branches.
/datum/unit_test/dq_requirement_burndown_consent/Run()
	var/list/pair = vore_test_pair()
	var/mob/living/carbon/human/predator = pair[1]
	var/mob/living/carbon/human/prey = pair[2]
	prey.vore_prefs.set_permit_healbelly(FALSE)
	TEST_ASSERT_EQUAL(vore_consent_refusal(VORE_CONSENT_HEAL, predator, prey), "they don't allow healing bellies", "The actual healing preference supplies its exact refusal")
	prey.vore_prefs.set_permit_healbelly(TRUE)
	TEST_ASSERT_NULL(vore_consent_refusal(VORE_CONSENT_HEAL, predator, prey), "A live consenting prey allows healing")
	prey.vore_prefs.set_strip_pref(FALSE)
	TEST_ASSERT_EQUAL(vore_consent_refusal(VORE_CONSENT_STRIP, predator, prey), "they don't allow stripping", "The actual stripping preference supplies its exact refusal")
	TEST_ASSERT(!vore_consents(VORE_CONSENT_STRIP, predator, prey), "The effect's boolean consumer agrees with the refusal")
	prey.vore_prefs.set_strip_pref(TRUE)
	TEST_ASSERT_NULL(vore_consent_refusal(VORE_CONSENT_STRIP, predator, prey), "The actual preference recovers stripping permission")
	TEST_ASSERT(vore_consents(VORE_CONSENT_STRIP, predator, prey), "The effect's boolean consumer agrees with recovery")
