/obj/machinery/alarm/interim_wire_actor_probe
	var/shock_actor_ref
	var/shock_chance
	var/shock_calls = 0

/obj/machinery/alarm/interim_wire_actor_probe/shock(mob/user, prb)
	shock_actor_ref = user ? REF(user) : null
	shock_chance = prb
	shock_calls++
	return ..()

/datum/unit_test/interim_air_alarm_wire_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/alarm/interim_wire_actor_probe/alarm = allocate(/obj/machinery/alarm/interim_wire_actor_probe, T)
	// The real shock implementation refuses broken machinery before RNG or sparks.
	dq_machine_clear(alarm)
	alarm.set_broken_condition(TRUE)
	var/datum/wires_test_adapter/wires = wires_test(alarm)
	TEST_ASSERT(istype(wires), "the actual air alarm initializes its wire controller")
	TEST_ASSERT(!alarm.shorted, "the alarm starts without a wiring short")
	wires.cut(WIRE_MAIN_POWER1, actor)
	TEST_ASSERT(wires.is_cut(WIRE_MAIN_POWER1) && alarm.shorted, "cutting power shorts the actual air alarm")
	TEST_ASSERT_EQUAL(alarm.shock_actor_ref, REF(actor), "cutting forwards the actor to the real shock boundary")
	TEST_ASSERT_EQUAL(alarm.shock_chance, 50, "cutting retains the existing shock probability")
	TEST_ASSERT_EQUAL(alarm.shock_calls, 1, "cutting attempts shock once")
	wires.cut(WIRE_MAIN_POWER1, actor)
	TEST_ASSERT(!wires.is_cut(WIRE_MAIN_POWER1) && !alarm.shorted, "mending removes the actual short")
	TEST_ASSERT_EQUAL(alarm.shock_actor_ref, REF(actor), "mending forwards the actor to the real shock boundary")
	TEST_ASSERT_EQUAL(alarm.shock_calls, 2, "mending attempts shock once")
	wires.cut_wire(WIRE_MAIN_POWER1)
	TEST_ASSERT(alarm.shorted, "ambient damage still shorts the actual air alarm")
	TEST_ASSERT_NULL(alarm.shock_actor_ref, "ambient damage intentionally has no initiating actor")
	TEST_ASSERT_EQUAL(alarm.shock_calls, 3, "ambient damage attempts the existing shock boundary once")
	wires.cut_wire(WIRE_MAIN_POWER1, actor)
	TEST_ASSERT_EQUAL(alarm.shock_calls, 3, "repeated scripted cuts leave an already cut wire unchanged")
