// setup(PROC_REF(x), early = TRUE) (code/engine/lifeforms/setup.dm): the hook that is the head of an Initialize(), run in phase 0 before the
// chain, ancestors first; and the three sites that used to override Initialize() for it (space, the angled bay airlock, the belly).

/obj/dq_setup_early_probe
	/// The handlers that ran, in order.
	var/list/ran
	/// Whether the atom was already initialized when the first hook ran.
	var/initialized_at_hook = -1
	/// What the Initialize() body saw of the hooks when it began.
	var/hooks_seen_by_initialize = -1

/obj/dq_setup_early_probe/Initialize(mapload)
	hooks_seen_by_initialize = length(ran)
	return ..()

/obj/dq_setup_early_probe/proc/early_first()
	if(!length(ran))
		initialized_at_hook = !!(flags & ATOM_INITIALIZED)
	LAZYADD(ran, "first")

/obj/dq_setup_early_probe/proc/early_second()
	LAZYADD(ran, "second")

/obj/dq_setup_early_probe/proc/early_child()
	LAZYADD(ran, "child")

/obj/dq_setup_early_probe/child

CAPABILITIES(/obj/dq_setup_early_probe)
	setup(PROC_REF(early_first), early = TRUE)
	setup(PROC_REF(early_second), early = TRUE)

CAPABILITIES(/obj/dq_setup_early_probe/child)
	setup(PROC_REF(early_child), early = TRUE)
	setup(PROC_REF(early_first), early = TRUE) // the same proc as the parent's: keyed by it, runs once

/datum/unit_test/dq_setup_early_before_chain

/datum/unit_test/dq_setup_early_before_chain/Run()
	var/turf/T = dq_containment_floor()
	var/obj/dq_setup_early_probe/probe = allocate(/obj/dq_setup_early_probe, T)
	TEST_ASSERT_EQUAL(probe.initialized_at_hook, 0, "the hook ran before the atom was initialized")
	TEST_ASSERT_EQUAL(probe.hooks_seen_by_initialize, 2, "and both hooks had run when the Initialize() body began")
	TEST_ASSERT_EQUAL(jointext(probe.ran, ","), "first,second", "in declaration order")
	TEST_ASSERT(probe.flags & ATOM_INITIALIZED, "and the atom initialized after them")

/datum/unit_test/dq_setup_early_subtype_inherits

/datum/unit_test/dq_setup_early_subtype_inherits/Run()
	var/turf/T = dq_containment_floor()
	var/obj/dq_setup_early_probe/child/probe = allocate(/obj/dq_setup_early_probe/child, T)
	TEST_ASSERT_EQUAL(jointext(probe.ran, ","), "first,second,child", "a subtype runs its parent's hooks first, then its own, a repeated proc once")

// The three converted sites.
/datum/unit_test/dq_setup_early_angled_bay_fill

/datum/unit_test/dq_setup_early_angled_bay_fill/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/door/airlock/angled_bay/standard/metal = allocate(/obj/machinery/door/airlock/angled_bay/standard, T)
	TEST_ASSERT(!metal.glass, "a metal-filled bay airlock is not glass")
	TEST_ASSERT(metal.opacity, "and blocks sight")
	var/obj/machinery/door/airlock/angled_bay/standard/glass/glassy = allocate(/obj/machinery/door/airlock/angled_bay/standard/glass, get_step(T, EAST))
	TEST_ASSERT(glassy.glass, "a glass-filled one is glass")
	TEST_ASSERT(!glassy.opacity, "and does not block sight")

/datum/unit_test/dq_setup_early_belly_shares_lists

/datum/unit_test/dq_setup_early_belly_shares_lists/Run()
	var/turf/T = dq_containment_floor()
	var/obj/belly/first = allocate(/obj/belly, T)
	var/obj/belly/second = allocate(/obj/belly, T)
	var/shared_checked = 0
	for(var/var_name in GLOBAL_TABLE_GET(belly_default_lists))
		TEST_ASSERT(first.vars[var_name] == second.vars[var_name], "two bellies share the [var_name] list")
		shared_checked++
	TEST_ASSERT(shared_checked > 0, "there are shared belly lists to check")

/datum/unit_test/dq_setup_early_space_appearance

/datum/unit_test/dq_setup_early_space_appearance/Run()
	// Space has no Initialize() or table_initialize() of its own: its appearance is a phase 0 hook, whichever way the turf comes in.
	var/turf/space/sample = locate(/turf/space)
	if(!sample)
		return // the test map has no open space
	var/datum/lifeform_plan/P = lifeform_plan_of(sample)
	TEST_ASSERT(("space_appearance" in P.setup_rows_early), "the plan of a space turf runs space_appearance in phase 0")
	TEST_ASSERT(sample.flags & ATOM_INITIALIZED, "and the turf initialized")
