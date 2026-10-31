// The tool pipeline (roadmap I4): quality checks, the tool ops' fuel, the
// interaction cost, every TOOL_* quality reaching interactions, and timing
// parity for a sample of converted hand-written sites.

// ---- Fixtures ----

/// A tier-2 wrench.
/obj/item/dq_tool_probe
	name = "tool probe"
	tool_qualities = list(TOOL_WRENCH = 2)

CAPABILITIES(/obj/item/dq_tool_probe)
	configure(item_tooling(speed = 0.5))

/// A digging tool: TOOL_SHOVEL has no focused *_act hook.
/obj/item/dq_shovel_probe
	name = "shovel probe"
	tool_qualities = list(TOOL_SHOVEL)

/// Two tool ops: a weld that burns 3 fuel as the op's cost, and a dig by a quality with no focused *_act hook.
/obj/dq_tool_target
	name = "tool target"
	anchored = TRUE
	var/list/done = list()

CAPABILITIES(/obj/dq_tool_target)
	op("dq_tool_weld", lit_welder(fuel = 3), wait(0), label("Probe weld"), then(PROC_REF(note_weld)))
	op("dq_tool_dig", tool(TOOL_SHOVEL), label("Probe dig"), then(PROC_REF(note_dig)))

/obj/dq_tool_target/proc/note_weld(datum/act/op/A)
	LAZYADD(done, "dq_tool_weld")
	return OP_OK

/obj/dq_tool_target/proc/note_dig(datum/act/op/A)
	LAZYADD(done, "dq_tool_dig")
	return OP_OK

/datum/unit_test/proc/dq_zero_speed(obj/item/tool)
	tool.set_toolspeed(0)
	return tool

// ---- tool checks ----

/// Quality and tier are checked, with the reason given.
/datum/unit_test/dq_tool_quality_failure

/datum/unit_test/dq_tool_quality_failure/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/obj/item/dq_tool_probe/probe = allocate(/obj/item/dq_tool_probe, T)

	TEST_ASSERT_EQUAL(tool_quality_failure(screwdriver, TOOL_WRENCH), "needs a wrench", "the reason names the quality")
	TEST_ASSERT_EQUAL(tool_quality_failure(null, TOOL_WELDER), "needs a welder", "no tool at all")
	TEST_ASSERT_NULL(tool_quality_failure(probe, TOOL_WRENCH, 2), "tier 2 meets tier 2")
	TEST_ASSERT_EQUAL(tool_quality_failure(probe, TOOL_WRENCH, 3), "needs a wrench (tier 3)", "the tier is named")

/// Time scales by tool speed and the skill factor, and an unscaled delay is recorded.
/datum/unit_test/dq_tool_delay

/datum/unit_test/dq_tool_delay/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/dq_tool_probe/probe = allocate(/obj/item/dq_tool_probe, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)

	TEST_ASSERT_EQUAL(tool_skill_factor(H, TOOL_WRENCH), 1, "the skill factor is a stub returning 1")
	TEST_ASSERT_EQUAL(tool_delay(H, probe, 4 SECONDS, TOOL_WRENCH), 2 SECONDS, "toolspeed 0.5 halves the wait")
	TEST_ASSERT_EQUAL(tool_delay(H, wrench, 4 SECONDS, TOOL_WRENCH), 4 SECONDS, "toolspeed 1 keeps it")
	TEST_ASSERT_EQUAL(tool_delay(H, null, 4 SECONDS, null), 4 SECONDS, "no tool, no scaling")
	TEST_ASSERT_EQUAL(tool_delay(H, wrench, 0, TOOL_WRENCH), 0, "no delay, no wait")

/// The op's cost goes through the tool: fuel is paid, an unlit welder blocks it.
/datum/unit_test/dq_use_tool_interaction_cost

