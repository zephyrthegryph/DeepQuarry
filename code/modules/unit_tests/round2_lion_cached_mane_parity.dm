/// Actual lion colour/sex requests and a fresh-image renderer oracle; no fake default-state branches.
/datum/unit_test/round2_lion_cached_mane_parity
	var/list/image/oracle_images

/datum/unit_test/round2_lion_cached_mane_parity/Run()
	test_driver_begin()
	exercise_mane()
	for(var/obj/effect/overlay/holder in allocated)
		holder.cut_overlays()
	oracle_images = null
	test_driver_end()

/datum/unit_test/round2_lion_cached_mane_parity/proc/mane_values(atom/holder)
	var/list/result = list()
	for(var/mutable_appearance/value as anything in holder.overlays)
		if(findtext(value.icon_state, "mane") == 1)
			result += value
	return result

/datum/unit_test/round2_lion_cached_mane_parity/proc/fresh_mane(mob/living/simple_mob/vore/retaliate/lion/lion)
	var/image/expected = image(lion.icon, "mane")
	expected.color = lion.mane_color
	expected.plane = PLANE_LIGHTING_ABOVE
	expected.appearance_flags = lion.appearance_flags | RESET_COLOR
	LAZYADD(oracle_images, expected)
	return expected

/datum/unit_test/round2_lion_cached_mane_parity/proc/compare_manes(mob/living/simple_mob/vore/retaliate/lion/lion, obj/effect/overlay/oracle)
	var/list/actual = mane_values(lion)
	var/list/expected = mane_values(oracle)
	TEST_ASSERT_EQUAL(length(actual), length(expected), "Actual cached visual operation keeps the fresh-image oracle's mane count")
	for(var/i in 1 to length(expected))
		TEST_ASSERT_EQUAL(actual[i], expected[i], "Actual cached mane insertion/removal keeps the exact fresh-image appearance and ordering")

/datum/unit_test/round2_lion_cached_mane_parity/proc/exercise_mane()
	var/turf/surface = test_floor()
	var/mob/living/simple_mob/vore/retaliate/lion/lion = allocate(/mob/living/simple_mob/vore/retaliate/lion, surface)
	var/obj/effect/overlay/oracle = allocate(/obj/effect/overlay, surface)
	TEST_ASSERT(lion.has_mane && lion.stat == CONSCIOUS && !lion.resting && !lion.vore_fullness, "Actual fresh base lion has its ordinary conscious empty mane configuration")
	lion.update_icon()
	TEST_ASSERT(lion.mane_overlay, "Actual public visual update installs the mane")
	var/image/current_oracle = fresh_mane(lion)
	TEST_ASSERT_EQUAL(lion.mane_overlay, current_oracle.appearance, "Actual cached default mane equals a fresh legacy image's full immutable appearance")
	TEST_ASSERT_EQUAL(lion.mane_overlay.icon_state, "mane", "Actual normal provider selects the base mane state")
	TEST_ASSERT_EQUAL(lion.mane_overlay.layer, FLOAT_LAYER, "Actual cache retains the original image's floating default layer")
	TEST_ASSERT_EQUAL(lion.mane_overlay.dir, current_oracle.dir, "Actual cache retains the original image's default direction")
	var/list/original_manes = mane_values(lion)
	TEST_ASSERT(length(original_manes), "Actual lion displays a real mane overlay before requests")
	oracle.add_overlay(original_manes)
	lion.set_mane_color()
	var/datum/prompt/color/color_question = SSrequests.open_for(lion)
	TEST_ASSERT(istype(color_question) && color_question.owner == lion, "Actual public mane colour action opens the real native request")
	test_answer(lion, "#123456")
	TEST_ASSERT_EQUAL(lion.mane_color, "#123456", "Actual accepted colour request changes the real visual colour")
	current_oracle = fresh_mane(lion)
	oracle.add_overlay(current_oracle)
	TEST_ASSERT_EQUAL(lion.mane_overlay, current_oracle.appearance, "Actual recolour gets the exact fresh-image visual snapshot")
	compare_manes(lion, oracle)
	lion.set_sex()
	var/datum/prompt/choice/sex_question = SSrequests.open_for(lion)
	TEST_ASSERT(istype(sex_question) && sex_question.owner == lion, "Actual public sex action opens its real native selection")
	test_answer(lion, FEMALE)
	TEST_ASSERT(!lion.has_mane && isnull(lion.mane_overlay), "Actual female selection removes and nulls the current mane through the production provider")
	oracle.cut_overlay(current_oracle)
	compare_manes(lion, oracle)
	lion.set_sex()
	test_answer(lion, MALE)
	TEST_ASSERT(lion.has_mane && lion.mane_overlay, "Actual male selection reinstalls the real mane through normal update_icon")
	current_oracle = fresh_mane(lion)
	oracle.add_overlay(current_oracle)
	TEST_ASSERT_EQUAL(lion.mane_overlay, current_oracle.appearance, "Actual restored male visual matches a fresh legacy mane image")
	compare_manes(lion, oracle)
	TEST_ASSERT_NULL(SSrequests.open_for(lion), "Actual completed public visual choices leave no pending request")
