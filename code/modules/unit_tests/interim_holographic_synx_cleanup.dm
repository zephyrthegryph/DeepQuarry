/datum/unit_test/interim_holographic_synx_cleanup
	var/gibbed = TRUE
	var/contained = FALSE

/datum/unit_test/interim_holographic_synx_cleanup/death
	gibbed = FALSE

/datum/unit_test/interim_holographic_synx_cleanup/contained
	contained = TRUE

/datum/unit_test/interim_holographic_synx_cleanup/Run()
	var/turf/T = test_floor()
	var/obj/structure/closet/holder
	if(contained)
		holder = allocate(/obj/structure/closet, T)
	var/mob/living/simple_mob/animal/synx/ai/pet/holo/source = allocate(/mob/living/simple_mob/animal/synx/ai/pet/holo, T)
	TEST_ASSERT(source && !QDELETED(source) && source.stat == CONSCIOUS, "The actual canonical holographic synx constructor creates its conscious original source")
	TEST_ASSERT(source.delete_on_death, "The actual canonical holographic synx retains its original deletion-on-death behavior")
	if(contained)
		TEST_ASSERT_EQUAL(holder.store_mobs(), 1, "Actual closet storage contains the exact original holographic synx")
		TEST_ASSERT_EQUAL(source.loc, holder, "The original holographic synx genuinely occupies its real holder")
		TEST_ASSERT(source in holder.slot_contents(CONTAINER_SLOT_INTERIOR), "The original synx occupies the real declared interior slot")
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/list/seeds_before = turf_contents_of_type(T, /obj/item/seeds/hardlightseed/typesx)
	var/list/gibs_before = turf_contents_of_type(T, /obj/effect/decal/cleanable/blood/gibs)
	if(gibbed)
		source.gib()
	else
		source.death()
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(source), "The actual holographic gib or ordinary-death path consumes its exact original source")
	var/list/seeds = turf_contents_of_type(T, /obj/item/seeds/hardlightseed/typesx) - seeds_before
	TEST_ASSERT_EQUAL(length(seeds), 1, "Actual holographic cleanup creates exactly one canonical real hardlight seed on the original floor")
	var/obj/item/seeds/hardlightseed/typesx/seed = seeds[1]
	TEST_ASSERT_EQUAL(seed.type, /obj/item/seeds/hardlightseed/typesx, "The actual original replacement seed has the exact canonical synx seed type")
	TEST_ASSERT(!QDELETED(seed) && seed.loc == T, "The actual original replacement seed survives on the original floor")
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/effect/decal/cleanable/blood/gibs) - gibs_before), 0, "Actual holographic cleanup creates no physical gib debris")
	TEST_ASSERT_NULL(locate_within(T, /mob/living/simple_mob/animal/synx/ai/pet/holo), "Actual holographic cleanup leaves no original source corpse on the floor")
	TEST_ASSERT(!QDELETED(pen) && pen.loc == T, "Actual holographic cleanup preserves the original unrelated floor item")
	if(contained)
		TEST_ASSERT(!QDELETED(holder) && holder.loc == T, "Actual contained holographic cleanup preserves the exact original holder")
		TEST_ASSERT_NULL(locate_within(holder, /mob/living/simple_mob/animal/synx/ai/pet/holo), "Actual contained cleanup leaves no original source corpse inside the holder")
		TEST_ASSERT_NULL(locate_within(holder, /obj/item/seeds/hardlightseed/typesx), "Actual contained cleanup leaves its canonical seed on the outer floor rather than inside the holder")
