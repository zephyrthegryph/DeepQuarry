// Behaviour-preservation tests for the wall frame items (/obj/item/frame and its subtypes): a frame held to a wall becomes the thing it frames,
// fixed to that wall, where the builder stands. Written against the legacy try_build() path and kept passing now that the build is the frame
// item's own op (frame.mount). Input is the player's click (test_click()), never a proc of the frame.
// A wrench on a loose frame takes it apart into its materials (the frame's op frame.refund).

/// A wall beside the run block's corner (made one for the test if the map has none there), and the turf it was.
/datum/unit_test/dq_p2_apc/frame
	abstract_type = /datum/unit_test/dq_p2_apc/frame
	var/turf/frame_wall
	var/frame_wall_was

/datum/unit_test/dq_p2_apc/frame/proc/wall_beside(turf/T)
	frame_wall = get_step(T, SOUTH)
	frame_wall_was = frame_wall.type
	if(!istype(frame_wall, /turf/simulated/wall))
		frame_wall.ChangeTurf(/turf/simulated/wall)
	return frame_wall

/datum/unit_test/dq_p2_apc/frame/proc/restore_wall()
	if(frame_wall && frame_wall.type != frame_wall_was)
		frame_wall.ChangeTurf(frame_wall_was)

/// The APCs of the test area, besides the ones the test made.
/datum/unit_test/dq_p2_apc/frame/proc/area_apc_count()
	. = 0
	for(var/obj/machinery/power/apc/A in REGISTRY_MEMBERS(REGISTRY_APCS))
		if(get_area(A) == p2_area)
			.++

/// An APC frame held to a wall makes a bare APC frame there: no cell, the cover open, the breaker off, at the first build stage.
/datum/unit_test/dq_p2_apc/frame/apc_frame_mounts_a_bare_frame

/datum/unit_test/dq_p2_apc/frame/apc_frame_mounts_a_bare_frame/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	p2_area.set_requires_power(TRUE)
	p2_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	if(p2_area.get_apc())
		restore_wall()
		return // the test map's area has its own APC: the frame would be refused (the next test pins that)
	var/turf/wall = wall_beside(T)
	var/mob/living/carbon/human/H = p2_actor(T)
	var/obj/item/frame/apc/frame = allocate(/obj/item/frame/apc, T)
	touch(H, wall, frame)
	var/obj/machinery/power/apc/A = locate() in T
	if(A)
		LAZYADD(p2_apcs, A)
	restore_wall()
	TEST_ASSERT_NOTNULL(A, "the frame became an APC where the builder stands")
	TEST_ASSERT(QDELETED(frame), "the frame item is used up")
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "frame", "a bare frame")
	TEST_ASSERT_NULL(A.cell, "with no cell")
	TEST_ASSERT(p2_apc_cover_open(A), "its cover open")
	TEST_ASSERT(!A.operating, "and its breaker off")
	TEST_ASSERT_EQUAL(A.dir, SOUTH, "facing the wall it hangs on")

/// An area that has an APC takes no second one: the frame stays in hand.
/datum/unit_test/dq_p2_apc/frame/apc_frame_refused_where_the_area_has_one

/datum/unit_test/dq_p2_apc/frame/apc_frame_refused_where_the_area_has_one/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	p2_area.set_requires_power(TRUE)
	p2_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	var/obj/machinery/power/apc/existing = p2_apc(run_loc_floor_top_right)
	TEST_ASSERT_EQUAL(p2_area.get_apc(), existing, "the area has its APC")
	var/turf/wall = wall_beside(T)
	var/mob/living/carbon/human/H = p2_actor(T)
	var/obj/item/frame/apc/frame = allocate(/obj/item/frame/apc, T)
	var/before = area_apc_count()
	touch(H, wall, frame)
	restore_wall()
	TEST_ASSERT(!QDELETED(frame), "the frame is not used")
	TEST_ASSERT_EQUAL(area_apc_count(), before, "and no APC is made")

/// A light fixture frame held to a wall makes the fixture's construction frame there.
/datum/unit_test/dq_p2_apc/frame/light_frame_mounts_a_fixture_frame

/datum/unit_test/dq_p2_apc/frame/light_frame_mounts_a_fixture_frame/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	p2_area.set_requires_power(TRUE)
	p2_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	var/turf/wall = wall_beside(T)
	var/mob/living/carbon/human/H = p2_actor(T)
	var/obj/item/frame/light/frame = allocate(/obj/item/frame/light, T)
	touch(H, wall, frame)
	var/obj/machinery/light_construct/L = locate() in T
	restore_wall()
	TEST_ASSERT_NOTNULL(L, "the fixture frame is on the wall where the builder stands")
	TEST_ASSERT(QDELETED(frame), "the frame item is used up")
	TEST_ASSERT_EQUAL(L.dir, SOUTH, "facing out of the wall")
	qdel(L)

/// A frame held to a wall from a spot that is not a floor makes nothing.
/datum/unit_test/dq_p2_apc/frame/frame_needs_a_floor_to_stand_on

/datum/unit_test/dq_p2_apc/frame/frame_needs_a_floor_to_stand_on/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	p2_area.set_requires_power(FALSE)
	p2_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	var/turf/wall = wall_beside(T)
	var/mob/living/carbon/human/H = p2_actor(T)
	var/obj/item/frame/light/frame = allocate(/obj/item/frame/light, T)
	touch(H, wall, frame)
	var/obj/machinery/light_construct/L = locate() in T
	restore_wall()
	TEST_ASSERT_NULL(L, "an area that needs no power takes no fixture")
	TEST_ASSERT(!QDELETED(frame), "and the frame is not used")

/// A wrench on a loose frame takes it apart: the frame is gone and its five sheets of steel lie where it was.
/datum/unit_test/dq_p2_apc/frame/wrench_refunds_a_loose_frame

/datum/unit_test/dq_p2_apc/frame/wrench_refunds_a_loose_frame/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = p2_actor(T)
	var/obj/item/frame/frame = allocate(/obj/item/frame, T)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, T)
	W.toolspeed = 0
	touch(H, frame, W)
	TEST_ASSERT(QDELETED(frame), "the frame is taken apart")
	var/sheets = 0
	for(var/obj/item/stack/material/steel/S in T)
		sheets += S.get_amount()
	TEST_ASSERT_EQUAL(sheets, 5, "into five sheets of steel")
	for(var/obj/item/stack/material/steel/S in T)
		qdel(S)

/// A frame held in the other hand is taken apart all the same.
/datum/unit_test/dq_p2_apc/frame/wrench_refunds_a_held_frame

/datum/unit_test/dq_p2_apc/frame/wrench_refunds_a_held_frame/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = p2_actor(T)
	var/obj/item/frame/frame = allocate(/obj/item/frame, T)
	H.put_in_inactive_hand(frame)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, T)
	W.toolspeed = 0
	H.put_in_active_hand(W)
	test_click(H, frame, W)
	p2_settle()
	TEST_ASSERT(QDELETED(frame), "the held frame is taken apart")
	for(var/obj/item/stack/material/steel/S in range(1, T))
		qdel(S)
