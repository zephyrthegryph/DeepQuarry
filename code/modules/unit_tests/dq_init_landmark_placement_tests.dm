/obj/effect/landmark/dq_coordinate_probe
	name = "tdome1"
	var/registered_seen_by_child
	var/tag_seen_by_child

/obj/effect/landmark/dq_coordinate_probe/Initialize(mapload)
	. = ..()
	registered_seen_by_child = (loc in GLOB.tdome1)
	tag_seen_by_child = tag

/obj/effect/landmark/dq_coordinate_start
	name = "start"

/obj/effect/landmark/dq_latejoin_probe
	name = "JoinLate"
	var/registered_seen_by_child
	var/simulated_seen_by_child

/obj/effect/landmark/dq_latejoin_probe/Initialize(mapload)
	. = ..()
	registered_seen_by_child = (src in REGISTRY_MEMBERS(REGISTRY_LATEJOIN))
	simulated_seen_by_child = simulated

/datum/unit_test/dq_init_landmark_placement
/datum/unit_test/dq_init_landmark_placement/Run()
	dq_init_objects_fixture_scope()
	set_global(nameof(GLOB.tdome1), list())
	set_global(nameof(GLOB.newplayer_start), list())
	var/turf/T = test_floor()
	var/obj/effect/landmark/dq_coordinate_probe/first = allocate(/obj/effect/landmark/dq_coordinate_probe, T)
	defer_cleanup(null, GLOBAL_PROC_REF(qdel), first, TRUE)
	var/obj/effect/landmark/dq_coordinate_probe/second = allocate(/obj/effect/landmark/dq_coordinate_probe, T)
	defer_cleanup(null, GLOBAL_PROC_REF(qdel), second, TRUE)
	TEST_ASSERT(first.registered_seen_by_child && second.registered_seen_by_child, "Actual child tails see registration before parent returns")
	TEST_ASSERT_EQUAL(first.tag_seen_by_child, "landmark*tdome1", "The existing pure tag derivation is complete before child code runs")
	TEST_ASSERT_EQUAL(length(GLOB.tdome1), 2, "Two real landmarks retain duplicate raw coordinate entries")
	TEST_ASSERT_EQUAL(GLOB.tdome1[1], T, "The first actual location identity is retained")
	TEST_ASSERT_EQUAL(GLOB.tdome1[2], T, "A duplicate location is appended rather than deduplicated")
	qdel(first, TRUE)
	TEST_ASSERT_EQUAL(length(GLOB.tdome1), 2, "Coordinate records intentionally survive landmark deletion")
	var/obj/effect/landmark/dq_latejoin_probe/late = allocate(/obj/effect/landmark/dq_latejoin_probe, T)
	defer_cleanup(null, GLOBAL_PROC_REF(qdel), late, TRUE)
	TEST_ASSERT(late.registered_seen_by_child && late.simulated_seen_by_child, "A real JoinLate child's tail observes moving-point membership and simulation policy")
	qdel(late, TRUE)
	TEST_ASSERT(!(late in REGISTRY_MEMBERS(REGISTRY_LATEJOIN)), "Live landmark membership ends on actual deletion")
	SSatoms.map_loader_begin("dq_landmark_placement")
	var/obj/effect/landmark/dq_coordinate_start/mapped = new(T)
	SSatoms.map_loader_stop("dq_landmark_placement")
	own(mapped)
	defer_cleanup(null, GLOBAL_PROC_REF(qdel), mapped, TRUE)
	SSatoms.InitializeAtoms(list(mapped))
	TEST_ASSERT(!QDELETED(mapped), "A non-resolver subtype with a coordinate name remains a real atom")
	TEST_ASSERT_EQUAL(length(GLOB.newplayer_start), 1, "That actual mapped subtype also appends exactly one coordinate")
	TEST_ASSERT_EQUAL(GLOB.newplayer_start[1], T, "Mapload registration preserves the actual location")
