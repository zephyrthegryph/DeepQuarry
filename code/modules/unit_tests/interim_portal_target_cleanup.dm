/// A targetless portal cleans up through its real entry, preserving exclusion ordering.
/datum/unit_test/interim_portal_target_cleanup
	var/delete_target = FALSE

/datum/unit_test/interim_portal_target_cleanup/deleted_target
	delete_target = TRUE

/datum/unit_test/interim_portal_target_cleanup/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/effect/portal/portal = allocate(/obj/effect/portal, T)
	var/obj/effect/excluded = allocate(/obj/effect, T)
	TEST_ASSERT(!QDELETED(portal), "actual portal initializes alive")
	TEST_ASSERT((portal in REGISTRY_MEMBERS(REGISTRY_PORTALS)), "actual portal joins its registry")
	TEST_ASSERT(time_scheduler().timer_count(portal) > 0, "actual portal initialization schedules expiration")
	if(delete_target)
		var/obj/item/pen/target = allocate(/obj/item/pen, T)
		rel_set(portal, nameof(portal.target), target)
		TEST_ASSERT_EQUAL(portal.target_ref(), target, "actual portal resolves its real linked destination")
		TEST_ASSERT(consume(target), "actual destination item is consumed")
		TEST_ASSERT(QDELETED(target), "actual linked destination is deleted")
		TEST_ASSERT_NULL(portal.target_ref(), "actual deletion clears the destination relation")
		TEST_ASSERT(!QDELETED(portal), "destination deletion preserves portal until its next real entry")
	else
		TEST_ASSERT_NULL(portal.target_ref(), "actual unlinked portal has no destination")
	portal.teleport(excluded)
	TEST_ASSERT(!QDELETED(portal) && !QDELETED(excluded), "actual effect exclusion precedes targetless cleanup")
	TEST_ASSERT_EQUAL(excluded.loc, T, "actual excluded effect retains its floor")
	portal.icon_state = "portal1"
	TEST_ASSERT_EQUAL(test_op_handler(portal, "interaction_enter_portal", user, null), TRUE, "actual disabled portal entry is handled")
	TEST_ASSERT(!QDELETED(portal), "actual disabled state prevents targetless cleanup")
	TEST_ASSERT_EQUAL(user.loc, T, "actual disabled entry preserves its actor floor")
	portal.icon_state = initial(portal.icon_state)
	TEST_ASSERT_EQUAL(test_op_handler(portal, "interaction_enter_portal", user, null), TRUE, "actual targetless living entry is handled")
	TEST_ASSERT(QDELETED(portal), "actual living entry consumes a targetless portal")
	TEST_ASSERT(!(portal in REGISTRY_MEMBERS(REGISTRY_PORTALS)), "actual portal cleanup removes its registry membership")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(portal), 0, "actual portal cleanup cancels its expiration timer")
	TEST_ASSERT(!QDELETED(user), "targetless portal cleanup preserves the entering actor")
	TEST_ASSERT_EQUAL(user.loc, T, "targetless cleanup leaves its actor on the original floor")
	TEST_ASSERT(!QDELETED(excluded), "targetless cleanup preserves the excluded effect")
