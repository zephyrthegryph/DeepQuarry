/// Counts observe real human inventory redraws and still chain their real implementations.
/mob/living/carbon/human/interim_toy_sword_holder
	var/left_redraws = 0
	var/right_redraws = 0

/mob/living/carbon/human/interim_toy_sword_holder/update_inv_l_hand()
	left_redraws++
	return ..()

/mob/living/carbon/human/interim_toy_sword_holder/update_inv_r_hand()
	right_redraws++
	return ..()

/// Counts of the toy sword's blade overlays on the real, drawn sword.
/proc/interim_toy_sword_blades(obj/item/toy/sword/sword)
	var/blades = 0
	for(var/entry in sword.overlays)
		var/image/overlay_image = entry
		if(overlay_image?.icon_state == "esword_blade")
			blades++
	return blades

/datum/unit_test/interim_toy_sword_holder_appearance/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/interim_toy_sword_holder/holder = allocate(/mob/living/carbon/human/interim_toy_sword_holder, T)
	var/mob/living/carbon/human/interim_toy_sword_holder/bystander = allocate(/mob/living/carbon/human/interim_toy_sword_holder, T)
	var/obj/item/toy/sword/sword = allocate(/obj/item/toy/sword, T)
	TEST_ASSERT(holder.put_in_active_hand(sword), "the actual toy sword occupies its holder's hand")
	sword.update_icon()
	test_time(2 SECONDS)
	var/inherited_count = length(sword.overlays)
	TEST_ASSERT_EQUAL(interim_toy_sword_blades(sword), 0, "the actual initial inactive appearance contains no blade")
	holder.left_redraws = 0
	holder.right_redraws = 0
	bystander.left_redraws = 0
	bystander.right_redraws = 0
	test_op_handler(sword, "toggled", holder, sword)
	TEST_ASSERT(sword.active, "the actual toy interaction extends its blade")
	TEST_ASSERT_EQUAL(sword.item_state, "esword_blade", "the actual extended blade has its held item state")
	TEST_ASSERT(holder.left_redraws > 0 && holder.right_redraws > 0, "extending the blade redraws the actual holder's hands")
	TEST_ASSERT_EQUAL(bystander.left_redraws, 0, "the blade does not redraw the bystander's left hand")
	TEST_ASSERT_EQUAL(bystander.right_redraws, 0, "the blade does not redraw the bystander's right hand")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(length(sword.overlays), inherited_count + 1, "the real extended sword adds exactly one overlay to its inherited appearance")
	TEST_ASSERT_EQUAL(interim_toy_sword_blades(sword), 1, "the actual extended appearance contains exactly one blade overlay")
	TEST_ASSERT_EQUAL(holder.get_active_hand(), sword, "appearance generation preserves actual held ownership")
	test_op_handler(sword, "toggled", holder, sword)
	TEST_ASSERT(!sword.active, "the actual toy interaction retracts its blade")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(length(sword.overlays), inherited_count, "retracting the actual blade restores its inherited appearance count")
	TEST_ASSERT_EQUAL(interim_toy_sword_blades(sword), 0, "the actual retracted appearance contains no blade overlay")
	TEST_ASSERT(holder.unEquip(sword), "the actual holder releases the sword to the floor")
	holder.left_redraws = 0
	holder.right_redraws = 0
	bystander.left_redraws = 0
	bystander.right_redraws = 0
	test_op_handler(sword, "toggled", bystander, sword)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(holder.left_redraws, 0, "an unheld toy sword does not redraw its former holder")
	TEST_ASSERT_EQUAL(holder.right_redraws, 0, "an unheld toy sword leaves its former holder's right hand untouched")
	TEST_ASSERT_EQUAL(bystander.left_redraws, 0, "an unheld toy sword never redraws an unrelated ambient caller")
	TEST_ASSERT_EQUAL(bystander.right_redraws, 0, "an unheld toy sword leaves the unrelated caller's right hand untouched")
	test_driver_end()
