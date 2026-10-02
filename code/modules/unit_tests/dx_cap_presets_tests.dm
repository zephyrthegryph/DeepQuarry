// The bundles (code/datums/capabilities/library/presets.dm).

/obj/machinery/cap_fixture_floor_machine
	name = "floor machine fixture"

/obj/machinery/cap_fixture_floor_machine/capabilities()
	. = ..()
	. += legacy_machine_basics(board = /obj/item/circuitboard)

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

	var/obj/machinery/cap_fixture_computer/console = allocate(/obj/machinery/cap_fixture_computer)
	kinds = dx_bundle_kinds(console)
	TEST_ASSERT(!("[/datum/capability/panel]" in kinds), "a console has no maintenance panel")
	TEST_ASSERT("[/datum/capability/deconstruct]" in kinds, "a console deconstructs")
	var/obj/machinery/cap_fixture_computer/no_power/bare = allocate(/obj/machinery/cap_fixture_computer/no_power)
	TEST_ASSERT(!("[/datum/capability/powered]" in dx_bundle_kinds(bare)), "without() removes a bundle's entry")

/// Two types with the same bundle share its interned capability datums (the flyweight).
/datum/unit_test/dx_bundles_interned/Run()
	var/obj/machinery/cap_fixture_computer/A = allocate(/obj/machinery/cap_fixture_computer)
	var/obj/machinery/cap_fixture_computer/no_power/B = allocate(/obj/machinery/cap_fixture_computer/no_power)
	var/datum/capability/deconstruct/from_a = cap_of(A, /datum/capability/deconstruct)
	var/datum/capability/deconstruct/from_b = cap_of(B, /datum/capability/deconstruct)
	TEST_ASSERT(from_a && from_a == from_b, "the subtype's identical capability is the same datum")
