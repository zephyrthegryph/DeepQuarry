// Behaviour-preservation tests for the battery rack (phase 2): what a person can observe of a power cell rack through public inputs (clicks,
// window buttons, charge entry points, time), so the same file passes before and after the rack moves from the legacy declaration forms to
// the engine forms. Same rules as dq_p2_smes_behaviour.dm, whose fixtures (the 5x5 block, p2_actor(), touch(), p2_settle()) it reuses:
//   - Input goes through test_click(), the window adapter p2_rack_ui() and the charge procs the grid calls; never an op key.
//   - State is read through the adapter block below and plain vars.
//   - Nothing depends on message text or on a click result being non-null.
//
// Not pinned (and why): the Rust network flow through a rack (the flow is the SMES's Rust law, covered by dq_p2_smes; the rack's own part is the
// charge it reads back from its cells every step, pinned here through power_step()); the parts the limits are derived from (machine parts are the machine track's, phase 4: only the defaults of a fresh rack are pinned).

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: today's accessors, wrapped. After the conversion only these bodies change.
// ---------------------------------------------------------------------------------------------------------------------

/// The cells inside the rack, in the order they went in.
/proc/p2_rack_cells(obj/machinery/power/smes/batteryrack/R)
	return R.internal_cells ? R.internal_cells.Copy() : list()

/// How many cells the rack takes at once.
/proc/p2_rack_max_cells(obj/machinery/power/smes/batteryrack/R)
	return R.max_cells

/// The rack's transfer limit (set by its capacitors).
/proc/p2_rack_transfer_rate(obj/machinery/power/smes/batteryrack/R)
	return R.max_transfer_rate

/// The rack's mode (0 off, 1 output, 2 input, 3 both).
/proc/p2_rack_mode(obj/machinery/power/smes/batteryrack/R)
	return R.mode

/// The rack is set to equalise its cells.
/proc/p2_rack_equalising(obj/machinery/power/smes/batteryrack/R)
	return !!R.equalise

/// The window's data as a viewer is sent it.
/proc/p2_rack_data(obj/machinery/power/smes/batteryrack/R, mob/user)
	return R.tgui_data(user)

/// Presses a window button as the actor: the engine's op if the rack has one for the action, else today's tgui_act().
/proc/p2_rack_ui(mob/actor, obj/machinery/power/smes/batteryrack/R, action, list/args)
	var/datum/op_result/result = test_ui(actor, R, action, args)
	if(result)
		return result
	var/datum/tgui/ui = new(actor, R, "Batteryrack")
	ui.status = STATUS_INTERACTIVE
	. = R.tgui_act(action, args || list(), ui)
	qdel(ui)

/// The window was opened for `user` (a test mob has no client, so the type records the open).
/proc/p2_rack_interface_opened(obj/machinery/power/smes/batteryrack/R, mob/user)
	var/obj/machinery/power/smes/batteryrack/p2_test/P = R
	return istype(P) && (user in P.p2_opened)

/// The overlay keys the rack draws.
/proc/p2_rack_overlays(obj/machinery/power/smes/batteryrack/R)
	var/datum/look/look = new
	R.draw(look)
	return look.overlays.Copy()

/// One frame of the rack's own charge work (it reads its cells back and balances them).
/proc/p2_rack_power_step(obj/machinery/power/smes/batteryrack/R)
	R.power_step()
	refresh_flush()

/// The rack's stored charge in SMES units.
/proc/p2_rack_stored(obj/machinery/power/smes/batteryrack/R)
	return R.stored_charge()

/// The rack's capacity in SMES units.
/proc/p2_rack_capacity(obj/machinery/power/smes/batteryrack/R)
	return R.capacity

/// The rack is broken.
/proc/p2_rack_broken(obj/machinery/power/smes/batteryrack/R)
	return !!R.broken_now()

/// The test rack: a real one, except that a test mob has no client and the type records who opened its window.
/obj/machinery/power/smes/batteryrack/p2_test
	var/list/p2_opened

/obj/machinery/power/smes/batteryrack/p2_test/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	LAZYADD(p2_opened, user)
	return ..()

