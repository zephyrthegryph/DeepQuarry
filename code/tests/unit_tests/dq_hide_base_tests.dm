// The base hide() (/obj/proc/hide): a thing that hides under flooring goes out of sight under intact tiles and comes back when they come up; anything
// else ignores it, even when a wall hides what stands in it (walls.dm calls hide(1) on its contents).

/// A navbeacon (no hide() of its own) hides under the tiles and shows when they come up; a terminal draws faded while hidden.
/datum/unit_test/dq_hide_base_hides_floor_things

/datum/unit_test/dq_hide_base_hides_floor_things/Run()
	var/turf/simulated/floor/floor = test_floor()
	TEST_ASSERT(istype(floor) && !floor.is_plating(), "the test floor has tiles on")
	var/datum/decl/flooring/tiles = floor.flooring
	var/obj/machinery/navbeacon/beacon = allocate(/obj/machinery/navbeacon, floor)
	var/obj/machinery/power/terminal/term = allocate(/obj/machinery/power/terminal, floor)
	floor.levelupdate()
	refresh_flush()
	TEST_ASSERT(beacon.invisibility >= INVISIBILITY_ABSTRACT, "the beacon hides under intact tiles")
	TEST_ASSERT(term.invisibility >= INVISIBILITY_ABSTRACT, "so does the terminal")
	floor.make_plating()
	refresh_flush()
	TEST_ASSERT(beacon.invisibility < INVISIBILITY_ABSTRACT, "the beacon shows on plating")
	TEST_ASSERT(term.invisibility < INVISIBILITY_ABSTRACT, "so does the terminal")
	floor.install_flooring(tiles)

/// Something that does not hide under flooring stays in sight when told to hide (a wall hiding its contents).
/datum/unit_test/dq_hide_base_ignores_others

/datum/unit_test/dq_hide_base_ignores_others/Run()
	var/obj/item/thing = allocate(/obj/item, test_floor())
	var/before = thing.invisibility
	thing.hide(TRUE)
	TEST_ASSERT_EQUAL(thing.invisibility, before, "an item is not hidden by hide()")

/// A T-ray scan of a hidden thing that still owes its first draw (the cover withheld it) draws it before building the scan image, so the image shows
/// its drawn state (the terminal's faded "term-f"), not the type's default.
/datum/unit_test/dq_tray_draws_covered_owed

/datum/unit_test/dq_tray_draws_covered_owed/Run()
	var/turf/simulated/floor/floor = test_floor()
	TEST_ASSERT(istype(floor) && !floor.is_plating(), "the test floor has tiles on")
	var/obj/machinery/power/terminal/term = allocate(/obj/machinery/power/terminal, floor)
	floor.levelupdate()
	refresh_flush()
	TEST_ASSERT(term.invisibility >= INVISIBILITY_ABSTRACT, "the terminal hides under the tiles")
	rx_of(term).look_key = null
	term.set_icon_state("term")
	interest_test_park(term) // owes its first draw, as the cover leaves it
	var/obj/item/t_scanner/scanner = allocate(/obj/item/t_scanner, floor)
	GLOB.overlay_cache -= handle_of(term)
	var/image/I = scanner.get_overlay(term)
	TEST_ASSERT(!term.refresh_queued, "the scan drew what it owed")
	TEST_ASSERT(!isnull(term.rx?.look_key), "and it has a look")
	TEST_ASSERT_EQUAL(I.icon_state, "term-f", "the scan image shows the drawn (faded) state")
