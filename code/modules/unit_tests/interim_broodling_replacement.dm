/// All real broodling families replace actual death with one living remains object and no corpse.
/datum/unit_test/interim_broodling_replacement
	var/broodling_type = /mob/living/simple_mob/animal/giant_spider/broodling
	var/contained = FALSE

/datum/unit_test/interim_broodling_replacement/frost
	broodling_type = /mob/living/simple_mob/animal/giant_spider/frost/broodling

/datum/unit_test/interim_broodling_replacement/electric
	broodling_type = /mob/living/simple_mob/animal/giant_spider/electric/broodling

/datum/unit_test/interim_broodling_replacement/hunter
	broodling_type = /mob/living/simple_mob/animal/giant_spider/hunter/broodling

/datum/unit_test/interim_broodling_replacement/lurker
	broodling_type = /mob/living/simple_mob/animal/giant_spider/lurker/broodling

/datum/unit_test/interim_broodling_replacement/nurse
	broodling_type = /mob/living/simple_mob/animal/giant_spider/nurse/broodling

/datum/unit_test/interim_broodling_replacement/pepper
	broodling_type = /mob/living/simple_mob/animal/giant_spider/pepper/broodling

/datum/unit_test/interim_broodling_replacement/thermic
	broodling_type = /mob/living/simple_mob/animal/giant_spider/thermic/broodling

/datum/unit_test/interim_broodling_replacement/tunneler
	broodling_type = /mob/living/simple_mob/animal/giant_spider/tunneler/broodling

/datum/unit_test/interim_broodling_replacement/webslinger
	broodling_type = /mob/living/simple_mob/animal/giant_spider/webslinger/broodling

/datum/unit_test/interim_broodling_replacement/contained
	contained = TRUE

/datum/unit_test/interim_broodling_replacement/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/structure/closet/holder
	if(contained)
		holder = allocate(/obj/structure/closet, T)
	var/mob/living/simple_mob/animal/giant_spider/broodling = allocate(broodling_type, T)
	TEST_ASSERT(!QDELETED(broodling), "the actual broodling initializes alive")
	TEST_ASSERT_EQUAL(broodling.stat, CONSCIOUS, "the actual broodling starts conscious before its death replacement")
	var/atom/original_location = T
	if(contained)
		TEST_ASSERT_EQUAL(holder.store_mobs(), 1, "actual closet storage takes the original broodling")
		TEST_ASSERT_EQUAL(broodling.loc, holder, "the original broodling physically occupies its actual holder")
		TEST_ASSERT(broodling in holder.slot_contents(CONTAINER_SLOT_INTERIOR), "the original broodling occupies the real declared interior slot")
		original_location = holder
	TEST_ASSERT_EQUAL(length(contents_of(original_location, /obj/effect/decal/cleanable/spiderling_remains)), 0, "the original location starts without broodling remains")
	TEST_ASSERT_EQUAL(broodling.death(), FALSE, "the actual death pipeline takes the replacement path instead of normal death")
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(broodling), "the actual replacement deletes the original broodling rather than leaving a corpse")
	TEST_ASSERT_EQUAL(length(contents_of(original_location, /obj/effect/decal/cleanable/spiderling_remains)), 1, "actual replacement creates exactly one remains object at the original location")
	var/obj/effect/decal/cleanable/spiderling_remains/remains = locate_within(original_location, /obj/effect/decal/cleanable/spiderling_remains)
	own(remains)
	TEST_ASSERT(!QDELETED(remains), "the real replacement remains survive the original body's deletion")
	TEST_ASSERT_EQUAL(remains.loc, original_location, "the prepared replacement preserves the original floor or holder location")
	TEST_ASSERT_EQUAL(length(contents_of(original_location, broodling_type)), 0, "the actual replacement leaves no duplicate broodling body")
	if(contained)
		TEST_ASSERT(!QDELETED(holder), "the actual death replacement preserves the independent closet")
		TEST_ASSERT_NULL(locate_within(T, /obj/effect/decal/cleanable/spiderling_remains), "the contained replacement does not create extra remains on the outer floor")
