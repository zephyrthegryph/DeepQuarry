// Procs moved off the base types to globals (doc/rewrite/init_and_turfs.md
// section 0.5). These cover the converted call paths.

/datum/unit_test/dq_moved_admin_coordinates

/datum/unit_test/dq_moved_admin_coordinates/Run()
	var/turf/T = run_loc_floor_bottom_left
	TEST_ASSERT_EQUAL(Safe_COORD_Location(T), T, "a turf is its own coordinate location")
	var/obj/structure/closet/box = allocate(/obj/structure/closet, T)
	var/obj/item/paper/P = allocate(/obj/item/paper, box)
	TEST_ASSERT_EQUAL(Safe_COORD_Location(P), T, "an item in a closet resolves to the closet's turf")
	TEST_ASSERT_EQUAL(COORD(P), " ([T.x],[T.y],[T.z])", "COORD() of a contained item")
	TEST_ASSERT(findtext(ADMIN_COORDJMP(T), "adminplayerobservecoodjump"), "ADMIN_COORDJMP carries a jump link")
	TEST_ASSERT_NULL(get_ultimate_mob(P), "nothing holds the paper")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/held = allocate(/obj/item/paper, H)
	TEST_ASSERT_EQUAL(get_ultimate_mob(held), H, "an item inside a mob resolves to that mob")
	TEST_ASSERT(!isinspace(H), "a floor is not space")
	TEST_ASSERT_NULL(extra_admin_link(P, "_src_=holder"), "objects add no admin link")
	TEST_ASSERT_NULL(extra_ghost_link(H, H), "a clientless mob adds no ghost link")
	TEST_ASSERT(findtext(admin_jump_link(H, "x"), "JMP"), "admin_jump_link still builds")
	TEST_ASSERT(findtext(ghost_follow_link(H, H), "follow"), "ghost_follow_link still builds")
	vv_auto_rename(P, "renamed")
	TEST_ASSERT_EQUAL(P.name, "renamed", "vv_auto_rename sets the name")

/datum/unit_test/dq_moved_datum_helpers

/datum/unit_test/dq_moved_datum_helpers/Run()
	var/datum/D = new /datum
	var/list/first = typelist(D, "dq_moved_test", list(1, 2))
	var/list/second = typelist(new /datum, "dq_moved_test", list(3))
	TEST_ASSERT(first == second, "typelist is shared per type")
	TEST_ASSERT_EQUAL(length(first), 2, "typelist keeps the first values")
	TEST_ASSERT(!is_abstract(D), "a plain datum is not abstract")

	var/obj/machinery/chem_master/M = allocate(/obj/machinery/chem_master, run_loc_floor_bottom_left)
	TEST_ASSERT_NULL(tgui_modal_data(M), "no modal open yet")
	tgui_modal_input(M, "dq_test", "Enter:", null, list(), "abc")
	var/list/data = tgui_modal_data(M)
	TEST_ASSERT(islist(data), "an input modal is open")
	TEST_ASSERT_EQUAL(data["id"], "dq_test", "the modal carries its id")
	tgui_modal_clear(M)
	TEST_ASSERT_NULL(tgui_modal_data(M), "the modal clears")
