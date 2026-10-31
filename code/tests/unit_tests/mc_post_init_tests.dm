/// A server world (sleep_offline_after_initializations) with RESUME_AFTER_INITIALIZATIONS
/// must not leave sleep_offline set after init: an empty world would stop advancing
/// world.time and the MC and pregame ticker would never fire (the silent post-init stall).
/// Pure decision test: it never writes world.sleep_offline or the config (either would
/// freeze this clientless test world).
/datum/unit_test/mc_post_init_resume_keeps_world_ticking

/datum/unit_test/mc_post_init_resume_keeps_world_ticking/Run()
	var/old_flag = Kernel.sleep_offline_after_initializations
	Kernel.sleep_offline_after_initializations = TRUE
	var/resumed = Kernel.post_init_sleep_offline(TRUE, TRUE)
	var/slept = Kernel.post_init_sleep_offline(FALSE, FALSE)
	Kernel.sleep_offline_after_initializations = FALSE
	var/untouched = Kernel.post_init_sleep_offline(FALSE, FALSE)
	Kernel.sleep_offline_after_initializations = old_flag
	TEST_ASSERT(!resumed, "RESUME_AFTER_INITIALIZATIONS left sleep_offline set after init")
	TEST_ASSERT(slept, "without RESUME_AFTER_INITIALIZATIONS a server world sleeps offline after init")
	TEST_ASSERT(!untouched, "worlds that opt out (tests, autowiki) are never put to sleep offline")
