// spawns() (code/library/transformations/transformation_spawns.dm): what a transformation step makes. Fixture rules of a regime of their own, so
// they never touch a real reagent holder or the dq_fixture rules.

#define DQ_SPAWN_REGIME "dq_spawn_fixture"

/datum/reagents/dq_spawn_fixture

/datum/reagents/dq_spawn_fixture/xform_regime()
	return DQ_SPAWN_REGIME

/// What the probes were made in, in order (a test clears it before and after).
GLOBAL_LIST_EMPTY(dq_spawn_log)

GLOBAL_LIST_INIT(dq_spawn_weights, list(/obj/item/dq_spawn_probe/a = 1, /obj/item/dq_spawn_probe/b = 1))

/obj/item/dq_spawn_probe

/obj/item/dq_spawn_probe/Initialize(mapload, ...)
	. = ..()
	GLOB.dq_spawn_log += type

/obj/item/dq_spawn_probe/a

/obj/item/dq_spawn_probe/b

/obj/item/dq_spawn_probe/c

/transformation/dq_spawn

CAPABILITIES(/transformation/dq_spawn)
	transformation(regime = DQ_SPAWN_REGIME, says = "")

/// Three probes every step, whatever the extent.
/transformation/dq_spawn/per_step

CAPABILITIES(/transformation/dq_spawn/per_step)
	configure(transformation(takes = list(reagent(REAGENT_ID_CHLORINE, 1)), made = 1, spawns = spawns(/obj/item/dq_spawn_probe, 3)))

/// One probe per whole unit made; the rule makes 2 per reaction unit.
/transformation/dq_spawn/per_made

CAPABILITIES(/transformation/dq_spawn/per_made)
	configure(transformation(takes = list(reagent(REAGENT_ID_MERCURY, 1)), made = 2, spawns = spawns(/obj/item/dq_spawn_probe, 1, per = SPAWN_PER_MADE)))

/// One stack of what was made.
/transformation/dq_spawn/stack

CAPABILITIES(/transformation/dq_spawn/stack)
	configure(transformation(takes = list(reagent(REAGENT_ID_TUNGSTEN, 1)), made = 1, spawns = spawns(/obj/item/stack/material/steel, 1, per = SPAWN_STACK_MADE)))

/// Two rows: two a, then one b.
/transformation/dq_spawn/ordered

CAPABILITIES(/transformation/dq_spawn/ordered)
	configure(transformation(takes = list(reagent(REAGENT_ID_SILVER, 1)), made = 1, spawns = list(spawns(/obj/item/dq_spawn_probe/a, 2), spawns(/obj/item/dq_spawn_probe/b, 1))))

/// Eight drawn by weight.
/transformation/dq_spawn/weighted

CAPABILITIES(/transformation/dq_spawn/weighted)
	configure(transformation(takes = list(reagent(REAGENT_ID_PLATINUM, 1)), made = 1, spawns = spawns(list(/obj/item/dq_spawn_probe/a = 1, /obj/item/dq_spawn_probe/b = 2, /obj/item/dq_spawn_probe/c = 3), 8)))

/// Drawn from a global list named in the entry.
/transformation/dq_spawn/from_global

CAPABILITIES(/transformation/dq_spawn/from_global)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLUORINE, 1)), made = 1, spawns = spawns("dq_spawn_weights", 4)))

/// Five, each shoved up to three steps away.
/transformation/dq_spawn/scattered

CAPABILITIES(/transformation/dq_spawn/scattered)
	configure(transformation(takes = list(reagent(REAGENT_ID_GOLD, 1)), made = 1, spawns = spawns(/obj/item/dq_spawn_probe, 5, scatter = 3)))

/// A random count.
/transformation/dq_spawn/ranged

CAPABILITIES(/transformation/dq_spawn/ranged)
	configure(transformation(takes = list(reagent(REAGENT_ID_CALCIUM, 1)), made = 1, spawns = spawns(/obj/item/dq_spawn_probe, list(2, 4))))

/// A made fixture holder inside a beaker, ready to fill.
/datum/unit_test/proc/dq_spawn_holder(turf/T)
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker, T || test_floor())
	var/datum/reagents/dq_spawn_fixture/H = new(1000, B)
	own(H)
	return H

/// The probes lying on `T`.
/datum/unit_test/proc/dq_spawn_probes_on(turf/T)
	. = list()
	for(var/obj/item/dq_spawn_probe/P in T)
		. += P

/// Deletes the products a spawns() test left, and clears the log.
/datum/unit_test/proc/dq_spawn_cleanup(turf/T)
	for(var/obj/item/dq_spawn_probe/P in T)
		qdel(P)
	for(var/obj/item/stack/material/steel/S in T)
		qdel(S)
	GLOB.dq_spawn_log.Cut()

/datum/unit_test/dq_xform_spawns_counts
	boot_needs = list()

