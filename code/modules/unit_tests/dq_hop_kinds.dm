// The hop kinds that are not vars (code/engine/refs/hops.dm): the turf and area hops resolve through any nesting, the movement choke point
// publishes them, and a draw that reads a var one container hop away redraws when that var changes there.

/obj/dq_hop_box
	name = "hop box"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/shown = 0

TRACKED(/obj/dq_hop_box, shown)

/obj/dq_hop_item
	name = "hop item"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"

/obj/dq_hop_item/draw(datum/look/look)
	..()
	var/obj/dq_hop_box/B = loc
	if(istype(B))
		look.overlay("box-[B.shown]")

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
