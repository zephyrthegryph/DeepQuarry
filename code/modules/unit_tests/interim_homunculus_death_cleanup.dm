/// Death of a real homunculus clears only its original face relation; this does not exercise the summon prompt.
/datum/unit_test/interim_homunculus_death_cleanup
	var/homunculus_type = /mob/living/simple_mob/homunculus

/datum/unit_test/interim_homunculus_death_cleanup/evil
	homunculus_type = /mob/living/simple_mob/homunculus/evil

/datum/unit_test/interim_homunculus_death_cleanup/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/glamour_face/face = allocate(/obj/item/glamour_face, T)
	var/obj/item/glamour_face/control_face = allocate(/obj/item/glamour_face, T)
	var/mob/living/simple_mob/homunculus/source = allocate(homunculus_type, T)
	var/mob/living/simple_mob/homunculus/control = allocate(/mob/living/simple_mob/homunculus, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT_EQUAL(source.type, homunculus_type, "the actual constructor produces the requested canonical homunculus variant")
	TEST_ASSERT_EQUAL(source.stat, CONSCIOUS, "the actual original homunculus starts conscious")
	TEST_ASSERT_EQUAL(control.stat, CONSCIOUS, "the actual independent control homunculus starts conscious")
	rel_set(face, nameof(face.homunculus), source)
	rel_set(source, nameof(source.owner), face)
	rel_set(control_face, nameof(control_face.homunculus), control)
	rel_set(control, nameof(control.owner), control_face)
	TEST_ASSERT_EQUAL(face.homunculus, source, "the production relation setter records the exact original homunculus in its face")
	TEST_ASSERT_EQUAL(source.owner, face, "the production relation setter records the exact original face in the homunculus")
	TEST_ASSERT_EQUAL(control_face.homunculus, control, "the independent control face records its exact original homunculus")
	TEST_ASSERT_EQUAL(control.owner, control_face, "the independent control homunculus records its exact original face")
	TEST_ASSERT_EQUAL(source.death(FALSE), FALSE, "the actual death pipeline takes replacement death instead of leaving a normal corpse")
	TEST_ASSERT(QDELETED(source), "actual replacement death consumes the exact original homunculus")
	TEST_ASSERT_NULL(face.homunculus, "real teardown clears the original surviving face's homunculus relation")
	TEST_ASSERT(!QDELETED(face), "actual homunculus death preserves its exact original face")
	TEST_ASSERT_EQUAL(face.loc, T, "actual homunculus death preserves the original face location")
	TEST_ASSERT(!QDELETED(control), "actual death preserves the independent original control homunculus")
	TEST_ASSERT_EQUAL(control.stat, CONSCIOUS, "the independent original control homunculus stays conscious")
	TEST_ASSERT_EQUAL(control.loc, T, "actual death preserves the original control homunculus location")
	TEST_ASSERT_EQUAL(control_face.homunculus, control, "actual death preserves the independent original face relation")
	TEST_ASSERT_EQUAL(control.owner, control_face, "actual death preserves the independent original reverse relation")
	TEST_ASSERT(!QDELETED(control_face), "actual death preserves the exact original independent face")
	TEST_ASSERT(!QDELETED(pen), "actual death preserves the exact original unrelated pen")
	TEST_ASSERT_EQUAL(pen.loc, T, "actual death preserves the original unrelated pen location")