/datum/unit_test/dq_xform_spawns_counts/Run()
	var/turf/T = test_floor()
	GLOB.dq_spawn_log.Cut()
	// SPAWN_PER_STEP: three each step, whatever the extent.
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_CHLORINE, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(length(dq_spawn_probes_on(T)), 3, "one unit: three probes")
	dq_spawn_cleanup(T)
	H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_CHLORINE, 40, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(length(dq_spawn_probes_on(T)), 3, "forty units go in one step: still three probes")
	dq_spawn_cleanup(T)
	// SPAWN_PER_MADE: n * FLOOR(made), made = 2 per reaction unit.
	H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_MERCURY, 5, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(length(dq_spawn_probes_on(T)), 10, "5 units make 10: ten probes")
	dq_spawn_cleanup(T)
	H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_MERCURY, 2.4, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(length(dq_spawn_probes_on(T)), 4, "2.4 units make 4.8: four probes, the fraction is not a probe")
	dq_spawn_cleanup(T)
	H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_MERCURY, 0.4, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(length(dq_spawn_probes_on(T)), 0, "0.4 units make 0.8: nothing")
	dq_spawn_cleanup(T)
	// SPAWN_STACK_MADE: one stack of what was made.
	H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_TUNGSTEN, 7, safety = 1)
	xform_settle_reagents(H)
	var/list/stacks = list()
	for(var/obj/item/stack/material/steel/S in T)
		stacks += S
	TEST_ASSERT_EQUAL(length(stacks), 1, "one stack")
	var/obj/item/stack/material/steel/stack = stacks[1]
	TEST_ASSERT_EQUAL(stack.amount, 7, "of 7 units")
	dq_spawn_cleanup(T)
	H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_TUNGSTEN, 0.5, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT(!(locate(/obj/item/stack/material/steel) in T), "half a unit makes no stack")
	// A count range rolls inside its bounds.
	for(var/round in 1 to 12)
		H = dq_spawn_holder(T)
		H.add_reagent(REAGENT_ID_CALCIUM, 1, safety = 1)
		xform_settle_reagents(H)
		var/got = length(dq_spawn_probes_on(T))
		TEST_ASSERT(got >= 2 && got <= 4, "a range of 2 to 4 made [got]")
		dq_spawn_cleanup(T)
	TEST_ASSERT_EQUAL(length(dq_spawn_probes_on(T)), 0, "the test left nothing behind")

/datum/unit_test/dq_xform_spawns_place_and_order
	boot_needs = list()

/datum/unit_test/dq_xform_spawns_place_and_order/Run()
	var/turf/T = test_floor()
	GLOB.dq_spawn_log.Cut()
	// Where: on the turf of the subject, not inside it.
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_CHLORINE, 1, safety = 1)
	xform_settle_reagents(H)
	for(var/obj/item/dq_spawn_probe/P as anything in dq_spawn_probes_on(T))
		TEST_ASSERT_EQUAL(P.loc, T, "a probe is on the turf of the subject")
	var/obj/item/reagent_containers/glass/beaker/B = H.my_atom
	TEST_ASSERT(!(locate(/obj/item/dq_spawn_probe) in B), "and none went into the beaker")
	dq_spawn_cleanup(T)
	// Order: rows in declaration order, copies in order.
	H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_SILVER, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(GLOB.dq_spawn_log.len, 3, "three made")
	TEST_ASSERT(GLOB.dq_spawn_log[1] == /obj/item/dq_spawn_probe/a && GLOB.dq_spawn_log[2] == /obj/item/dq_spawn_probe/a && GLOB.dq_spawn_log[3] == /obj/item/dq_spawn_probe/b, "two a, then one b")
	dq_spawn_cleanup(T)
	// Weighted draws are the pickweight() sequence of the seed, one draw per copy.
	var/list/weights = list(/obj/item/dq_spawn_probe/a = 1, /obj/item/dq_spawn_probe/b = 2, /obj/item/dq_spawn_probe/c = 3)
	rand_seed(7001)
	var/list/expected = list()
	for(var/i in 1 to 8)
		expected += pickweight(weights)
	rand_seed(7001)
	H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_PLATINUM, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(GLOB.dq_spawn_log.len, 8, "eight drawn")
	for(var/i in 1 to 8)
		TEST_ASSERT_EQUAL(GLOB.dq_spawn_log[i], expected[i], "draw [i] is the seed's draw")
	dq_spawn_cleanup(T)
	// The same seed gives the same sequence twice.
	rand_seed(7001)
	H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_PLATINUM, 1, safety = 1)
	xform_settle_reagents(H)
	for(var/i in 1 to 8)
		TEST_ASSERT_EQUAL(GLOB.dq_spawn_log[i], expected[i], "replay draw [i]")
	dq_spawn_cleanup(T)
	// A global list named in the entry is read when the step goes.
	H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_FLUORINE, 1, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(GLOB.dq_spawn_log.len, 4, "four from the global list")
	for(var/type in GLOB.dq_spawn_log)
		TEST_ASSERT(type == /obj/item/dq_spawn_probe/a || type == /obj/item/dq_spawn_probe/b, "only what the list names")
	dq_spawn_cleanup(T)
	// Scatter: every copy takes at least one step (the legacy loop re-rolled its bound after each step, so how far is a geometric tail, not a cap).
	H = dq_spawn_holder(T)
	H.add_reagent(REAGENT_ID_GOLD, 1, safety = 1)
	xform_settle_reagents(H)
	var/found = 0
	var/moved = 0
	for(var/obj/item/dq_spawn_probe/P in world)
		if(QDELETED(P))
			continue
		found++
		if(P.loc != T)
			moved++
		qdel(P)
	TEST_ASSERT_EQUAL(found, 5, "five scattered copies")
	TEST_ASSERT(moved >= 1, "scattering moved at least one copy off the turf")
	GLOB.dq_spawn_log.Cut()

