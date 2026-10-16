// A clientless sound-enabled audience exercises the actual belly sound replay handler.
/mob/living/simple_mob/e0_fixture/prey_loop_audience/check_sound_preference(list/preference)
	return TRUE

/datum/unit_test/dq_prey_loop_cooldown_home
/datum/unit_test/dq_prey_loop_cooldown_home/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/mob/living/simple_mob/e0_fixture/holder = allocate(/mob/living/simple_mob/e0_fixture, test_floor())
	var/obj/belly/B = allocate(/obj/belly, holder)
	var/mob/living/simple_mob/e0_fixture/prey_loop_audience/prey = allocate(/mob/living/simple_mob/e0_fixture/prey_loop_audience, B)
	var/mob/living/simple_mob/e0_fixture/prey_loop_audience/other = allocate(/mob/living/simple_mob/e0_fixture/prey_loop_audience, test_floor())
	B.update_belly_surrounding()
	TEST_ASSERT(prey in B.belly_surrounding, "the actual contained audience is selected")
	TEST_ASSERT(!cooldown_started(prey, next_preyloop), "the replay clock is initially unset")
	var/before = world.time
	B.prey_loop()
	TEST_ASSERT(cooldown_end(prey, next_preyloop) >= before + (52 SECONDS) && cooldown_end(prey, next_preyloop) <= world.time + (52 SECONDS), "the real handler starts the original 52-second replay interval")
	TEST_ASSERT(!cooldown_started(other, next_preyloop), "an unrelated listener's replay clock is unchanged")
	cooldown_set_end(prey, next_preyloop, world.time)
	var/exact = cooldown_end(prey, next_preyloop)
	B.prey_loop()
	TEST_ASSERT_EQUAL(cooldown_end(prey, next_preyloop), exact, "the strict old boundary does not replay exactly at expiry")
	cooldown_set_end(prey, next_preyloop, world.time - (1 DECISECONDS))
	B.prey_loop()
	TEST_ASSERT(cooldown_end(prey, next_preyloop) >= world.time + (52 SECONDS), "the sound replays after the deadline")
