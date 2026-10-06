// The mob repeats that moved from DECLARE_REPEAT to a type-level every() gated on a tracked var (doc/rewrite/om_retirement.md):
// each runs while its var holds, parks when the handler clears it, and the old REPEAT_STOP paths still end the work.

/// The jittery shake runs while the status does; a death ends the status at the next shake.
/datum/unit_test/life_om/shake_ends_on_death

/datum/unit_test/life_om/shake_ends_on_death/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.status_adjust(STAT_JITTERY, 500)
	TEST_ASSERT(H.jittery_shaking, "the status start sets the shake's gate")
	H.death()
	life_test_advance(0.5)
	TEST_ASSERT(!H.has_status(STAT_JITTERY), "the dead stop jittering")
	TEST_ASSERT(!H.jittery_shaking, "and the shake parks")
	TEST_ASSERT_EQUAL(H.pixel_x, H.old_x, "with the offset reset")

/// The transform animation plays its drill sounds 0.8 s apart, then ends the lockdown it started.
/datum/unit_test/life_om/robot_transform_sounds_end_the_lockdown

/datum/unit_test/life_om/robot_transform_sounds_end_the_lockdown/run_life()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	TEST_ASSERT(life_test_place(R), "no floor to place the test robot on")
	R.do_transform_animation()
	TEST_ASSERT_EQUAL(R.transform_sounds_left, 7, "seven steps to go")
	TEST_ASSERT(R.notransform, "the robot is held while it transforms")
	life_test_advance(3 * 0.8 + 0.1)
	TEST_ASSERT_EQUAL(R.transform_sounds_left, 4, "one step every 0.8 seconds")
	life_test_advance(4 * 0.8)
	TEST_ASSERT_EQUAL(R.transform_sounds_left, 0, "the countdown ends")
	TEST_ASSERT(!R.notransform, "and the lockdown with it")
	TEST_ASSERT(!R.anchored, "the robot is free to move")

/// A burst macrophage holding no human dies at its 3 minute check, and the check parks.
/datum/unit_test/life_om/macrophage_deathwatch

/datum/unit_test/life_om/macrophage_deathwatch/run_life()
	var/mob/living/simple_mob/vore/aggressive/macrophage/M = allocate(/mob/living/simple_mob/vore/aggressive/macrophage)
	TEST_ASSERT(life_test_place(M), "no floor to place the test macrophage on")
	var/turf/T = get_turf(M)
	M.set_deathwatch(TRUE)
	life_test_advance(2 * 60)
	TEST_ASSERT(M.stat != DEAD, "alive before the check")
	life_test_advance(60 + 1)
	TEST_ASSERT_EQUAL(M.stat, DEAD, "the check kills it")
	TEST_ASSERT(!M.deathwatch, "and clears its gate")
	qdel(M)
	life_test_advance(5)
	// The corpse bleeds where it lay (wherever that ended up): sweep what it left.
	for(var/obj/effect/decal/cleanable/blood/B in world)
		if(B.z == T.z && get_dist(B, T) <= 7)
			qdel(B)

/// A chain with no target to attack ends at the next attack and parks.
/datum/unit_test/life_om/jellyfish_chain_needs_a_target

/datum/unit_test/life_om/jellyfish_chain_needs_a_target/run_life()
	var/mob/living/simple_mob/vore/boss_jellyfish/J = allocate(/mob/living/simple_mob/vore/boss_jellyfish)
	TEST_ASSERT(life_test_place(J), "no floor to place the test jellyfish on")
	J.set_chain_number(3)
	life_test_advance(4 + 0.1)
	TEST_ASSERT_EQUAL(J.chain_number, 0, "no target: the chain ends")
	TEST_ASSERT_EQUAL(J.icon_state, "jellyfish", "back to its idle look")

/// A dream shows its fragments one every dream_wait while the dreamer sleeps, and waking ends it.
/datum/unit_test/life_om/dream_ends_on_waking

/datum/unit_test/life_om/dream_ends_on_waking/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.set_stat(UNCONSCIOUS)
	H.set_dream_fragments(list("one", "two", "three"))
	life_test_advance(0.2)
	TEST_ASSERT_EQUAL(length(H.dream_fragments), 2, "the first fragment shows at once")
	H.set_stat(CONSCIOUS)
	life_test_advance(3.1)
	TEST_ASSERT(isnull(H.dream_fragments), "waking ends the dream")

