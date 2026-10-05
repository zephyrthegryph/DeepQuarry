/// Actual Zorgoia provider snapshots retain legacy image defaults and every overlay input.
/datum/unit_test/round2_zorgoia_overlay_cache/Run()
	test_driver_begin()
	var/mob/living/simple_mob/vore/zorgoia/goia = allocate(/mob/living/simple_mob/vore/zorgoia)
	goia.init_vore(TRUE)
	var/list/parts = list("main", "ears", "spots", "claws", "spines", "fluff", "eyes", "spike", "belly", "underbelly")
	for(var/index in 1 to length(parts))
		var/part = parts[index]
		goia.goia_overlays[part] = "zorgoia_[part]"
		goia.goia_overlays["zorgoia_[part]"] = rgb(index * 20, 255 - index * 20, index * 10)
	goia.set_resting(FALSE)
	TEST_ASSERT_EQUAL(goia.vore_fullness, 0, "Actual empty initialized belly starts with zero fullness")
	var/list/standing = goia.appearance_overlays()
	assert_provider(goia, parts, standing, FALSE, 0)
	var/list/snapshots = standing.Copy()
	var/obj/belly/belly = goia.vore_selected
	TEST_ASSERT(istype(belly) && (belly in goia.vore_organs), "Actual public login initialization supplies the selected owned belly")
	var/mob/living/carbon/human/prey_one = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/prey_two = allocate(/mob/living/carbon/human)
	TEST_ASSERT(belly.belly_insert(prey_one, goia), "Actual public belly slot insertion accepts first real prey")
	TEST_ASSERT(belly.belly_insert(prey_two, goia), "Actual public belly slot insertion accepts second real prey")
	TEST_ASSERT_EQUAL(prey_one.loc, belly, "First real prey is actually inside the initialized belly")
	TEST_ASSERT_EQUAL(prey_two.loc, belly, "Second real prey is actually inside the initialized belly")
	goia.update_fullness()
	TEST_ASSERT_EQUAL(goia.vore_fullness, 2, "Actual belly contents compute fullness two without a fake fullness gate")
	var/list/full = goia.appearance_overlays()
	TEST_ASSERT_EQUAL(goia.vore_fullness, 2, "Actual provider parent retains genuine computed prey fullness")
	assert_provider(goia, parts, full, FALSE, 2)
	goia.set_resting(TRUE)
	var/list/resting = goia.appearance_overlays()
	assert_provider(goia, parts, resting, TRUE, 2)
	// Later builds overwrite the private scratch's state, tint, plane and layer.
	goia.goia_overlays["zorgoia_main"] = "#010203"
	goia.set_resting(FALSE)
	goia.appearance_overlays()
	TEST_ASSERT_EQUAL(length(standing), length(snapshots), "Later real provider builds cannot change the earlier returned list")
	for(var/index in 1 to length(snapshots))
		TEST_ASSERT_EQUAL(standing[index], snapshots[index], "Later scratch builds leave every earlier immutable snapshot unchanged")
	var/mutable_appearance/first = standing[length(standing) - 9]
	TEST_ASSERT_EQUAL(first.color, rgb(20, 235, 10), "Earlier actual main snapshot retains its original tint after another cache build")
	TEST_ASSERT_EQUAL(first.icon_state, "zorgoia_main", "Earlier actual snapshot retains its original standing state")
	test_driver_end()

/datum/unit_test/round2_zorgoia_overlay_cache/proc/assert_provider(mob/living/simple_mob/vore/zorgoia/goia, list/parts, list/overlays, rested, fullness)
	TEST_ASSERT(length(overlays) >= 10, "Actual live provider appends all ten Zorgoia overlays")
	var/offset = length(overlays) - 10
	for(var/index in 1 to length(parts))
		var/part = parts[index]
		var/state = "zorgoia_[part]"
		if(rested)
			state += "-rest"
		else if(fullness && (part == "belly" || part == "underbelly"))
			state += "-[fullness]"
		// Independent oracle uses the exact old fresh-image constructor defaults.
		var/image/expected = image('icons/mob/zorgoia64x32.dmi', state, pixel_x = -16)
		expected.color = goia.goia_overlays["zorgoia_[part]"]
		expected.appearance_flags |= RESET_COLOR|PIXEL_SCALE
		expected.plane = part == "eyes" ? PLANE_LIGHTING_ABOVE : MOB_PLANE
		if(part != "eyes")
			expected.layer = MOB_LAYER
		var/mutable_appearance/actual = overlays[offset + index]
		TEST_ASSERT_EQUAL(actual.icon_state, state, "Actual provider preserves ordered state, rest and belly fullness")
		TEST_ASSERT_EQUAL(actual.color, expected.color, "Actual provider preserves each distinct part tint")
		TEST_ASSERT_EQUAL(actual.pixel_x, expected.pixel_x, "Actual provider preserves the old negative pixel offset")
		TEST_ASSERT_EQUAL(actual.plane, expected.plane, "Actual eyes retain their distinct lighting plane")
		TEST_ASSERT_EQUAL(actual.layer, expected.layer, "Actual eyes retain the fresh image's implicit default layer")
		TEST_ASSERT_EQUAL(actual.appearance_flags, expected.appearance_flags, "Actual flags match fresh-image defaults plus original flags")
		TEST_ASSERT_EQUAL(actual, expected.appearance, "Complete actual immutable appearance equals the independent legacy constructor snapshot")
