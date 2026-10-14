/datum/experiment_handler/interim_actor_recorder
	var/announcements = 0
	var/last_announcement

/datum/experiment_handler/interim_actor_recorder/announce_message(message)
	announcements++
	last_announcement = message

/// Mindless scan refusals announce for the supplied living actor and never advance progress.
/datum/unit_test/interim_people_scan_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/pen/owner = allocate(/obj/item/pen, T)
	var/datum/experiment_handler/interim_actor_recorder/handler = allocate(/datum/experiment_handler/interim_actor_recorder, owner, list(), list(), EXPERIMENT_CONFIG_ATTACKSELF, null, EXPERIMENT_CONFIG_NO_AUTOCONNECT)
	var/datum/experiment/scanning/people/experiment = allocate(/datum/experiment/scanning/people)
	rel_set(handler, nameof(/datum/experiment_handler::selected_experiment), experiment)
	experiment.mind_required = TRUE
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	TEST_ASSERT_NULL(target.mind, "the scan fixture is actually mindless")
	TEST_ASSERT(!handler.action_experiment(owner, target, actor), "a mindless scan is refused for the living actor")
	TEST_ASSERT_EQUAL(handler.announcements, 1, "the explicit living actor triggers the mindless warning")
	TEST_ASSERT_EQUAL(handler.last_announcement, "Subject is mindless!", "the refusal announces its actual reason")
	TEST_ASSERT_EQUAL(length(experiment.scanned[/mob/living/carbon/human]), 0, "the refused scan earns no progress")
	TEST_ASSERT(!handler.action_experiment(owner, target, ghost), "the mind requirement also refuses a ghost actor")
	TEST_ASSERT_EQUAL(handler.announcements, 1, "a nonliving actor does not trigger the living-only warning")
	experiment.mind_required = FALSE
	TEST_ASSERT(handler.action_experiment(owner, target, actor), "disabling the mind requirement admits the same target")
	TEST_ASSERT_EQUAL(length(experiment.scanned[/mob/living/carbon/human]), 1, "the admitted scan records exactly one individual")
	TEST_ASSERT(!handler.action_experiment(owner, target, actor), "the same individual cannot contribute twice")
