/// A real default-child implant exercises completion and ownership transfer.
/obj/item/implanter/interim_sizecontrol_actor
DECLARE_DEFAULT_CHILD(/obj/item/implanter/interim_sizecontrol_actor, "imp", /obj/item/implant/sizecontrol)

/datum/unit_test/interim_implant_installer_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/installer = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, T)
	var/obj/item/implanter/interim_sizecontrol_actor/device = allocate(/obj/item/implanter/interim_sizecontrol_actor, T)
	var/obj/item/implant/sizecontrol/implant = device.imp
	TEST_ASSERT(istype(implant), "the real implanter starts loaded with its owned implant")
	TEST_ASSERT(installer.put_in_active_hand(device), "the installer holds the loaded device")
	TEST_ASSERT_EQUAL(device.attack(patient, installer, BP_TORSO, null), ITEM_INTERACT_SUCCESS, "the actual implant attack begins")
	TEST_ASSERT_EQUAL(device.imp, implant, "the device remains loaded before the timed completion")
	TEST_ASSERT_NULL(implant.imp_in(), "the implant is not installed before completion")
	test_time(6 SECONDS)
	TEST_ASSERT_NULL(device.imp, "completion releases the implant from its device")
	TEST_ASSERT_EQUAL(implant.imp_in(), patient, "completion installs the same real implant into the patient")
	TEST_ASSERT_EQUAL(implant.owner, installer, "completion records the explicit installer without ambient usr")
	qdel(installer)
	TEST_ASSERT_NULL(implant.owner, "deleting the installer clears the owner relation")
	TEST_ASSERT_EQUAL(implant.imp_in(), patient, "owner deletion leaves the patient's implant installed")

/datum/unit_test/interim_implant_self_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, T)
	var/obj/item/implanter/interim_sizecontrol_actor/device = allocate(/obj/item/implanter/interim_sizecontrol_actor, T)
	var/obj/item/implant/sizecontrol/implant = device.imp
	TEST_ASSERT(istype(implant), "the self-implant fixture has a real implant")
	TEST_ASSERT(patient.put_in_active_hand(device), "the patient holds the loaded device")
	TEST_ASSERT_EQUAL(device.attack(patient, patient, BP_TORSO, null), ITEM_INTERACT_SUCCESS, "the real self-implant attack runs")
	test_time(1 SECOND)
	TEST_ASSERT_NULL(device.imp, "self-implant completion empties the device")
	TEST_ASSERT_EQUAL(implant.imp_in(), patient, "self-implant physically installs the same implant")
	TEST_ASSERT_NULL(implant.owner, "self-implant preserves the existing absence of an external owner")
