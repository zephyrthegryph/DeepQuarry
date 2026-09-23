// The tool pipeline (roadmap I4): use_tool() checks, fuel and stack use, the
// interaction cost, every TOOL_* quality reaching interactions, and timing
// parity for a sample of converted hand-written sites.

// ---- Fixtures ----

/// A tier-2 wrench.
/obj/item/dq_tool_probe
	name = "tool probe"
	tool_qualities = list(TOOL_WRENCH = 2)
	toolspeed = 0.5

/// A digging tool: TOOL_SHOVEL has no focused *_act hook.
/obj/item/dq_shovel_probe
	name = "shovel probe"
	tool_qualities = list(TOOL_SHOVEL)

/// Burns 3 fuel through the interaction cost.
/datum/interaction/dq_tool_weld
	id = "dq_tool_weld"
	name = "Probe weld"
	category = INTERACTION_CAT_REPAIR
	priority = 1
	default_action = INPUT_ACTION_USE
	tool = TOOL_WELDER
	tool_amount = 3
	effect = /obj/dq_tool_target/proc/note_tool

/// Answers a quality with no focused *_act hook.
/datum/interaction/dq_tool_dig
	id = "dq_tool_dig"
	name = "Probe dig"
	category = INTERACTION_CAT_REPAIR
	priority = 1
	default_action = INPUT_ACTION_USE
	tool = TOOL_SHOVEL
	effect = /obj/dq_tool_target/proc/note_tool

/obj/dq_tool_target
	name = "tool target"
	anchored = TRUE
	var/list/done = list()

/obj/dq_tool_target/declare_interactions(list/into)
	..()
	into += list(/datum/interaction/dq_tool_weld, /datum/interaction/dq_tool_dig)

/obj/dq_tool_target/proc/note_tool(mob/actor, obj/item/held, datum/interaction/interaction)
	done += interaction.id
	return TRUE

/datum/unit_test/proc/dq_zero_speed(obj/item/tool)
	tool.toolspeed = 0
	return tool

// ---- use_tool() checks ----

/// Quality and tier are checked, with the reason given.
/datum/unit_test/dq_use_tool_quality

