/// Record the actual rename callback's final interaction actor without opening a client UI.
/obj/item/areaeditor/blueprints/interim_actor_probe
	var/mob/last_actor

/obj/item/areaeditor/blueprints/interim_actor_probe/interact(mob/user)
	rel_set(src, nameof(last_actor), user)

/// A separate type keeps the real test room's area lookup intact.
/area/interim_blueprint_actor
	requires_power = FALSE

/datum/unit_test/interim_blueprint_actor/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = run_loc_floor_bottom_left
	var/area/original_room = get_area(T)
	var/area/original_lookup = GLOB.areas_by_type[original_room.type]
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/areaeditor/blueprints/interim_actor_probe/blueprint = allocate(/obj/item/areaeditor/blueprints/interim_actor_probe, T)
	// allocate() substitutes the test floor even for an explicit null location.
	var/area/interim_blueprint_actor/isolated = new /area/interim_blueprint_actor()
	own(isolated)
	TEST_ASSERT_EQUAL(get_area(T), original_room, "creating the private area preserves the test floor's room")
	TEST_ASSERT_EQUAL(length(get_area_turfs(isolated.type)), 0, "the private area owns no map turfs")
	isolated.outdoors = TRUE
	TEST_ASSERT_EQUAL(blueprint.get_area_type(isolated), AREA_SPACE, "an explicit outdoor area is unclaimed")
	TEST_ASSERT_EQUAL(get_new_area_type(isolated), 1, "an explicit outdoor area allows creation")
	isolated.outdoors = FALSE
	TEST_ASSERT_EQUAL(blueprint.get_area_type(isolated), AREA_STATION, "an explicit ordinary indoor area is a station area")
	TEST_ASSERT_EQUAL(get_new_area_type(isolated), 0, "an ordinary indoor area does not allow new-area creation")
	TEST_ASSERT_EQUAL(blueprint.get_area_type(null), 0, "missing areas have no editing classification")
	TEST_ASSERT_EQUAL(get_new_area_type(null), 0, "missing areas do not allow creation")
	var/page = blueprint.areaeditor_text(user)
	TEST_ASSERT(length(page), "the actor can generate the actual editing page without an ambient caller")
	TEST_ASSERT(findtext(page, "create_area=1"), "the actor's editing page offers the actual creation action")
	TEST_ASSERT(user.put_in_r_hand(blueprint), "the actor holds the real blueprint for its rename request")
	var/renamed = "Interim blueprint renamed area"
	open_request(blueprint, /datum/prompt/text/blueprint_rename_area, TYPE_PROC_REF(/obj/item/areaeditor, area_renamed), answerer = user, area_to_rename = isolated)
	TEST_ASSERT(!isnull(SSrequests.open_for(user)), "the real rename request opens")
	test_answer(user, renamed)
	TEST_ASSERT_EQUAL(isolated.name, renamed, "the callback changes the actual area name")
	TEST_ASSERT_EQUAL(blueprint.last_actor, user, "the callback refreshes the explicit actor's interaction")
	qdel(isolated)
	TEST_ASSERT(!QDELETED(original_room), "deleting the private area preserves the actual test room")
	TEST_ASSERT_EQUAL(get_area(T), original_room, "deleting the private area preserves the test floor's room")
	TEST_ASSERT_EQUAL(GLOB.areas_by_type[original_room.type], original_lookup, "the real room's type lookup retains its original identity")
