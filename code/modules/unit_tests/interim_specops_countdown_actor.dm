/datum/interim_specops_actor_witness
	var/calls = 0
	var/mob/user
	var/announcer_ref
	var/owned_at_callback = FALSE

/obj/item/radio/intercom/interim_actor_probe
	var/datum/interim_specops_actor_witness/witness

/proc/interim_specops_actor_arrived(obj/item/radio/intercom/interim_actor_probe/announcer, mob/user)
	var/datum/interim_specops_actor_witness/witness = announcer.witness
	witness.calls++
	rel_set(witness, nameof(witness.user), user)
	witness.announcer_ref = REF(announcer)
	witness.owned_at_callback = (announcer in SSshuttles.specops_announcers)
	// Chain the real blocked-launch branch; no live shuttle areas are moved.
	specops_launch(announcer, user)

/obj/interim_specops_countdown_click
	var/obj/item/radio/intercom/announcer
	var/mob/user

/obj/interim_specops_countdown_click/Click(location, control, params)
	specops_countdown(list(), announcer, GLOBAL_PROC_REF(interim_specops_actor_arrived), user)

/datum/unit_test/om/interim_specops_actor
	abstract_type = /datum/unit_test/om/interim_specops_actor

/datum/unit_test/om/interim_specops_actor/proc/prepare_refusal()
	set_global("specops_shuttle_moving_to_station", 0)
	set_global("specops_shuttle_moving_to_centcom", 0)
	set_global("specops_shuttle_at_station", 0)
	set_global("specops_shuttle_time", world.timeofday + 1 MINUTE)
	set_global("specops_shuttle_timeleft", 0)
	var/obj/machinery/computer/specops_shuttle/console = allocate(/obj/machinery/computer/specops_shuttle, run_loc_floor_bottom_left)
	EXPIRY_SET(console, specops_shuttle_timereset, 1 DAY, CLOCK_WORLD)
	TEST_ASSERT(!specops_can_move(), "the actual registered console's real reset deadline refuses shuttle movement")
	return console

/datum/unit_test/om/interim_specops_actor/countdown/run_om(list/made)
	var/obj/machinery/computer/specops_shuttle/console = prepare_refusal()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/interim_specops_actor_witness/witness = allocate(/datum/interim_specops_actor_witness)
	var/obj/item/radio/intercom/interim_actor_probe/announcer = allocate(/obj/item/radio/intercom/interim_actor_probe, run_loc_floor_bottom_left)
	var/obj/interim_specops_countdown_click/probe = allocate(/obj/interim_specops_countdown_click, run_loc_floor_bottom_left)
	made += list(console, actor, bystander, witness, announcer, probe)
	var/prior_count = LAZYLEN(SSshuttles.specops_announcers)
	var/announcer_ref = REF(announcer)
	var/obj/item/radio/intercom/unrelated = allocate(/obj/item/radio/intercom, run_loc_floor_bottom_left)
	made += unrelated
	SSshuttles.hold_specops_announcer(unrelated)
	TEST_ASSERT_EQUAL(SSshuttles.hold_specops_announcer(announcer), announcer, "the actual shuttle owner adopts the real temporary radio")
	TEST_ASSERT_EQUAL(LAZYLEN(SSshuttles.specops_announcers), prior_count + 2, "both actual pending radios are retained before the asynchronous countdown")
	rel_set(announcer, nameof(announcer.witness), witness)
	rel_set(probe, nameof(probe.announcer), announcer)
	rel_set(probe, nameof(probe.user), actor)
	km_synthetic_click(bystander, probe)
	TEST_ASSERT_EQUAL(witness.calls, 0, "the real countdown schedules rather than completing before its deadline")
	TEST_ASSERT(!QDELETED(announcer), "the owned actual countdown radio remains alive before its timer")
	set_global("specops_shuttle_time", world.timeofday - 1 SECOND)
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(witness.calls, 1, "the actual scheduled countdown invokes its real arrival callback exactly once")
	TEST_ASSERT_EQUAL(witness.user, actor, "the actual timer callback retains the explicit initiating actor rather than the native bystander")
	TEST_ASSERT_EQUAL(witness.announcer_ref, announcer_ref, "the callback receives the exact retained actual radio")
	TEST_ASSERT(witness.owned_at_callback, "the actual owner retains its pending radio through arrival")
	TEST_ASSERT(QDELETED(announcer), "the real blocked launch disposes its temporary announcer")
	TEST_ASSERT_EQUAL(LAZYLEN(SSshuttles.specops_announcers), prior_count + 1, "blocked arrival releases exactly its own radio")
	TEST_ASSERT(!QDELETED(unrelated) && (unrelated in SSshuttles.specops_announcers), "the real callback preserves the exact unrelated pending radio")
	TEST_ASSERT(SSshuttles.release_specops_announcer(unrelated), "the actual owner API releases the remaining unrelated radio explicitly")
	TEST_ASSERT(QDELETED(unrelated), "the real release disposes exactly that pending radio")
	TEST_ASSERT_EQUAL(LAZYLEN(SSshuttles.specops_announcers), prior_count, "both completed radio lifetimes restore the original pending count")
	TEST_ASSERT_EQUAL(GLOB.specops_shuttle_moving_to_station, 0, "the actual blocked callback preserves existing moving-state cleanup")
	TEST_ASSERT_EQUAL(GLOB.specops_shuttle_moving_to_centcom, 0, "the actual blocked callback clears both existing moving flags")

/datum/unit_test/om/interim_specops_actor/deleted_actor/run_om(list/made)
	var/obj/machinery/computer/specops_shuttle/console = prepare_refusal()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/interim_specops_actor_witness/witness = allocate(/datum/interim_specops_actor_witness)
	var/obj/item/radio/intercom/interim_actor_probe/announcer = allocate(/obj/item/radio/intercom/interim_actor_probe, run_loc_floor_bottom_left)
	made += list(console, actor, witness, announcer)
	var/prior_count = LAZYLEN(SSshuttles.specops_announcers)
	SSshuttles.hold_specops_announcer(announcer)
	rel_set(announcer, nameof(announcer.witness), witness)
	specops_countdown(list(), announcer, GLOBAL_PROC_REF(interim_specops_actor_arrived), actor)
	qdel(actor)
	TEST_ASSERT(QDELETED(actor), "the real initiating actor is deleted while the countdown is still pending")
	set_global("specops_shuttle_time", world.timeofday - 1 SECOND)
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(witness.calls, 1, "ordinary current-master timer semantics still finish after actor deletion")
	TEST_ASSERT_NULL(witness.user, "the deleted initiating actor resolves to null without canceling the countdown")
	TEST_ASSERT(witness.owned_at_callback, "actor deletion does not release the actual announcer prematurely")
	TEST_ASSERT(QDELETED(announcer), "the actual blocked arrival still disposes its retained announcer without a user")
	TEST_ASSERT_EQUAL(LAZYLEN(SSshuttles.specops_announcers), prior_count, "deleted-actor completion leaves no extra owned pending radio")
