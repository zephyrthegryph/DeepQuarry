/// Queue selection uses actual metadata and relations without firing any world event.
/datum/unit_test/om/interim_event_queue_actor/run_om(list/made)
	sched.test_prompts = list()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/event_manager_panel/panel = allocate(/datum/event_manager_panel)
	var/datum/event_container/container = allocate(/datum/event_container)
	container.severity = EVENT_LEVEL_MUNDANE
	var/datum/event_meta/first = allocate(/datum/event_meta, EVENT_LEVEL_MUNDANE, "First actual queue fixture", /datum/event/nothing, 1)
	var/datum/event_meta/second = allocate(/datum/event_meta, EVENT_LEVEL_MUNDANE, "Second actual queue fixture", /datum/event/nothing, 1)
	rel_add(container, nameof(container.event_pool), first)
	rel_add(container, nameof(container.event_pool), second)
	rel_add(container, nameof(container.available_events), first)
	rel_add(container, nameof(container.available_events), second)
	TEST_ASSERT(panel.ui_act_select_event(actor, list("ref" = container), null, null, "select_event"), "the actual panel action requests event selection")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "the actual container creates one selection prompt")
	var/datum/om/prompt/choice/queue_event/ask = sched.test_prompts[1]
	made += ask
	TEST_ASSERT_EQUAL(ask.peek("answerer"), actor, "the actual selection prompt uses the panel's explicit actor")
	TEST_ASSERT_EQUAL(ask.peek("subject"), container, "the actual selection prompt refers to its container")
	TEST_ASSERT_NULL(om_prompt_answer(ask, first), "the real typed choice queues its selected metadata")
	TEST_ASSERT_EQUAL(container.next_event(), first, "the actual next-event relation resolves the selected object")
	TEST_ASSERT(!(first in container.available_events), "the queued event leaves actual random availability")
	TEST_ASSERT(second in container.available_events, "the unselected event remains available")
	panel.ui_act_select_event(actor, list("ref" = container), null, null, "select_event")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 2, "a second real request creates a new selection prompt")
	ask = sched.test_prompts[2]
	made += ask
	TEST_ASSERT_EQUAL(ask.peek("answerer"), actor, "the second real prompt keeps the explicit actor")
	TEST_ASSERT_NULL(om_prompt_answer(ask, second), "the actual answer replaces the queued event")
	TEST_ASSERT_EQUAL(container.next_event(), second, "the next-event relation resolves the replacement object")
	TEST_ASSERT(first in container.available_events, "replacement restores the previous event to actual availability")
	TEST_ASSERT(!(second in container.available_events), "replacement removes its newly queued event from availability")
	TEST_ASSERT_EQUAL(owner_of(first), container, "queue replacement preserves ownership of the first metadata")
	TEST_ASSERT_EQUAL(owner_of(second), container, "queue replacement preserves ownership of the second metadata")

/datum/unit_test/om/interim_event_queue_stale_choice/run_om(list/made)
	sched.test_prompts = list()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/event_container/container = allocate(/datum/event_container)
	container.severity = EVENT_LEVEL_MUNDANE
	var/datum/event_meta/event = allocate(/datum/event_meta, EVENT_LEVEL_MUNDANE, "Actual stale queue fixture", /datum/event/nothing, 1)
	rel_add(container, nameof(container.event_pool), event)
	rel_add(container, nameof(container.available_events), event)
	container.SelectEvent(actor)
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "the real container opens its initial event choice")
	var/datum/om/prompt/choice/queue_event/ask = sched.test_prompts[1]
	made += ask
	rel_remove(container, nameof(container.available_events), event)
	TEST_ASSERT_NOTNULL(om_prompt_answer(ask, event), "the actual validity guard refuses metadata no longer available")
	TEST_ASSERT_NULL(container.next_event(), "a stale answer cannot install an actual queued event")
	TEST_ASSERT_EQUAL(owner_of(event), container, "the refusal preserves actual metadata ownership")
