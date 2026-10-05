// The wires library's bulk operations on a bare holder: cut-all and mend-all change each wire once, a random cut takes only intact wires, and the
// interactive cut toggles. The holder counts the cut and mend notices it hears.

/obj/wires_unit_test
	var/cuts = 0
	var/mends = 0

CAPABILITIES(/obj/wires_unit_test)
	wires(name = "unit test", count = 2, tools = FALSE, at = null)
	power_wires(count = 2)
	on_notice(/datum/notice/wire_cut, then(PROC_REF(heard_cut)))

/obj/wires_unit_test/proc/heard_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(N.mended)
		mends++
	else
		cuts++

/datum/unit_test/wires_bulk_cut_is_idempotent/Run()
	var/obj/wires_unit_test/H = allocate(/obj/wires_unit_test)

	TEST_ASSERT_EQUAL(wires_cut_all(H), 2, "The first bulk cut should cut every intact wire")
	TEST_ASSERT(wires_all_cut(H), "Every wire should be cut after wires_cut_all()")
	TEST_ASSERT_EQUAL(H.cuts, 2, "Each wire should receive exactly one cut notice")
	TEST_ASSERT_EQUAL(H.mends, 0, "Bulk cutting must not mend wires")

	TEST_ASSERT_EQUAL(wires_cut_all(H), 0, "A repeated bulk cut should make no changes")
	TEST_ASSERT(wires_all_cut(H), "Repeated bulk cutting must leave every wire cut")
	TEST_ASSERT_EQUAL(H.cuts, 2, "Repeated bulk cutting must not repeat notices")
	TEST_ASSERT_EQUAL(H.mends, 0, "Repeated bulk cutting must never mend wires")

	TEST_ASSERT_EQUAL(wires_mend_all(H), 2, "Bulk mending should mend every cut wire")
	TEST_ASSERT(!wires_all_cut(H), "Bulk mending should leave the wires intact")
	TEST_ASSERT_EQUAL(H.mends, 2, "Each cut wire should receive exactly one mend notice")
	TEST_ASSERT_EQUAL(wires_mend_all(H), 0, "Repeated bulk mending should make no changes")
	TEST_ASSERT_EQUAL(H.mends, 2, "Repeated bulk mending must not repeat notices")

/datum/unit_test/wires_random_cut_only_targets_intact_wires/Run()
	var/obj/wires_unit_test/H = allocate(/obj/wires_unit_test)

	TEST_ASSERT(wires_cut_random(H), "The first random cut should cut an intact wire")
	TEST_ASSERT(wires_cut_random(H), "The second random cut should cut the remaining intact wire")
	TEST_ASSERT(wires_all_cut(H), "Random cuts should eventually cut every wire")
	TEST_ASSERT(!wires_cut_random(H), "Random cutting should be a no-op when every wire is cut")
	TEST_ASSERT_EQUAL(H.cuts, 2, "Random cutting should cut each wire once")
	TEST_ASSERT_EQUAL(H.mends, 0, "Random cutting must never mend wires")

/datum/unit_test/wires_interactive_cut_remains_a_toggle/Run()
	var/obj/wires_unit_test/H = allocate(/obj/wires_unit_test)

	wires_toggle(H, WIRE_MAIN_POWER1)
	TEST_ASSERT(wire_is_cut(H, WIRE_MAIN_POWER1), "Interactive cutting should cut an intact wire")
	wires_toggle(H, WIRE_MAIN_POWER1)
	TEST_ASSERT(!wire_is_cut(H, WIRE_MAIN_POWER1), "Interactive cutting should mend a cut wire")
	TEST_ASSERT_EQUAL(H.cuts, 1, "Interactive cutting should issue one cut notice")
	TEST_ASSERT_EQUAL(H.mends, 1, "Interactive mending should issue one mend notice")

// ---------------------------------------------------------------------------------------------------------------------
// Composed wires: a capability brings its wires to every holder that has it, and the wire's effect is the capability's, the same on each holder.

