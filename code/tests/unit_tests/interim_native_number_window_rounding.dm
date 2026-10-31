/// Actual content numeric windows preserve float versus integer presentation without a client.
/datum/unit_test/interim_native_number_window_rounding

/datum/unit_test/interim_native_number_window_rounding/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	TEST_ASSERT(isnull(user.client), "The real human is clientless; this test does not claim a displayed UI")
	var/datum/prompt/number/pin_value/floating = allocate(/datum/prompt/number/pin_value)
	var/datum/tgui_input_number/prompt/float_box = floating.present(user)
	own(float_box)
	TEST_ASSERT(istype(float_box), "The production float kind creates an actual native number window")
	TEST_ASSERT_EQUAL(float_box.round_value, FALSE, "Actual float window submission preserves fractional values")
	TEST_ASSERT_EQUAL(floating.normalize(1.25), 1.25, "The production float schema also preserves the fractional value")
	var/datum/prompt/number/lasertag_setting/integer = allocate(/datum/prompt/number/lasertag_setting)
	var/datum/tgui_input_number/prompt/integer_box = integer.present(user)
	own(integer_box)
	TEST_ASSERT(istype(integer_box), "The production lasertag setting kind creates an actual native number window")
	TEST_ASSERT_EQUAL(integer_box.round_value, TRUE, "Actual integer window submission rounds values")
	TEST_ASSERT_EQUAL(integer.normalize(1.25), 1, "The production integer schema rounds the same value")
