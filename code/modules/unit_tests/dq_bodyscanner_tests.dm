// Unit tests for the qualitative bodyscanner output — damage bands,
// health bands, the damage panel, and scanner-audience symptom filtering.
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


// --- whole-body health band thresholds -----------------------------

/datum/unit_test/dq_bodyscanner_health_bands

/datum/unit_test/dq_bodyscanner_health_bands/Run()
	TEST_ASSERT_EQUAL(dq_qualitative_health_band(100, 100), "uninjured", "full hp = uninjured")
	TEST_ASSERT_EQUAL(dq_qualitative_health_band(70, 100), "minor", "70% hp = minor")
	TEST_ASSERT_EQUAL(dq_qualitative_health_band(45, 100), "moderate", "45% hp = moderate")
	TEST_ASSERT_EQUAL(dq_qualitative_health_band(20, 100), "severe", "20% hp = severe")
	TEST_ASSERT_EQUAL(dq_qualitative_health_band(0, 100), "critical", "0 hp = critical")
	TEST_ASSERT_EQUAL(dq_qualitative_health_band(-50, 100), "critical", "negative hp = critical")


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

	var/datum/medical_issue/condition/lacerated_artery/C = _dq_spawn_condition_on(H, BP_L_ARM, /datum/medical_issue/condition/lacerated_artery)
	TEST_ASSERT_NOTNULL(C, "lacerated_artery didn't spawn")
	C.severity = 80
	C.tick_condition()

	// Force bleeding_visible into the active set so the test doesn't
	// depend on RNG.
	var/seen = FALSE
	for(var/datum/medical_symptom/S as anything in C.active_symptoms)
		if(istype(S, /datum/medical_symptom/bleeding_visible))
			seen = TRUE
			break
	if(!seen)
		var/datum/medical_symptom/bleeding_visible/B = new()
		B.source_condition = C
		LAZYADD(C.active_symptoms, B)

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
	var/datum/medical_issue/condition/lacerated_artery/C = _dq_spawn_condition_on(H, BP_L_ARM, /datum/medical_issue/condition/lacerated_artery)
	TEST_ASSERT_NOTNULL(C, "spawn failed")
	C.severity = 50

	// Force a SCANNER symptom into the active set so a finding is emitted.
	var/datum/medical_symptom/bleeding_visible/B = new()
	B.source_condition = C
	C.active_symptoms = list(B)

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
	var/datum/medical_issue/condition/concussion/C = _dq_spawn_condition_on(H, BP_HEAD, /datum/medical_issue/condition/concussion)
	TEST_ASSERT_NOTNULL(C, "concussion didn't spawn")

	var/datum/medical_symptom/headache/HA = new()
	HA.source_condition = C
	C.active_symptoms = list(HA)

	var/list/findings = dq_qualitative_scanner_findings(H)
	for(var/list/f in findings)
		if(findtext(f["phrase"], "headache"))
			TEST_FAIL("PATIENT-only symptom 'headache' should not appear in scanner findings")

#endif