/// Every holder that has a wire-bringing library capability has that capability's wires, and its wire list is exactly what its capabilities bring
/// (plus duds).
/datum/unit_test/dq_wires_capability_brings_its_wire/Run()
	var/turf/T = test_floor()
	var/list/holders = list(/obj/machinery/alarm, /obj/machinery/power/shield_generator, /obj/machinery/door/airlock, /obj/machinery/vending,
		/obj/machinery/smartfridge, /obj/machinery/suit_cycler, /obj/machinery/autolathe, /obj/machinery/rnd/production/protolathe,
		/obj/machinery/rnd/destructive_analyzer, /obj/machinery/seed_storage, /obj/machinery/p2_box)
	var/list/cap_ids = list(CAP_AI_CONTROL, CAP_POWER_WIRES, CAP_SHOCK_WIRE, CAP_ID_SCAN, CAP_ITEM_THROW, CAP_SAFETY_WIRE, CAP_LATHE_WIRES, CAP_BOLTS, CAP_LOCK)
	var/list/seen = list()
	for(var/path in holders)
		var/atom/H = allocate(path, T)
		var/list/all = wires_all(H)
		for(var/cap_id in cap_ids)
			var/datum/capability/C = cap_of(H, cap_id)
			if(!C)
				continue
			for(var/wire in C.brings_wires())
				seen["[cap_id]"] = TRUE
				TEST_ASSERT(wire in all, "[path] has [wire]: its [C.type] brings it")
		var/list/real = list()
		for(var/wire in all)
			if(!wire_is_dud(wire))
				real += wire
		var/list/brought = wire_bringers(H)
		TEST_ASSERT_EQUAL(length(real), length(brought), "[path]: its working wires are what its capabilities bring")
		for(var/wire in brought)
			TEST_ASSERT(wire in real, "[path]: [wire] is brought and laid out")
	for(var/cap_id in list(CAP_AI_CONTROL, CAP_POWER_WIRES, CAP_SHOCK_WIRE, CAP_ID_SCAN, CAP_ITEM_THROW, CAP_SAFETY_WIRE, CAP_LATHE_WIRES, CAP_BOLTS))
		TEST_ASSERT(seen["[cap_id]"], "capability [cap_id] brought its wire to a holder")

/// Two holders that share a wire share its effect: the AI control wire on an air alarm and an airlock (ai_control(), each its own stat and
/// pulse length), and the lathe wires on an autolathe and a protolathe (lathe_wires()). Cut holds the stat, mending releases it, a pulse holds it
/// for the capability's time, one keyed hold however often it is pulsed, and a pulse running out leaves a cut wire's hold in place.
/datum/unit_test/dq_wires_shared_wire_shares_its_effect/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/obj/machinery/alarm/alarm = allocate(/obj/machinery/alarm, T)
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, T)
	TEST_ASSERT(!alarm.aidisabled && !door.aiControlDisabled, "the AI starts in control of both")
	wires_cut(alarm, WIRE_AI_CONTROL)
	wires_cut(door, WIRE_AI_CONTROL)
	TEST_ASSERT(alarm.aidisabled && door.aiControlDisabled, "the cut AI control wire locks the AI out of both")
	wires_mend(alarm, WIRE_AI_CONTROL)
	wires_mend(door, WIRE_AI_CONTROL)
	TEST_ASSERT(!alarm.aidisabled && !door.aiControlDisabled, "mended, the AI is back in both")
	wires_pulse(alarm, WIRE_AI_CONTROL)
	wires_pulse(door, WIRE_AI_CONTROL)
	wires_pulse(door, WIRE_AI_CONTROL)
	TEST_ASSERT(alarm.aidisabled && door.aiControlDisabled, "a pulse locks the AI out of both")
	TEST_ASSERT_EQUAL(length(held_by(door, STAT_AICONTROLDISABLED)), 1, "two pulses are one keyed hold")
	test_time(2 SECONDS)
	TEST_ASSERT(!door.aiControlDisabled, "the airlock's one-second pulse has run out")
	TEST_ASSERT(alarm.aidisabled, "the alarm's ten-second pulse has not")
	wires_cut(alarm, WIRE_AI_CONTROL)
	test_time(10 SECONDS)
	TEST_ASSERT(alarm.aidisabled, "a pulse running out leaves the cut wire's hold")
	wires_mend(alarm, WIRE_AI_CONTROL)
	TEST_ASSERT(!alarm.aidisabled, "mended, the AI is back")

	var/obj/machinery/autolathe/lathe = allocate(/obj/machinery/autolathe, T)
	var/obj/machinery/rnd/production/protolathe/proto = allocate(/obj/machinery/rnd/production/protolathe, T)
	for(var/obj/machinery/M as anything in list(lathe, proto))
		wires_cut(M, WIRE_LATHE_DISABLE)
	TEST_ASSERT(lathe.disabled && proto.disabled, "the cut disable wire stops both lathes")
	for(var/obj/machinery/M as anything in list(lathe, proto))
		wires_mend(M, WIRE_LATHE_DISABLE)
		wires_pulse(M, WIRE_LATHE_HACK)
	TEST_ASSERT(!lathe.disabled && !proto.disabled, "mended, both work")
	TEST_ASSERT(lathe.hacked && proto.hacked, "a hack pulse unlocks both")
	test_time(6 SECONDS)
	TEST_ASSERT(!lathe.hacked && !proto.hacked, "and runs out on both after five seconds")
