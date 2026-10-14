/datum/unit_test/interim_cockroach_death_cleanup
	var/contained = FALSE

/datum/unit_test/interim_cockroach_death_cleanup/contained
	contained = TRUE

/datum/unit_test/interim_cockroach_death_cleanup/Run()
	var/turf/T = test_floor()
	var/obj/structure/closet/holder
	if(contained)
		holder = allocate(/obj/structure/closet, T)
	var/mob/living/simple_mob/animal/passive/cockroach/roach = allocate(/mob/living/simple_mob/animal/passive/cockroach, T)
	TEST_ASSERT(!QDELETED(roach) && roach.stat == CONSCIOUS, "The actual cockroach constructor creates a living conscious original mob")
	var/atom/original_location = T
	if(contained)
		TEST_ASSERT_EQUAL(holder.store_mobs(), 1, "Actual closet storage takes the exact original cockroach")
		TEST_ASSERT_EQUAL(roach.loc, holder, "The original cockroach physically occupies its actual holder")
		TEST_ASSERT(roach in holder.slot_contents(CONTAINER_SLOT_INTERIOR), "The original cockroach occupies the real declared interior slot")
		original_location = holder
	var/list/before = contents_of(original_location, /obj/effect/decal/cleanable/bug_remains)
	TEST_ASSERT_EQUAL(roach.death(), FALSE, "The real death pipeline takes its original replacement path instead of normal corpse death")
	own_turf_contents(T)
	var/list/products = contents_of(original_location, /obj/effect/decal/cleanable/bug_remains) - before
	for(var/obj/effect/decal/cleanable/bug_remains/R as anything in products)
		own(R)
	TEST_ASSERT(QDELETED(roach), "Actual replacement death consumes the exact original cockroach")
	TEST_ASSERT_EQUAL(length(products), 1, "Actual replacement death creates exactly one real bug-remains product at its original location")
	var/obj/effect/decal/cleanable/bug_remains/remains = products[1]
	TEST_ASSERT_EQUAL(remains.type, /obj/effect/decal/cleanable/bug_remains, "Actual replacement death creates the exact canonical bug-remains type")
	TEST_ASSERT(!QDELETED(remains) && remains.loc == original_location, "The exact original replacement product survives original mob deletion at its original location")
	TEST_ASSERT_NULL(locate_within(original_location, /mob/living/simple_mob/animal/passive/cockroach), "The actual replacement path leaves no duplicate cockroach body")
	if(contained)
		TEST_ASSERT(!QDELETED(holder) && holder.loc == T, "Actual contained death preserves the exact original closet")
		TEST_ASSERT_NULL(locate_within(T, /obj/effect/decal/cleanable/bug_remains), "Actual contained death creates no additional bug remains on the outer floor")
