// This otherwise-latent pen has a real variant row with an observable applied effect.
/obj/item/pen/dq_storage_variant

CAPABILITIES(/obj/item/pen/dq_storage_variant)
	variants(nameof(variant), PROC_REF(storage_variant_table))

/obj/item/pen/dq_storage_variant/proc/storage_variant_table()
	var/static/list/rows = list("red" = list("name" = "phase-applied red pen"))
	return rows

// Constructor observations, not synthetic callbacks around the storage initializer.
/obj/item/dq_storage_birth_probe
	storage_cost = 42
	var/owner_initialized
	var/owner_materialized
	var/owner_had_emissive
	var/owner_space_at_birth
	var/owner_actions_at_birth

/obj/item/dq_storage_birth_probe/Initialize(mapload)
	var/obj/item/storage/S = src.loc
	if(istype(S))
		owner_initialized = !!(S.flags & ATOM_INITIALIZED)
		owner_materialized = !!(S.flags & ATOM_MATERIALIZED)
		owner_space_at_birth = S.max_storage_space
		owner_actions_at_birth = length(S.actions)
		for(var/entry in S.overlays)
			var/image/I = entry
			if(I.plane == PLANE_EMISSIVE)
				owner_had_emissive = TRUE
	return ..()

/datum/action/item_action/dq_storage_order_probe
	var/owner_space_at_action
	var/unsafe_children_at_action

/datum/action/item_action/dq_storage_order_probe/New(Target)
	. = ..()
	var/obj/item/storage/S = action_target()
	owner_space_at_action = S.max_storage_space
	for(var/obj/item/dq_storage_birth_probe/I in S.contents)
		unsafe_children_at_action++

/obj/item/storage/box/dq_storage_order_probe
	max_storage_space = 1
	starts_with = list(/obj/item/dq_storage_birth_probe = list(1), /obj/item/paper = list(2), /obj/item/pen/dq_storage_variant = list(1, "red"))
	actions_types = list(/datum/action/item_action/dq_storage_order_probe)
	var/entered_initialized
	var/entered_materialized

/obj/item/storage/box/dq_storage_order_probe/Entered(atom/movable/thing, atom/OldLoc)
	if(istype(thing, /obj/item/dq_storage_birth_probe))
		entered_initialized = !!(flags & ATOM_INITIALIZED)
		entered_materialized = !!(flags & ATOM_MATERIALIZED)
	return ..()

/obj/item/storage/box/dq_storage_order_probe/empty
	empty = TRUE

/datum/unit_test/dq_storage_native_phase

/datum/unit_test/dq_storage_native_phase/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/storage/box/dq_storage_order_probe/S = allocate(/obj/item/storage/box/dq_storage_order_probe, test_floor())
	var/obj/item/dq_storage_birth_probe/I = locate() in S
	TEST_ASSERT(I, "the actual unsafe generator child is eagerly constructed")
	TEST_ASSERT(I.owner_initialized && S.entered_initialized, "real child initialization and storage Entered both see ATOM_INITIALIZED")
	TEST_ASSERT(!I.owner_materialized && !S.entered_materialized, "both real callbacks run before the owner materializes")
	TEST_ASSERT(I.owner_had_emissive, "the actual movable parent appearance already exists before unsafe child initialization")
	TEST_ASSERT_EQUAL(I.owner_space_at_birth, 1, "unsafe construction still precedes capacity calibration")
	TEST_ASSERT_EQUAL(I.owner_actions_at_birth, 0, "the unsafe child is still made before item actions")
	var/obj/item/pen/dq_storage_variant/P = locate() in S
	TEST_ASSERT(P && P.variant == "red", "a variant-marked otherwise-safe pen is eagerly created")
	TEST_ASSERT_EQUAL(P.name, "phase-applied red pen", "the actual variant row was applied, not merely its key assigned")
	TEST_ASSERT(S.has_latent(), "plain safe papers remain latent at constructor return")
	TEST_ASSERT_NULL(locate(/obj/item/paper) in S, "the safe paper has not been eagerly allocated")
	var/expected = 42 + dq_type_storage_cost(/obj/item/paper) * 2 + P.get_storage_cost()
	TEST_ASSERT_EQUAL(S.max_storage_space, expected, "calibration accounts for exact eager and latent costs")
	var/datum/action/item_action/dq_storage_order_probe/A = locate() in S.actions
	TEST_ASSERT(A, "the real declared item action is created")
	TEST_ASSERT_EQUAL(A.owner_space_at_action, expected, "actual action New observes calibrated capacity, not the old default")
	TEST_ASSERT_EQUAL(A.unsafe_children_at_action, 1, "the actual action observes precisely one unsafe child")
	S.make_contents_real()
	TEST_ASSERT_EQUAL(S.held_count(), 4, "materialization preserves all original generator multiplicities")
	S.make_contents_real()
	TEST_ASSERT_EQUAL(S.held_count(), 4, "repeated materialization never repeats starting effects")
	var/obj/item/storage/box/dq_storage_order_probe/empty/E = allocate(/obj/item/storage/box/dq_storage_order_probe/empty, test_floor())
	TEST_ASSERT_EQUAL(E.held_count(), 0, "the actual empty override suppresses both eager and latent contents")
	TEST_ASSERT_NULL(E.starts_with, "empty construction clears the original generator")
	TEST_ASSERT_EQUAL(E.max_storage_space, 1, "empty storage does not invent capacity")
	qdel(S)
	TEST_ASSERT(QDELETED(I) && QDELETED(P), "real storage destruction disposes its real contained children")