/datum/unit_test/dq_use_tool_quality/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/dq_tool_target/target = allocate(/obj/dq_tool_target, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/obj/item/dq_tool_probe/probe = allocate(/obj/item/dq_tool_probe, T)

	TEST_ASSERT(!use_tool(H, screwdriver, target, quality = TOOL_WRENCH, silent = TRUE), "a screwdriver is not a wrench")
	TEST_ASSERT_EQUAL(tool_quality_failure(screwdriver, TOOL_WRENCH), "needs a wrench", "the reason names the quality")
	TEST_ASSERT_EQUAL(tool_quality_failure(null, TOOL_WELDER), "needs a welder", "no tool at all")
	TEST_ASSERT(use_tool(H, screwdriver, target, quality = TOOL_SCREWDRIVER), "the right quality, no wait")
	TEST_ASSERT(use_tool(H, probe, target, quality = TOOL_WRENCH, tier = 2), "tier 2 meets tier 2")
	TEST_ASSERT(!use_tool(H, probe, target, quality = TOOL_WRENCH, tier = 3, silent = TRUE), "tier 2 fails tier 3")
	TEST_ASSERT_EQUAL(tool_quality_failure(probe, TOOL_WRENCH, 3), "needs a wrench (tier 3)", "the tier is named")

/// Time scales by tool speed and the skill factor, and an unscaled delay is recorded.
/datum/unit_test/dq_use_tool_delay

/datum/unit_test/dq_use_tool_delay/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/dq_tool_probe/probe = allocate(/obj/item/dq_tool_probe, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)

	TEST_ASSERT_EQUAL(tool_skill_factor(H, TOOL_WRENCH), 1, "the skill factor is a stub returning 1")
	TEST_ASSERT_EQUAL(tool_delay(H, probe, 4 SECONDS, TOOL_WRENCH), 2 SECONDS, "toolspeed 0.5 halves the wait")
	TEST_ASSERT_EQUAL(tool_delay(H, wrench, 4 SECONDS, TOOL_WRENCH), 4 SECONDS, "toolspeed 1 keeps it")
	TEST_ASSERT_EQUAL(tool_delay(H, null, 4 SECONDS, null), 4 SECONDS, "no tool, no scaling")
	TEST_ASSERT_EQUAL(tool_delay(H, wrench, 0, TOOL_WRENCH), 0, "no delay, no wait")

/// A welder must be lit and hold the fuel; the fuel is burned at the end.
/datum/unit_test/dq_use_tool_fuel

/datum/unit_test/dq_use_tool_fuel/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/dq_tool_target/target = allocate(/obj/dq_tool_target, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool, T)

	TEST_ASSERT(!welder.isOn(), "the welder starts unlit")
	TEST_ASSERT(!use_tool(H, welder, target, quality = TOOL_WELDER, silent = TRUE), "an unlit welder is refused")
	welder.welding = TRUE
	var/start = welder.get_fuel()
	TEST_ASSERT(use_tool(H, welder, target, quality = TOOL_WELDER, amount = 5), "a lit welder with fuel works")
	TEST_ASSERT_EQUAL(welder.get_fuel(), start - 5, "exactly the asked fuel is burned")
	TEST_ASSERT(use_tool(H, welder, target, quality = TOOL_WELDER), "a zero-fuel job works")
	TEST_ASSERT_EQUAL(welder.get_fuel(), start - 5, "a zero-fuel job burns nothing")
	TEST_ASSERT(!use_tool(H, welder, target, quality = TOOL_WELDER, amount = 1000, silent = TRUE), "not enough fuel is refused")
	TEST_ASSERT_EQUAL(welder.get_fuel(), start - 5, "a refused job burns nothing")

/// A stack pays units.
/datum/unit_test/dq_use_tool_stack

/datum/unit_test/dq_use_tool_stack/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/dq_tool_target/target = allocate(/obj/dq_tool_target, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 10)

	TEST_ASSERT(use_tool(H, coil, target, quality = TOOL_CABLE_COIL, amount = 4), "enough cable")
	TEST_ASSERT_EQUAL(coil.get_amount(), 6, "four lengths used")
	TEST_ASSERT(!use_tool(H, coil, target, quality = TOOL_CABLE_COIL, amount = 7, silent = TRUE), "not enough cable")
	TEST_ASSERT_EQUAL(coil.get_amount(), 6, "nothing used when refused")

/// The interaction cost goes through use_tool(): fuel is paid, an unlit welder blocks it.
/datum/unit_test/dq_use_tool_interaction_cost

/datum/unit_test/dq_use_tool_interaction_cost/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/dq_tool_target/target = allocate(/obj/dq_tool_target, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool, T)
	var/datum/interaction/weld = INTERACTION(/datum/interaction/dq_tool_weld)

	TEST_ASSERT(!weld.perform(H, target, welder), "an unlit welder can't pay")
	TEST_ASSERT(!("dq_tool_weld" in target.done), "the effect did not run")
	welder.welding = TRUE
	var/start = welder.get_fuel()
	TEST_ASSERT(weld.perform(H, target, welder), "a lit welder pays")
	TEST_ASSERT(("dq_tool_weld" in target.done), "the effect ran")
	TEST_ASSERT_EQUAL(welder.get_fuel(), start - 3, "tool_amount fuel was burned")

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

/// Girder: secure 4 s, unsecure struts 4 s, dislodge 4 s, disassemble 35 + integrity/50.
/datum/unit_test/dq_tool_parity_girder

/datum/unit_test/dq_tool_parity_girder/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/wrench = dq_zero_speed(allocate(/obj/item/tool/wrench, T))
	var/obj/item/tool/crowbar/crowbar = dq_zero_speed(allocate(/obj/item/tool/crowbar, T))
	var/obj/structure/girder/girder = allocate(/obj/structure/girder, T)

	TEST_ASSERT(girder.crowbar_act(H, crowbar) & ITEM_INTERACT_SUCCESS, "crowbar dislodges")
	TEST_ASSERT(!girder.anchored, "dislodged")
	TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["delay"], 4 SECONDS, "dislodging takes 4 s")
	TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["volume"], 100, "at volume 100")
	TEST_ASSERT(girder.wrench_act(H, wrench) & ITEM_INTERACT_SUCCESS, "wrench secures")
	TEST_ASSERT(girder.anchored, "secured")
	TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["delay"], 4 SECONDS, "securing takes 4 s")
	var/expected = 35 + round(girder.max_integrity / 50)
	girder.wrench_act(H, wrench)
	TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["delay"], expected, "disassembling takes 35 + integrity/50")
	TEST_ASSERT(QDELETED(girder), "disassembled")
