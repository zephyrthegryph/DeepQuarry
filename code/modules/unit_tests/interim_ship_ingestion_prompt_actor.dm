/mob/living/simple_mob/interim_ship_ingestion_prompt_actor
	vore_default_mode = DM_HOLD

/// This drives the real native ship MouseDrop without changing parent routing.
/obj/interim_ship_ingestion_prompt_actor_click
	var/obj/effect/overmap/visitable/ship/ship
	var/mob/living/eater

/obj/interim_ship_ingestion_prompt_actor_click/Click(location, control, params)
	ship.MouseDrop(eater)

/datum/unit_test/om/interim_ship_ingestion_prompt_actor/run_om(list/made)
	test_prompts_reset()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/far = get_step(get_step(get_step(start, EAST), EAST), EAST)
	TEST_ASSERT(istype(far, /turf/simulated/floor), "the real distant fixture turf is a floor")
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, start)
	var/mob/living/simple_mob/eater = allocate(/mob/living/simple_mob/interim_ship_ingestion_prompt_actor, start)
	eater.init_vore(TRUE)
	TEST_ASSERT(length(eater.vore_organs), "the recipient has actual initialized belly choices")
	set_global("map_sectors", GLOB.map_sectors.Copy())
	set_var(using_map, nameof(using_map.player_levels), using_map.player_levels.Copy())
	set_var(using_map, nameof(using_map.sealed_levels), using_map.sealed_levels.Copy())
	var/obj/effect/overmap/visitable/ship/ship = allocate(/obj/effect/overmap/visitable/ship, null)
	defer_cleanup(src, PROC_REF(cleanup_ship), ship)
	ship.forceMove(start)
	TEST_ASSERT(ship.Adjacent(actor) && ship.Adjacent(eater), "the actual ship starts adjacent to both drag actor and recipient")
	var/obj/interim_ship_ingestion_prompt_actor_click/probe = allocate(/obj/interim_ship_ingestion_prompt_actor_click, start)
	rel_set(probe, nameof(probe.ship), ship)
	rel_set(probe, nameof(probe.eater), eater)
	km_synthetic_click(actor, probe)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the real native drag opens one recipient confirmation")
	var/datum/prompt/choice/first = GLOB.test_prompts[1]
	made += first
	TEST_ASSERT_EQUAL(first.answerer, eater, "the native confirmation belongs to the prospective eater")
	actor.forceMove(far)
	TEST_ASSERT(!ship.Adjacent(actor) && ship.Adjacent(eater), "only the original drag actor moves out of the real adjacency guard")
	test_prompt_answer(first, "Eat it!")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "actual confirmation rechecks the original actor and opens no belly prompt after they leave")
	TEST_ASSERT_EQUAL(ship.loc, start, "rejected confirmation leaves the real ship at its original turf")
	actor.forceMove(start)
	TEST_ASSERT(ship.Adjacent(actor), "the control drag actor returns to actual adjacency")
	km_synthetic_click(actor, probe)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 2, "a new native drag opens a fresh confirmation after the rejected flow ends")
	var/datum/prompt/choice/second = GLOB.test_prompts[2]
	made += second
	test_prompt_answer(second, "Eat it!")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 3, "nearby original actor allows the actual confirmation to open the real belly choice")
	var/datum/prompt/choice/belly = GLOB.test_prompts[3]
	made += belly
	TEST_ASSERT_EQUAL(belly.answerer, eater, "the actual second choice still belongs to the recipient")
	TEST_ASSERT_EQUAL(test_prompt_answer(belly, null, TRUE), "no answer", "actual belly-choice cancellation is accepted")
	TEST_ASSERT_EQUAL(ship.loc, start, "actual cancellation preserves the real ship turf")
	TEST_ASSERT(!QDELETED(ship), "actual refusal and cancellation preserve the original live ship")

/// Release the actual newly registered destination before ship teardown clears its relation view.
/datum/unit_test/om/interim_ship_ingestion_prompt_actor/proc/cleanup_ship(obj/effect/overmap/visitable/ship/ship)
	if(QDELETED(ship))
		return
	var/datum/flight_destination/destination = SSflight.destination_for_target(ship)
	if(destination)
		SSflight.unregister_destination(destination.id)
	qdel(ship)
