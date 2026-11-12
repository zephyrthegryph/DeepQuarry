// A crew record's photos come from the shared portrait cache, off the join tick (data_records.dm request_photos()).

/// A record made for a human holds the no-image photos until the portraits land, each direction lands on its own, and the join tick draws no compound icon.
/datum/unit_test/dq_record_photos_land_from_the_portrait_cache

/datum/unit_test/dq_record_photos_land_from_the_portrait_cache/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/data/record/G = GLOB.data_core.CreateGeneralRecord(H, "PHOTO")
	TEST_ASSERT(G.fields["photo-south"] && G.fields["photo-west"], "the record has a photo in both directions from the start")
	TEST_ASSERT(G.fields["photo_front"] && G.fields["photo_side"], "and both pictures")
	// Stand in for the two renders still in flight: the record waits on one key per direction.
	G.photos_waiting = list("[SOUTH]" = "south-key", "[WEST]" = "west-key")
	var/datum/portrait/south = new
	south.set_key("south-key")
	south.set_b64("SOUTHPNG")
	south.picture = icon('html/images/no_image32.png')
	G.photo_landed(south)
	TEST_ASSERT(findtext(G.fields["photo-south"], "SOUTHPNG"), "the south portrait is the front photo once it lands")
	TEST_ASSERT(!findtext(G.fields["photo-west"], "SOUTHPNG"), "and not the side photo")
	TEST_ASSERT_EQUAL(length(G.photos_waiting), 1, "the west render is still awaited")
	var/datum/portrait/west = new
	west.set_key("west-key")
	west.set_b64("WESTPNG")
	west.picture = icon('html/images/no_image32.png')
	G.photo_landed(west)
	TEST_ASSERT(findtext(G.fields["photo-west"], "WESTPNG"), "the west portrait is the side photo")
	TEST_ASSERT_NULL(G.photos_waiting, "nothing is awaited any more")
	spent(south)
	spent(west)
	qdel(G)
	test_driver_end()
