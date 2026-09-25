// Unit tests for cyborgs as machine bodies (doc/mob_life_architecture.md §5):
// one body tick per Life, stat from the plan, one EMP pass, the power ledger,
// parts carrying their damage, brownout and the core death rule.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Counts its ticks; exists on every plan and biology.
/datum/affliction/dq_test_tick_counter
	name = "test tick counter"
	catalogued = FALSE
	biology = BIOLOGY_ALL
	body_plans = BODY_PLAN_ALL
	progression_rate = 0
	min_symptoms = 0
	max_symptoms = 0
	var/ticks = 0

/datum/affliction/dq_test_tick_counter/tick()
	ticks++

/// Bug 8: a robot's body ticks exactly once per Life.
/datum/unit_test/dq_robot_body_ticks_once

/datum/unit_test/dq_robot_body_ticks_once/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/datum/affliction/dq_test_tick_counter/counter = R.body.afflict(/datum/affliction/dq_test_tick_counter)
	TEST_ASSERT_NOTNULL(counter, "the test affliction should attach to a robot body")
	om_run_frame_now(R, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(counter.ticks, 1, "one robot Life should tick its body once")

/// Bug 8: incapacitation keeps a robot down until it wears off; only the plan sets stat.
/datum/unit_test/dq_robot_stun_stays_down

/datum/unit_test/dq_robot_stun_stays_down/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	R.status_at_least(EFFECT_STUNNED, 5)
	om_run_frame_now(R, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(R.stat, UNCONSCIOUS, "a stunned cyborg should stay unconscious through its Life tick")
	om_run_frame_now(R, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(R.stat, UNCONSCIOUS, "a stunned cyborg should not flicker awake on the next tick")
	R.status_set(EFFECT_STUNNED, 0)
	om_run_frame_now(R, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(R.stat, CONSCIOUS, "a cyborg should wake once the stun ends")

/// Bug 9: one EMP drains the cell once and injures once.
/datum/unit_test/dq_robot_emp_hits_once

/datum/unit_test/dq_robot_emp_hits_once/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	var/obj/item/cell/C = R.cell
	TEST_ASSERT_NOTNULL(C, "a new cyborg should have a cell")
	var/before = C.charge
	R.emp_act(1)
	TEST_ASSERT(C.charge < before, "an EMP should drain the cell")
	// One pass at cell_emp_mult 2 leaves about half; a double pass would leave a quarter.
	TEST_ASSERT(C.charge > before * 0.4, "an EMP should drain the cell once ([before] -> [C.charge])")
	var/load = R.injury_load(INJURY_CATEGORY_THERMAL)
	TEST_ASSERT(load > 0 && load <= 20, "a severity-1 EMP should inflict one surge of at most 20 (got [load])")

/// Bug 14: the ledger never overdraws or overfills the cell.
/datum/unit_test/dq_robot_power_ledger_bounds

/datum/unit_test/dq_robot_power_ledger_bounds/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/obj/item/cell/C = R.cell
	TEST_ASSERT(!R.draw_power(ROBOT_CELL_JOULES(C.maxcharge * 2), null), "the ledger must refuse a draw larger than the cell")
	R.add_power(ROBOT_CELL_JOULES(C.maxcharge * 2), null)
	TEST_ASSERT(C.charge <= C.maxcharge, "the ledger must not overfill the cell")
	R.draw_power(ROBOT_CELL_JOULES(C.maxcharge * 2), null, 0, TRUE)
	TEST_ASSERT(C.charge >= 0, "a partial drain must not go negative")

/// Power demand is cached and follows the lights.
/datum/unit_test/dq_robot_power_demand_cached

/datum/unit_test/dq_robot_power_demand_cached/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	R.set_lights(FALSE)
	var/dark = R.power_demand
	R.set_lights(TRUE)
	TEST_ASSERT_EQUAL(R.power_demand, dark + ROBOT_LIGHT_DRAW * CYBORG_POWER_USAGE_MULTIPLIER, "turning the light on should raise the cached demand")

/// Bug 15: a removed part takes its damage with it and brings it back.
/datum/unit_test/dq_robot_part_carries_damage

/datum/unit_test/dq_robot_part_carries_damage/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/datum/robot_component/camera = R.get_component(ROBOT_SLOT_CAMERA)
	R.injure(INJURY_BLUNT, 10, ROBOT_SLOT_CAMERA, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/load = camera.get_total_damage()
	TEST_ASSERT(load > 0, "a targeted hit should land on the camera")
	var/obj/item/part = camera.uninstall()
	TEST_ASSERT_EQUAL(camera.get_total_damage(), 0, "an empty slot carries no damage")
	TEST_ASSERT_EQUAL(R.injury_load(INJURY_CATEGORY_PHYSICAL), 0, "the removed part's damage leaves the body")
	camera.install(part)
	TEST_ASSERT_EQUAL(camera.get_total_damage(), load, "reinstalling the part must not repair it")

	R.injure(INJURY_BLUNT, 10, ROBOT_SLOT_POWER, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/datum/robot_component/mount = R.get_component(ROBOT_SLOT_POWER)
	var/cell_load = mount.get_total_damage()
	var/obj/item/cell/C = R.remove_cell()
	R.set_cell(C)
	TEST_ASSERT_EQUAL(mount.get_total_damage(), cell_load, "reinserting a cell must not repair its mount")

/// No cell is a brownout: unconscious until power returns.
/datum/unit_test/dq_robot_brownout

/datum/unit_test/dq_robot_brownout/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/obj/item/cell/C = R.remove_cell()
	om_run_frame_now(R, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(R.stat, UNCONSCIOUS, "a cyborg without power should brown out")
	R.set_cell(C)
	om_run_frame_now(R, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(R.stat, CONSCIOUS, "a cyborg should come back when power returns")

/// The plan's second death rule: a destroyed processor core.
/datum/unit_test/dq_robot_core_death

/datum/unit_test/dq_robot_core_death/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/datum/robot_component/core = R.get_component(ROBOT_SLOT_CORE)
	R.injure(INJURY_NEURAL, core.max_damage, ROBOT_SLOT_CORE, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT_EQUAL(core.installed, ROBOT_PART_DESTROYED, "the core should be destroyed at its max damage")
	TEST_ASSERT_EQUAL(R.stat, DEAD, "a cyborg with a destroyed core should be dead")

/// Upgrades detect themselves.
/datum/unit_test/dq_robot_upgrade_detection

/datum/unit_test/dq_robot_upgrade_detection/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/obj/item/borg/upgrade/proto = robot_upgrade_prototype(/obj/item/borg/upgrade/basic/vtec)
	TEST_ASSERT_NOTNULL(proto, "upgrade prototypes should resolve by type")
	TEST_ASSERT(!proto.is_installed(R), "a new cyborg has no VTEC")
	add_verb(R, /mob/living/silicon/robot/proc/toggle_vtec)
	TEST_ASSERT(proto.is_installed(R), "VTEC is detected once its verb is present")

#endif
