// Tool-quality helpers (code/datums/capabilities/library/tool_helpers.dm): tool_ready(), tool_use(),
// tool_buffer() and the common needs procs.

/obj/cap_fixture/weldable/capabilities()
	. = ..()
	. += cap_tool("Weld", TOOL_WELDER, PROC_REF(fx_weld), needs = GLOBAL_PROC_REF(cap_needs_lit_welder))

/obj/cap_fixture/weldable/proc/fx_weld(mob/user, obj/item/held)
	LAZYADD(calls, "weld")
	return TRUE

/datum/unit_test/dx_cap_tool

/datum/unit_test/dx_cap_tool/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/weldable/target = allocate(/obj/cap_fixture/weldable, T)
	var/obj/item/weldingtool/welder = dq_zero_speed(allocate(/obj/item/weldingtool, T))
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)

	// Quality.
	TEST_ASSERT(istext(tool_ready(wrench, TOOL_WELDER)), "a wrench is no welder")
	TEST_ASSERT(istext(tool_ready(null, TOOL_WELDER)), "nothing in hand is no welder")
	TEST_ASSERT_EQUAL(tool_ready(wrench, TOOL_WRENCH), TRUE, "a wrench is ready as a wrench")

	// Welder fuel and lighting.
	TEST_ASSERT_EQUAL(tool_ready(welder, TOOL_WELDER), "it needs to be lit", "an unlit welder isn't ready")
	TEST_ASSERT(!tool_use(welder, TOOL_WELDER, 1), "an unlit welder spends nothing")
	welder.set_welding(TRUE)
	TEST_ASSERT_EQUAL(tool_ready(welder, TOOL_WELDER, amount = 5), TRUE, "lit with fuel")
	TEST_ASSERT_EQUAL(tool_ready(welder, TOOL_WELDER, amount = 1000), "it needs more fuel", "not enough fuel")
	var/start = welder.get_fuel()
	TEST_ASSERT(tool_use(welder, TOOL_WELDER, 5), "spends without a user")
	TEST_ASSERT_EQUAL(welder.get_fuel(), start - 5, "five units burned")
	TEST_ASSERT(tool_use(welder, TOOL_WELDER, 2, user = H, target = target), "spends through use_tool() with a user and target")
	TEST_ASSERT_EQUAL(welder.get_fuel(), start - 7, "two more burned")
	TEST_ASSERT(!tool_use(welder, TOOL_WELDER, 1000, silent = TRUE), "refused when short")
	TEST_ASSERT_EQUAL(welder.get_fuel(), start - 7, "and nothing burned")
	TEST_ASSERT(!tool_use(wrench, TOOL_WELDER, 0), "the wrong quality spends nothing")

	// A needs proc built on tool_ready() gates a cap_tool() entry.
	var/datum/interaction/capability/weld = dx_cap_entry(target, "Weld")
	welder.set_welding(FALSE)
	TEST_ASSERT_EQUAL(weld.why_not(H, target, welder), "it needs to be lit", "the entry refuses an unlit welder with the reason")
	welder.set_welding(TRUE)
	TEST_ASSERT_NULL(weld.why_not(H, target, welder), "a lit welder passes")
	TEST_ASSERT(weld.perform(H, target, welder), "and the entry runs")
	TEST_ASSERT(("weld" in target.calls), "the handler ran")

	// Stacks.
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 10)
	TEST_ASSERT(istext(tool_ready(coil, TOOL_CABLE_COIL, amount = 20)), "not enough cable")
	TEST_ASSERT(tool_use(coil, TOOL_CABLE_COIL, 4), "spends cable")
	TEST_ASSERT_EQUAL(coil.get_amount(), 6, "four lengths used")

	// A multitool's buffer.
	var/obj/item/multitool/M = allocate(/obj/item/multitool, T)
	TEST_ASSERT_EQUAL(tool_ready(M, TOOL_MULTITOOL), TRUE, "a multitool is ready without a buffer")
	TEST_ASSERT_EQUAL(tool_ready(M, TOOL_MULTITOOL, needs_buffer = TRUE), "its buffer is empty", "needs_buffer wants one")
	TEST_ASSERT_EQUAL(cap_needs_buffer(target, H, M), "its buffer is empty", "the common needs proc")
	var/obj/machinery/machine = allocate(/obj/machinery, T)
	rel_set(M, nameof(M.connectable), machine)
	TEST_ASSERT_EQUAL(tool_buffer(M), machine, "tool_buffer() reads the buffered machine")
	TEST_ASSERT_EQUAL(tool_ready(M, TOOL_MULTITOOL, needs_buffer = TRUE), TRUE, "buffered")
