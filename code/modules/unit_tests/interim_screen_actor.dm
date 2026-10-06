/// The existing synthetic-click API exercises the actual native screen Click boundary.
/datum/unit_test/interim_screen_native_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	var/atom/movable/screen/button = allocate(/atom/movable/screen)
	button.name = I_WALK
	actor.m_intent = I_RUN
	bystander.m_intent = I_RUN
	km_synthetic_click(actor, button)
	TEST_ASSERT_EQUAL(actor.m_intent, I_WALK, "the actual native screen click acts on its supplied actor")
	TEST_ASSERT_EQUAL(actor.m_int, "14,14", "the native click updates the actor's actual movement selection state")
	TEST_ASSERT_EQUAL(bystander.m_intent, I_RUN, "the native screen click leaves a separate mob's intent unchanged")
	button.name = I_RUN
	TEST_ASSERT_EQUAL(button.click_with_actor(actor, null, null, null), 1, "the actor-based path preserves the named control return value")
	TEST_ASSERT_EQUAL(actor.m_intent, I_RUN, "the actual actor-based control selects running")
	button.name = "face"
	button.click_with_actor(actor, null, null, null)
	TEST_ASSERT_EQUAL(actor.m_intent, "face", "the actual actor-based control selects facing")
	TEST_ASSERT_EQUAL(actor.m_int, "15,14", "the actual facing control updates its selection state")
	TEST_ASSERT_EQUAL(button.click_with_actor(null, null, null, null), 1, "an absent actor retains the native null-actor return")
	TEST_ASSERT_EQUAL(actor.m_intent, "face", "an absent actor cannot change another mob's intent")

/datum/unit_test/interim_screen_throw_actor_guard/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	var/atom/movable/screen/button = allocate(/atom/movable/screen)
	button.name = "throw"
	TEST_ASSERT(!actor.in_throw_mode, "the actual actor begins outside throw mode")
	button.click_with_actor(actor, null, null, null)
	TEST_ASSERT(actor.in_throw_mode, "the real named control enables its actor's throw mode")
	TEST_ASSERT(!bystander.in_throw_mode, "enabling throw mode does not alter another mob")
	button.click_with_actor(actor, null, null, null)
	TEST_ASSERT(!actor.in_throw_mode, "the real named control toggles its actor's throw mode off")
	var/obj/item/handcuffs/cuffs = allocate(/obj/item/handcuffs, T)
	TEST_ASSERT(move_into(actor, SLOT_ID_HANDCUFFED, cuffs), "real handcuffs occupy the actor's restraint slot")
	TEST_ASSERT(actor.restrained(), "the actual actor is restrained before the refusal")
	button.click_with_actor(actor, null, null, null)
	TEST_ASSERT(!actor.in_throw_mode, "the real restraint guard refuses to enable throw mode")
	TEST_ASSERT_EQUAL(actor.get_equipped_item(SLOT_ID_HANDCUFFED), cuffs, "the refusal preserves actual restraint ownership")

/datum/unit_test/interim_screen_internals_actor_inventory/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	var/atom/movable/screen/button = allocate(/atom/movable/screen)
	button.name = "internal"
	var/obj/item/clothing/mask/gas/mask = allocate(/obj/item/clothing/mask/gas, T)
	TEST_ASSERT(move_into(actor, SLOT_ID_MASK, mask), "the actual actor wears a suitable airtight mask")
	var/obj/item/tank/oxygen/foreign_tank = allocate(/obj/item/tank/oxygen, T)
	TEST_ASSERT(bystander.put_in_active_hand(foreign_tank), "a separate mob actually owns the nearby oxygen tank")
	button.click_with_actor(actor, null, null, null)
	TEST_ASSERT_NULL(actor.internal, "the actual inventory search refuses to use a nearby tank owned by another mob")
	TEST_ASSERT_EQUAL(bystander.get_active_hand(), foreign_tank, "the refused inventory search preserves the other mob's held tank")
	var/obj/item/tank/oxygen/tank = allocate(/obj/item/tank/oxygen, T)
	TEST_ASSERT(actor.put_in_active_hand(tank), "the actual actor holds its own usable oxygen tank")
	button.click_with_actor(actor, null, null, null)
	TEST_ASSERT_EQUAL(actor.internal, tank, "the actual internals control links the actor's own oxygen tank")
	TEST_ASSERT_NULL(bystander.internal, "the actor's control leaves the bystander's internals unchanged")
	button.click_with_actor(actor, null, null, null)
	TEST_ASSERT_NULL(actor.internal, "the actual internals control clears its actor's active tank link")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), tank, "turning internals off leaves the owned tank in the actor's hand")
	var/obj/item/handcuffs/cuffs = allocate(/obj/item/handcuffs, T)
	TEST_ASSERT(move_into(actor, SLOT_ID_HANDCUFFED, cuffs), "the actor wears actual restraints before retrying internals")
	TEST_ASSERT(actor.restrained(), "the actor is actually restrained before retrying")
	button.click_with_actor(actor, null, null, null)
	TEST_ASSERT_NULL(actor.internal, "the real restraint guard refuses to enable internals")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), tank, "refusal preserves ownership of the actor's tank")

