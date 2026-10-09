// The cell holder and charger capabilities (code/datums/capabilities/library/cell_holder.dm).

/// Whether A's applied look carries the overlay `name`.
/proc/dxs_has_layer(atom/A, name)
	return dx_look_shows(A, name) ? TRUE : FALSE

/// A cell behind the cover.
/obj/cap_fixture/cell_box
	var/obj/item/cell/cell

/obj/cap_fixture/cell_box/capabilities()
	. = ..()
	. += cap_cell_holder(nameof(cell), /obj/item/cell, needs = req_set(COVER))

/// A charger with its own cell slot.
/obj/cap_fixture/cell_charger
	var/obj/item/cell/charging

/obj/cap_fixture/cell_charger/capabilities()
	. = ..()
	. += cap_cell_holder(nameof(charging))
	. += cap_charger(rate = 100)

/// The first capability entry of A of `type`.
/proc/dxs_entry_of_type(atom/A, type)
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(istype(E, type))
			return E
	return null

/// Insert and remove: gating behind the cover, ownership, examine, the layer, the empty refusal.
/datum/unit_test/dx_cap_cell_holder_insert_remove/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/cell_box/box = allocate(/obj/cap_fixture/cell_box, T)
	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/datum/interaction/capability/insert_cell = dxs_entry_of_type(box, /datum/interaction/capability/slot_insert)
	var/datum/interaction/capability/remove_cell = dxs_entry_of_type(box, /datum/interaction/capability/slot_eject)
	TEST_ASSERT(istype(cap_of(box, /datum/capability/slot/cell_holder), /datum/capability/slot), "the cell holder is a slot")
	TEST_ASSERT_NOTNULL(insert_cell, "the cell holder offers Insert cell")
	TEST_ASSERT_NOTNULL(remove_cell, "and Remove cell")
	TEST_ASSERT(!insert_cell.is_meant(H, box, screwdriver), "a screwdriver is not a cell")
	TEST_ASSERT("It has no cell." in caps_examine(box, H), "examine says there is no cell")
	TEST_ASSERT_EQUAL(insert_cell.why_not(H, box, cell), "open the cover first", "the holder is behind the cover")
	TEST_ASSERT(!remove_cell.applies_to(box), "Remove cell isn't offered while empty")
	cap_set(box, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT(H.put_in_active_hand(cell), "the human holds the cell")
	TEST_ASSERT(insert_cell.perform(H, box, cell), "the held cell goes in")
	TEST_ASSERT_EQUAL(box.cell, cell, "the holder var holds the cell")
	TEST_ASSERT_EQUAL(cell.loc, box, "the cell is inside")
	TEST_ASSERT(!H.is_in_hands(cell), "and out of the hand")
	TEST_ASSERT(remove_cell.applies_to(box), "Remove cell is offered once full")
	TEST_ASSERT(findtext(jointext(caps_examine(box, H), " "), "charged to"), "examine shows the charge")
	refresh_flush()
	TEST_ASSERT(dxs_has_layer(box, "cell"), "the cell layer is drawn")
	var/list/data = list()
	caps_ui_data(box, H, data)
	TEST_ASSERT_EQUAL(data["caps"]?["cell"]?["item"]?["name"], cell.name, "the UI data names the cell, under caps")
	TEST_ASSERT(remove_cell.perform(H, box, null), "Remove cell runs")
	TEST_ASSERT_NULL(box.cell, "the var is cleared")
	TEST_ASSERT(H.is_in_hands(cell), "the cell is in the hand")
	refresh_flush()
	TEST_ASSERT(!dxs_has_layer(box, "cell"), "the layer is gone")

/// The charger joins the periodic lane while a cell is in and the holder works, and charges by rate.
/datum/unit_test/dx_cap_charger_periodic/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/cap_fixture/cell_charger/charger = allocate(/obj/cap_fixture/cell_charger, T)
	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	cell.charge = 0
	TEST_ASSERT_EQUAL(charger.periodic_cadence, PERIODIC_SECOND, "the holder took the charger's cadence")
	refresh_flush()
	TEST_ASSERT(!charger.should_run(), "no cell, no periodic work")
	TEST_ASSERT(!(!isnull(charger.periodic_pipe)), "and nothing is running")
	TEST_ASSERT(slot_insert(charger, nameof(charger.charging), cell, null), "slot_insert(src) puts the cell in from code")
	refresh_flush()
	TEST_ASSERT(charger.should_run(), "with a cell, it should run")
	TEST_ASSERT((!isnull(charger.periodic_pipe)), "and the refresh started it")
	charger.periodic_step(1 SECOND)
	TEST_ASSERT_EQUAL(cell.charge, 100, "one second at rate 100 gives 100")
	cap_set(charger, CAP_BROKEN, TRUE)
	refresh_flush()
	TEST_ASSERT(!charger.should_run(), "a broken charger doesn't run")
	TEST_ASSERT(!(!isnull(charger.periodic_pipe)), "and the refresh stopped it")
	TEST_ASSERT_EQUAL(charger.periodic_step(1 SECOND), PROCESS_KILL, "a step with nothing to do parks")
	TEST_ASSERT_EQUAL(cell.charge, 100, "and gave nothing")
	cap_set(charger, CAP_BROKEN, FALSE)
	TEST_ASSERT_EQUAL(slot_eject(charger, nameof(charger.charging), null), cell, "slot_eject(src) takes it out from code")
	refresh_flush()
	TEST_ASSERT(!(!isnull(charger.periodic_pipe)), "no cell, not running")
	TEST_ASSERT(!("It is charging \the [cell]." in caps_examine(charger, null)), "no charging line without a cell")