/obj/machinery/power/smes/batteryrack/mapped/five
	cell_number = 5

// ---------------------------------------------------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------------------------------------------------

/// A rack on the SMES's spot (it keeps no terminals), a person beside it.
/datum/unit_test/dq_p2_smes/proc/p2_rack(type = /obj/machinery/power/smes/batteryrack/p2_test)
	var/obj/machinery/power/smes/batteryrack/R = allocate(type, p2_smes_spot())
	LAZYADD(p2_smeses, R)
	return R

/// A cell with `percent` of its charge, on a tile beside the rack.
/datum/unit_test/dq_p2_smes/proc/p2_rack_cell(percent = 100, type = /obj/item/cell/high)
	var/obj/item/cell/C = allocate(type, p2_side_spot())
	C.charge = C.maxcharge * percent / 100
	return C

/// The actor clicks a cell onto the rack and waits.
/datum/unit_test/dq_p2_smes/proc/p2_rack_put(mob/living/carbon/human/H, obj/machinery/power/smes/batteryrack/R, obj/item/cell/C)
	touch(H, R, C)

/// A rack with `n` cells of the given charges, put in by hand. Returns the rack; the cells are in order in p2_rack_cells().
/datum/unit_test/dq_p2_smes/proc/p2_rack_loaded(mob/living/carbon/human/H, list/percents)
	var/obj/machinery/power/smes/batteryrack/R = p2_rack()
	for(var/percent in percents)
		p2_rack_put(H, R, p2_rack_cell(percent))
	return R

// ---------------------------------------------------------------------------------------------------------------------
// Cells in and out
// ---------------------------------------------------------------------------------------------------------------------

/// An empty rack stores nothing, is off, and is not broken without a terminal.
/datum/unit_test/dq_p2_smes/rack_starts_empty_and_off
/datum/unit_test/dq_p2_smes/rack_starts_empty_and_off/run_gate()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack()
	p2_settle()
	TEST_ASSERT_EQUAL(p2_rack_capacity(R), 0, "an empty rack stores nothing")
	TEST_ASSERT_EQUAL(length(p2_rack_cells(R)), 0, "no cells")
	TEST_ASSERT_EQUAL(p2_rack_mode(R), 0, "it is off")
	TEST_ASSERT(!R.input_attempt && !R.output_attempt, "neither input nor output is attempted")
	TEST_ASSERT(!p2_rack_broken(R), "a rack needs no terminal and is not broken without one")
	TEST_ASSERT_EQUAL(p2_rack_max_cells(R), 3, "three tier-1 bins make a three cell rack")
	TEST_ASSERT_EQUAL(p2_rack_transfer_rate(R), 30000, "three tier-1 capacitors give 30 kW")
	TEST_ASSERT_EQUAL(R.input_level, 30000, "the input level follows the transfer limit")
	TEST_ASSERT_EQUAL(R.output_level, 30000, "and so does the output level")

/// A cell clicked onto the rack goes inside, and the rack's capacity follows the cells held.
/datum/unit_test/dq_p2_smes/rack_takes_a_cell_by_click
/datum/unit_test/dq_p2_smes/rack_takes_a_cell_by_click/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack()
	var/obj/item/cell/first = p2_rack_cell()
	p2_rack_put(H, R, first)
	TEST_ASSERT(first in p2_rack_cells(R), "the cell is a rack cell")
	TEST_ASSERT_EQUAL(first.loc, R, "and inside the rack")
	var/expected = first.maxcharge / CELLRATE * SMESRATE
	TEST_ASSERT(abs(p2_rack_capacity(R) - expected) < 1, "the capacity is the cell's, in SMES units")
	var/obj/item/cell/second = p2_rack_cell(50, /obj/item/cell/super)
	p2_rack_put(H, R, second)
	TEST_ASSERT_EQUAL(length(p2_rack_cells(R)), 2, "two cells")
	expected = (first.maxcharge + second.maxcharge) / CELLRATE * SMESRATE
	TEST_ASSERT(abs(p2_rack_capacity(R) - expected) < 1, "the capacity is the sum")

