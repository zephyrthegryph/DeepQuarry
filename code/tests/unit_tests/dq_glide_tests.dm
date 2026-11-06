// A mover's glide follows the step it is making: the reset armed by an earlier step must not undo the glide of the next one (a crawl step at
// glide 8 slides 32 pixels in a few ticks instead of over its whole delay, which reads as a jump).

/datum/unit_test/dq_glide_survives_the_previous_steps_reset

/datum/unit_test/dq_glide_survives_the_previous_steps_reset/Run()
	test_driver_begin()
	var/obj/item/mover = allocate(/obj/item, test_floor())
	var/delay = 1.2 SECONDS // a prone mob's step
	mover.glide_for(delay)
	var/crawl_glide = mover.glide_size
	TEST_ASSERT(crawl_glide < initial(mover.glide_size), "a long step glides slower than the default ([crawl_glide] against [initial(mover.glide_size)])")
	// The next step starts as the first one's delay runs out (a held key steps at the previous deadline), before that step's reset is due.
	test_time(delay - 1 DECISECONDS)
	mover.glide_for(delay)
	test_time(2 DECISECONDS) // the first step's reset falls due
	TEST_ASSERT_EQUAL(mover.glide_size, crawl_glide, "the first step's reset left the second step's glide alone")
	test_time(delay)
	TEST_ASSERT_EQUAL(mover.glide_size, initial(mover.glide_size), "the glide returns to the default once the last step is over")
	test_driver_end()
