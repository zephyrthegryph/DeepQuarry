/datum/unit_test/dq_secbot_surrender_relation

/datum/unit_test/dq_secbot_surrender_relation/Run()
	var/turf/test_turf = run_loc_floor_bottom_left
	var/mob/living/bot/secbot/bot = new(test_turf)
	var/mob/living/carbon/human/first = new(test_turf)
	var/mob/living/carbon/human/second = new(test_turf)
	bot.declare_arrests = FALSE
	bot.set_pursuit_target(first)
	bot.demand_surrender(first, 0)
	TEST_ASSERT(bot.Observed(first, COMSIG_MOVABLE_ATTEMPTED_MOVE, TYPE_PROC_REF(/mob/living/bot/secbot, target_moved)), "surrender target was not observed")
	TEST_ASSERT(first._listen_lookup?[COMSIG_MOVABLE_ATTEMPTED_MOVE], "surrender target movement listener was not installed")
	bot.set_pursuit_target(second)
	TEST_ASSERT(!bot.Observed(first, COMSIG_MOVABLE_ATTEMPTED_MOVE, TYPE_PROC_REF(/mob/living/bot/secbot, target_moved)), "retargeting left the previous observation")
	TEST_ASSERT(!first._listen_lookup?[COMSIG_MOVABLE_ATTEMPTED_MOVE], "retargeting left the previous movement listener")
	bot.demand_surrender(second, 0)
	TEST_ASSERT(bot.Observed(second, COMSIG_MOVABLE_ATTEMPTED_MOVE, TYPE_PROC_REF(/mob/living/bot/secbot, target_moved)), "replacement surrender target was not watched")
	bot.resetTarget()
	TEST_ASSERT_NULL(bot.target, "reset did not clear the pursuit target")
	TEST_ASSERT(!bot.Observed(second, COMSIG_MOVABLE_ATTEMPTED_MOVE, TYPE_PROC_REF(/mob/living/bot/secbot, target_moved)), "reset left the surrender observation")
	TEST_ASSERT(!second._listen_lookup?[COMSIG_MOVABLE_ATTEMPTED_MOVE], "reset left the movement listener")
	bot.set_pursuit_target(second)
	bot.demand_surrender(second, 0)
	qdel(second)
	TEST_ASSERT_NULL(bot.target, "target deletion left a stale pursuit target")
	TEST_ASSERT(!second._listen_lookup?[COMSIG_MOVABLE_ATTEMPTED_MOVE], "target deletion left the movement listener")
	bot.set_pursuit_target(first)
	bot.demand_surrender(first, 0)
	qdel(bot)
	TEST_ASSERT(!first._listen_lookup?[COMSIG_MOVABLE_ATTEMPTED_MOVE], "secbot deletion left a movement listener on its target")
	qdel(first)

/datum/object_model/test_observation_owner
	var/hits = 0
	var/lost = 0

/datum/object_model/test_observation_owner/proc/on_moved(datum/source, atom/old_loc)
	SIGNAL_HANDLER
	hits++

/datum/object_model/test_observation_owner/proc/on_lost(datum/source)
	lost++

/datum/unit_test/om_owned_signal_observation
	needs_test_block = FALSE

/datum/unit_test/om_owned_signal_observation/Run()
	var/datum/object_model/test_observation_owner/owner = new
	var/obj/first = new
	var/obj/second = new
	var/obj/third = new
	var/handler = TYPE_PROC_REF(/datum/object_model/test_observation_owner, on_moved)
	var/lost_handler = TYPE_PROC_REF(/datum/object_model/test_observation_owner, on_lost)
	TEST_ASSERT(owner.Observe(first, COMSIG_MOVABLE_MOVED, handler, null, lost_handler), "first source could not be observed")
	SEND_SIGNAL(first, COMSIG_MOVABLE_MOVED, null, 0, FALSE, 0)
	TEST_ASSERT_EQUAL(owner.hits, 1, "first source did not deliver")
	TEST_ASSERT(owner.Observe(second, COMSIG_MOVABLE_MOVED, handler, null, lost_handler), "replacement source could not be observed")
	SEND_SIGNAL(first, COMSIG_MOVABLE_MOVED, null, 0, FALSE, 0)
	SEND_SIGNAL(second, COMSIG_MOVABLE_MOVED, null, 0, FALSE, 0)
	TEST_ASSERT_EQUAL(owner.hits, 2, "replacement delivered from an old source or missed the new source")
	TEST_ASSERT(owner.ObserveSet(list(first, second, third), COMSIG_MOVABLE_MOVED, handler, null, lost_handler), "source set could not be installed")
	SEND_SIGNAL(first, COMSIG_MOVABLE_MOVED, null, 0, FALSE, 0)
	SEND_SIGNAL(third, COMSIG_MOVABLE_MOVED, null, 0, FALSE, 0)
	TEST_ASSERT_EQUAL(owner.hits, 4, "source set did not deliver exactly once per member")
	qdel(second)
	TEST_ASSERT_EQUAL(owner.lost, 1, "deleted source did not report loss")
	TEST_ASSERT(!owner.Observed(second, COMSIG_MOVABLE_MOVED, handler), "deleted source remained observed")
	TEST_ASSERT(owner.ObserveSet(list(third), COMSIG_MOVABLE_MOVED, handler, null, lost_handler), "source set did not shrink")
	SEND_SIGNAL(first, COMSIG_MOVABLE_MOVED, null, 0, FALSE, 0)
	TEST_ASSERT_EQUAL(owner.hits, 4, "removed set member still delivered")
	qdel(owner)
	TEST_ASSERT(!third._listen_lookup?[COMSIG_MOVABLE_MOVED], "owner deletion left the signal registered")
	qdel(first)
	qdel(third)