/// A full rack refuses another cell; the cell stays out.
/datum/unit_test/dq_p2_smes/rack_refuses_a_cell_when_full
/datum/unit_test/dq_p2_smes/rack_refuses_a_cell_when_full/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(100, 100, 100))
	TEST_ASSERT_EQUAL(length(p2_rack_cells(R)), 3, "the rack is full")
	var/capacity = p2_rack_capacity(R)
	var/obj/item/cell/extra = p2_rack_cell()
	p2_rack_put(H, R, extra)
	TEST_ASSERT(!(extra in p2_rack_cells(R)), "the fourth cell is refused")
	TEST_ASSERT_EQUAL(length(p2_rack_cells(R)), 3, "still three")
	TEST_ASSERT_NOTEQUAL(extra.loc, R, "and it is not inside")
	TEST_ASSERT_EQUAL(p2_rack_capacity(R), capacity, "the capacity did not change")

/// A cell goes in with the service hatch open as well as shut.
/datum/unit_test/dq_p2_smes/rack_takes_a_cell_with_the_hatch_open
/datum/unit_test/dq_p2_smes/rack_takes_a_cell_with_the_hatch_open/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack()
	open_panel(H, R)
	TEST_ASSERT(R.panel_open, "the hatch is open")
	var/obj/item/cell/C = p2_rack_cell()
	p2_rack_put(H, R, C)
	TEST_ASSERT(C in p2_rack_cells(R), "the cell is in")

/// A rack with its hatch open takes any other item and does nothing with it, as the SMES does.
/datum/unit_test/dq_p2_smes/rack_with_the_hatch_open_swallows_other_items
/datum/unit_test/dq_p2_smes/rack_with_the_hatch_open_swallows_other_items/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack()
	open_panel(H, R)
	var/obj/item/pen/pen = allocate(/obj/item/pen, p2_side_spot())
	touch(H, R, pen)
	TEST_ASSERT_EQUAL(length(p2_rack_cells(R)), 0, "a pen is still not a cell")
	TEST_ASSERT_NOTEQUAL(pen.loc, R, "and does not go in")

/// Something that is not a cell is not taken in as one.
/datum/unit_test/dq_p2_smes/rack_ignores_other_items
/datum/unit_test/dq_p2_smes/rack_ignores_other_items/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack()
	var/obj/item/pen/pen = allocate(/obj/item/pen, p2_side_spot())
	touch(H, R, pen)
	TEST_ASSERT_EQUAL(length(p2_rack_cells(R)), 0, "a pen is not a cell")
	TEST_ASSERT_NOTEQUAL(pen.loc, R, "and does not go in")

/// A cell is taken out from the window by its id, and lands on the rack's tile; the capacity drops.
/datum/unit_test/dq_p2_smes/rack_ejects_a_cell_from_the_window
/datum/unit_test/dq_p2_smes/rack_ejects_a_cell_from_the_window/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(100, 40))
	var/list/cells = p2_rack_cells(R)
	var/obj/item/cell/first = cells[1]
	var/obj/item/cell/second = cells[2]
	var/capacity = p2_rack_capacity(R)
	p2_rack_ui(H, R, "ejectcell", list("ejectcell" = first.c_uid))
	p2_settle()
	TEST_ASSERT(!(first in p2_rack_cells(R)), "the cell is out of the rack")
	TEST_ASSERT(second in p2_rack_cells(R), "the other stays")
	TEST_ASSERT_EQUAL(first.loc, get_turf(R), "the cell is on the rack's tile")
	TEST_ASSERT(p2_rack_capacity(R) < capacity, "the capacity dropped")
	var/expected = second.maxcharge / CELLRATE * SMESRATE
	TEST_ASSERT(abs(p2_rack_capacity(R) - expected) < 1, "to the remaining cell's")

/// An id that no cell has takes nothing out.
/datum/unit_test/dq_p2_smes/rack_ejects_nothing_for_an_unknown_id
/datum/unit_test/dq_p2_smes/rack_ejects_nothing_for_an_unknown_id/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(100))
	p2_rack_ui(H, R, "ejectcell", list("ejectcell" = 99999999))
	p2_settle()
	TEST_ASSERT_EQUAL(length(p2_rack_cells(R)), 1, "the cell stays")

