// Real profile-backed preference and ordered refusal behavior.
/datum/unit_test/dq_vore_native_consent

/datum/unit_test/dq_vore_native_consent/Run()
	var/list/pair = vore_test_pair()
	var/mob/living/carbon/human/pred = pair[1]
	var/mob/living/carbon/human/prey = pair[2]
	var/datum/entry/part/req/vore_consent/devour/R = part_make(/datum/entry/part/req/vore_consent/devour)
	var/datum/act/op/acceptance/A = acceptance_act(prey, null, prey, null, pred)
	var/list/reads = R.read_keys(A)
	var/found_profile = FALSE
	var/found_preference = FALSE
	var/found_pred_absorbed = FALSE
	for(var/list/read as anything in reads)
		if(read[1] == prey && read[2] == "vore_prefs")
			found_profile = TRUE
		if(read[1] == prey.vore_prefs && read[2] == "devourable")
			found_preference = TRUE
		if(read[1] == pred && read[2] == "absorbed")
			found_pred_absorbed = TRUE
	TEST_ASSERT(found_profile && found_preference && found_pred_absorbed, "real record reference, field and other actor state are declared dependencies")
	acceptance_act_release(A)
	prey.vore_prefs.set_devourable(TRUE)
	pred.set_absorbed(FALSE)
	prey.set_absorbed(FALSE)
	TEST_ASSERT_NULL(vore_consent_refusal(/datum/entry/part/req/vore_consent/devour, pred, prey), "willing actual humans are admitted")
	pred.set_absorbed(TRUE)
	prey.vore_prefs.set_devourable(FALSE)
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/entry/part/req/vore_consent/devour, pred, prey), "They aren't able to be devoured.", "prey preference refuses before predator state")
	prey.vore_prefs.set_devourable(TRUE)
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/entry/part/req/vore_consent/devour, pred, prey), "They aren't in a state to be devoured.", "predator state is checked after prey permission")
	pred.set_absorbed(FALSE)
	TEST_ASSERT_NULL(vore_consent_refusal(/datum/entry/part/req/vore_consent/devour, pred, prey), "restoring actual sources allows again")
	var/datum/record/vore_prefs/copied = allocate(/datum/record/vore_prefs)
	copied.set_devourable(FALSE)
	record_copy(prey.vore_prefs, copied)
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/entry/part/req/vore_consent/devour, pred, prey), "They aren't able to be devoured.", "real record copy follows setter-backed source")
