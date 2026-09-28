// MED-9 group C regression tests: body scanner parts (D19) and the split procs.

/// Find the diagnosis part entry named `part_name` of `kind`, or null.
/proc/dq_test_find_part(datum/diagnosis/D, part_name, kind)
	for(var/list/entry as anything in D.parts)
		if(entry["name"] == part_name && entry["kind"] == kind)
			return entry
	return null

/// D19: internal organs reach the scanner as diagnose_parts entries.
/datum/unit_test/dq_k_c_d19_scanner_organs_from_diagnosis

/datum/unit_test/dq_k_c_d19_scanner_organs_from_diagnosis/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/appendix/A = H.organ_in(O_APPENDIX)
	TEST_ASSERT(istype(A), "the test human has an appendix")
	A.inflamed = 1
	var/datum/diagnosis/D = H.diagnose(/datum/diagnostic_profile/body_scanner)
	var/list/entry = dq_test_find_part(D, A.name, DIAG_PART_INTERNAL)
	TEST_ASSERT_NOTNULL(entry, "the appendix is an internal part of the scanner diagnosis")
	TEST_ASSERT("appendicitis" in entry["flags"], "an inflamed appendix is flagged in the diagnosis part")
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	TEST_ASSERT_NOTNULL(dq_test_find_part(D, chest.name, DIAG_PART_EXTERNAL), "limbs are external parts")
	qdel(D)

/// D19: the scanner no longer carries its own organ emitters.
/datum/unit_test/dq_k_c_d19_scanner_emitters_removed

/datum/unit_test/dq_k_c_d19_scanner_emitters_removed/Run()
	var/obj/machinery/bodyscanner/S = allocate(/obj/machinery/bodyscanner)
	TEST_ASSERT(!hascall(S, "dq_emit_internal_organs"), "the raw internal organ emitter is gone")
	TEST_ASSERT(!hascall(S, "dq_emit_external_organs"), "the raw external organ emitter is gone")

/// D19: feigned death reads as brain death in the part bands, once, in diagnose().
/datum/unit_test/dq_k_c_d19_fake_death_parts

/datum/unit_test/dq_k_c_d19_fake_death_parts/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.organ_in(O_BRAIN)
	TEST_ASSERT(istype(B), "the test human has a brain")
	H.status_flags |= FAKEDEATH
	var/datum/diagnosis/D = H.diagnose(/datum/diagnostic_profile/body_scanner)
	var/list/entry = dq_test_find_part(D, B.name, DIAG_PART_INTERNAL)
	TEST_ASSERT_NOTNULL(entry, "the brain is an internal part")
	TEST_ASSERT_EQUAL(entry["band"], DIAG_BAND_CRITICAL, "a feigned death shows a critical brain")
	qdel(D)
	H.status_flags &= ~FAKEDEATH

/// P2-F6: transform_into_other_human takes an options datum; the defaults keep our name.
/datum/unit_test/dq_k_c_f6_transform_options

/datum/unit_test/dq_k_c_f6_transform_options/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human)
	H.name = "shifter"
	victim.name = "target"
	H.transform_into_other_human(victim)
	TEST_ASSERT_EQUAL(H.name, "shifter", "the default options don't copy the name")
	H.transform_into_other_human(victim, new /datum/human_transform_options(copy_name = TRUE))
	TEST_ASSERT_EQUAL(H.name, "target", "copy_name copies the name")

/// P2-F2: examine reads a visible infection from the glance diagnosis, not the organ's germ level.
/datum/unit_test/dq_k_c_f2_examine_infection_from_diagnosis

/datum/unit_test/dq_k_c_f2_examine_infection_from_diagnosis/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.germ_level = INFECTION_LEVEL_THREE
	TEST_ASSERT(!findtext(jointext(H.examine_diagnosis_lines(), ""), "looks very infected"), "germs alone, with no infection affliction, don't show on examine")
	arm.germ_level = 0
	H.body.afflict(/datum/affliction/wound_infection, arm, 80)
	TEST_ASSERT(findtext(jointext(H.examine_diagnosis_lines(), ""), "looks very infected"), "a severe wound infection shows on examine through the diagnosis")
