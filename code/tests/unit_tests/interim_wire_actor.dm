/// Capture the real shock call without changing its machinery implementation.
/obj/machinery/media/jukebox/interim_actor_probe
	var/shock_actor_ref
	var/shock_chance
	var/shock_calls = 0

/obj/machinery/media/jukebox/interim_actor_probe/shock(mob/user, prb)
	shock_actor_ref = user ? REF(user) : null
	shock_chance = prb
	shock_calls++
	return ..()

/obj/machinery/power/grid_checker/interim_actor_probe
	var/shock_actor_ref
	var/shock_chance
	var/shock_calls = 0

/obj/machinery/power/grid_checker/interim_actor_probe/shock(mob/user, prb)
	shock_actor_ref = user ? REF(user) : null
	shock_chance = prb
	shock_calls++
	return ..()

/datum/unit_test/interim_jukebox_wire_actor/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/media/jukebox/interim_actor_probe/machine = allocate(/obj/machinery/media/jukebox/interim_actor_probe, T)
	// The parent shock implementation refuses broken machines before RNG or sparks.
	dq_machine_clear(machine)
	machine.set_broken_condition(TRUE)
	var/datum/wires_test_adapter/wires = wires_test(machine)
	TEST_ASSERT(wires, "The real jukebox must create its wires")
	wires.cut(WIRE_MAIN_POWER1, actor)
	TEST_ASSERT(wires.is_cut(WIRE_MAIN_POWER1), "Cutting power must change the actual wire state")
	TEST_ASSERT_EQUAL(machine.shock_actor_ref, REF(actor), "Power cutting must forward its actor to the real shock boundary")
	TEST_ASSERT_EQUAL(machine.shock_chance, 90, "Power cutting must retain its shock chance")
	wires.cut(WIRE_MAIN_POWER1, actor)
	TEST_ASSERT(!wires.is_cut(WIRE_MAIN_POWER1), "Mending power must restore the actual wire")
	machine.shock_actor_ref = null
	wires.pulse(WIRE_MAIN_POWER1, actor)
	TEST_ASSERT_EQUAL(machine.shock_actor_ref, REF(actor), "Power pulsing must forward its actor")
	var/list/unused_wires = wires.all_wires() - list(WIRE_MAIN_POWER1, WIRE_JUKEBOX_HACK, WIRE_SPEEDUP, WIRE_SPEEDDOWN, WIRE_REVERSE, WIRE_START, WIRE_STOP, WIRE_PREV, WIRE_NEXT)
	TEST_ASSERT(length(unused_wires), "The real jukebox wiring must contain an unused wire")
	wires.pulse(unused_wires[1], actor)
	TEST_ASSERT_EQUAL(machine.shock_chance, 10, "An unused wire must retain its distinct shock chance")
	TEST_ASSERT_EQUAL(machine.shock_actor_ref, REF(actor), "The unused-wire pulse must forward its actor")
	wires.cut(WIRE_JUKEBOX_HACK, actor)
	TEST_ASSERT(machine.hacked, "Cutting the parental guidance wire must hack the real jukebox")
	wires.cut(WIRE_JUKEBOX_HACK, actor)
	TEST_ASSERT(!machine.hacked, "Mending the parental guidance wire must clear hacking")
	wires.cut(WIRE_SPEEDUP, actor)
	TEST_ASSERT_EQUAL(machine.freq, 2, "Cutting speed-up must double playback frequency")
	wires.cut(WIRE_REVERSE, actor)
	TEST_ASSERT_EQUAL(machine.freq, -2, "Cutting reverse must invert the sped-up frequency")
	wires.cut(WIRE_SPEEDUP, actor)
	wires.cut(WIRE_REVERSE, actor)
	TEST_ASSERT_EQUAL(machine.freq, 1, "Mending both playback wires must restore normal frequency")

/datum/unit_test/interim_grid_checker_wire_actor/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/grid_checker/interim_actor_probe/machine = allocate(/obj/machinery/power/grid_checker/interim_actor_probe, T)
	dq_machine_clear(machine)
	machine.set_broken_condition(TRUE)
	var/datum/wires_test_adapter/wires = wires_test(machine)
	TEST_ASSERT(wires, "The real grid checker must create its wires")
	wires.cut(WIRE_ELECTRIFY, actor)
	TEST_ASSERT(wires.is_cut(WIRE_ELECTRIFY), "Electrify cutting must change actual wire state")
	TEST_ASSERT_EQUAL(machine.shock_actor_ref, REF(actor), "Electrify cutting must forward its actor")
	TEST_ASSERT_EQUAL(machine.shock_chance, 70, "Electrify cutting must retain its shock chance")
	wires.cut(WIRE_ELECTRIFY, actor)
	machine.shock_actor_ref = null
	wires.pulse(WIRE_ELECTRIFY, actor)
	TEST_ASSERT_EQUAL(machine.shock_actor_ref, REF(actor), "Electrify pulsing must forward its actor")
	wires.cut(WIRE_ALLOW_MANUAL1, actor)
	TEST_ASSERT(machine.wire_allow_manual_1, "Cutting manual wire must enable its real manual flag")
	wires.cut(WIRE_ALLOW_MANUAL1, actor)
	TEST_ASSERT(!machine.wire_allow_manual_1, "Mending manual wire must clear its flag")
	wires.cut(WIRE_LOCKOUT, actor)
	TEST_ASSERT(machine.wire_locked_out, "Cutting lockout must lock out the real controller")
	var/calls_before = machine.shock_calls
	wires.pulse(WIRE_ELECTRIFY, actor)
	TEST_ASSERT_EQUAL(machine.shock_calls, calls_before, "Lockout must prevent an electrify pulse from attempting shock")
	wires.cut(WIRE_LOCKOUT, actor)
	TEST_ASSERT(!machine.wire_locked_out, "Mending lockout must unlock the controller")
	wires.pulse(WIRE_ELECTRIFY, actor)
	TEST_ASSERT_EQUAL(machine.shock_calls, calls_before + 1, "Unlocked electrify pulsing must resume shock attempts")
