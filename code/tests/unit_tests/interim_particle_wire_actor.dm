/// Assembled state is fixture data; this test exercises power and strength control, not construction.
/obj/machinery/particle_accelerator/control_box/interim_wire_actor_probe
	assembled = TRUE
	var/strength_actor_ref
	var/power_actor_ref
	var/power_calls = 0
	var/add_calls = 0
	var/remove_calls = 0

/obj/machinery/particle_accelerator/control_box/interim_wire_actor_probe/add_strength(mob/user, s)
	strength_actor_ref = user ? REF(user) : null
	add_calls++
	return ..()

/obj/machinery/particle_accelerator/control_box/interim_wire_actor_probe/remove_strength(mob/user, s)
	strength_actor_ref = user ? REF(user) : null
	remove_calls++
	return ..()

/obj/machinery/particle_accelerator/control_box/interim_wire_actor_probe/toggle_power(mob/user)
	power_actor_ref = user ? REF(user) : null
	power_calls++
	return ..()

/datum/unit_test/interim_particle_wire_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/particle_accelerator/control_box/interim_wire_actor_probe/control = allocate(/obj/machinery/particle_accelerator/control_box/interim_wire_actor_probe, T)
	var/datum/wires_test_adapter/wires = wires_test(control)
	TEST_ASSERT(istype(wires), "the real control box initializes its wire controller")
	TEST_ASSERT(control.assembled, "the fixture provides assembled control state")
	TEST_ASSERT_EQUAL(control.strength, 0, "the actual control starts at zero strength")
	TEST_ASSERT(!control.active, "the actual control starts powered off")
	wires.pulse(WIRE_PARTICLE_POWER, actor)
	TEST_ASSERT(control.active, "the real power pulse turns the control on")
	TEST_ASSERT_EQUAL(control.power_actor_ref, REF(actor), "power pulse forwards the actual operator to parent logging")
	TEST_ASSERT_EQUAL(control.power_calls, 1, "power pulse calls the actual toggle once")
	wires.cut(WIRE_PARTICLE_POWER, actor)
	TEST_ASSERT(!control.active, "cutting the powered control wire turns it off")
	TEST_ASSERT_EQUAL(control.power_actor_ref, REF(actor), "power cutting forwards the actual operator to parent logging")
	TEST_ASSERT_EQUAL(control.power_calls, 2, "power cutting calls the actual toggle once")
	wires.pulse(WIRE_PARTICLE_POWER, actor)
	TEST_ASSERT(!control.active, "a cut power wire refuses further pulses")
	TEST_ASSERT_EQUAL(control.power_calls, 2, "a refused pulse cannot call the power toggle")
	wires.cut(WIRE_PARTICLE_POWER, actor)
	TEST_ASSERT(control.active, "mending the power wire restores the actual on state")
	TEST_ASSERT_EQUAL(control.power_actor_ref, REF(actor), "power mending retains the actor")
	TEST_ASSERT_EQUAL(control.power_calls, 3, "mending calls the actual parent toggle once")
	wires.pulse(WIRE_PARTICLE_POWER, actor)
	TEST_ASSERT(!control.active, "a pulse after mending can turn the control back off")
	TEST_ASSERT_EQUAL(control.power_calls, 4, "restored pulses run the actual toggle")
	wires.pulse(WIRE_PARTICLE_STRENGTH, actor)
	TEST_ASSERT_EQUAL(control.strength, 1, "the real parent increases strength through a wire pulse")
	TEST_ASSERT_EQUAL(control.strength_actor_ref, REF(actor), "the strength pulse forwards its actor")
	wires.pulse(WIRE_PARTICLE_STRENGTH, actor)
	wires.pulse(WIRE_PARTICLE_STRENGTH, actor)
	TEST_ASSERT_EQUAL(control.strength, 2, "the real parent clamps strength at the normal limit")
	wires.cut(WIRE_PARTICLE_POWER_LIMIT, actor)
	TEST_ASSERT_EQUAL(control.strength_upper_limit, 3, "cutting the limit wire permits maximum strength")
	wires.pulse(WIRE_PARTICLE_STRENGTH, actor)
	TEST_ASSERT_EQUAL(control.strength, 3, "a subsequent real pulse reaches the unlocked limit")
	wires.cut(WIRE_PARTICLE_POWER_LIMIT, actor)
	TEST_ASSERT_EQUAL(control.strength, 2, "mending the limit wire reduces actual strength to the safe limit")
	TEST_ASSERT_EQUAL(control.strength_actor_ref, REF(actor), "limit mending forwards the actor to real reduction and logging")
	TEST_ASSERT_EQUAL(control.remove_calls, 1, "limit mending performs one reduction")
	wires.cut(WIRE_PARTICLE_STRENGTH, actor)
	TEST_ASSERT_EQUAL(control.strength, 0, "cutting strength performs the existing two real reductions")
	TEST_ASSERT_EQUAL(control.strength_actor_ref, REF(actor), "both strength reductions retain the actor")
	TEST_ASSERT_EQUAL(control.remove_calls, 3, "strength cutting performs two reduction calls")
	var/add_before = control.add_calls
	wires.pulse(WIRE_PARTICLE_STRENGTH, actor)
	TEST_ASSERT_EQUAL(control.add_calls, add_before, "a cut strength wire refuses further pulses")
	wires.cut(WIRE_PARTICLE_STRENGTH, actor)
	wires.pulse(WIRE_PARTICLE_STRENGTH, actor)
	wires.pulse(WIRE_PARTICLE_STRENGTH, actor)
	TEST_ASSERT_EQUAL(control.strength, 2, "mending restores actual pulse control")
	wires.cut_wire(WIRE_PARTICLE_STRENGTH)
	TEST_ASSERT_EQUAL(control.strength, 0, "scripted ambient cutting still performs actual reductions without a null-actor logging runtime")
	TEST_ASSERT_NULL(control.strength_actor_ref, "ambient cutting intentionally has no player operator")
