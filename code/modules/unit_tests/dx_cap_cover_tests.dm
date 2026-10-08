// The cover capability (code/datums/capabilities/library/cover.dm).

/// Base of the capability-library fixtures: declares nothing itself.
/obj/cap_fixture
	name = "capability fixture"
	anchored = TRUE

/// The entry with this id among A's capability entries, or null.
/proc/cap_test_entry(atom/A, id)
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(E.id == id)
			return E
	return null

/// Whether A's draw() shows `name` now: as an overlay or a part (look.part(), which the library draws; a
/// part resolves to an icon state only when the fixture's icon has it, so the test reads the look, not the applied
/// overlays). The standard part names are dashed ("cover-open"): the legacy underscore spelling is accepted.
/proc/dx_look_shows(atom/A, name)
	name = replacetext(name, "_", "-")
	var/datum/look/L = GLOB.look_builder
	L.reset()
	A.draw(L)
	. = (name in L.overlays)
	for(var/list/entry in L.parts)
		if(entry[1] == name || (!isnull(entry[2]) && "[entry[1]]-[entry[2]]" == name))
			. = TRUE
	L.reset()

/// Whether A's draw() carries the layer `name` (dx_look_shows()).
/proc/cap_test_has_layer(atom/A, name)
	return dx_look_shows(A, name) ? TRUE : FALSE

/obj/cap_fixture/cover_hand/capabilities()
	. = ..()
	. += cap_cover(open_tool = BY_HAND, needs = req_clear(LOCK))
	. += cap_lock(access = list(ACCESS_SECURITY))
	. += cap_panel(needs = req_set(COVER))

/obj/cap_fixture/cover_crowbar/capabilities()
	. = ..()
	. += cap_cover()

/// A cover opened by hand: the bit, the name by state, examine, the layer and gating of others.
/datum/unit_test/dx_cap_cover_by_hand/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/cover_hand/A = allocate(/obj/cap_fixture/cover_hand, T)
	var/datum/interaction/capability/toggle = cap_test_entry(A, "cover:[BY_HAND]")
	var/datum/interaction/capability/panel_entry = cap_test_entry(A, "panel:[TOOL_SCREWDRIVER]")
	TEST_ASSERT_NOTNULL(toggle, "the cover offers a by-hand entry")
	TEST_ASSERT_NOTNULL(panel_entry, "the panel offers its entry")
	TEST_ASSERT(!cover_is_open(A), "the cover starts closed")
	TEST_ASSERT_EQUAL(toggle.display_name(H, A), "Open cover", "named for opening while closed")
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, null, panel_entry), "open the cover first", "the panel is behind the cover")
	TEST_ASSERT(!("Its cover is open." in caps_examine(A, H)), "no open line while closed")
	TEST_ASSERT(toggle.perform(H, A, null), "opening the cover runs")
	TEST_ASSERT(cover_is_open(A), "the cover is open")
	TEST_ASSERT(capability_bits(A) & CAP_COVER_OPEN, "the state bit is set")
	TEST_ASSERT_EQUAL(toggle.display_name(H, A), "Close cover", "named for closing while open")
	TEST_ASSERT_NULL(cap_gate_reason(A, H, null, panel_entry), "the panel is reachable with the cover open")
	TEST_ASSERT("Its cover is open." in caps_examine(A, H), "the examine line shows while open")
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(A, "cover_open"), "the cover_open layer is drawn")
	TEST_ASSERT(toggle.perform(H, A, null), "closing the cover runs")
	TEST_ASSERT(!cover_is_open(A), "the cover is closed again")
	refresh_flush()
	TEST_ASSERT(!cap_test_has_layer(A, "cover_open"), "the layer is gone once closed")

/// locked_by = LOCK refuses the cover while locked; broken and unpowered don't stop it.
/datum/unit_test/dx_cap_cover_locked/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/cover_hand/A = allocate(/obj/cap_fixture/cover_hand, T)
	var/datum/interaction/capability/toggle = cap_test_entry(A, "cover:[BY_HAND]")
	cap_set(A, CAP_LOCKED, TRUE)
	TEST_ASSERT_EQUAL(toggle.why_not(H, A, null), "it's locked", "a locked cover refuses")
	TEST_ASSERT(!toggle.perform(H, A, null), "the refused toggle does not run")
	TEST_ASSERT(!cover_is_open(A), "and the cover stays closed")
	cap_set(A, CAP_LOCKED, FALSE)
	cap_set(A, CAP_BROKEN, TRUE)
	TEST_ASSERT_NULL(toggle.why_not(H, A, null), "a cover works on a broken holder")

/// The default cover needs a crowbar.
/datum/unit_test/dx_cap_cover_tool/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/cover_crowbar/A = allocate(/obj/cap_fixture/cover_crowbar, T)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/datum/interaction/capability/toggle = cap_test_entry(A, "cover:[TOOL_CROWBAR]")
	TEST_ASSERT_NOTNULL(toggle, "the crowbar cover offers a tool entry")
	TEST_ASSERT(!toggle.is_meant(H, A, screwdriver), "a screwdriver is not meant")
	TEST_ASSERT(H.put_in_active_hand(crowbar), "the human holds a crowbar")
	TEST_ASSERT(toggle.is_meant(H, A, crowbar), "a crowbar is meant")
	TEST_ASSERT_EQUAL(try_interaction(H, A, crowbar, INPUT_ACTION_USE, TOOL_CROWBAR), INTERACTION_TRY_RAN, "the crowbar opens it through the resolver")
	TEST_ASSERT(cover_is_open(A), "the cover is open")
