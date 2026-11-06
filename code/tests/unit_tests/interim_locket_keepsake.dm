/// Inserting an actual inactive-hand keepsake releases only that ingredient and updates the locket's view.
/datum/unit_test/interim_locket_keepsake_insert/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/accessory/locket/locket = allocate(/obj/item/clothing/accessory/locket, T)
	locket.open = TRUE
	var/obj/item/paper/paper = allocate(/obj/item/paper, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(user.put_in_active_hand(pen), "the unrelated pen occupies the active hand")
	TEST_ASSERT(user.put_in_inactive_hand(paper), "the actual keepsake occupies the inactive hand")
	test_op_handler(locket, "locket_insert_item", user, paper)
	TEST_ASSERT_EQUAL(paper.loc, locket, "the actual paper is physically inside the locket")
	TEST_ASSERT_EQUAL(locket.held(), paper, "the locket views the actual installed paper")
	TEST_ASSERT_NULL(user.get_inactive_hand(), "insertion correctly vacates the keepsake's hand")
	TEST_ASSERT_EQUAL(user.get_active_hand(), pen, "insertion preserves the unrelated active pen")
	TEST_ASSERT(!QDELETED(paper), "insertion preserves the actual paper")

/// Sticky keepsakes refuse insertion before any hand or locket state changes.
/datum/unit_test/interim_locket_keepsake_sticky_refusal/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/accessory/locket/locket = allocate(/obj/item/clothing/accessory/locket, T)
	locket.open = TRUE
	var/obj/item/paper/paper = allocate(/obj/item/paper, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(user.put_in_active_hand(pen), "the unrelated pen occupies the active hand")
	TEST_ASSERT(user.put_in_inactive_hand(paper), "the actual keepsake occupies the inactive hand")
	add_trait(paper, TRAIT_NODROP, "interim_locket_keepsake")
	TEST_ASSERT(paper.loc.release_refusal(paper, user), "the actual sticky paper refuses release")
	TEST_ASSERT(locket.can_insert_keepsake(user, locket, paper) != TRUE, "the insertion requirement rejects the sticky paper")
	test_op_handler(locket, "locket_insert_item", user, paper)
	TEST_ASSERT_NULL(locket.held(), "refusal leaves the locket without a keepsake")
	TEST_ASSERT_NULL(locate_within(locket, /obj/item/paper), "refusal puts no paper inside the locket")
	TEST_ASSERT_EQUAL(user.get_inactive_hand(), paper, "refusal preserves the keepsake's original hand")
	TEST_ASSERT_EQUAL(paper.loc, user, "refusal preserves the actual paper on its holder")
	TEST_ASSERT_EQUAL(user.get_active_hand(), pen, "refusal preserves the unrelated active item")
	remove_trait(paper, TRAIT_NODROP, "interim_locket_keepsake")