/datum/unit_test/dq_storage_native_descendants

/datum/unit_test/dq_storage_native_descendants/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/storage/box/remote_scene_tools/R = allocate(/obj/item/storage/box/remote_scene_tools, test_floor())
	var/list/tools = list()
	var/cost = 0
	for(var/obj/item/remote_scene_tool/I in R)
		tools += I
		cost += I.get_storage_cost()
	TEST_ASSERT_EQUAL(length(tools), 2, "the actual remote kit creates exactly two devices")
	var/obj/item/remote_scene_tool/first = tools[1]
	var/obj/item/remote_scene_tool/second = tools[2]
	TEST_ASSERT_EQUAL(first.linked(), second, "the actual first device links its exact counterpart")
	TEST_ASSERT_EQUAL(second.linked(), first, "the actual reciprocal connection survives construction")
	TEST_ASSERT(R.max_storage_space >= cost, "the original second calibration includes the linked devices")
	var/obj/item/storage/belt/utility/fluff/vulpine/V = allocate(/obj/item/storage/belt/utility/fluff/vulpine, test_floor())
	TEST_ASSERT_EQUAL(V.held_count(), 7, "the actual belt creates each original tool once")
	TEST_ASSERT_EQUAL(V.max_storage_space, initial(V.max_storage_space), "the original belt tail adds tools after calibration without silently growing capacity")
	var/obj/item/stack/cable_coil/C = locate() in V
	TEST_ASSERT(C && C.amount == 30, "the real cable still receives its original positional amount argument")
	TEST_ASSERT_EQUAL(C.color, COLOR_RED, "the actual coil keeps its original red constructor selection")
	var/obj/item/storage/fancy/fluff/charlotte/F = allocate(/obj/item/storage/fancy/fluff/charlotte, test_floor())
	TEST_ASSERT_EQUAL(F.open_state, "charlotte0", "the preserved pre-parent subtype preparation remains visible")
	TEST_ASSERT_EQUAL(F.closed_state, "charlotte", "closed-state preparation is not delayed behind native population")
	TEST_ASSERT_EQUAL(F.held_count(), 7, "the actual case retains all seven starting cigarettes")
	var/obj/item/storage/box/fluff/cassandra/B = allocate(/obj/item/storage/box/fluff/cassandra, test_floor())
	TEST_ASSERT_EQUAL(B.storage_slots, 3, "the real pre-parent fluff box still sizes slots before storage population")
	TEST_ASSERT_EQUAL(B.held_count(), 3, "its three original children are not duplicated by the native parent")
	TEST_ASSERT(B.max_storage_space > 0, "the actual parent still calibrates its pre-parent children")
