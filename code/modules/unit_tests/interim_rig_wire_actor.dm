/// Record the electrical victim without random electrocution obscuring wire state.
/obj/item/rig/interim_wire_actor_probe
	var/shock_actor_ref
	var/shock_count = 0

/obj/item/rig/interim_wire_actor_probe/shock(mob/user)
	shock_actor_ref = user ? REF(user) : null
	shock_count++
	return FALSE

/datum/unit_test/interim_rig_wire_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/rig/interim_wire_actor_probe/rig = allocate(/obj/item/rig/interim_wire_actor_probe, T)
	var/datum/wires/rig/wires = rig.wires
	TEST_ASSERT(istype(wires), "the real RIG initializes its wire controller")
	var/security_before = rig.security_check_enabled
	wires.pulse(WIRE_RIG_SECURITY, actor)
	TEST_ASSERT_EQUAL(rig.security_check_enabled, !security_before, "security pulse toggles the real access gate")
	var/interface_before = rig.interface_locked
	wires.pulse(WIRE_RIG_INTERFACE_LOCK, actor)
	TEST_ASSERT_EQUAL(rig.interface_locked, !interface_before, "interface pulse toggles the real lock")
	wires.pulse(WIRE_RIG_INTERFACE_SHOCK, actor)
	TEST_ASSERT_EQUAL(rig.electrified, 30, "electrification pulse sets the existing temporary shock state")
	TEST_ASSERT_EQUAL(rig.shock_count, 1, "electrification pulse attempts one shock")
	TEST_ASSERT_EQUAL(rig.shock_actor_ref, REF(actor), "pulse targets the explicit actor")
	wires.cut(WIRE_RIG_INTERFACE_SHOCK, actor)
	TEST_ASSERT(wires.is_cut(WIRE_RIG_INTERFACE_SHOCK), "cutting marks the wire cut")
	TEST_ASSERT_EQUAL(rig.electrified, -1, "cutting enables permanent electrification")
	TEST_ASSERT_EQUAL(rig.shock_count, 2, "cutting attempts one additional shock")
	TEST_ASSERT_EQUAL(rig.shock_actor_ref, REF(actor), "cut targets the explicit actor")
	wires.pulse(WIRE_RIG_INTERFACE_SHOCK, actor)
	TEST_ASSERT_EQUAL(rig.shock_count, 2, "a cut wire refuses the pulse before its shock callback")
	wires.cut(WIRE_RIG_INTERFACE_SHOCK, actor)
	TEST_ASSERT(!wires.is_cut(WIRE_RIG_INTERFACE_SHOCK), "cut toggle mends the wire")
	TEST_ASSERT_EQUAL(rig.electrified, 0, "mending removes permanent electrification")
	TEST_ASSERT_EQUAL(rig.shock_count, 3, "mending attempts one additional shock")
	TEST_ASSERT_EQUAL(rig.shock_actor_ref, REF(actor), "mend targets the explicit actor")
	var/malfunction_before = rig.malfunctioning
	wires.pulse(WIRE_RIG_SYSTEM_CONTROL, actor)
	TEST_ASSERT_EQUAL(rig.malfunctioning, malfunction_before + 10, "system-control pulse increases the real malfunction state")
	TEST_ASSERT_EQUAL(rig.shock_count, 4, "system-control pulse attempts one additional shock")
	TEST_ASSERT_EQUAL(rig.shock_actor_ref, REF(actor), "system-control pulse targets the explicit actor")
