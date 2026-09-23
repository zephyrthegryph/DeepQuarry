// Unit tests for the qualitative bodyscanner output: damage bands,
// vitality bands, and the body scanner diagnosis (signs, trends, GM
// afflictions).
//
// See dq_surgery_tests.dm for the include scheme and macro scope.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// --- damage band thresholds ----------------------------------------

/datum/unit_test/dq_bodyscanner_qualitative_bands

/datum/unit_test/dq_bodyscanner_qualitative_bands/Run()
	TEST_ASSERT_EQUAL(dq_qualitative_damage_band(0, 100), "uninjured", "0 damage = uninjured")
	TEST_ASSERT_EQUAL(dq_qualitative_damage_band(10, 100), "minor", "10% damage = minor")
	TEST_ASSERT_EQUAL(dq_qualitative_damage_band(35, 100), "moderate", "35% damage = moderate")
	TEST_ASSERT_EQUAL(dq_qualitative_damage_band(60, 100), "severe", "60% damage = severe")
	TEST_ASSERT_EQUAL(dq_qualitative_damage_band(90, 100), "critical", "90% damage = critical")
	// Defensive: zero max shouldn't crash.
	TEST_ASSERT_EQUAL(dq_qualitative_damage_band(10, 0), "minor", "zero max defaults to minor when damage present")


// --- whole-body vitality band thresholds ----------------------------

/datum/unit_test/dq_bodyscanner_health_bands