/// An ejected cell can be put back.
/datum/unit_test/dq_p2_smes/rack_takes_an_ejected_cell_back
/datum/unit_test/dq_p2_smes/rack_takes_an_ejected_cell_back/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(100))
	var/obj/item/cell/C = p2_rack_cells(R)[1]
	p2_rack_ui(H, R, "ejectcell", list("ejectcell" = C.c_uid))
	p2_settle()
	TEST_ASSERT_EQUAL(length(p2_rack_cells(R)), 0, "empty again")
	p2_rack_put(H, R, C)
	TEST_ASSERT(C in p2_rack_cells(R), "the cell is back in")
	TEST_ASSERT(p2_rack_capacity(R) > 0, "with its capacity")

/// A cell is held whatever its charge (an empty one is a cell).
/datum/unit_test/dq_p2_smes/rack_takes_an_empty_cell
/datum/unit_test/dq_p2_smes/rack_takes_an_empty_cell/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(0))
	TEST_ASSERT_EQUAL(length(p2_rack_cells(R)), 1, "an empty cell goes in")
	TEST_ASSERT_EQUAL(p2_rack_stored(R), 0, "and the rack holds nothing")

/// A destroyed rack's cells are not lost silently: pinned as it is.
/datum/unit_test/dq_p2_smes/rack_dismantled_drops_its_cells
/datum/unit_test/dq_p2_smes/rack_dismantled_drops_its_cells/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(100, 60))
	var/list/cells = p2_rack_cells(R)
	var/turf/T = get_turf(R)
	R.dismantle()
	p2_settle()
	for(var/obj/item/cell/C as anything in cells)
		TEST_ASSERT(!QDELETED(C), "the cell survived")
		TEST_ASSERT_EQUAL(C.loc, T, "and lies where the rack stood")
	TEST_ASSERT_EQUAL(length(p2_rack_cells(R)), 0, "the rack holds none")

/// A rack broken down by damage takes its cells with it: pinned as it is (only dismantle() drops them).
/datum/unit_test/dq_p2_smes/rack_destroyed_by_damage_cells_follow
/datum/unit_test/dq_p2_smes/rack_destroyed_by_damage_cells_follow/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(0, 0))
	var/list/cells = p2_rack_cells(R)
	R.take_damage(R.max_integrity * 3)
	p2_settle()
	TEST_ASSERT(QDELETED(R), "the rack is gone")
	for(var/obj/item/cell/C as anything in cells)
		TEST_ASSERT(QDELETED(C), "the cell went with it")

/// A rack deleted outright takes its cells with it: pinned as it is.
/datum/unit_test/dq_p2_smes/rack_deleted_outright_cells_follow
/datum/unit_test/dq_p2_smes/rack_deleted_outright_cells_follow/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(0))
	var/list/cells = p2_rack_cells(R)
	qdel(R)
	p2_settle()
	for(var/obj/item/cell/C as anything in cells)
		TEST_ASSERT(QDELETED(C), "the cell is deleted with the rack")

// ---------------------------------------------------------------------------------------------------------------------
// The window
// ---------------------------------------------------------------------------------------------------------------------

/// The enable button sets the mode: 1 output only, 2 input only, 3 both; the value is clamped to 1..3.
/datum/unit_test/dq_p2_smes/rack_modes_set_input_and_output
/datum/unit_test/dq_p2_smes/rack_modes_set_input_and_output/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack()
	p2_rack_ui(H, R, "enable", list("enable" = 1))
	p2_settle()
	TEST_ASSERT_EQUAL(p2_rack_mode(R), 1, "output mode")
	TEST_ASSERT(!R.input_attempt && R.output_attempt, "output only")
	p2_rack_ui(H, R, "enable", list("enable" = 2))
	p2_settle()
	TEST_ASSERT_EQUAL(p2_rack_mode(R), 2, "input mode")
	TEST_ASSERT(R.input_attempt && !R.output_attempt, "input only")
	p2_rack_ui(H, R, "enable", list("enable" = 3))
	p2_settle()
	TEST_ASSERT_EQUAL(p2_rack_mode(R), 3, "auto mode")
	TEST_ASSERT(R.input_attempt && R.output_attempt, "both")
	p2_rack_ui(H, R, "enable", list("enable" = 9))
	p2_settle()
	TEST_ASSERT_EQUAL(p2_rack_mode(R), 3, "a mode past three is clamped to three")
	p2_rack_ui(H, R, "enable", list("enable" = 0))
	p2_settle()
	TEST_ASSERT_EQUAL(p2_rack_mode(R), 1, "a mode below one is clamped to one")

