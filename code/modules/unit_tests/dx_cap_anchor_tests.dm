// anchor() (code/datums/capabilities/library/anchor.dm).

/obj/cap_fixture/anchorable/capabilities()
	. = ..()
	. += cap_anchor()

/obj/cap_fixture/anchorable/space_ok/capabilities()
	. = ..()
	. = without(., /datum/capability/anchor)
	. += cap_anchor(tool = TOOL_SCREWDRIVER, delay = 0, needs_floor = FALSE)

/datum/unit_test/dx_cap_anchor

/datum/unit_test/dx_cap_anchor/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/anchorable/F = allocate(/obj/cap_fixture/anchorable, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/wrench = dq_zero_speed(allocate(/obj/item/tool/wrench, T))

	var/datum/interaction/capability/E = dx_cap_entry(F, "Anchor")
	TEST_ASSERT_NOTNULL(E, "anchor() offers its entry")
	TEST_ASSERT_EQUAL(E.tool, TOOL_WRENCH, "a wrench by default")
	TEST_ASSERT_EQUAL(E.log, LOG_GAME, "logged by default")
	TEST_ASSERT_EQUAL(E.display_name(H, F), "Anchor", "named for its state")
	TEST_ASSERT("It is unanchored." in F.caps_examine(H), "examine says unanchored")

	TEST_ASSERT(E.perform(H, F, wrench), "the wrench anchors it")
	TEST_ASSERT(F.anchored, "anchored")
	TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["delay"], 2 SECONDS, "it takes 2 s unscaled")
	TEST_ASSERT_EQUAL(E.display_name(H, F), "Unanchor", "renamed for the new state")
	TEST_ASSERT("It is anchored." in F.caps_examine(H), "examine says anchored")
	TEST_ASSERT(E.perform(H, F, wrench), "the wrench frees it")
	TEST_ASSERT(!F.anchored, "unanchored")

	// Off the floor: refused with a reason, and unchanged.
	var/obj/structure/closet/crate/box = allocate(/obj/structure/closet/crate, T)
	F.forceMove(box)
	TEST_ASSERT_EQUAL(E.why_not(H, F, wrench), "it has to be on the floor", "needs_floor refuses off a turf")
	TEST_ASSERT(!E.perform(H, F, wrench), "and does not anchor")
	TEST_ASSERT(!F.anchored, "still unanchored")

	var/obj/cap_fixture/anchorable/space_ok/G = allocate(/obj/cap_fixture/anchorable/space_ok, box)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/datum/interaction/capability/E2 = dx_cap_entry(G, "Anchor")
	TEST_ASSERT_EQUAL(length(caps_of(G)), 1, "without() replaced the inherited anchor")
	TEST_ASSERT_EQUAL(E2.tool, TOOL_SCREWDRIVER, "the configured tool")
	TEST_ASSERT_NULL(E2.why_not(H, G, screwdriver), "needs_floor = FALSE doesn't check the floor")
	F.forceMove(T)
	G.forceMove(T)
