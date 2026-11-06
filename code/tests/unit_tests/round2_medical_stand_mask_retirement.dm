/// Actual periodic stand mask replacement; no prompt, gas-transfer, or observer-phase claim.
/datum/unit_test/round2_medical_stand_mask_retirement/Run()
	var/turf/surface = test_floor()
	var/obj/structure/medical_stand/stand = allocate(/obj/structure/medical_stand, surface)
	var/obj/structure/medical_stand/control = allocate(/obj/structure/medical_stand, surface)
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, surface)
	patient.enable_godmode()
	var/obj/item/clothing/mask/breath/original = stand.contained
	var/obj/item/clothing/mask/breath/control_mask = control.contained
	TEST_ASSERT(istype(original) && istype(control_mask), "Real stand constructors materialize their medical masks")
	TEST_ASSERT_EQUAL(owner_of(original), stand, "Original mask is actually owned by its stand")
	TEST_ASSERT_EQUAL(original.loc, stand, "Original mask starts physically inside the real stand")
	TEST_ASSERT_NULL(patient.get_equipped_item(SLOT_ID_MASK), "Real patient begins without the supplied mask")
	rel_set(stand, nameof(stand.breather), patient)
	TEST_ASSERT_EQUAL(stand.breather(), patient, "Actual breather relation records the patient")
	test_op_handler(stand, "medical_stand_step", null) // the stand's every() step
	TEST_ASSERT(QDELETED(original), "Actual periodic invalid-patient branch retires the original owned mask")
	var/obj/item/clothing/mask/breath/replacement = stand.contained
	TEST_ASSERT(istype(replacement) && replacement != original && !QDELETED(replacement), "Actual replacement is a distinct live medical mask")
	TEST_ASSERT_EQUAL(owner_of(replacement), stand, "Replacement is adopted by the original stand")
	TEST_ASSERT_EQUAL(replacement.loc, stand, "Replacement remains physically in the stand")
	TEST_ASSERT_NULL(stand.breather(), "Actual cleanup clears the patient relation")
	TEST_ASSERT_EQUAL(control.contained, control_mask, "Independent stand keeps its exact mask")
	TEST_ASSERT(!QDELETED(control_mask), "Independent mask remains alive")
	TEST_ASSERT_EQUAL(owner_of(control_mask), control, "Independent mask keeps its owner")