/datum/unit_test/dq_bodyscanner_health_bands/Run()
	TEST_ASSERT_EQUAL(dq_qualitative_vitality_band(1), "uninjured", "full vitality = uninjured")
	TEST_ASSERT_EQUAL(dq_qualitative_vitality_band(0.7), "minor", "70% vitality = minor")
	TEST_ASSERT_EQUAL(dq_qualitative_vitality_band(0.45), "moderate", "45% vitality = moderate")
	TEST_ASSERT_EQUAL(dq_qualitative_vitality_band(0.2), "severe", "20% vitality = severe")
	TEST_ASSERT_EQUAL(dq_qualitative_vitality_band(0), "critical", "no vitality = critical")
	TEST_ASSERT_EQUAL(dq_qualitative_vitality_band(0.95, TRUE), "critical", "a patient down from injury reads critical whatever the number")

	// A real patient: healthy reads uninjured, a serious injury drops the band.
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(dq_qualitative_vitality_band(H.vitality(), H.is_critical()), "uninjured", "a fresh human should read uninjured")
	H.injure(INJURY_BLUNT, 60, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT(_dq_band_rank(dq_qualitative_vitality_band(H.vitality(), H.is_critical())) > _dq_band_rank("uninjured"), "a heavy chest injury should lower the vitality band")


// --- body scanner diagnosis: SCANNER-audience symptoms present as signs ----

/datum/unit_test/dq_bodyscanner_scanner_findings_filter

/// Names of the body scanner diagnosis findings of `kind` (all when null).
/datum/unit_test/proc/_body_scanner_finding_names(mob/living/carbon/human/H, kind = null)
	. = list()
	var/datum/diagnosis/D = H.diagnose(/datum/diagnostic_profile/body_scanner)
	for(var/datum/diagnosis_finding/F as anything in D.findings_of(kind))
		. += F.name
	qdel(D)

/datum/unit_test/dq_bodyscanner_scanner_findings_filter/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/list/empty = _body_scanner_finding_names(H)
	TEST_ASSERT_EQUAL(length(empty), 0, "no conditions = no findings (got [english_list(empty)])")

	var/datum/affliction/lacerated_artery/C = _spawn_affliction_on(H, BP_L_ARM, /datum/affliction/lacerated_artery)
	TEST_ASSERT_NOTNULL(C, "lacerated_artery didn't spawn")
	C.set_severity(80)
	C.tick()

	// Force bleeding_visible into the active set so the test doesn't
	// depend on RNG. Symptoms are singletons: the set holds typepaths.
	if(!(/datum/affliction_symptom/bleeding_visible in C.active_symptoms))
		LAZYADD(C.active_symptoms, /datum/affliction_symptom/bleeding_visible)

	var/saw_bleed = FALSE
	for(var/name in _body_scanner_finding_names(H, DIAG_FINDING_SIGN))
		if(findtext(name, "blood loss"))
			saw_bleed = TRUE
			break
	TEST_ASSERT(saw_bleed, "scanner_phrase 'blood loss' should be reported as a sign")


// --- body scanner diagnosis: trend tracks severity changes -------------

/datum/unit_test/dq_bodyscanner_finding_trend

/datum/unit_test/proc/_lacerated_artery_trend(mob/living/carbon/human/H)
	var/datum/diagnosis/D = H.diagnose(/datum/diagnostic_profile/body_scanner)
	for(var/datum/diagnosis_finding/F as anything in D.findings)
		if(F.source_type == /datum/affliction/lacerated_artery)
			. = F.trend
	qdel(D)

/datum/unit_test/dq_bodyscanner_finding_trend/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/lacerated_artery/C = _spawn_affliction_on(H, BP_L_ARM, /datum/affliction/lacerated_artery)
	TEST_ASSERT_NOTNULL(C, "spawn failed")
	C.severity = 50

	TEST_ASSERT_EQUAL(_lacerated_artery_trend(H), "new", "first scan trend should be 'new'")
	TEST_ASSERT_EQUAL(_lacerated_artery_trend(H), "stable", "unchanged severity should read 'stable'")
	C.severity = 70
	TEST_ASSERT_EQUAL(_lacerated_artery_trend(H), "worsening", "rising severity should read 'worsening'")
	C.severity = 30
	TEST_ASSERT_EQUAL(_lacerated_artery_trend(H), "improving", "falling severity should read 'improving'")
	C.severity = 31
	TEST_ASSERT_EQUAL(_lacerated_artery_trend(H), "stable", "tiny drift should stay in the dead zone")


// --- body scanner diagnosis: PATIENT-only symptoms stay hidden ----------

/datum/unit_test/dq_bodyscanner_patient_symptoms_hidden

/datum/unit_test/dq_bodyscanner_patient_symptoms_hidden/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/concussion/C = _spawn_affliction_on(H, BP_HEAD, /datum/affliction/concussion)
	TEST_ASSERT_NOTNULL(C, "concussion didn't spawn")

	C.active_symptoms = list(/datum/affliction_symptom/headache)

	for(var/name in _body_scanner_finding_names(H, DIAG_FINDING_SIGN))
		if(findtext(name, "headache"))
			TEST_FAIL("PATIENT-only symptom 'headache' should not appear in scanner findings")


// --- body scanner diagnosis: GM custom afflictions honour showscanner ------

/datum/unit_test/dq_bodyscanner_custom_affliction_findings

/datum/unit_test/dq_bodyscanner_custom_affliction_findings/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/liver = H.internal_organs_by_name[O_LIVER]
	TEST_ASSERT_NOTNULL(liver, "test human has no liver")
	var/datum/affliction/custom/A = H.body.afflict(/datum/affliction/custom, liver, 60)
	TEST_ASSERT_NOTNULL(A, "custom affliction could not be afflicted")
	A.name = "glowing liver"

	A.showscanner = FALSE
	if("glowing liver" in _body_scanner_finding_names(H))
		TEST_FAIL("a custom affliction hidden from scanners appeared in the findings")

	A.showscanner = TRUE
	var/found = FALSE
	var/datum/diagnosis/D = H.diagnose(/datum/diagnostic_profile/body_scanner)
	for(var/datum/diagnosis_finding/F as anything in D.findings)
		if(F.name == "glowing liver" && F.location == liver.name)
			found = TRUE
	qdel(D)
	TEST_ASSERT(found, "a scanner-visible custom affliction was not reported on its organ")

#endif
