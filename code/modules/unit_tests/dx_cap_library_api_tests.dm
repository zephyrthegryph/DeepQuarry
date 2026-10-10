// Live legacy-slot bridge regression retained until the bridge itself retires.

/obj/cap_fixture/lib_slot
	var/obj/item/cell/cell

/obj/cap_fixture/lib_slot/capabilities()
	. = ..()
	. += cap_slot(nameof(cell), /obj/item/cell, part = LOOK_CELL, needs = req_clear(COVER))

/// A slot that draws its item: part, draws_var, req_clear gating; the accessors.
/datum/unit_test/dx_cap_library_slot_layer/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/lib_slot/A = allocate(/obj/cap_fixture/lib_slot, T)
	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	var/datum/capability/slot/S = slot_capability(A, nameof(A.cell))
	TEST_ASSERT_EQUAL(S.draws_var, nameof(A.cell), "a slot with a part draws its var")
	var/obj/item/cap_slot_probe/probe = allocate(/obj/item/cap_slot_probe, T)
	var/datum/capability/slot/plain = slot_capability(probe, nameof(probe.cell))
	TEST_ASSERT_NULL(plain.draws_var, "a slot without a part draws nothing")
	TEST_ASSERT_EQUAL(plain.layer_name, CAP_NO_LAYER, "its look name is CAP_NO_LAYER")
	var/datum/interaction/capability/insert
	for(var/datum/interaction/capability/slot_insert/E in cap_interactions(A))
		insert = E
	TEST_ASSERT(H.put_in_active_hand(cell), "holding a cell")
	cap_set(A, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT_EQUAL(insert.why_not(H, A, cell), "close the cover first", "req_clear(COVER) gates the slot")
	cap_set(A, CAP_COVER_OPEN, FALSE)
	TEST_ASSERT(insert.perform(H, A, cell), "inserting runs through cap_dispatch")
	TEST_ASSERT_EQUAL(A.cell, cell, "inserted")
	refresh_flush()
	var/datum/look/L = allocate(/datum/look)
	A.draw(L)
	var/shows_cell = LOOK_CELL in L.overlays
	for(var/list/part in L.parts)
		if(part[1] == LOOK_CELL || (!isnull(part[2]) && "[part[1]]-[part[2]]" == LOOK_CELL))
			shows_cell = TRUE
	TEST_ASSERT(shows_cell, "the slot's part is drawn while filled")
	L.reset()
