/// Actual petrification release and shattering both remove the statue but have different living outcomes.
/datum/unit_test/interim_statue_endings
	var/shatter = FALSE

/datum/unit_test/interim_statue_endings/shatter
	shatter = TRUE

/datum/unit_test/interim_statue_endings/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/person = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_EQUAL(person.stat, CONSCIOUS, "the actual person starts alive and conscious")
	TEST_ASSERT(!(person.sdisabilities & MUTE), "the actual person starts without petrification muting")
	var/obj/structure/closet/statue/statue = allocate(/obj/structure/closet/statue, T, person)
	TEST_ASSERT(!QDELETED(statue), "the actual statue initializes around a valid person")
	TEST_ASSERT_EQUAL(person.loc, statue, "actual petrification moves the original person inside the statue")
	TEST_ASSERT(person in statue.slot_contents(CONTAINER_SLOT_INTERIOR), "the original person occupies the actual declared interior")
	TEST_ASSERT(person.sdisabilities & MUTE, "actual petrification mutes the original person")
	TEST_ASSERT_EQUAL(statue.get_integrity(), statue.original_int, "the actual statue starts without structural damage to transfer")
	if(shatter)
		statue.shatter(person)
	else
		statue.release()
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(statue), "actual release or shattering consumes the original statue")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/closet/statue), "the actual ending leaves no duplicate statue")
	TEST_ASSERT(!QDELETED(person), "the original person still exists during the immediate ending transaction")
	TEST_ASSERT_EQUAL(person.loc, T, "the actual ending releases the original person onto the floor")
	TEST_ASSERT(!(person.sdisabilities & MUTE), "the actual ending removes the original petrification muting")
	if(shatter)
		TEST_ASSERT_EQUAL(person.stat, DEAD, "actual shattering dusts and kills the original encased person")
		TEST_ASSERT_EQUAL(person.invisibility, INVISIBILITY_ABSTRACT, "actual dusting hides the original body for its deferred disintegration")
	else
		TEST_ASSERT_EQUAL(person.stat, CONSCIOUS, "actual undamaged release preserves the living conscious person")
