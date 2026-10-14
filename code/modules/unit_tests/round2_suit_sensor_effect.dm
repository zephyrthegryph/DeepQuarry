/// Actual data effect and pure policy states; excludes request/window/permission coverage.
/datum/unit_test/round2_suit_sensor_effect/Run()
	test_driver_begin()
	exercise_sensor_state()
	test_driver_end()

/datum/unit_test/round2_suit_sensor_effect/proc/exercise_sensor_state()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	user.enable_godmode()
	var/obj/item/clothing/under/color/grey/suit = allocate(/obj/item/clothing/under/color/grey)
	var/obj/item/clothing/under/color/grey/control = allocate(/obj/item/clothing/under/color/grey)
	suit.has_sensor = 1
	TEST_ASSERT(user.equip_to_slot_if_possible(suit, SLOT_ID_UNIFORM, disable_warning = TRUE), "real uniform equips on actual human")
	TEST_ASSERT(!user.stat && !user.restrained(), "real initial actor is conscious and unrestrained")
	TEST_ASSERT(isnull(suit.sensor_mode_refusal(user, TRUE)), "ordinary equipped sensor controls allow current actor")
	var/original_control_mode = control.sensor_mode
	for(var/mode in list(SUIT_SENSOR_OFF, SUIT_SENSOR_BINARY, SUIT_SENSOR_VITAL, SUIT_SENSOR_TRACKING))
		suit.apply_sensor_mode(user, mode)
		TEST_ASSERT_EQUAL(suit.sensor_mode, mode, "actual mode effect writes each real sensor mode")
		TEST_ASSERT_EQUAL(control.sensor_mode, original_control_mode, "independent uniform remains unchanged")
	suit.has_sensor = 2
	TEST_ASSERT(!isnull(suit.sensor_mode_refusal(user, FALSE)), "current locked controls refuse")
	suit.has_sensor = 0
	TEST_ASSERT(!isnull(suit.sensor_mode_refusal(user, FALSE)), "current absent sensors refuse")
	suit.has_sensor = 1
	var/obj/item/handcuffs/cuffs = allocate(/obj/item/handcuffs)
	TEST_ASSERT(user.equip_to_slot(cuffs, SLOT_ID_HANDCUFFED), "actual cuffs occupy real handcuff slot")
	TEST_ASSERT(user.restrained(), "actual equipped cuffs restrain the human")
	TEST_ASSERT(!isnull(suit.sensor_mode_refusal(user, FALSE)), "actual restraint refuses current controls")
	TEST_ASSERT(user.unEquip(cuffs), "actual cuff release restores actor")
	TEST_ASSERT(!user.restrained(), "actual released actor is unrestrained")
	var/turf/origin = get_turf(user)
	TEST_ASSERT(user.unEquip(suit), "actual uniform release permits floor distance case")
	var/turf/far = locate(origin.x + 2, origin.y, origin.z)
	TEST_ASSERT(far, "actual world has distinct far destination")
	user.forceMove(far)
	TEST_ASSERT(get_dist(user, suit) > 1, "actual actor is beyond original distance threshold")
	TEST_ASSERT(isnull(suit.sensor_mode_refusal(user, FALSE)), "initial opening policy intentionally permits far actor")
	TEST_ASSERT(!isnull(suit.sensor_mode_refusal(user, TRUE)), "accepted-answer policy rejects actual late distance")