/datum/unit_test/dq_xform_spawns_heat_and_safety
	boot_needs = list()

/datum/unit_test/dq_xform_spawns_heat_and_safety/Run()
	var/turf/T = test_floor()
	GLOB.dq_spawn_log.Cut()
	// Heat: the copies start at the temperature the subject had.
	var/datum/reagents/dq_spawn_fixture/H = dq_spawn_holder(T)
	var/obj/item/reagent_containers/glass/beaker/B = H.my_atom
	var/list/properties = B.thermal_properties()
	B.add_heat(properties[THERMAL_CAPACITY] * 40)
	var/hot = B.get_temperature()
	TEST_ASSERT(hot > T20C + 20, "the subject is warm ([hot] K)")
	H.add_reagent(REAGENT_ID_CHLORINE, 1, safety = 1)
	xform_settle_reagents(H)
	var/list/probes = dq_spawn_probes_on(T)
	TEST_ASSERT_EQUAL(length(probes), 3, "three probes")
	for(var/obj/item/dq_spawn_probe/P as anything in probes)
		TEST_ASSERT(abs(P.get_temperature() - hot) < 2, "a probe starts at the subject's temperature (probe [P.get_temperature()] K, subject [hot] K)")
	dq_spawn_cleanup(T)
	// A subject that is gone spawns nothing, and nothing runtimes.
	H = dq_spawn_holder(T)
	var/datum/xform/gone_rule = xform_of(/transformation/dq_spawn/per_step)
	var/obj/doomed = H.my_atom
	qdel(doomed)
	xform_run_spawns(gone_rule, H, 1)
	TEST_ASSERT_EQUAL(length(dq_spawn_probes_on(T)), 0, "a deleted subject spawns nothing")
	// A subject in nullspace has no turf: nothing either.
	H = dq_spawn_holder(T)
	var/obj/item/reagent_containers/glass/beaker/lost = H.my_atom
	lost.moveToNullspace()
	xform_run_spawns(gone_rule, H, 1)
	TEST_ASSERT_EQUAL(length(dq_spawn_probes_on(T)), 0, "a subject off the map spawns nothing")
	lost.forceMove(T)
	// The declaration refuses what is not built.
	var/list/reported = list()
	GLOB.declare_report_capture = reported
	TEST_ASSERT_NULL(xform_spawn_rows(/transformation/dq_spawn, "test", spawns(null)), "no what")
	TEST_ASSERT_NULL(xform_spawn_rows(/transformation/dq_spawn, "test", spawns(/obj/item/dq_spawn_probe, at = "elsewhere")), "an unbuilt place")
	TEST_ASSERT_NULL(xform_spawn_rows(/transformation/dq_spawn, "test", spawns(/obj/item/dq_spawn_probe, per = "often")), "an unknown scaling")
	TEST_ASSERT_NULL(xform_spawn_rows(/transformation/dq_spawn, "test", spawns(/obj/item/dq_spawn_probe, n = "many")), "a count that is not a number")
	TEST_ASSERT_NULL(xform_spawn_rows(/transformation/dq_spawn, "test", spawns(/obj/item/dq_spawn_probe, per = SPAWN_STACK_MADE)), "a stack of something that is not a stack")
	TEST_ASSERT_NULL(xform_spawn_rows(/transformation/dq_spawn, "test", list()), "no rows")
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(reported), 6, "each refusal was reported ([jointext(reported, "; ")])")
	var/list/good = xform_spawn_rows(/transformation/dq_spawn, "test", spawns(/obj/item/dq_spawn_probe, 2, scatter = 1))
	TEST_ASSERT_EQUAL(length(good), 1, "a good row compiles")
	// Nothing leaks.
	TEST_ASSERT_EQUAL(length(dq_spawn_probes_on(T)), 0, "no probe is left")
	GLOB.dq_spawn_log.Cut()
