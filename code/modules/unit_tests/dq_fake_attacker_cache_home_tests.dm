// Image-cache allocation is lazy without changing the actual cardinal images.
/datum/unit_test/dq_fake_attacker_cache_home
/datum/unit_test/dq_fake_attacker_cache_home/Run()
	var/turf/T = test_floor()
	var/obj/effect/fake_attacker/F = allocate(/obj/effect/fake_attacker, T)
	var/list/initial_cache = F.vars["dir_images"]
	TEST_ASSERT_NULL(initial_cache, "an attacker which has no source does not allocate four-image cache state")
	var/obj/item/pen/source = allocate(/obj/item/pen, T)
	F.create_images_from(source)
	var/list/cache = F.vars["dir_images"]
	TEST_ASSERT_EQUAL(length(cache), 4, "the actual cache materializes all four cardinal images")
	var/list/images = list()
	for(var/direction in list(NORTH, SOUTH, EAST, WEST))
		var/image/I = cache["[direction]"]
		TEST_ASSERT(istype(I), "each cardinal entry is a real image")
		images += I
		TEST_ASSERT_EQUAL(I.dir, direction, "each real image preserves its cardinal facing")
		TEST_ASSERT_EQUAL(I.icon, source.icon, "the image copies the actual source icon")
		TEST_ASSERT_EQUAL(I.icon_state, source.icon_state, "the image copies the actual source appearance")
		TEST_ASSERT_EQUAL(I.loc, T, "the image is anchored at the attacker's real location")
		TEST_ASSERT_EQUAL(I.mouse_opacity, MOUSE_OPACITY_TRANSPARENT, "the image keeps the non-interactive cursor behavior")
	var/turf/destination = get_step(T, EAST)
	F.forceMove(destination)
	for(var/key in cache)
		var/image/I = cache[key]
		TEST_ASSERT_EQUAL(I.loc, destination, "real movement reanchors the existing image")
	qdel(F)
	TEST_ASSERT_EQUAL(length(images), 4, "the test retained all actual images before teardown")
	for(var/image/I as anything in images)
		TEST_ASSERT(QDELETED(I), "the real ending path deletes each cached image")