/datum/unit_test/dq_use_tool_interaction_cost/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/dq_tool_target/target = allocate(/obj/dq_tool_target, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool, T)

	test_click(H, target, welder)
	TEST_ASSERT(!("dq_tool_weld" in target.done), "an unlit welder can't pay: the effect did not run")
	welder.set_welding(TRUE)
	var/start = welder.get_fuel()
	cooldown_set_end(H, next_click, 0)
	test_click(H, target, welder)
	test_time(1 SECOND)
	TEST_ASSERT(("dq_tool_weld" in target.done), "a lit welder pays: the effect ran")
	TEST_ASSERT_EQUAL(welder.get_fuel(), start - 3, "the op's cost in fuel was burned")
	test_driver_end()

/// A quality with no focused *_act hook (shovel) still reaches its interaction through Use.
/datum/unit_test/dq_tool_all_qualities_route

/datum/unit_test/dq_tool_all_qualities_route/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/dq_tool_target/target = allocate(/obj/dq_tool_target, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/dq_shovel_probe/shovel = allocate(/obj/item/dq_shovel_probe, T)

	var/result = target.tool_act(H, shovel, TOOL_SHOVEL)
	TEST_ASSERT(result & ITEM_INTERACT_SUCCESS, "tool_act routes TOOL_SHOVEL to interactions")
	TEST_ASSERT(("dq_tool_dig" in target.done), "the shovel interaction ran")
	// Every quality is dispatched: none falls off the end of tool_act without asking the resolver.
	for(var/quality in list(TOOL_CABLE_COIL, TOOL_ANALYZER, TOOL_MINING, TOOL_RETRACTOR, TOOL_HEMOSTAT, TOOL_CAUTERY, TOOL_DRILL, TOOL_SCALPEL, TOOL_SAW, TOOL_BONESET, TOOL_KNIFE, TOOL_BLOODFILTER, TOOL_ROLLINGPIN))
		TEST_ASSERT_EQUAL(target.tool_act(H, shovel, quality), NONE, "[quality] with no interaction for it answers NONE")

// ---- Parity: converted sites keep their timings ----

/// Girder: secure 4 s, unsecure struts 4 s, dislodge 4 s, disassemble 35 + integrity/50 (ops with a wait each, scaled by the tool's speed).
/datum/unit_test/dq_tool_parity_girder

/datum/unit_test/dq_tool_parity_girder/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.enable_godmode() // the test floor has no air
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar, T)
	var/obj/structure/girder/girder = allocate(/obj/structure/girder, T)

	TEST_ASSERT(girder.interaction_tool_act(H, crowbar, TOOL_CROWBAR) & ITEM_INTERACT_SUCCESS, "crowbar dislodges")
	test_time(3 SECONDS)
	TEST_ASSERT(girder.anchored, "still anchored after 3 s")
	test_time(2 SECONDS)
	TEST_ASSERT(!girder.anchored, "dislodging takes 4 s")
	TEST_ASSERT(girder.interaction_tool_act(H, wrench, TOOL_WRENCH) & ITEM_INTERACT_SUCCESS, "wrench secures")
	test_time(3 SECONDS)
	TEST_ASSERT(!girder.anchored, "still loose after 3 s")
	test_time(2 SECONDS)
	TEST_ASSERT(girder.anchored, "securing takes 4 s")
	var/expected = 35 + round(girder.max_integrity / 50)
	girder.interaction_tool_act(H, wrench, TOOL_WRENCH)
	test_time(expected - 1)
	TEST_ASSERT(!QDELETED(girder), "still standing a tick before 35 + integrity/50")
	test_time(2)
	TEST_ASSERT(QDELETED(girder), "disassembling takes 35 + integrity/50")
	own_turf_contents(T) // the salvaged steel
	test_driver_end()

/// Manual valve: the wrench is an op with a 4 s wait (intended_changes.md, "Pipe devices"; was a timer helper of 40 ticks).
/datum/unit_test/dq_tool_parity_valve

/datum/unit_test/dq_tool_parity_valve/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/obj/machinery/atmospherics/valve/valve = allocate(/obj/machinery/atmospherics/valve, T)
	test_click(H, valve, wrench)
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(valve), "the wrench is still unfastening it after 3 s")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(valve), "the valve comes off as a pipe item after its 4 s wait")
	test_driver_end()
	own_turf_contents(T)
