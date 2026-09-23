// Unit tests for the qualitative bodyscanner output — damage bands,
// vitality bands, the damage panel, and scanner-audience symptom filtering.
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


// --- damage panel emits every kind ---------------------------------

/datum/unit_test/dq_bodyscanner_damage_panel_emits_all_kinds

/datum/unit_test/dq_bodyscanner_damage_panel_emits_all_kinds/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/list/panel = dq_qualitative_damage_panel(H)
	TEST_ASSERT(length(panel) > 0, "damage panel should emit at least one row")
	for(var/list/row in panel)
		TEST_ASSERT(row["kind"], "panel row missing 'kind'")
		TEST_ASSERT(row["label"], "panel row missing 'label'")
		TEST_ASSERT(row["band"], "panel row missing 'band'")


// --- scanner findings: SCANNER-audience symptoms show up -----------

/datum/unit_test/dq_bodyscanner_scanner_findings_filter

/datum/unit_test/dq_bodyscanner_scanner_findings_filter/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/list/empty = dq_qualitative_scanner_findings(H)
	TEST_ASSERT_EQUAL(length(empty), 0, "no conditions = no findings")

	var/datum/affliction/lacerated_artery/C = _spawn_affliction_on(H, BP_L_ARM, /datum/affliction/lacerated_artery)
	TEST_ASSERT_NOTNULL(C, "lacerated_artery didn't spawn")
	C.set_severity(80)
	C.tick()

	// Force bleeding_visible into the active set so the test doesn't
	// depend on RNG. Symptoms are singletons: the set holds typepaths.
	if(!(/datum/affliction_symptom/bleeding_visible in C.active_symptoms))
		LAZYADD(C.active_symptoms, /datum/affliction_symptom/bleeding_visible)

	var/list/findings = dq_qualitative_scanner_findings(H)
	TEST_ASSERT(length(findings) > 0, "lacerated_artery with scanner symptom should produce a finding")
	var/saw_bleed = FALSE
	for(var/list/f in findings)
		if(findtext(f["phrase"], "blood loss"))
			saw_bleed = TRUE
			break
	TEST_ASSERT(saw_bleed, "scanner_phrase 'blood loss' should be reported in findings")


// --- scanner findings: trend arrow tracks severity changes -----------

/datum/unit_test/dq_bodyscanner_finding_trend

/datum/unit_test/dq_bodyscanner_finding_trend/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/lacerated_artery/C = _spawn_affliction_on(H, BP_L_ARM, /datum/affliction/lacerated_artery)
	TEST_ASSERT_NOTNULL(C, "spawn failed")
	C.severity = 50

	// Force a SCANNER symptom into the active set so a finding is emitted.
	C.active_symptoms = list(/datum/affliction_symptom/bleeding_visible)

	// First scan: trend should be "new" — no prior baseline.
	var/list/findings1 = dq_qualitative_scanner_findings(H)
	TEST_ASSERT(length(findings1) > 0, "first scan should emit a finding")
	TEST_ASSERT_EQUAL(findings1[1]["trend"], "new", "first scan trend should be 'new'")

	// Severity unchanged between scans: "stable".
	var/list/findings2 = dq_qualitative_scanner_findings(H)
	TEST_ASSERT_EQUAL(findings2[1]["trend"], "stable", "unchanged severity should read 'stable'")

	// Severity rises significantly: "worsening".
	C.severity = 70
	var/list/findings3 = dq_qualitative_scanner_findings(H)
	TEST_ASSERT_EQUAL(findings3[1]["trend"], "worsening", "rising severity should read 'worsening'")

	// Severity drops significantly: "improving".
	C.severity = 30
	var/list/findings4 = dq_qualitative_scanner_findings(H)
	TEST_ASSERT_EQUAL(findings4[1]["trend"], "improving", "falling severity should read 'improving'")

	// Tiny drift stays "stable" (dead zone).
	C.severity = 31
	var/list/findings5 = dq_qualitative_scanner_findings(H)
	TEST_ASSERT_EQUAL(findings5[1]["trend"], "stable", "tiny drift should stay in the dead zone")


// --- scanner findings: PATIENT-only symptoms stay hidden -----------

/datum/unit_test/dq_bodyscanner_patient_symptoms_hidden

/datum/unit_test/dq_bodyscanner_patient_symptoms_hidden/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/concussion/C = _spawn_affliction_on(H, BP_HEAD, /datum/affliction/concussion)
	TEST_ASSERT_NOTNULL(C, "concussion didn't spawn")

	C.active_symptoms = list(/datum/affliction_symptom/headache)

	var/list/findings = dq_qualitative_scanner_findings(H)
	for(var/list/f in findings)
		if(findtext(f["phrase"], "headache"))
			TEST_FAIL("PATIENT-only symptom 'headache' should not appear in scanner findings")


// --- scanner findings: GM custom afflictions honour showscanner --------

/datum/unit_test/dq_bodyscanner_custom_affliction_findings

/datum/unit_test/dq_bodyscanner_custom_affliction_findings/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/liver = H.internal_organs_by_name[O_LIVER]
	TEST_ASSERT_NOTNULL(liver, "test human has no liver")
	var/datum/affliction/custom/A = H.body.afflict(/datum/affliction/custom, liver, 60)
	TEST_ASSERT_NOTNULL(A, "custom affliction could not be afflicted")
	A.name = "glowing liver"

	A.showscanner = FALSE
	for(var/list/f in dq_qualitative_scanner_findings(H))
		if(f["phrase"] == "glowing liver")
			TEST_FAIL("a custom affliction hidden from scanners appeared in the findings")

	A.showscanner = TRUE
	var/found = FALSE
	for(var/list/f in dq_qualitative_scanner_findings(H))
		if(f["phrase"] == "glowing liver" && f["organ"] == liver.name)
			found = TRUE
	TEST_ASSERT(found, "a scanner-visible custom affliction was not reported on its organ")

#endif
