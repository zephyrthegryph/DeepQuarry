/// Record the actual rename callback's final interaction actor without opening a client UI.
/obj/item/areaeditor/blueprints/interim_actor_probe
	var/mob/last_actor

/obj/item/areaeditor/blueprints/interim_actor_probe/interact(mob/user)
	rel_set(src, nameof(last_actor), user)

/datum/unit_test/interim_blueprint_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/areaeditor/blueprints/interim_actor_probe/blueprint = allocate(/obj/item/areaeditor/blueprints/interim_actor_probe, T)
	var/area/unit_test/isolated = allocate(/area/unit_test)
	isolated.outdoors = TRUE
	TEST_ASSERT_EQUAL(blueprint.get_area_type(isolated), AREA_SPACE, "an explicit outdoor area is unclaimed")
	TEST_ASSERT_EQUAL(get_new_area_type(isolated), 1, "an explicit outdoor area allows creation")
	isolated.outdoors = FALSE
	TEST_ASSERT_EQUAL(blueprint.get_area_type(isolated), AREA_STATION, "an explicit ordinary indoor area is a station area")
	TEST_ASSERT_EQUAL(get_new_area_type(isolated), 0, "an ordinary indoor area does not allow new-area creation")
	TEST_ASSERT_EQUAL(blueprint.get_area_type(null), 0, "missing areas have no editing classification")
	TEST_ASSERT_EQUAL(get_new_area_type(null), 0, "missing areas do not allow creation")
	var/page = blueprint.areaeditor_text(user, null, null)
	TEST_ASSERT(length(page), "the actor can generate the actual editing page without an ambient caller")
	TEST_ASSERT(findtext(page, "create_area=1"), "the actor's editing page offers the actual creation action")
	var/datum/om/prompt/text/blueprint_rename_area/ask = allocate(/datum/om/prompt/text/blueprint_rename_area)
	rel_set(ask, nameof(ask.answerer), user)
	rel_set(ask, nameof(ask.area_to_rename), isolated)
	ask.text = "Interim blueprint renamed area"
	TEST_ASSERT(blueprint.area_renamed(ask), "the real rename callback succeeds")
	TEST_ASSERT_EQUAL(isolated.name, ask.text, "the callback changes the actual area name")
	TEST_ASSERT_EQUAL(blueprint.last_actor, user, "the callback refreshes the explicit actor's interaction")
