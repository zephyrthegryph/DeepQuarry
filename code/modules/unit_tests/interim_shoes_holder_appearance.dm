/// Observation chains the real wearer shoe redraw implementation.
/mob/living/carbon/human/interim_shoe_appearance_holder
	var/shoe_redraws = 0

/mob/living/carbon/human/interim_shoe_appearance_holder/update_inv_shoes()
	shoe_redraws++
	return ..()

/obj/item/clothing/shoes/boots/jackboots/interim_holder_appearance
	var/list/observed_overlays

/// Runs the queued draws (the presentation lane) and records the icon states of the overlays the boots show now.
/obj/item/clothing/shoes/boots/jackboots/interim_holder_appearance/proc/observe_look()
	appearance_flush()
	observed_overlays = list()
	for(var/mutable_appearance/entry as anything in overlays)
		observed_overlays += entry.icon_state

/datum/unit_test/interim_shoes_holder_appearance/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/interim_shoe_appearance_holder/wearer = allocate(/mob/living/carbon/human/interim_shoe_appearance_holder, T)
	var/mob/living/carbon/human/interim_shoe_appearance_holder/bystander = allocate(/mob/living/carbon/human/interim_shoe_appearance_holder, T)
	var/obj/item/clothing/shoes/boots/jackboots/interim_holder_appearance/boots = allocate(/obj/item/clothing/shoes/boots/jackboots/interim_holder_appearance, T)
	TEST_ASSERT(move_into(wearer, SLOT_ID_SHOES, boots), "the actual wearer equips its real jackboots")
	var/obj/item/material/knife/tacknife/knife = allocate(/obj/item/material/knife/tacknife, T)
	TEST_ASSERT(wearer.put_in_active_hand(knife), "the actual wearer holds a compatible boot knife")
	wearer.shoe_redraws = 0
	bystander.shoe_redraws = 0
	test_op_handler(boots, "shoes_stuff_item", wearer, knife)
	TEST_ASSERT_EQUAL(boots.holding, knife, "the real insertion stores the exact supplied knife in the boots")
	TEST_ASSERT_EQUAL(knife.loc, boots, "real insertion moves the knife into the boot contents")
	TEST_ASSERT_NULL(wearer.get_active_hand(), "real insertion releases the knife's original hand")
	boots.observe_look()
	TEST_ASSERT(wearer.shoe_redraws > 0, "actual boot appearance generation redraws the real wearer's shoe layer")
	TEST_ASSERT_EQUAL(bystander.shoe_redraws, 0, "actual appearance generation does not redraw the unrelated ambient caller")
	TEST_ASSERT("jackboots_knife" in boots.observed_overlays, "the actual appearance retains its inserted knife overlay")
	TEST_ASSERT_EQUAL(wearer.get_equipped_item(SLOT_ID_SHOES), boots, "appearance generation preserves actual equipped boot ownership")
	boots.draw_knife(wearer)
	TEST_ASSERT_NULL(boots.holding, "real knife removal clears the boot storage link")
	TEST_ASSERT_EQUAL(wearer.get_active_hand(), knife, "real removal returns the exact knife to the wearer's hand")
	boots.observe_look()
	TEST_ASSERT(!("jackboots_knife" in boots.observed_overlays), "actual knife removal clears the appearance overlay")
	TEST_ASSERT(wearer.unEquip(boots), "the actual wearer releases the boots to the floor")
	wearer.shoe_redraws = 0
	boots.observe_look()
	TEST_ASSERT_EQUAL(wearer.shoe_redraws, 0, "floor boot appearance does not redraw the former wearer")
	TEST_ASSERT_EQUAL(bystander.shoe_redraws, 0, "floor boot appearance does not redraw the unrelated caller")
