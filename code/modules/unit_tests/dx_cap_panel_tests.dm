// The panel capability (code/datums/capabilities/library/panel.dm).

/obj/cap_fixture/panel/capabilities()
	. = ..()
	. += cap_panel()
	. += cap_hand("Poke", TYPE_PROC_REF(/obj/cap_fixture/panel, poke), behind = PANEL)

/obj/cap_fixture/panel
	var/pokes = 0

/obj/cap_fixture/panel/proc/poke(mob/user, obj/item/held)
	pokes++
	return TRUE

/// A screwdriver toggles the panel; the bit, name, examine, layer and gating of a PANEL entry follow.
/datum/unit_test/dx_cap_panel_toggle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/panel/A = allocate(/obj/cap_fixture/panel, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/datum/interaction/capability/toggle = cap_test_entry(A, "panel:[TOOL_SCREWDRIVER]")
	var/datum/interaction/capability/poke
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(E.name == "Poke")
			poke = E
	TEST_ASSERT_NOTNULL(toggle, "the panel offers its entry")
	TEST_ASSERT_NOTNULL(poke, "the fixture's own entry is there")
	TEST_ASSERT_EQUAL(toggle.why_not(H, A, null), "needs a screwdriver", "the panel needs a screwdriver")
	TEST_ASSERT_EQUAL(poke.why_not(H, A, null), "open the maintenance panel first", "a PANEL entry refuses while it is closed")
	TEST_ASSERT(H.put_in_active_hand(screwdriver), "the human holds a screwdriver")
	TEST_ASSERT_EQUAL(toggle.display_name(H, A), "Open maintenance panel", "named for opening")
	TEST_ASSERT(toggle.perform(H, A, screwdriver), "the screwdriver opens the panel")
	TEST_ASSERT(panel_is_open(A), "the panel is open")
	TEST_ASSERT_EQUAL(toggle.display_name(H, A), "Close maintenance panel", "named for closing")
	TEST_ASSERT("The maintenance panel is open." in caps_examine(A, H), "the examine line shows")
	TEST_ASSERT_NULL(poke.why_not(H, A, null), "the PANEL entry is reachable now")
	TEST_ASSERT(poke.perform(H, A, null), "and it runs")
	TEST_ASSERT_EQUAL(A.pokes, 1, "its handler ran once")
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(A, "panel_open"), "the panel_open layer is drawn")
	TEST_ASSERT(toggle.perform(H, A, screwdriver), "the screwdriver closes it")
	TEST_ASSERT(!panel_is_open(A), "the panel is closed")
	refresh_flush()
	TEST_ASSERT(!cap_test_has_layer(A, "panel_open"), "the layer is gone")
	TEST_ASSERT(!("The maintenance panel is open." in caps_examine(A, H)), "the examine line is gone")
