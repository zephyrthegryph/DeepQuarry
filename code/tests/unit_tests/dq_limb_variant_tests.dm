// A species' has_limbs row names a plain limb type and a variant row; the limb it builds carries the row's values.

/datum/unit_test/dq_limb_variant_rows

/datum/unit_test/dq_limb_variant_rows/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(SPECIES_PROTEAN)
	var/obj/item/organ/external/arm/arm = H.organs_by_name[BP_L_ARM]
	TEST_ASSERT(arm, "protean has a left arm")
	TEST_ASSERT_EQUAL(arm.type, /obj/item/organ/external/arm, "the limb is the plain type")
	TEST_ASSERT_EQUAL(arm.variant, LIMB_VARIANT_NANO_LIMB, "it keeps its variant key")
	TEST_ASSERT_EQUAL(arm.robotic, ORGAN_NANOFORM, "the row made it nanite")
	TEST_ASSERT_EQUAL(arm.max_damage, 40, "the row sets its health")
	TEST_ASSERT(arm.cannot_break, "the row makes it unbreakable")
	var/obj/item/organ/external/chest/chest = H.organs_by_name[BP_TORSO]
	TEST_ASSERT_EQUAL(chest.max_damage, 70, "a chest row differs from a limb row")
	var/obj/item/organ/external/head/head = H.organs_by_name[BP_HEAD]
	TEST_ASSERT(head.cannot_disfigure, "the nano head cannot be disfigured")

	H.set_species(SPECIES_XENO)
	var/obj/item/organ/external/head/xhead = H.organs_by_name[BP_HEAD]
	TEST_ASSERT_EQUAL(xhead.eye_icon, "blank_eyes", "the xeno head row sets its eyes")
	TEST_ASSERT(xhead.cannot_amputate, "xeno limbs cannot be amputated")