/// A trait's disability is a capability granted with the trait as its source: it ticks once a Life cycle on the mob's clock while
/// granted, and its revoke ends it.
/datum/unit_test/life_om/disability_ticks_while_granted

/datum/unit_test/life_om/disability_ticks_while_granted/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/datum/source = src
	grant(H, /datum/capability/disability/gibbing, source)
	TEST_ASSERT(granted(H, /datum/capability/disability/gibbing), "the disability is granted")
	life_test_advance(LIFE_CYCLE_SECONDS * 3 + 0.1)
	TEST_ASSERT(H.disability_gut_pressure >= 0.029 && H.disability_gut_pressure <= 0.031, "three cycles built three steps of pressure ([H.disability_gut_pressure])")
	revoke(H, /datum/capability/disability/gibbing, source)
	var/pressure = H.disability_gut_pressure
	life_test_advance(LIFE_CYCLE_SECONDS * 2)
	TEST_ASSERT_EQUAL(H.disability_gut_pressure, pressure, "revoked: it stops")
	H.status_end(STAT_WEAKENED)

/// Observers keep their upkeep once a Life cycle on their every(), with no Life sequence.
/datum/unit_test/life_om/observer_upkeep_every_cycle

/datum/unit_test/life_om/observer_upkeep_every_cycle/run_life()
	var/mob/observer/dead/life_test/G = allocate(/mob/observer/dead/life_test)
	var/before = G.upkeeps
	life_test_advance(OBSERVER_UPKEEP_INTERVAL / 10 * 3 + 0.1)
	TEST_ASSERT_EQUAL(G.upkeeps - before, 3, "one upkeep per cycle")

GLOBAL_LIST_EMPTY(life_test_bio_hits)

/proc/life_test_bio_hit(tag)
	GLOB.life_test_bio_hits += tag

/// CLOCK_BIO runs at the clock_rate_bio stat: a hold at 0 freezes it and the mob's own timers, 0.5 halves it, and releasing the
/// hold brings it back to world speed. Time already passed is kept across each change.
/datum/unit_test/life_om/bio_clock_follows_its_stat

/datum/unit_test/life_om/bio_clock_follows_its_stat/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/datum/source = new
	GLOB.life_test_bio_hits = list()
	after(H, 2 SECONDS, GLOBAL_PROC_REF(life_test_bio_hit), with = list("bio"))
	var/start = clock_now(H, CLOCK_BIO)
	life_test_advance(1)
	TEST_ASSERT(abs(clock_now(H, CLOCK_BIO) - start - 10) < 0.01, "rate 1: a second of biological time")
	hold(H, STAT_CLOCK_RATE_BIO, 0, source, clock = HOLD_CLOCK_WORLD)
	TEST_ASSERT_EQUAL(H.clock_rate_bio, 0, "the hold stops biology")
	var/frozen = clock_now(H, CLOCK_BIO)
	life_test_advance(5)
	TEST_ASSERT(abs(clock_now(H, CLOCK_BIO) - frozen) < 0.01, "a stopped clock keeps its time")
	TEST_ASSERT(!("bio" in GLOB.life_test_bio_hits), "and the mob's timer waits")
	release(H, STAT_CLOCK_RATE_BIO, source)
	hold(H, STAT_CLOCK_RATE_BIO, 0.5, source, clock = HOLD_CLOCK_WORLD)
	TEST_ASSERT_EQUAL(H.clock_rate_bio, 0.5, "a half-speed hold")
	life_test_advance(1)
	TEST_ASSERT(abs(clock_now(H, CLOCK_BIO) - frozen - 5) < 0.01, "rate 0.5: half a second for a second, got [clock_now(H, CLOCK_BIO) - frozen]")
	TEST_ASSERT(!("bio" in GLOB.life_test_bio_hits), "the timer has had 1.5 seconds")
	release(H, STAT_CLOCK_RATE_BIO, source)
	TEST_ASSERT_EQUAL(H.clock_rate_bio, 1, "released: world speed again")
	life_test_advance(0.6)
	TEST_ASSERT("bio" in GLOB.life_test_bio_hits, "the timer fires once its clock passed 2 seconds")
	qdel(source)
