/obj/machinery/camera/interim_wire_actor_probe
	var/deactivate_actor_ref
	var/deactivate_calls = 0

/obj/machinery/camera/interim_wire_actor_probe/deactivate(mob/user, choice = 1)
	deactivate_actor_ref = user ? REF(user) : null
	deactivate_calls++
	return ..()

/datum/unit_test/interim_camera_wire_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/camera/interim_wire_actor_probe/camera = allocate(/obj/machinery/camera/interim_wire_actor_probe, T)
	var/datum/wires_test_adapter/wires = wires_test(camera)
	TEST_ASSERT(istype(wires), "the actual camera initializes its wire controller")
	TEST_ASSERT(camera.status, "the actual camera starts enabled")
	wires.cut(WIRE_MAIN_POWER1, actor)
	TEST_ASSERT(wires.is_cut(WIRE_MAIN_POWER1) && !camera.status, "cutting the power wire disables the actual camera")
	TEST_ASSERT_EQUAL(camera.deactivate_actor_ref, REF(actor), "cutting forwards the initiating actor to the real deactivate implementation")
	TEST_ASSERT_EQUAL(camera.deactivate_calls, 1, "the cut deactivates once")
	wires.cut(WIRE_MAIN_POWER1, actor)
	TEST_ASSERT(!wires.is_cut(WIRE_MAIN_POWER1) && camera.status, "mending the power wire enables the actual camera")
	TEST_ASSERT_EQUAL(camera.deactivate_actor_ref, REF(actor), "mending retains the initiating actor")
	TEST_ASSERT_EQUAL(camera.deactivate_calls, 2, "the mend reactivates once")
	wires.cut_wire(WIRE_MAIN_POWER1)
	TEST_ASSERT(!camera.status, "ambient damage still disables the actual camera")
	TEST_ASSERT_NULL(camera.deactivate_actor_ref, "ambient damage intentionally has no player actor")
	TEST_ASSERT_EQUAL(camera.deactivate_calls, 3, "ambient damage deactivates once")
	wires.cut_wire(WIRE_MAIN_POWER1, actor)
	TEST_ASSERT_EQUAL(camera.deactivate_calls, 3, "repeated scripted cuts do not toggle an already cut wire")
