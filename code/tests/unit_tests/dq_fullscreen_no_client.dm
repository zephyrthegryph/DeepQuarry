/// A fading fullscreen is kept alive by its viewer's screen list. With no client there is no fade: the screen goes through qdel now, never left for BYOND to collect under a live timer handle.
/datum/unit_test/dq_fullscreen_clear_without_client

/datum/unit_test/dq_fullscreen_clear_without_client/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NULL(H.client, "the test mob has no client")
	var/atom/movable/screen/fullscreen/screen = H.overlay_fullscreen("flash", /atom/movable/screen/fullscreen/flash)
	H.clear_fullscreen("flash")
	TEST_ASSERT(QDELETED(screen), "a cleared fullscreen with no viewer is deleted at once")
