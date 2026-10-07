/obj/item/gun/energy/monorifle/interim_actor_probe
	var/zoom_actor_ref
	var/zoom_offset_seen
	var/zoom_view_seen
	var/zoom_calls = 0

/obj/item/gun/energy/monorifle/interim_actor_probe/zoom(mob/living/M, tileoffset = 14, viewsize = 9)
	zoom_actor_ref = M ? REF(M) : null
	zoom_offset_seen = tileoffset
	zoom_view_seen = viewsize
	zoom_calls++
	return ..()

/datum/unit_test/interim_scope_actor_refusal/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/gun/energy/monorifle/interim_actor_probe/device = allocate(/obj/item/gun/energy/monorifle/interim_actor_probe, T)
	TEST_ASSERT_NULL(actor.client, "the fixture exercises actual clientless refusal")
	TEST_ASSERT(actor.put_in_active_hand(device), "the actor holds the actual optical device")
	var/accuracy_before = device.accuracy
	var/recoil_before = device.recoil
	device.monorifle_verb_sights(actor, null, null)
	TEST_ASSERT_EQUAL(device.zoom_calls, 1, "the handler invokes real zoom once")
	TEST_ASSERT_EQUAL(device.zoom_actor_ref, REF(actor), "the handler forwards its actual actor")
	TEST_ASSERT_EQUAL(device.zoom_offset_seen, round(world.view * device.scope_multiplier), "the correct offset remains separate from interaction arguments")
	TEST_ASSERT_EQUAL(device.zoom_view_seen, round(world.view + device.scope_multiplier), "the correct view size remains separate from interaction arguments")
	TEST_ASSERT(!device.zoom && !actor.is_remote_viewing(), "clientless refusal leaves real remote view inactive")
	TEST_ASSERT_EQUAL(device.accuracy, accuracy_before, "refusal preserves gun accuracy")
	TEST_ASSERT_EQUAL(device.recoil, recoil_before, "refusal preserves gun recoil")
	device.ui_action_click(actor, null)
	TEST_ASSERT_EQUAL(device.zoom_calls, 2, "the real UI shortcut uses the declared interaction resolver")
	TEST_ASSERT_EQUAL(device.zoom_actor_ref, REF(actor), "the resolved UI shortcut forwards its actor")
	TEST_ASSERT(!device.zoom, "the resolved clientless UI shortcut preserves inactive zoom")
	device.zoom(null)
	TEST_ASSERT_EQUAL(device.zoom_calls, 3, "a missing actor reaches safe refusal")
	TEST_ASSERT_NULL(device.zoom_actor_ref, "a missing actor does not inherit its previous operator")
	TEST_ASSERT(!device.zoom, "missing actor preserves inactive zoom")

/obj/item/binoculars/interim_actor_probe
	var/zoom_actor_ref
	var/zoom_offset_seen
	var/zoom_view_seen
	var/zoom_calls = 0

/obj/item/binoculars/interim_actor_probe/zoom(mob/living/M, tileoffset = 14, viewsize = 9)
	zoom_actor_ref = M ? REF(M) : null
	zoom_offset_seen = tileoffset
	zoom_view_seen = viewsize
	zoom_calls++
	return ..()

/datum/unit_test/interim_binocular_actor_refusal/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/binoculars/interim_actor_probe/device = allocate(/obj/item/binoculars/interim_actor_probe, T)
	TEST_ASSERT_NULL(actor.client, "the fixture exercises actual clientless refusal")
	TEST_ASSERT(actor.put_in_active_hand(device), "the actor holds the actual optical device")
	TEST_ASSERT(device.attack_self(actor), "the actual self-use dispatcher runs its in_hand() op")
	TEST_ASSERT_EQUAL(device.zoom_calls, 1, "the handler invokes real zoom once")
	TEST_ASSERT_EQUAL(device.zoom_actor_ref, REF(actor), "the handler forwards its actual actor")
	TEST_ASSERT_EQUAL(device.zoom_offset_seen, 14, "the correct offset remains separate from interaction arguments")
	TEST_ASSERT_EQUAL(device.zoom_view_seen, 9, "the correct view size remains separate from interaction arguments")
	TEST_ASSERT(!device.zoom && !actor.is_remote_viewing(), "clientless refusal leaves real remote view inactive")
	device.zoom(null)
	TEST_ASSERT_EQUAL(device.zoom_calls, 2, "a missing actor reaches safe refusal")
	TEST_ASSERT_NULL(device.zoom_actor_ref, "a missing actor does not inherit its previous operator")
	TEST_ASSERT(!device.zoom, "missing actor preserves inactive zoom")

/// Canceling no aim must not create a child, especially while dropping a held gun.
/datum/unit_test/interim_stop_aiming_idle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NULL(actor.aiming, "the idle fixture starts without an aiming overlay")
	actor.stop_aiming()
	TEST_ASSERT_NULL(actor.aiming, "canceling an idle aim does not allocate an overlay")