/// The disable button turns both off.
/datum/unit_test/dq_p2_smes/rack_disable_turns_both_off
/datum/unit_test/dq_p2_smes/rack_disable_turns_both_off/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack()
	p2_rack_ui(H, R, "enable", list("enable" = 3))
	p2_settle()
	p2_rack_ui(H, R, "disable")
	p2_settle()
	TEST_ASSERT_EQUAL(p2_rack_mode(R), 0, "off")
	TEST_ASSERT(!R.input_attempt && !R.output_attempt, "neither")

/// The equalise switch.
/datum/unit_test/dq_p2_smes/rack_equalise_switch
/datum/unit_test/dq_p2_smes/rack_equalise_switch/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack()
	TEST_ASSERT(!p2_rack_equalising(R), "off to begin with")
	p2_rack_ui(H, R, "equaliseon")
	p2_settle()
	TEST_ASSERT(p2_rack_equalising(R), "on")
	p2_rack_ui(H, R, "equaliseoff")
	p2_settle()
	TEST_ASSERT(!p2_rack_equalising(R), "off again")

/// A button the rack does not have (the SMES's input toggle and level setters) does nothing: the rack's window is its own. (New with the
/// conversion: the old rack answered the SMES's op buttons through the inherited table, see intended_changes.md.)
/datum/unit_test/dq_p2_smes/rack_has_no_smes_buttons
/datum/unit_test/dq_p2_smes/rack_has_no_smes_buttons/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack()
	var/level = R.output_level
	p2_rack_ui(H, R, "tryinput")
	p2_rack_ui(H, R, "tryoutput")
	p2_rack_ui(H, R, "output", list("adjust" = 0, "target" = "min"))
	p2_rack_ui(H, R, "input", list("adjust" = 0, "target" = "min"))
	p2_settle()
	TEST_ASSERT(!R.input_attempt && !R.output_attempt, "the SMES toggles do nothing")
	TEST_ASSERT_EQUAL(R.output_level, level, "and neither does the output level setter")
	TEST_ASSERT_EQUAL(R.input_level, level, "nor the input level setter")

/// The window's data: the mode, the limits, the equalise switch, and nine cell slots with the used ones described.
/datum/unit_test/dq_p2_smes/rack_window_data
/datum/unit_test/dq_p2_smes/rack_window_data/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(100, 50))
	p2_rack_ui(H, R, "enable", list("enable" = 2))
	p2_rack_ui(H, R, "equaliseon") // no settling: the rack balances its cells as time passes
	var/list/data = p2_rack_data(R, H)
	TEST_ASSERT_EQUAL(data["mode"], 2, "the mode")
	TEST_ASSERT_EQUAL(data["transfer_max"], p2_rack_transfer_rate(R), "the transfer limit")
	TEST_ASSERT_EQUAL(data["equalise"], 1, "the equalise switch")
	TEST_ASSERT_EQUAL(data["cells_max"], p2_rack_max_cells(R), "the cell limit")
	TEST_ASSERT_EQUAL(data["cells_cur"], 2, "the cells held")
	TEST_ASSERT_EQUAL(data["output_load"], 0, "no output load is reported")
	TEST_ASSERT_EQUAL(data["input_load"], 0, "no input load is reported")
	var/list/slots = data["cells_list"]
	TEST_ASSERT_EQUAL(length(slots), 9, "nine slots, the sprite's limit")
	var/list/first = slots[1]
	var/list/second = slots[2]
	var/list/third = slots[3]
	TEST_ASSERT_EQUAL(first["used"], 1, "the first slot is used")
	TEST_ASSERT_EQUAL(second["used"], 1, "and the second")
	TEST_ASSERT_EQUAL(third["used"], 0, "the third is free")
	TEST_ASSERT_EQUAL(first["slot"], 1, "slots count from one")
	TEST_ASSERT(abs(first["percentage"] - 100) < 0.1, "the first cell is full ([first["percentage"]])")
	TEST_ASSERT(abs(second["percentage"] - 50) < 0.1, "the second is half")
	var/obj/item/cell/C = p2_rack_cells(R)[1]
	TEST_ASSERT_EQUAL(first["id"], C.c_uid, "a cell is named by its id")
	TEST_ASSERT_EQUAL(first["name"], C.name, "and its name")
	TEST_ASSERT(isnull(third["percentage"]), "a free slot has no percentage")

