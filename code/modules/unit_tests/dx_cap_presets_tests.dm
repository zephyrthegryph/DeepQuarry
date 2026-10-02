// The bundles (code/datums/capabilities/library/presets.dm).

/obj/machinery/cap_fixture_floor_machine
	name = "floor machine fixture"

/obj/machinery/cap_fixture_floor_machine/capabilities()
	. = ..()
	. += machine_basics(board = /obj/item/circuitboard)

/obj/machinery/cap_fixture_wall_machine
	name = "wall machine fixture"
	req_access = list(ACCESS_ENGINE_EQUIP)
	var/cover_held = TRUE

/obj/machinery/cap_fixture_wall_machine/capabilities()
	. = ..()
	. += wall_machine(board = /obj/item/circuitboard)
	. += maintenance_hatch(cover_holds = PROC_REF(cover_holds), panel_needs_cover_closed = TRUE, wires = /datum/wires/smes)

/obj/machinery/cap_fixture_wall_machine/proc/cover_holds()
	return cover_held

/obj/machinery/cap_fixture_computer
	name = "computer fixture"

/obj/machinery/cap_fixture_computer/capabilities()
	. = ..()
	. += console(board = /obj/item/circuitboard)

/obj/machinery/cap_fixture_computer/no_power/capabilities()
	. = ..()
	. = without(., /datum/capability/powered)

/proc/dx_bundle_kinds(atom/A)
	. = list()
	for(var/datum/capability/C as anything in caps_of(A))
		. += "[C.type]"

/proc/dx_bundle_entry(atom/A, cap_type)
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(istype(E.cap, cap_type))
			return E

/// The bundles contribute the expected capabilities, and a later same-key capability replaces in place.
/datum/unit_test/dx_bundles_contents/Run()
	var/obj/machinery/cap_fixture_floor_machine/floor = allocate(/obj/machinery/cap_fixture_floor_machine)
	var/list/kinds = dx_bundle_kinds(floor)
	for(var/path in list(/datum/capability/panel, /datum/capability/breakable, /datum/capability/powered, /datum/capability/anchor, /datum/capability/deconstruct))
		TEST_ASSERT("[path]" in kinds, "machine_basics has [path]")

	var/obj/machinery/cap_fixture_wall_machine/wall = allocate(/obj/machinery/cap_fixture_wall_machine)
	kinds = dx_bundle_kinds(wall)
	TEST_ASSERT(!("[/datum/capability/anchor]" in kinds), "a wall machine never unanchors")
	TEST_ASSERT("[/datum/capability/wall_mount]" in kinds, "a wall machine has the wall mount")
	var/panels = 0
	for(var/kind in kinds)
		if(kind == "[/datum/capability/panel]")
			panels++
	TEST_ASSERT_EQUAL(panels, 1, "the hatch's panel replaced the basics' panel (one per key)")
	TEST_ASSERT(kinds.Find("[/datum/capability/panel]") < kinds.Find("[/datum/capability/wall_mount]"), "replaced in the first one's position")

	var/obj/machinery/cap_fixture_computer/console = allocate(/obj/machinery/cap_fixture_computer)
	kinds = dx_bundle_kinds(console)
	TEST_ASSERT(!("[/datum/capability/panel]" in kinds), "a console has no maintenance panel")
	TEST_ASSERT("[/datum/capability/deconstruct]" in kinds, "a console deconstructs")
	var/obj/machinery/cap_fixture_computer/no_power/bare = allocate(/obj/machinery/cap_fixture_computer/no_power)
	TEST_ASSERT(!("[/datum/capability/powered]" in dx_bundle_kinds(bare)), "without() removes a bundle's entry")

/// The entry of `A` whose op has `key`, or null.
/proc/dx_bundle_op(atom/A, key)
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(E.op?.key == key)
			return E

/// maintenance_hatch() relations: coverlock, panel only with the cover closed, lock/emag only closed up.
/datum/unit_test/dx_bundles_hatch_relations/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/machinery/cap_fixture_wall_machine/M = allocate(/obj/machinery/cap_fixture_wall_machine, get_turf(H))
	var/datum/interaction/capability/cover = dx_bundle_entry(M, /datum/capability/cover)
	var/datum/interaction/capability/panel = dx_bundle_entry(M, /datum/capability/panel)
	var/datum/interaction/capability/lock = dx_bundle_op(M, CAP_LOCK)
	var/datum/interaction/capability/emag = dx_bundle_op(M, CAP_EMAG)
	TEST_ASSERT(cover && panel && lock && emag, "the hatch has its four entries")
	TEST_ASSERT_NOTNULL(compartment_of(M, BAY_HATCH), "and the compartment behind its cover")
	TEST_ASSERT_EQUAL(op_entry_reason(cover, H, M, null, null), "the cover is locked", "the coverlock holds the cover shut")
	M.cover_held = FALSE
	TEST_ASSERT_NULL(op_entry_reason(cover, H, M, null, null), "the cover opens once the coverlock releases")
	cap_set(M, CAP_COVER_OPEN, TRUE)
	M.cover_held = TRUE
	TEST_ASSERT_EQUAL(op_entry_reason(cover, H, M, null, null), "the cover is locked", "the holder's proc answers for closing too")
	M.cover_held = FALSE
	TEST_ASSERT_NULL(op_entry_reason(cover, H, M, null, null), "closing is allowed when the holder says so")
	TEST_ASSERT_EQUAL(op_entry_reason(panel, H, M, null, null), "close the cover first", "the wire panel needs the cover closed")
	TEST_ASSERT_EQUAL(op_entry_reason(lock, H, M, null, null), "close the cover first", "the ID lock needs the cover closed")
	TEST_ASSERT_EQUAL(op_entry_reason(emag, H, M, null, null), "close the cover first", "the emag needs the cover closed")
	cap_set(M, CAP_COVER_OPEN, FALSE)
	cap_set(M, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT_EQUAL(op_entry_reason(lock, H, M, null, null), "close the maintenance panel first", "the ID lock needs the panel closed")

/// Two types with the same bundle share its interned capability datums (the flyweight).
/datum/unit_test/dx_bundles_interned/Run()
	var/obj/machinery/cap_fixture_computer/A = allocate(/obj/machinery/cap_fixture_computer)
	var/obj/machinery/cap_fixture_computer/no_power/B = allocate(/obj/machinery/cap_fixture_computer/no_power)
	var/datum/capability/deconstruct/from_a = cap_of(A, /datum/capability/deconstruct)
	var/datum/capability/deconstruct/from_b = cap_of(B, /datum/capability/deconstruct)
	TEST_ASSERT(from_a && from_a == from_b, "the subtype's identical capability is the same datum")
