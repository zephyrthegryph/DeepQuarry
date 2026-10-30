// The hop kinds that are not vars (code/engine/refs/hops.dm): the turf and area hops resolve through any nesting, the movement choke point
// publishes them, and a draw that reads a var one container hop away redraws when that var changes there.

/obj/dq_hop_box
	name = "hop box"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/shown = 0


/obj/dq_hop_item
	name = "hop item"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"

/obj/dq_hop_item/draw(datum/look/look)
	..()
	var/obj/dq_hop_box/B = loc
	if(istype(B))
		look.overlay("box-[B.shown]")

/// A cell in a crate: a draw inside the crate reads the cell's level through two hops (the container, then a declared relation).
/obj/dq_hop_cell
	name = "hop cell"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/gauge_level = 0


/obj/dq_hop_crate
	name = "hop crate"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/obj/dq_hop_cell/gauge

CAPABILITIES(/obj/dq_hop_crate)
	ref_one(nameof(gauge), /obj/dq_hop_cell)

/obj/dq_hop_reader
	name = "hop reader"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"

/obj/dq_hop_reader/draw(datum/look/look)
	..()
	var/obj/dq_hop_crate/C = loc
	if(istype(C) && C.gauge)
		look.overlay("level-[C.gauge.gauge_level]")

/datum/unit_test/dq_hop_turf_and_area_resolve_through_nesting

/datum/unit_test/dq_hop_turf_and_area_resolve_through_nesting/Run()
	var/turf/T = test_floor()
	var/obj/dq_hop_box/B = allocate(/obj/dq_hop_box, T)
	var/obj/dq_hop_item/I = allocate(/obj/dq_hop_item, B)
	TEST_ASSERT_EQUAL(hop_step(I, HOP_TURF), T, "the turf hop reaches the turf through the box")
	TEST_ASSERT_EQUAL(hop_step(I, HOP_AREA), T.loc, "and the area hop the area")
	TEST_ASSERT_EQUAL(hop_step(T, HOP_TURF), T, "a turf's turf is itself")
	TEST_ASSERT_EQUAL(hop_step(I, "loc"), B, "a var segment is the var")
	TEST_ASSERT((I in hop_sources(T, HOP_TURF)), "the reverse of the turf hop finds what stands on it at any depth")
	TEST_ASSERT((I in hop_sources(B, "loc")), "the reverse of the container hop finds what is inside")
	TEST_ASSERT_EQUAL(change_walk(I, "turf.x"), T.x, "a hop path walks the turf hop")

/datum/unit_test/dq_hop_draw_hears_its_container

/datum/unit_test/dq_hop_draw_hears_its_container/Run()
	var/turf/T = test_floor()
	var/obj/dq_hop_box/B = allocate(/obj/dq_hop_box, T)
	var/obj/dq_hop_item/I = allocate(/obj/dq_hop_item, B)
	TEST_ASSERT(("loc.shown" in draw_hop_reads_of(I)), "the build generated the hop read: [json_encode(draw_hop_reads_of(I))]")
	state_changed(I)
	refresh_flush()
	TEST_ASSERT(("box-0" in I.rx?.look_overlays), "the draw read the container: [json_encode(I.rx?.look_overlays)]")
	B.set_shown(2)
	refresh_flush()
	TEST_ASSERT(("box-2" in I.rx?.look_overlays), "a change on the container redraws what is inside: [json_encode(I.rx?.look_overlays)]")

/datum/unit_test/dq_hop_draw_hears_a_two_hop_chain

/datum/unit_test/dq_hop_draw_hears_a_two_hop_chain/Run()
	var/turf/T = test_floor()
	var/obj/dq_hop_crate/C = allocate(/obj/dq_hop_crate, T)
	var/obj/dq_hop_cell/first = allocate(/obj/dq_hop_cell, T)
	var/obj/dq_hop_cell/second = allocate(/obj/dq_hop_cell, T)
	rel_set(C, nameof(C.gauge), first)
	var/obj/dq_hop_reader/R = allocate(/obj/dq_hop_reader, C)
	TEST_ASSERT(("loc.gauge.gauge_level" in draw_hop_reads_of(R)), "the build generated the chain: [json_encode(draw_hop_reads_of(R))]")
	state_changed(R)
	refresh_flush()
	TEST_ASSERT(("level-0" in R.rx?.look_overlays), "the draw read through the crate to the cell: [json_encode(R.rx?.look_overlays)]")
	first.set_gauge_level(3)
	refresh_flush()
	TEST_ASSERT(("level-3" in R.rx?.look_overlays), "the far end of the chain changed and the draw redrew: [json_encode(R.rx?.look_overlays)]")
	second.set_gauge_level(5)
	rel_set(C, nameof(C.gauge), second)
	refresh_flush()
	TEST_ASSERT(("level-5" in R.rx?.look_overlays), "a link of the chain changed and the draw redrew: [json_encode(R.rx?.look_overlays)]")
