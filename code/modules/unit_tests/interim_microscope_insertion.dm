/// A real forensic swab is released from its hand and physically inserted with the microscope's relation intact.
/datum/unit_test/interim_microscope_sample_insert/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/microscope/microscope = allocate(/obj/machinery/microscope, T)
	var/obj/item/forensics/swab/swab = allocate(/obj/item/forensics/swab, T)
	TEST_ASSERT(user.put_in_active_hand(swab), "the real forensic sample is held")
	TEST_ASSERT_EQUAL(test_op_handler(microscope, "interaction_attackby", user, swab), OP_OK, "actual sample insertion succeeds")
	TEST_ASSERT_EQUAL(microscope.sample(), swab, "the microscope views the actual installed sample")
	TEST_ASSERT_EQUAL(swab.loc, microscope, "the actual sample is physically inside the microscope")
	TEST_ASSERT_NULL(user.get_active_hand(), "insertion correctly vacates the sample's hand")
	TEST_ASSERT(!QDELETED(swab), "insertion preserves the actual forensic sample")

/// A sticky forensic swab is rejected without changing the microscope or its actual holder.
/datum/unit_test/interim_microscope_sample_sticky_refusal/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/microscope/microscope = allocate(/obj/machinery/microscope, T)
	var/obj/item/forensics/swab/swab = allocate(/obj/item/forensics/swab, T)
	TEST_ASSERT(user.put_in_active_hand(swab), "the real forensic sample is held")
	add_trait(swab, TRAIT_NODROP, "interim_microscope_sample")
	TEST_ASSERT(swab.loc.release_refusal(swab, user), "the actual sticky sample refuses release")
	TEST_ASSERT(microscope.can_insert_sample(user, microscope, swab) != TRUE, "the interaction requirement rejects the sticky sample")
	TEST_ASSERT_EQUAL(test_op_handler(microscope, "interaction_attackby", user, swab), OP_DECLINE, "the actual callback respects sample refusal")
	TEST_ASSERT_NULL(microscope.sample(), "refusal leaves the microscope's sample view empty")
	TEST_ASSERT_NULL(locate_within(microscope, /obj/item/forensics/swab), "refusal puts no swab inside the microscope")
	TEST_ASSERT_EQUAL(swab.loc, user, "refusal leaves the actual sample on its holder")
	TEST_ASSERT_EQUAL(user.get_active_hand(), swab, "refusal preserves the sample's original hand")
	remove_trait(swab, TRAIT_NODROP, "interim_microscope_sample")
