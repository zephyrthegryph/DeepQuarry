/// Retain the real vore feedback hook while observing the supplied callback actor.
/datum/tgui_module/appearance_changer/vore/interim_actor_probe
	var/actor_ref_seen
	var/change_flag_seen
	var/hook_calls = 0

/datum/tgui_module/appearance_changer/vore/interim_actor_probe/changed_hook(flag, mob/user)
	actor_ref_seen = user ? REF(user) : null
	change_flag_seen = flag
	hook_calls++
	return ..()

/// Colour answers and UI actions forward the operator independently of the target.
/datum/unit_test/interim_appearance_callback_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/operator = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	var/datum/tgui_module/appearance_changer/vore/interim_actor_probe/changer = allocate(/datum/tgui_module/appearance_changer/vore/interim_actor_probe, operator, target)
	var/datum/prompt/color/appearance/ask = allocate(/datum/prompt/color/appearance)
	ask.answerer = operator
	ask.field = "hair_color"
	ask.value = "#040506"
	target.change_hair_color(1, 2, 3)
	TEST_ASSERT(changer.apply_color(ask), "the actual callback changes the target's hair")
	TEST_ASSERT_EQUAL(target.r_hair, 4, "the callback writes the actual red channel")
	TEST_ASSERT_EQUAL(target.g_hair, 5, "the callback writes the actual green channel")
	TEST_ASSERT_EQUAL(target.b_hair, 6, "the callback writes the actual blue channel")
	TEST_ASSERT_EQUAL(changer.actor_ref_seen, REF(operator), "the delayed callback forwards its prompt answerer")
	TEST_ASSERT_EQUAL(changer.change_flag_seen, APPEARANCECHANGER_CHANGED_HAIRCOLOR, "the real hair-color feedback flag is preserved")
	TEST_ASSERT_EQUAL(changer.hook_calls, 1, "a real change invokes the feedback hook exactly once")
	TEST_ASSERT(!changer.apply_color(ask), "repeating the same color reports no change")
	TEST_ASSERT_EQUAL(changer.hook_calls, 1, "an unchanged color produces no extra feedback")
	var/new_identity = target.identifying_gender == FEMALE ? MALE : FEMALE
	test_ui(operator, changer, "gender_id", list("gender_id" = new_identity))
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(target.identifying_gender, new_identity, "the target's actual gender identity changes")
	TEST_ASSERT_EQUAL(changer.actor_ref_seen, REF(operator), "the UI handler forwards its supplied operator")
	TEST_ASSERT_EQUAL(changer.change_flag_seen, APPEARANCECHANGER_CHANGED_GENDER_ID, "the UI handler preserves the identity feedback flag")
	TEST_ASSERT_EQUAL(changer.hook_calls, 2, "the separate UI change invokes one more feedback hook")
