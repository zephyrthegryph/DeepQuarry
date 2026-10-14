/// Actual turret-control emagging removes both interface locks without changing its targeting policy, spends one real card use, and leaves the subverted panel impossible to relock with an authorized ID.
/datum/unit_test/interim_turret_controller_emag_locks/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/turretid/controller = allocate(/obj/machinery/turretid, T)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, T)
	var/obj/item/card/id/id = allocate(/obj/item/card/id, T)
	card.uses = 3
	id.access = list(ACCESS_AI_UPLOAD)
	controller.set_ailock(TRUE)
	var/area_before = controller.control_area
	var/list/access_before = controller.req_access
	var/enabled_before = controller.enabled
	var/lethal_before = controller.lethal
	var/weapons_before = controller.check_weapons
	var/all_before = controller.check_all
	TEST_ASSERT(lock_locked(controller), "the actual turret interface starts locked for the actual human")
	TEST_ASSERT(!emag_emagged(controller), "the actual controller starts unsubverted")
	TEST_ASSERT(user.put_in_active_hand(card), "the actual actor holds its charged emag")
	TEST_ASSERT(op_known_anywhere(user, controller, card, "emag.use"), "the actual turret controller exposes its declared emag op")
	TEST_ASSERT(test_op_committed(perform_op(user, controller, "emag.use", card)), "the actual declared emag op subverts the turret controller")
	TEST_ASSERT_EQUAL(card.uses, 2, "the actual accepted emag spends exactly one card use")
	TEST_ASSERT(emag_emagged(controller) && !lock_locked(controller) && !controller.ailock, "actual emagging subverts and clears both human and silicon locks")
	TEST_ASSERT_EQUAL(controller.control_area, area_before, "actual subversion preserves the controlled area identity")
	TEST_ASSERT_EQUAL(controller.req_access, access_before, "actual subversion preserves its configured access-list identity")
	TEST_ASSERT_EQUAL(controller.enabled, enabled_before, "actual subversion does not itself enable the turret network")
	TEST_ASSERT_EQUAL(controller.lethal, lethal_before, "actual subversion does not itself change lethality")
	TEST_ASSERT_EQUAL(controller.check_weapons, weapons_before, "actual subversion preserves weapon targeting policy")
	TEST_ASSERT_EQUAL(controller.check_all, all_before, "actual subversion preserves indiscriminate targeting policy")
	TEST_ASSERT(!test_op_committed(perform_op(user, controller, "emag.use", card)), "a subverted controller refuses a repeat emag")
	TEST_ASSERT_EQUAL(card.uses, 2, "actual repeat refusal spends no additional card use")
	TEST_ASSERT(user.drop_from_inventory(card), "the actual actor releases its emag before using an ID")
	TEST_ASSERT(user.put_in_active_hand(id), "the actual actor holds an authorized ID")
	TEST_ASSERT(controller.allowed(user), "the actual held ID satisfies the controller's access configuration")
	perform_op(user, controller, "lock.toggle", id)
	TEST_ASSERT(!lock_locked(controller), "actual authorized ID toggling cannot relock a subverted panel")
	TEST_ASSERT_EQUAL(user.get_active_hand(), id, "actual refused relocking preserves the actor's ID")
	TEST_ASSERT_EQUAL(card.uses, 2, "actual refused relocking cannot consume another emag use")
