// Read-driven tracking (doc/rewrite/read_driven_tracking.md): no var here is declared tracked; the draw reads them, so the build gives them setters.

/obj/read_tracking_lamp
	name = "read tracking lamp"
	var/brightness = 0
	var/hue = "red"
	var/unread = 0
	var/draw_calls = 0

/obj/read_tracking_lamp/draw(datum/look/look)
	. = ..()
	look.state("rt-[brightness]-[hue]")

/// A var the draw reads, declared nowhere as tracked, redraws the holder when written through its generated setter.
/datum/unit_test/dq_read_tracking_setter_redraws
	boot_needs = list()

/datum/unit_test/dq_read_tracking_setter_redraws/Run()
	var/obj/read_tracking_lamp/L = allocate(/obj/read_tracking_lamp)
	refresh_flush()
	TEST_ASSERT(hascall(L, "set_brightness"), "the build generated a setter for a var the draw reads")
	TEST_ASSERT(hascall(L, "__setter_brightness"), "and registered it, so VV edits go through it")
	TEST_ASSERT(!hascall(L, "set_unread"), "a var nothing reads and nothing writes gets none")
	TEST_ASSERT_EQUAL(L.set_brightness(3), TRUE, "a changed value reports TRUE")
	TEST_ASSERT_EQUAL(L.brightness, 3, "and is written")
	TEST_ASSERT_EQUAL(L.refresh_queued & DEP_DRAW, DEP_DRAW, "the write queued the draw")
	refresh_flush()
	TEST_ASSERT_EQUAL(L.set_brightness(3), FALSE, "the same value is unchanged")
	TEST_ASSERT_EQUAL(L.refresh_queued, 0, "and queues nothing")

/// An admin edit of a derived-tracked var goes through its setter and publishes.
/datum/unit_test/dq_read_tracking_vv_publishes
	boot_needs = list()

/datum/unit_test/dq_read_tracking_vv_publishes/Run()
	var/obj/read_tracking_lamp/L = allocate(/obj/read_tracking_lamp)
	refresh_flush()
	TEST_ASSERT(L.vv_edit_var(nameof(L.hue), "blue"), "VV accepts the edit")
	TEST_ASSERT_EQUAL(L.hue, "blue", "the value changed")
	TEST_ASSERT_EQUAL(L.refresh_queued & DEP_DRAW, DEP_DRAW, "and the draw that reads it was queued")
