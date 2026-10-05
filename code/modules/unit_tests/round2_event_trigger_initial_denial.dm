/// Public setup rejects an actual clientless actor without deleting its landmark.
/datum/unit_test/round2_event_trigger_initial_denial
	var/trigger_type = /obj/effect/landmark/event_trigger

/datum/unit_test/round2_event_trigger_initial_denial/Run()
	test_driver_begin()
	exercise_denial()
	own_turf_contents(test_floor())
	test_driver_end()

/datum/unit_test/round2_event_trigger_initial_denial/proc/exercise_denial()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_floor())
	var/obj/effect/landmark/event_trigger/trigger = allocate(trigger_type, test_floor())
	TEST_ASSERT_NULL(user.client, "Actual headless human has no admin client; the fixture does not invent one")
	TEST_ASSERT(!QDELETED(trigger), "Actual constructed landmark exists before the public setup call")
	var/original_name = trigger.name
	var/original_coordinates = trigger.coordinates
	var/opened_before = SSrequests.opened
	trigger.set_vars(user)
	TEST_ASSERT(!QDELETED(trigger), "Initial actual authority denial preserves the existing landmark")
	TEST_ASSERT_EQUAL(trigger.name, original_name, "Initial denial does not configure the real landmark name")
	TEST_ASSERT_EQUAL(trigger.coordinates, original_coordinates, "Initial denial leaves original real coordinates intact")
	TEST_ASSERT_EQUAL(trigger.creator_ckey, "", "Denied setup does not assign a creator")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Actual public denial opens no setup question")
	TEST_ASSERT_EQUAL(SSrequests.opened, opened_before, "Initial denial does not open then cancel a native request")

/datum/unit_test/round2_event_trigger_initial_denial/narration
	trigger_type = /obj/effect/landmark/event_trigger/auto_narrate