/// Real AI construction uses the same safety flag as existing actor-adapter tests.
/datum/unit_test/interim_screen_unsupported_silicon_guard/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/silicon/ai/actor = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)
	TEST_ASSERT(!QDELETED(actor), "the real safety-mode AI survives initialization")
	TEST_ASSERT(issilicon(actor) && !isrobot(actor), "the actual actor is a silicon without robot module APIs")
	var/atom/movable/screen/button = allocate(/atom/movable/screen)
	var/original_name = actor.name
	var/original_location = actor.loc
	var/datum/announcement/priority/original_announcement = actor.announcement
	TEST_ASSERT_NOTNULL(original_announcement, "the real AI owns its initialized announcement before either click")
	button.name = "radio"
	TEST_ASSERT_EQUAL(button.click_with_actor(actor, null, null, null), 1, "the actual radio control safely declines an unsupported silicon")
	button.name = "panel"
	TEST_ASSERT_EQUAL(button.click_with_actor(actor, null, null, null), 1, "the actual module panel control safely declines an unsupported silicon")
	TEST_ASSERT_EQUAL(actor.name, original_name, "declining robot-only controls preserves the actual AI identity")
	TEST_ASSERT_EQUAL(actor.loc, original_location, "declining robot-only controls preserves the actual AI location")
	TEST_ASSERT_EQUAL(actor.announcement, original_announcement, "declining robot-only controls preserves the actual owned AI announcement")
	TEST_ASSERT(!QDELETED(actor), "neither unsupported control destroys its actual silicon actor")

/// Observation chains the real helper and typed prompt instead of replacing either.
/atom/movable/screen/interim_camera_rerun
	var/helper_calls = 0
	var/last_callback
	var/list/last_args

/atom/movable/screen/interim_camera_rerun/click_with_actor(mob/user, location, control, params)
	helper_calls++
	last_args = args.Copy()
	return ..()

/atom/movable/screen/interim_camera_rerun/rerun_ask_proc(mob/user, key, proc_name, list/proc_args, prompt, list/fields)
	last_callback = proc_name
	return ..()

/obj/machinery/camera/interim_screen_prompt_camera
	c_tag = "Interim HUD camera rerun"

/datum/unit_test/om/interim_screen_camera_rerun_actor/run_om(list/made)
	test_prompts_reset()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/camera_turf = get_step(T, EAST)
	TEST_ASSERT_NOTNULL(camera_turf, "the actual camera has a separate destination turf")
	var/mob/living/silicon/ai/actor = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)
	actor.forceMove(T)
	TEST_ASSERT(!actor.check_unable(), "the actual initialized AI can use camera controls")
	var/mob/observer/eye/eye = actor.active_eye()
	TEST_ASSERT_NOTNULL(eye, "the actual initialized AI owns its active eye")
	eye.setLoc(T)
	var/obj/machinery/camera/interim_screen_prompt_camera/camera = allocate(/obj/machinery/camera/interim_screen_prompt_camera, camera_turf)
	TEST_ASSERT(camera.can_use(), "the real initialized camera is usable")
	var/atom/movable/screen/interim_camera_rerun/button = allocate(/atom/movable/screen/interim_camera_rerun)
	button.name = "Show Camera List"
	var/control = "interim_camera_control"
	var/params = "left=1;screen-loc=1,1"
	button.click_with_actor(actor, T, control, params)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the actual camera helper opens exactly one typed prompt")
	var/datum/prompt/choice/ask = GLOB.test_prompts[1]
	made += ask
	TEST_ASSERT_EQUAL(ask.answerer, actor, "the real camera prompt belongs to its explicit AI actor")
	TEST_ASSERT(camera.c_tag in ask.choices, "the actual camera list offers the initialized camera")
	TEST_ASSERT_EQUAL(actor.track.cameras[camera.c_tag], camera, "the real camera list stores the exact initialized camera")
	TEST_ASSERT_EQUAL(button.last_callback, TYPE_PROC_REF(/atom/movable/screen, click_with_actor), "the typed answer resumes the actor helper by its actual proc name")
	TEST_ASSERT_EQUAL(eye.loc, T, "opening the real choice does not move the AI eye")
	TEST_ASSERT_NULL(test_prompt_answer(ask, camera.c_tag), "the real typed camera answer resumes successfully")
	TEST_ASSERT_EQUAL(button.helper_calls, 2, "the actual answer reenters the actor helper exactly once")
	TEST_ASSERT_EQUAL(length(button.last_args), 4, "the resumed helper keeps exactly its four original arguments")
	TEST_ASSERT_EQUAL(button.last_args[1], actor, "the actual rerun preserves the explicit actor argument")
	TEST_ASSERT_EQUAL(button.last_args[2], T, "the actual rerun preserves the location argument")
	TEST_ASSERT_EQUAL(button.last_args[3], control, "the actual rerun preserves the control argument")
	TEST_ASSERT_EQUAL(button.last_args[4], params, "the actual rerun preserves the parameter argument")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the consumed camera answer does not reopen its prompt")
	TEST_ASSERT_EQUAL(eye.loc, camera_turf, "the actual selected camera moves the AI eye to its real turf")
	var/cache_key = "[REF(button)]:[TYPE_PROC_REF(/atom/movable/screen, click_with_actor)]"
	TEST_ASSERT_NULL(GLOB.rerun_answers[cache_key], "the completed real rerun releases its answer cache")
