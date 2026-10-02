/// The real entopic constructor registers its exact image; deletion must remove that global entry.
/datum/unit_test/interim_entopic_deletion/Run()
	var/turf/T = test_floor()
	var/obj/item/device = allocate(/obj/item, T)
	var/before_count = length(GLOB.entopic_images)
	var/datum/entopic/entopic = allocate(/datum/entopic, device, icon('icons/obj/device.dmi'), "signaler")
	var/image/registered_image = entopic.my_image
	TEST_ASSERT(registered_image, "The actual constructor must create an image")
	TEST_ASSERT(entopic.registered, "The actual constructor must register the entopic")
	TEST_ASSERT(registered_image in GLOB.entopic_images, "The exact constructed image must enter the global image list")
	TEST_ASSERT_EQUAL(length(GLOB.entopic_images), before_count + 1, "Construction must add exactly one global image")
	qdel(entopic)
	var/still_registered = registered_image in GLOB.entopic_images
	var/after_count = length(GLOB.entopic_images)
	// Preserve global isolation even when a regression leaves this exact fixture image behind.
	GLOB.entopic_images -= registered_image
	TEST_ASSERT(QDELETED(entopic), "The actual entopic must be deleted")
	TEST_ASSERT(!still_registered, "Deletion must unregister its exact image before the owned reference clears")
	TEST_ASSERT_EQUAL(after_count, before_count, "Deletion must restore the actual global image count")
	TEST_ASSERT(!QDELETED(device), "Entopic deletion must preserve the real image holder")
