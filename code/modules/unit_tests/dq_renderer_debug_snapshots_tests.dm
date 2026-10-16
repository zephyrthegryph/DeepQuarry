/// Real renderer snapshots remain mutable, recursive, explicit and per-holder.
/datum/unit_test/dq_renderer_debug_snapshots

/datum/unit_test/dq_renderer_debug_snapshots/Run()
	var/obj/item/A = allocate(/obj/item, test_floor())
	var/obj/item/B = allocate(/obj/item, test_floor())
	var/mutable_appearance/child = new
	child.icon_state = "dq_renderer_child"
	var/mutable_appearance/root = new
	root.icon_state = "dq_renderer_root"
	root.overlays += child
	root.underlays += child
	A.overlays = list(root)
	A.underlays = list(child)
	A.realize_overlays()
	var/datum/cap_engine_state/state = cap_engine_state_of(A)
	TEST_ASSERT_NOTNULL(state, "explicit realization uses the actual native renderer context")
	TEST_ASSERT_EQUAL(length(state.realized_overlays), 3, "both nested overlay and underlay are flattened")
	TEST_ASSERT_EQUAL(length(state.realized_underlays), 1, "top-level underlays are captured separately")
	var/list/states = list()
	for(var/key in state.realized_overlays)
		var/mutable_appearance/entry = state.realized_overlays[key]
		states += entry.icon_state
	TEST_ASSERT_EQUAL(states[1], "dq_renderer_root", "parent stays first")
	TEST_ASSERT_EQUAL(states[2], "dq_renderer_child", "nested overlay follows parent")
	TEST_ASSERT_EQUAL(states[3], "dq_renderer_child", "duplicate nested underlay has a distinct debug key")
	var/list/first_snapshot = state.realized_overlays
	var/mutable_appearance/first = first_snapshot[first_snapshot[1]]
	first.icon_state = "dq_renderer_edited_snapshot"
	var/mutable_appearance/actual_root = A.overlays[1]
	TEST_ASSERT_EQUAL(actual_root.icon_state, "dq_renderer_root", "VV mutable snapshots do not mutate real appearance")
	A.overlays = list(child)
	TEST_ASSERT_EQUAL(state.realized_overlays, first_snapshot, "appearance changes do not implicitly refresh explicit snapshots")
	A.realize_overlays()
	TEST_ASSERT(state.realized_overlays != first_snapshot, "another explicit realization replaces its list")
	TEST_ASSERT_EQUAL(cap_engine_state_of(A), state, "renderer context identity survives repeated capture")
	B.realize_overlays()
	TEST_ASSERT(cap_engine_state_of(B) != state, "different atoms never share renderer snapshots")
	var/image/I = image()
	I.overlays = list(root)
	I.underlays = list(child)
	I.realize_overlays()
	TEST_ASSERT_EQUAL(length(I.realized_overlays), 3, "independent image API and recursion remain unchanged")
	TEST_ASSERT_EQUAL(length(I.realized_underlays), 1, "image underlay debug snapshot remains available")
	TEST_ASSERT(state.can_vv_get("realized_overlays"), "the actual context exposes its snapshot through native VV")
	TEST_ASSERT(state.can_vv_get("realized_underlays"), "both lists remain inspectable")
	qdel(A)
	TEST_ASSERT(QDELETED(state), "renderer context and its captured lists are released with the real holder")
