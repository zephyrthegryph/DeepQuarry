// The capability presets (code/datums/capabilities/library/presets.dm).

/obj/machinery/cap_fixture_floor_machine
	name = "floor machine fixture"

/obj/machinery/cap_fixture_floor_machine/capabilities()
	. = ..()
	. += cap_floor_machine(board = /obj/item/circuitboard, wires = /datum/wires/smes)

/obj/machinery/cap_fixture_wall_machine
	name = "wall machine fixture"

/obj/machinery/cap_fixture_wall_machine/capabilities()
	. = ..()
	. += cap_wall_machine(board = /obj/item/circuitboard)

/obj/machinery/cap_fixture_computer
	name = "computer fixture"

/obj/machinery/cap_fixture_computer/capabilities()
	. = ..()
	. += cap_computer(board = /obj/item/circuitboard)

/obj/machinery/cap_fixture_computer/no_power/capabilities()
	. = ..()
	. = without(., /datum/capability/powered)

/proc/dx_preset_kinds(atom/A)
	. = list()
	for(var/datum/capability/C as anything in caps_of(A))
		. += "[C.type]"

/// The presets contribute the expected capabilities, in order, and without() edits them like any list.
/datum/unit_test/dx_cap_presets_contents/Run()
	var/obj/machinery/cap_fixture_floor_machine/floor = allocate(/obj/machinery/cap_fixture_floor_machine)
	var/list/kinds = dx_preset_kinds(floor)
	TEST_ASSERT("[/datum/capability/panel]" in kinds, "floor machine has a panel")
	TEST_ASSERT("[/datum/capability/breakable]" in kinds, "floor machine breaks")
	TEST_ASSERT("[/datum/capability/powered]" in kinds, "floor machine goes dark without power")
	TEST_ASSERT("[/datum/capability/wires]" in kinds, "floor machine has its wires")
	TEST_ASSERT("[/datum/capability/deconstruct]" in kinds, "floor machine deconstructs")
	TEST_ASSERT("[/datum/capability/anchor]" in kinds, "floor machine anchors")
	TEST_ASSERT(kinds.Find("[/datum/capability/panel]") < kinds.Find("[/datum/capability/anchor]"), "the preset keeps its order")

	var/obj/machinery/cap_fixture_wall_machine/wall = allocate(/obj/machinery/cap_fixture_wall_machine)
	kinds = dx_preset_kinds(wall)
	TEST_ASSERT(!("[/datum/capability/anchor]" in kinds), "a wall machine never unanchors")
	TEST_ASSERT(!("[/datum/capability/wires]" in kinds), "no wires unless given")
	TEST_ASSERT("[/datum/capability/deconstruct]" in kinds, "wall machine deconstructs")

	var/obj/machinery/cap_fixture_computer/console = allocate(/obj/machinery/cap_fixture_computer)
	kinds = dx_preset_kinds(console)
	TEST_ASSERT(!("[/datum/capability/panel]" in kinds), "a computer has no maintenance panel")
	TEST_ASSERT("[/datum/capability/deconstruct]" in kinds, "a computer deconstructs")

	var/obj/machinery/cap_fixture_computer/no_power/bare = allocate(/obj/machinery/cap_fixture_computer/no_power)
	TEST_ASSERT(!("[/datum/capability/powered]" in dx_preset_kinds(bare)), "without() removes a preset's entry")

/// Presets gate like their parts: the floor machine's deconstruct entry needs the panel open.
/datum/unit_test/dx_cap_presets_gating/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/machinery/cap_fixture_floor_machine/floor = allocate(/obj/machinery/cap_fixture_floor_machine, get_turf(H))
	var/datum/interaction/capability/dismantle
	for(var/datum/interaction/capability/E as anything in cap_interactions(floor))
		if(istype(E.cap, /datum/capability/deconstruct))
			dismantle = E
	TEST_ASSERT_NOTNULL(dismantle, "the deconstruct entry exists")
	TEST_ASSERT(dismantle.behind & PANEL, "deconstruction is behind the panel")
	TEST_ASSERT_EQUAL(cap_gate_reason(floor, H, null, dismantle), "open the maintenance panel first", "refused with the panel closed")
	cap_set(floor, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT_NULL(cap_gate_reason(floor, H, null, dismantle), "allowed with the panel open")

/// Two types using the same preset share its interned capability datums (the flyweight).
/datum/unit_test/dx_cap_presets_interned/Run()
	var/obj/machinery/cap_fixture_computer/A = allocate(/obj/machinery/cap_fixture_computer)
	var/obj/machinery/cap_fixture_computer/no_power/B = allocate(/obj/machinery/cap_fixture_computer/no_power)
	var/datum/capability/deconstruct/from_a = cap_of(A, /datum/capability/deconstruct)
	var/datum/capability/deconstruct/from_b = cap_of(B, /datum/capability/deconstruct)
	TEST_ASSERT(from_a && from_a == from_b, "the subtype's identical capability is the same datum")
