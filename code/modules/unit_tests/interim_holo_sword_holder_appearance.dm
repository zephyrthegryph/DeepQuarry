/// Counts observe real human inventory redraws and still chain their real implementations.
/mob/living/carbon/human/interim_holo_sword_holder
	var/left_redraws = 0
	var/right_redraws = 0

/mob/living/carbon/human/interim_holo_sword_holder/update_inv_l_hand()
	left_redraws++
	return ..()

/mob/living/carbon/human/interim_holo_sword_holder/update_inv_r_hand()
	right_redraws++
	return ..()

/// A synthetic native click supplies ambient usr while observing the real appearance output.
/obj/item/holo/esword/interim_holder_appearance
	var/list/observed_overlays

/obj/item/holo/esword/interim_holder_appearance/Click(location, control, params)
	observed_overlays = appearance_overlays()

/datum/unit_test/interim_holo_sword_holder_appearance/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/interim_holo_sword_holder/holder = allocate(/mob/living/carbon/human/interim_holo_sword_holder, T)
	var/mob/living/carbon/human/interim_holo_sword_holder/bystander = allocate(/mob/living/carbon/human/interim_holo_sword_holder, T)
	var/obj/item/holo/esword/interim_holder_appearance/sword = allocate(/obj/item/holo/esword/interim_holder_appearance, T)
	TEST_ASSERT(holder.put_in_active_hand(sword), "the actual holographic sword occupies its holder's hand")
	km_synthetic_click(bystander, sword)
	var/inherited_count = length(sword.observed_overlays)
	var/inactive_blades = 0
	for(var/mutable_appearance/entry as anything in sword.observed_overlays)
		if(entry && entry.icon_state == "esword_blade")
			inactive_blades++
	TEST_ASSERT_EQUAL(inactive_blades, 0, "the actual initial inactive appearance contains no blade")
	test_op_handler(sword, "interaction_self", holder, sword)
	TEST_ASSERT(sword.active, "the actual sword interaction extends its blade")
	TEST_ASSERT_EQUAL(sword.force, 30, "actual holo activation applies its configured active force")
	TEST_ASSERT_EQUAL(sword.w_class, ITEMSIZE_LARGE, "actual holo activation enlarges its real blade")
	TEST_ASSERT_EQUAL(sword.item_state, "esword_blade", "the actual extended blade has its held item state")
	holder.left_redraws = 0
	holder.right_redraws = 0
	bystander.left_redraws = 0
	bystander.right_redraws = 0
	km_synthetic_click(bystander, sword)
	TEST_ASSERT(holder.left_redraws > 0 && holder.right_redraws > 0, "real appearance generation redraws the actual holder's hands")
	TEST_ASSERT_EQUAL(bystander.left_redraws, 0, "appearance generation does not redraw the ambient caller's left hand")
	TEST_ASSERT_EQUAL(bystander.right_redraws, 0, "appearance generation does not redraw the ambient caller's right hand")
	TEST_ASSERT_EQUAL(length(sword.observed_overlays), inherited_count + 1, "the real extended sword adds exactly one overlay to its inherited appearance")
	var/active_blades = 0
	for(var/mutable_appearance/entry as anything in sword.observed_overlays)
		if(entry && entry.icon_state == "esword_blade")
			active_blades++
	TEST_ASSERT_EQUAL(active_blades, 1, "the actual extended appearance contains exactly one blade overlay")
	TEST_ASSERT_EQUAL(holder.get_active_hand(), sword, "appearance generation preserves actual held ownership")
	test_op_handler(sword, "interaction_self", holder, sword)
	TEST_ASSERT(!sword.active, "the actual sword interaction retracts its blade")
	TEST_ASSERT_EQUAL(sword.force, 3, "actual holo retraction restores its force")
	TEST_ASSERT_EQUAL(sword.w_class, ITEMSIZE_SMALL, "actual holo retraction restores its concealable size")
	TEST_ASSERT_EQUAL(sword.item_state, "esword", "the actual retracted sword restores its held item state")
	km_synthetic_click(bystander, sword)
	TEST_ASSERT_EQUAL(length(sword.observed_overlays), inherited_count, "retracting the actual blade restores its inherited appearance count")
	var/retracted_blades = 0
	for(var/mutable_appearance/entry as anything in sword.observed_overlays)
		if(entry && entry.icon_state == "esword_blade")
			retracted_blades++
	TEST_ASSERT_EQUAL(retracted_blades, 0, "the actual retracted appearance contains no blade overlay")
	TEST_ASSERT(holder.unEquip(sword), "the actual holder releases the sword to the floor")
	holder.left_redraws = 0
	holder.right_redraws = 0
	km_synthetic_click(bystander, sword)
	TEST_ASSERT_EQUAL(holder.left_redraws, 0, "an unheld holographic sword does not redraw its former holder")
	TEST_ASSERT_EQUAL(holder.right_redraws, 0, "an unheld holographic sword leaves its former holder's right hand untouched")
	TEST_ASSERT_EQUAL(bystander.left_redraws, 0, "an unheld holographic sword never redraws an unrelated ambient caller")
	TEST_ASSERT_EQUAL(bystander.right_redraws, 0, "an unheld holographic sword leaves the unrelated caller's right hand untouched")
