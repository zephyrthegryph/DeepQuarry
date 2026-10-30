// adjacency(KIND, dirs =, connects =, into =, when =, changed =) (code/engine/lifeforms/adjacency.dm; the index is verdigris/core/src/adjacency.rs).

#define ADJ_KIND_DQ_PROBE "dq_probe"

/obj/structure/dq_adjacency_probe
	name = "adjacency probe"
	anchored = TRUE
	var/adj_mask = 0
	var/changes = 0
	/// A probe that refuses to join (connects =).
	var/aloof = FALSE

CAPABILITIES(/obj/structure/dq_adjacency_probe)
	adjacency(ADJ_KIND_DQ_PROBE, connects = PROC_REF(joins), into = nameof(adj_mask), when = nameof(anchored), changed = PROC_REF(adj_mask_changed))

/obj/structure/dq_adjacency_probe/proc/joins(obj/structure/dq_adjacency_probe/other, bit)
	return !aloof && !other.aloof

/obj/structure/dq_adjacency_probe/proc/adj_mask_changed(mask)
	changes++

/obj/structure/dq_adjacency_probe/aloof
	aloof = TRUE

/datum/unit_test/dq_lifeform_adjacency

/datum/unit_test/dq_lifeform_adjacency/Run()
	var/turf/T = dq_containment_floor()
	var/turf/east = get_step(T, EAST)
	var/turf/east2 = get_step(east, EAST)
	var/turf/north = get_step(T, NORTH)
	TEST_ASSERT(east && east2 && north, "the test floor has room around it")

	var/obj/structure/dq_adjacency_probe/A = allocate(/obj/structure/dq_adjacency_probe, T)
	TEST_ASSERT_EQUAL(A.adj_mask, 0, "alone, it joins nothing")
	var/obj/structure/dq_adjacency_probe/B = allocate(/obj/structure/dq_adjacency_probe, east)
	TEST_ASSERT_EQUAL(A.adj_mask, EAST, "a neighbour's creation updates the member next to it")
	TEST_ASSERT_EQUAL(B.adj_mask, WEST, "and the new member sees it")
	TEST_ASSERT(A.changes >= 1, "changed = runs after the mask changed")

	B.forceMove(north)
	TEST_ASSERT_EQUAL(A.adj_mask, NORTH, "a move updates the old and the new neighbours")
	TEST_ASSERT_EQUAL(B.adj_mask, SOUTH, "the moved member is recomputed where it went")

	B.set_anchored(FALSE)
	TEST_ASSERT_EQUAL(A.adj_mask, 0, "a when = that turns false takes the member out")
	B.set_anchored(TRUE)
	TEST_ASSERT_EQUAL(A.adj_mask, NORTH, "and true again puts it back")

	var/obj/structure/dq_adjacency_probe/aloof/C = allocate(/obj/structure/dq_adjacency_probe/aloof, east)
	TEST_ASSERT_EQUAL(A.adj_mask, NORTH, "connects = decides: an aloof neighbour is seen but not joined")
	TEST_ASSERT(C in adjacency_seen(A, ADJ_KIND_DQ_PROBE), "adjacency_seen() lists every neighbour of the kind")

	qdel(B)
	TEST_ASSERT_EQUAL(A.adj_mask, 0, "a neighbour's destruction updates the member next to it")
	qdel(C)
	qdel(A)
	TEST_ASSERT_EQUAL(A.adj_handle, 0, "a destroyed member gives its handle back")
