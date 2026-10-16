// Native presentation-device setup retains real parent binding and owned UI lifetime.
/datum/unit_test/dq_init_objects_particle_communicator

/datum/unit_test/dq_init_objects_particle_communicator/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/P = allocate(/obj/item, test_floor())
	var/obj/effect/abstract/particle_holder/H = allocate(/obj/effect/abstract/particle_holder, P, /particles/smoke, NONE)
	TEST_ASSERT(!QDELETED(H), "a particle holder with a real parent survives construction")
	TEST_ASSERT_EQUAL(H.get_parent(), P, "native setup retains the exact supplied real parent")
	TEST_ASSERT_NULL(H.loc, "the presentation-only holder leaves real item contents")
	TEST_ASSERT(H in P.vis_contents, "the real parent receives the holder in vis_contents")
	TEST_ASSERT(istype(H.particles, /particles/smoke), "the actual constructor instantiates its supplied particle type")
	TEST_ASSERT_EQUAL(H.mouse_opacity, MOUSE_OPACITY_TRANSPARENT, "storage/container changes do not make the particle holder intercept clicks")
	qdel(P)
	TEST_ASSERT(QDELETED(H), "the actual parent-deletion observer deletes its nullspace presentation holder")

/datum/unit_test/dq_init_objects_particle_communicator/parent_movement

/datum/unit_test/dq_init_objects_particle_communicator/parent_movement/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/M = allocate(/mob/living/carbon/human, T)
	var/obj/item/P = allocate(/obj/item, M)
	var/obj/effect/abstract/particle_holder/H = allocate(/obj/effect/abstract/particle_holder, P, /particles/smoke, PARTICLE_ATTACH_MOB)
	TEST_ASSERT(H in M.vis_contents, "the constructor attaches particles to a real mob carrying their parent")
	P.forceMove(T)
	TEST_ASSERT(!(H in M.vis_contents), "the actual parent movement observer removes the old carrier's particles")
	TEST_ASSERT_EQUAL(H.get_parent(), P, "parent movement preserves the exact parent reference")
	P.forceMove(M)
	TEST_ASSERT(H in M.vis_contents, "moving the real parent back restores its carrier presentation")
	qdel(P)
	TEST_ASSERT(QDELETED(H), "the moved presentation holder still follows parent deletion")

/datum/unit_test/dq_init_objects_particle_communicator/communicator

/datum/unit_test/dq_init_objects_particle_communicator/communicator/Run()
	dq_init_objects_fixture_scope()
	var/obj/machinery/exonet_node/available = allocate(/obj/machinery/exonet_node, test_floor())
	TEST_ASSERT(available.on, "the real Exonet-node fixture begins online")
	var/obj/machinery/exonet_node/expected = get_exonet_node()
	TEST_ASSERT(expected, "the actual registry has an online Exonet node")
	var/obj/item/communicator/C = allocate(/obj/item/communicator)
	TEST_ASSERT_EQUAL(C.node, expected, "the constructor binds the actual first online Exonet node")
	TEST_ASSERT(C.camera, "the native camera owner creates the real communicator camera")
	TEST_ASSERT_EQUAL(C.camera.c_tag, C.camera.name, "the constructed camera retains its matching generated tag")
	TEST_ASSERT(findtext(C.camera.name, "[C] #") == 1, "the real camera name retains the device prefix and random suffix")
	TEST_ASSERT_EQUAL(C.cam_screen.assigned_map, C.map_name, "the actual view screen is initialized on this communicator's map")
	TEST_ASSERT_EQUAL(C.cam_background.assigned_map, C.map_name, "the actual background is initialized on the same map")
	TEST_ASSERT_EQUAL(C.local_skybox.assigned_map, C.map_name, "the actual skybox is initialized on the same map")
	TEST_ASSERT(length(C.cam_plane_masters), "the constructor creates actual UI plane masters")
	var/obj/machinery/camera/communicator/camera = C.camera
	var/atom/movable/screen/map_view/screen = C.cam_screen
	qdel(C)
	TEST_ASSERT(QDELETED(camera) && QDELETED(screen), "deleting the communicator retains native ownership of the real camera and screen")
	TEST_ASSERT(!QDELETED(expected), "the communicator does not own or delete the borrowed Exonet node")