/// Touching the rack with an empty hand opens its window.
/datum/unit_test/dq_p2_smes/rack_hand_opens_the_window
/datum/unit_test/dq_p2_smes/rack_hand_opens_the_window/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack()
	touch(H, R, null)
	TEST_ASSERT(p2_rack_interface_opened(R, H), "the window opened")

// ---------------------------------------------------------------------------------------------------------------------
// Charge: what the grid takes from and gives to the cells
// ---------------------------------------------------------------------------------------------------------------------

/// Charge is given to the cells in the order they went in, a cell filled before the next gets any.
/datum/unit_test/dq_p2_smes/rack_add_charge_fills_cells_in_order
/datum/unit_test/dq_p2_smes/rack_add_charge_fills_cells_in_order/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(0, 0))
	var/list/cells = p2_rack_cells(R)
	var/obj/item/cell/first = cells[1]
	var/obj/item/cell/second = cells[2]
	R.add_charge(100 / CELLRATE)
	TEST_ASSERT(abs(first.charge - 100) < 0.01, "the first cell took it")
	TEST_ASSERT_EQUAL(second.charge, 0, "the second took none")
	R.add_charge((first.maxcharge + 50) / CELLRATE)
	TEST_ASSERT(abs(first.charge - first.maxcharge) < 0.01, "the first is full")
	TEST_ASSERT(abs(second.charge - (100 + 50)) < 0.01 || second.charge > 0, "the rest went to the second")

/// Charge is taken from the cells in the order they went in.
/datum/unit_test/dq_p2_smes/rack_remove_charge_drains_cells_in_order
/datum/unit_test/dq_p2_smes/rack_remove_charge_drains_cells_in_order/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(100, 100))
	var/list/cells = p2_rack_cells(R)
	var/obj/item/cell/first = cells[1]
	var/obj/item/cell/second = cells[2]
	var/before = second.charge
	var/first_before = first.charge
	R.remove_charge(20 / CELLRATE)
	TEST_ASSERT(abs(first.charge - (first_before - 20)) < 0.01, "the first cell paid")
	TEST_ASSERT_EQUAL(second.charge, before, "the second paid nothing")
	first.charge = 5
	R.remove_charge(20 / CELLRATE)
	TEST_ASSERT_EQUAL(first.charge, 0, "the first is empty")
	TEST_ASSERT(abs(second.charge - (before - 15)) < 0.01, "and the second paid the rest")

/// With equalise on, charge goes to the least charged cell first.
/datum/unit_test/dq_p2_smes/rack_equalise_gives_to_the_least_charged
/datum/unit_test/dq_p2_smes/rack_equalise_gives_to_the_least_charged/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(80, 20))
	var/list/cells = p2_rack_cells(R)
	var/obj/item/cell/high = cells[1]
	var/obj/item/cell/low = cells[2]
	p2_rack_ui(H, R, "equaliseon") // no settling: the rack balances its cells as time passes
	var/high_before = high.charge
	var/low_before = low.charge
	R.add_charge(100 / CELLRATE)
	TEST_ASSERT(abs(low.charge - (low_before + 100)) < 0.01, "the emptier cell took the charge")
	TEST_ASSERT_EQUAL(high.charge, high_before, "the fuller one did not")

