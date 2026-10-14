/// An accessory's on-mob draw is pure: it writes no state, and stays correct across attach, detach and a different wearer.
/datum/unit_test/dq_accessory_draw_purity

/datum/unit_test/dq_accessory_draw_purity/proc/pure_draw(obj/item/clothing/accessory/A)
	var/before = length(GLOB.op_pure_violations)
	op_pure_begin()
	var/image/result = A.get_mob_overlay()
	op_pure_end()
	TEST_ASSERT_EQUAL(length(GLOB.op_pure_violations), before, "drawing [A] reported a purity violation")
	return result

/datum/unit_test/dq_accessory_draw_purity/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/under/color/black/U = allocate(/obj/item/clothing/under/color/black, T)
	var/obj/item/clothing/accessory/medal/conduct/M = allocate(/obj/item/clothing/accessory/medal/conduct, T)
	U.attach_accessory(null, M)
	TEST_ASSERT_NULL(pure_draw(M), "an accessory on an unworn uniform draws nothing")
	TEST_ASSERT(first.equip_to_slot_if_possible(U, SLOT_ID_UNIFORM, disable_warning = TRUE), "the first wearer equips the uniform")
	var/image/worn = pure_draw(M)
	TEST_ASSERT(istype(worn), "the accessory draws on the first wearer")
	TEST_ASSERT_EQUAL(worn.icon_state, M.icon_state, "the drawn state is the accessory's own")
	TEST_ASSERT(first.drop_from_inventory(U), "the uniform comes off the first wearer")
	TEST_ASSERT_NULL(pure_draw(M), "the dropped accessory draws nothing")
	TEST_ASSERT(second.equip_to_slot_if_possible(U, SLOT_ID_UNIFORM, disable_warning = TRUE), "the second wearer equips the uniform")
	TEST_ASSERT(istype(pure_draw(M)), "the accessory draws on the second wearer")
	U.remove_accessory(null, M)
	TEST_ASSERT_NULL(pure_draw(M), "a detached accessory draws nothing")
	U.attach_accessory(null, M)
	TEST_ASSERT(istype(pure_draw(M)), "the reattached accessory draws on the second wearer")
