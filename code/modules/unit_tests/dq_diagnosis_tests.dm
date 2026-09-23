// Unit tests for the diagnosis layer (code/modules/medical/diagnosis/):
// profiles perceive different things, hidden afflictions need the right
// instrument, renderers work on every body plan, and no readout falls back to
// the legacy four-number injury loads.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Diagnose `M` through `profile_type` and return the report (caller qdels).
/datum/unit_test/proc/_diagnose(mob/living/M, profile_type)
	var/datum/diagnosis/D = M.diagnose(profile_type)
	TEST_ASSERT_NOTNULL(D, "[M] ([M.type]) produced no diagnosis through [profile_type]")
	return D

/// qdel every report passed.
/datum/unit_test/proc/_qdel_reports(...)
	for(var/datum/diagnosis/D as anything in args)
		qdel(D)

/// A human with a visible limb wound and a hidden organ lesion.
/datum/unit_test/proc/_diagnosis_patient()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.injure(INJURY_CUT, 25, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	H.injure(INJURY_BLUNT, liver.max_damage * 0.4, liver, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	return H


// --- The same patient reads differently through different instruments ------

/datum/unit_test/dq_diagnosis_profiles_differ

/datum/unit_test/dq_diagnosis_profiles_differ/Run()
	var/mob/living/carbon/human/H = _diagnosis_patient()

	var/datum/diagnosis/glance = _diagnose(H, /datum/diagnostic_profile/glance)
	var/datum/diagnosis/basic = _diagnose(H, /datum/diagnostic_profile/health_analyzer)
	var/datum/diagnosis/advanced = _diagnose(H, /datum/diagnostic_profile/health_analyzer/advanced)
	var/datum/diagnosis/scanner = _diagnose(H, /datum/diagnostic_profile/body_scanner)

	// The naked eye sees the wound but measures nothing.
	TEST_ASSERT(length(glance.findings_of(DIAG_FINDING_WOUND)), "a glance should see the open limb wound")
	TEST_ASSERT_NULL(glance.heart_rate, "a glance should not measure a heart rate")
	TEST_ASSERT_NULL(glance.oxygenation, "a glance should not measure SpO2")

	// A basic analyzer measures vitals and sees the wound, not the organ.
	TEST_ASSERT_NOTNULL(basic.heart_rate, "a health analyzer should measure the heart rate")
	TEST_ASSERT_NOTNULL(basic.temperature, "a health analyzer should measure temperature")
	TEST_ASSERT_NULL(basic.blood_pressure, "a basic analyzer has no blood pressure cuff")
	TEST_ASSERT(length(basic.findings_of(DIAG_FINDING_WOUND)), "a health analyzer should report the limb wound")
	TEST_ASSERT(!length(basic.findings_of(DIAG_FINDING_LESION)), "a basic analyzer can't image organ lesions")

	// Internal imaging finds the lesion, and the advanced tier reads BP.
	TEST_ASSERT(length(advanced.findings_of(DIAG_FINDING_LESION)), "an advanced analyzer should image the liver lesion")
	TEST_ASSERT_NOTNULL(advanced.blood_pressure, "an advanced analyzer should read blood pressure")
	TEST_ASSERT(length(scanner.findings_of(DIAG_FINDING_LESION)), "the body scanner should image the liver lesion")
	TEST_ASSERT(LAZYLEN(scanner.parts), "the body scanner should report per-limb bands")
	TEST_ASSERT(!LAZYLEN(basic.parts), "a basic analyzer should not report per-limb bands")

	TEST_ASSERT(LAZYLEN(advanced.findings) > LAZYLEN(basic.findings), "the advanced report should hold more findings than the basic one")
	TEST_ASSERT(LAZYLEN(scanner.hints), "the body scanner should give treatment hints")
	TEST_ASSERT(!LAZYLEN(basic.hints), "a basic analyzer gives no treatment hints")

	_qdel_reports(glance, basic, advanced, scanner)


// --- A hidden affliction needs the right instrument -------------------------

/datum/unit_test/dq_diagnosis_hidden_affliction

/datum/unit_test/dq_diagnosis_hidden_affliction/Run()
	var/mob/living/carbon/human/H = _diagnosis_patient()

	// Organ lesions present to internal imaging only.
	var/datum/diagnosis/basic = _diagnose(H, /datum/diagnostic_profile/health_analyzer)
	var/datum/diagnosis/advanced = _diagnose(H, /datum/diagnostic_profile/health_analyzer/advanced)
	TEST_ASSERT(!basic.has_finding_for(/datum/affliction/lesion), "the basic analyzer should not see an organ lesion")
	TEST_ASSERT(advanced.has_finding_for(/datum/affliction/lesion), "the advanced analyzer should see the organ lesion")
	_qdel_reports(basic, advanced)

	// A condition declared lab-only needs the body scanner or a phasic analyzer.
	var/datum/affliction/A = H.body.afflict(/datum/affliction/toxic_poisoning, null, 50)
	TEST_ASSERT_NOTNULL(A, "toxic poisoning could not be afflicted")
	A.presentation = PRESENT_LAB
	basic = _diagnose(H, /datum/diagnostic_profile/health_analyzer)
	advanced = _diagnose(H, /datum/diagnostic_profile/health_analyzer/advanced)
	var/datum/diagnosis/scanner = _diagnose(H, /datum/diagnostic_profile/body_scanner)
	TEST_ASSERT(!basic.has_finding_for(/datum/affliction/toxic_poisoning), "a lab-only condition should be invisible to the basic analyzer")
	TEST_ASSERT(!advanced.has_finding_for(/datum/affliction/toxic_poisoning), "a lab-only condition should be invisible to the advanced analyzer")
	TEST_ASSERT(scanner.has_finding_for(/datum/affliction/toxic_poisoning), "the body scanner should find a lab-only condition")
	_qdel_reports(basic, advanced, scanner)

	// treatment_demand() follows what the instrument can perceive.
	var/list/basic_demand = H.body.treatment_demand(/datum/diagnostic_profile/health_analyzer)
	var/list/lab_demand = H.body.treatment_demand(/datum/diagnostic_profile/body_scanner)
	TEST_ASSERT(!basic_demand?[TREAT_ANTITOXIN], "the basic analyzer should not ask for antitoxin for a condition it can't see")
	TEST_ASSERT(lab_demand?[TREAT_ANTITOXIN], "the body scanner should ask for antitoxin for the poisoning it found")

	// Declared surface presentation brings it back to the basic analyzer.
	A.presentation = PRESENT_SURFACE
	basic = _diagnose(H, /datum/diagnostic_profile/health_analyzer)
	TEST_ASSERT(basic.has_finding_for(/datum/affliction/toxic_poisoning), "a surface-presenting condition should reach the basic analyzer")
	qdel(basic)


// --- Feigned death is applied once, inside diagnose() ------------------------

/datum/unit_test/dq_diagnosis_fake_death

/datum/unit_test/dq_diagnosis_fake_death/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.status_flags |= FAKEDEATH
	var/datum/diagnosis/basic = _diagnose(H, /datum/diagnostic_profile/health_analyzer)
	var/datum/diagnosis/admin = _diagnose(H, /datum/diagnostic_profile/admin)
	TEST_ASSERT_EQUAL(basic.status, DIAG_STATUS_DEAD, "an analyzer should read a feigned death as dead")
	TEST_ASSERT_EQUAL(basic.heart_rate, 0, "an analyzer should read a flat pulse on a feigned death")
	TEST_ASSERT_EQUAL(admin.status, DIAG_STATUS_ALIVE, "the admin profile sees through feigned death")
	H.status_flags &= ~FAKEDEATH
	_qdel_reports(basic, admin)


// --- Renderers work on every body plan ---------------------------------------

/datum/unit_test/dq_diagnosis_renderers_all_plans

/datum/unit_test/dq_diagnosis_renderers_all_plans/Run()
	var/list/patients = list()

	var/mob/living/carbon/human/H = _diagnosis_patient()
	patients += H

	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	R.injure(INJURY_BLUNT, 10, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	R.injure(INJURY_BURN, 10, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	patients += R

	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/animal/passive/mouse)
	S.injure(INJURY_BLUNT, 1, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	patients += S

	var/mob/living/carbon/human/P = allocate(/mob/living/carbon/human)
	P.set_species(SPECIES_PROTEAN)
	TEST_ASSERT(istype(P.body, /datum/body/humanoid/nanoform), "the protean patient should have the nanoform plan, got [P.body?.type]")
	P.injure(INJURY_BLUNT, 10, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	patients += P

	for(var/mob/living/M as anything in patients)
		for(var/profile_type in typesof(/datum/diagnostic_profile))
			var/datum/diagnosis/D = _diagnose(M, profile_type)
			TEST_ASSERT(length(D.render_chat()), "[M.type] through [profile_type]: the chat renderer produced nothing")
			var/list/ui = D.report_data()
			TEST_ASSERT(islist(ui) && islist(ui["vitals"]) && islist(ui["findings"]), "[M.type] through [profile_type]: malformed TGUI data")
			D.examine_lines()
			TEST_ASSERT(D.hud_status() in list("dead", "critical", "ill", "healthy"), "[M.type] through [profile_type]: bad HUD status '[D.hud_status()]'")
			qdel(D)
		TEST_ASSERT(sensor_status(M), "[M.type]: no suit-sensor status")

	// The cyborg analyzer reports the robot's chassis load; examine sees it.
	var/datum/diagnosis/robot_scan = _diagnose(R, /datum/diagnostic_profile/robot_analyzer)
	TEST_ASSERT(LAZYLEN(robot_scan.findings), "the cyborg analyzer should report the robot's damage")
	TEST_ASSERT(LAZYLEN(robot_scan.parts), "the cyborg analyzer should report the robot's components")
	qdel(robot_scan)
	TEST_ASSERT(length(machine_examine_lines(R)), "examining a damaged robot should describe the damage")

	// Organic analyzers can't read synthetic chassis faults.
	var/datum/diagnosis/organic_scan = _diagnose(R, /datum/diagnostic_profile/health_analyzer)
	TEST_ASSERT(!LAZYLEN(organic_scan.findings), "an organic health analyzer should not read a robot's chassis")
	qdel(organic_scan)


// --- No readout falls back to the four legacy injury loads --------------------

/datum/unit_test/dq_diagnosis_no_legacy_readouts

/datum/unit_test/dq_diagnosis_no_legacy_readouts/Run()
	var/static/list/readouts = list(
		"code/game/objects/items/devices/scanners/health.dm",
		"code/game/objects/items/devices/scanners/guide.dm",
		"code/game/machinery/adv_med.dm",
		"code/modules/medical/bodyscanner/data.dm",
		"code/modules/medical/bodyscanner/qualitative.dm",
		"code/game/machinery/computer/Operating.dm",
		"code/datums/repositories/crew.dm",
		"code/game/machinery/vitals_monitor.dm",
		"code/game/machinery/medical_kiosk.dm",
		"code/game/machinery/Sleeper.dm",
		"code/modules/mob/living/silicon/robot/analyzer.dm",
		"code/modules/mob/living/silicon/robot/examine.dm",
		"code/modules/mob/living/silicon/robot/robot_ui.dm",
		"code/modules/mob/living/silicon/ai/examine.dm",
		"code/modules/mob/living/silicon/robot/dogborg/dog_sleeper.dm",
		"code/modules/mob/mob_grab_specials.dm",
		"code/modules/pda/utilities.dm",
		"code/game/objects/items/weapons/medigun/medigun_backpack_ui.dm",
		"code/game/mecha/equipment/tools/sleeper.dm",
		"code/modules/integrated_electronics/subtypes/input.dm",
		"code/modules/integrated_electronics/subtypes/z_mixed.dm",
		"code/modules/medical/diagnosis/diagnose.dm",
		"code/modules/medical/diagnosis/renderers.dm",
	)
	var/regex/legacy = regex(@"injury_load\(INJURY_CATEGORY_(PHYSICAL|THERMAL|TOXIC|" + "ASPHYXIA" + @")\)")
	for(var/path in readouts)
		var/text = file2text(path)
		if(!text)
			TEST_FAIL("readout source [path] could not be read")
			continue
		if(legacy.Find(text))
			TEST_FAIL("[path] builds a readout from a legacy injury load: [legacy.match]")

#endif