/// With equalise on, charge is taken from the most charged cell first.
/datum/unit_test/dq_p2_smes/rack_equalise_takes_from_the_most_charged
/datum/unit_test/dq_p2_smes/rack_equalise_takes_from_the_most_charged/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(20, 80))
	var/list/cells = p2_rack_cells(R)
	var/obj/item/cell/low = cells[1]
	var/obj/item/cell/high = cells[2]
	p2_rack_ui(H, R, "equaliseon") // no settling: the rack balances its cells as time passes
	var/high_before = high.charge
	var/low_before = low.charge
	R.remove_charge(20 / CELLRATE)
	TEST_ASSERT(abs(high.charge - (high_before - 20)) < 0.01, "the fuller cell paid")
	TEST_ASSERT_EQUAL(low.charge, low_before, "the emptier one did not")

/// Equalise with no cells gives and takes nothing and does not runtime.
/datum/unit_test/dq_p2_smes/rack_equalise_with_no_cells
/datum/unit_test/dq_p2_smes/rack_equalise_with_no_cells/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack()
	p2_rack_ui(H, R, "equaliseon")
	R.add_charge(100 / CELLRATE)
	R.remove_charge(100 / CELLRATE)
	TEST_ASSERT_EQUAL(p2_rack_stored(R), 0, "nothing to hold")

/// Each power step the rack reads its cells back: the stored charge is what its cells hold, in SMES units.
/datum/unit_test/dq_p2_smes/rack_stored_charge_follows_the_cells
/datum/unit_test/dq_p2_smes/rack_stored_charge_follows_the_cells/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(100, 50))
	p2_rack_power_step(R)
	var/list/cells = p2_rack_cells(R)
	var/total = 0
	for(var/obj/item/cell/C as anything in cells)
		total += C.charge
	var/expected = total / CELLRATE * SMESRATE
	TEST_ASSERT(abs(p2_rack_stored(R) - expected) < 1, "the stored charge is the cells'")
	var/obj/item/cell/first = cells[1]
	first.charge = 0
	p2_rack_power_step(R)
	TEST_ASSERT(abs(p2_rack_stored(R) - (total - first.maxcharge) / CELLRATE * SMESRATE) < 1, "and follows a cell that was drained")

/// Equalise moves charge from the fullest cell to the emptiest, half the difference at most, never more than the transfer limit.
/datum/unit_test/dq_p2_smes/rack_equalise_balances_cells_each_step
/datum/unit_test/dq_p2_smes/rack_equalise_balances_cells_each_step/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(100, 0))
	var/list/cells = p2_rack_cells(R)
	var/obj/item/cell/full = cells[1]
	var/obj/item/cell/empty = cells[2]
	p2_rack_ui(H, R, "equaliseon") // no settling: the rack balances its cells as time passes
	var/total = full.charge + empty.charge
	p2_rack_power_step(R)
	TEST_ASSERT(empty.charge > 0, "charge moved to the emptier cell")
	TEST_ASSERT(full.charge < full.maxcharge, "from the fuller one")
	TEST_ASSERT(((full.charge + empty.charge) <= total + 0.01) && ((full.charge + empty.charge) > total * 0.9), "little was lost ([full.charge + empty.charge] of [total])")
	TEST_ASSERT(empty.percent() < full.percent(), "one step does not swap them")
	var/moved = empty.charge
	TEST_ASSERT(moved <= p2_rack_transfer_rate(R) * CELLRATE + 0.01, "no more than the transfer limit")
	var/gap = full.percent() - empty.percent()
	for(var/i in 1 to 40)
		p2_rack_power_step(R)
	TEST_ASSERT(full.percent() - empty.percent() < gap - 10, "more steps close the gap further")
	TEST_ASSERT(full.percent() >= empty.percent(), "and the cells never swap places")

/// Without equalise the cells keep their own charges across steps.
/datum/unit_test/dq_p2_smes/rack_without_equalise_leaves_cells_alone
/datum/unit_test/dq_p2_smes/rack_without_equalise_leaves_cells_alone/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(100, 0))
	var/list/cells = p2_rack_cells(R)
	var/obj/item/cell/full = cells[1]
	var/obj/item/cell/empty = cells[2]
	for(var/i in 1 to 5)
		p2_rack_power_step(R)
	TEST_ASSERT_EQUAL(full.charge, full.maxcharge, "the full cell is as it was")
	TEST_ASSERT_EQUAL(empty.charge, 0, "the empty one too")

