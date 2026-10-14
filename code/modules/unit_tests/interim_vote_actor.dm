/// Keep real startup, logging and clocks; suppress only world-wide poll announcements.
/datum/vote/interim_actor
	vote_type_text = "interim"
	var/start_actor_ref
	var/announcement_text
	var/announcement_count = 0

/datum/vote/interim_actor/start(mob/user)
	start_actor_ref = user ? REF(user) : null
	return ..()

/datum/vote/interim_actor/announce(start_text, time = vote_time)
	announcement_text = start_text
	announcement_count++

/datum/unit_test/interim_vote_explicit_initiator/Run()
	test_driver_begin()
	TEST_ASSERT_NULL(SSvote.get_active_vote(), "the fixture begins without an active server vote")
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/vote/interim_actor/vote = allocate(/datum/vote/interim_actor, "Fixture operator", "Fixture question", list("Yes", "No"), TRUE)
	SSvote.start_vote(vote, actor)
	TEST_ASSERT_EQUAL(SSvote.get_active_vote(), vote, "the actual singleton owns the newly started vote")
	TEST_ASSERT_EQUAL(owner_of(vote), SSvote, "startup transfers ownership to the real vote service")
	TEST_ASSERT_EQUAL(vote.start_actor_ref, REF(actor), "the real service forwards the explicit initiating mob to parent startup and logging")
	TEST_ASSERT_EQUAL(vote.vote_type_text, "custom", "the real startup marks the supplied custom vote")
	TEST_ASSERT_EQUAL(vote.initiator, "Fixture operator", "startup preserves the configured initiator text")
	TEST_ASSERT_EQUAL(vote.question, "Fixture question", "startup preserves the custom question")
	TEST_ASSERT_EQUAL(length(vote.choices), 2, "startup preserves both supplied choices")
	TEST_ASSERT(("Yes" in vote.choices) && ("No" in vote.choices), "startup retains the actual answer values")
	TEST_ASSERT_EQUAL(vote.announcement_count, 1, "the actual startup requests exactly one announcement")
	TEST_ASSERT_EQUAL(vote.announcement_text, "Interim vote started by Fixture operator.\nFixture question", "startup retains the complete existing custom announcement")
	TEST_ASSERT(vote.remaining() > 0 && vote.remaining() <= (vote.vote_time / (1 SECOND)), "the actual startup stamps a live countdown")
	TEST_ASSERT_NOTNULL(SSvote.get_active_vote(), "the real service reports the active vote as work")
	qdel(vote)
	TEST_ASSERT_NULL(SSvote.get_active_vote(), "deleting the actual vote clears the service's owned slot")
	TEST_ASSERT_EQUAL(SSvote.tick_vote(0), STEP_PARK, "vote deletion parks the real service")

/datum/unit_test/interim_vote_automated_initiator/Run()
	test_driver_begin()
	TEST_ASSERT_NULL(SSvote.get_active_vote(), "the fixture begins without an active server vote")
	var/datum/vote/interim_actor/vote = allocate(/datum/vote/interim_actor, null, null, list("Continue", "Transfer"), FALSE)
	SSvote.start_vote(vote)
	TEST_ASSERT_EQUAL(SSvote.get_active_vote(), vote, "the actual actorless startup installs its vote")
	TEST_ASSERT_NULL(vote.start_actor_ref, "automated startup intentionally passes no initiating player")
	TEST_ASSERT_EQUAL(vote.initiator, "the server", "automated startup preserves the server attribution")
	TEST_ASSERT_EQUAL(vote.vote_type_text, "interim", "automated startup preserves its normal vote type")
	TEST_ASSERT_EQUAL(vote.announcement_count, 1, "automated startup requests its normal announcement")
	TEST_ASSERT_EQUAL(vote.announcement_text, "Interim vote started by the server.", "automated startup retains the existing announcement text")
	TEST_ASSERT_EQUAL(length(vote.choices), 2, "automated startup retains its answer choices")
	TEST_ASSERT(vote.remaining() > 0 && vote.remaining() <= (vote.vote_time / (1 SECOND)), "automated startup starts the real countdown")
	qdel(vote)
	TEST_ASSERT_NULL(SSvote.get_active_vote(), "automated vote deletion clears the service slot")