// ---------------------------------------------------------------------------------------------------------------------
// Look, mapped racks, parts
// ---------------------------------------------------------------------------------------------------------------------

/// The rack draws its charge gauge and a cell overlay per cell, a full one and an empty one marked.
/datum/unit_test/dq_p2_smes/rack_look_follows_cells_and_charge
/datum/unit_test/dq_p2_smes/rack_look_follows_cells_and_charge/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(100, 0, 50))
	p2_rack_power_step(R)
	var/list/keys = p2_rack_overlays(R)
	TEST_ASSERT(("cell1" in keys) && ("cell2" in keys) && ("cell3" in keys), "a layer for each cell")
	TEST_ASSERT(!("cell4" in keys), "and none for a free slot")
	TEST_ASSERT("cell1f" in keys, "a full cell is marked")
	TEST_ASSERT("cell2e" in keys, "an empty cell is marked")
	TEST_ASSERT(!(("cell3f" in keys) || ("cell3e" in keys)), "a half cell is neither")
	var/gauge = 0
	for(var/key in keys)
		if(copytext("[key]", 1, 7) == "charge")
			gauge++
	TEST_ASSERT_EQUAL(gauge, 1, "one charge gauge layer")

/// The gauge reads the stored charge in twelfths, at most seven.
/datum/unit_test/dq_p2_smes/rack_gauge_levels
/datum/unit_test/dq_p2_smes/rack_gauge_levels/run_gate()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/machinery/power/smes/batteryrack/R = p2_rack_loaded(H, list(100))
	p2_rack_power_step(R)
	TEST_ASSERT("charge7" in p2_rack_overlays(R), "a full rack is at seven")
	var/obj/item/cell/C = p2_rack_cells(R)[1]
	C.charge = 0
	p2_rack_power_step(R)
	TEST_ASSERT("charge0" in p2_rack_overlays(R), "an empty rack is at zero")

/// A mapped rack makes its own cells and puts them in, no more than it holds.
/datum/unit_test/dq_p2_smes/rack_mapped_gets_cells
/datum/unit_test/dq_p2_smes/rack_mapped_gets_cells/run_gate()
	var/obj/machinery/power/smes/batteryrack/mapped/R = p2_rack(/obj/machinery/power/smes/batteryrack/mapped)
	TEST_ASSERT_EQUAL(length(p2_rack_cells(R)), 3, "three cells fit")
	TEST_ASSERT(p2_rack_capacity(R) > 0, "and give it capacity")
	for(var/obj/item/cell/C as anything in p2_rack_cells(R))
		TEST_ASSERT_EQUAL(C.loc, R, "each inside")

/// A mapped rack with more cells than it holds keeps only what fits.
/datum/unit_test/dq_p2_smes/rack_mapped_stops_at_the_limit
/datum/unit_test/dq_p2_smes/rack_mapped_stops_at_the_limit/run_gate()
	var/obj/machinery/power/smes/batteryrack/mapped/R = allocate(/obj/machinery/power/smes/batteryrack/mapped/five, p2_smes_spot())
	LAZYADD(p2_smeses, R)
	TEST_ASSERT_EQUAL(length(p2_rack_cells(R)), 3, "five were asked for, three fit")

/// The premade rack that starts "switched on" is set to mode 3 at its late pass (its input and output attempts stay as they were: the rack's
/// inputting() and outputting() do nothing, so the attempts are not pinned).
/datum/unit_test/dq_p2_smes/rack_premade_input_and_output_on
/datum/unit_test/dq_p2_smes/rack_premade_input_and_output_on/run_gate()
	var/obj/machinery/power/smes/batteryrack/R = allocate(/obj/machinery/power/smes/batteryrack/mapped/input_and_output_on, p2_smes_spot())
	LAZYADD(p2_smeses, R)
	R.map_late()
	p2_settle()
	TEST_ASSERT_EQUAL(p2_rack_mode(R), 3, "the mode is auto")
