/obj/structure/fence/init_large_hole_fixture
	hole_size = 2

/datum/unit_test/dq_init_objects_fence_shape

/datum/unit_test/dq_init_objects_fence_shape/Run()
	dq_init_objects_fixture_scope()
	var/obj/structure/fence/F = allocate(/obj/structure/fence)
	var/obj/structure/fence/init_large_hole_fixture/H = allocate(/obj/structure/fence/init_large_hole_fixture)
	var/obj/structure/fence/door/opened/O = allocate(/obj/structure/fence/door/opened)
	var/obj/structure/fence/door/C = allocate(/obj/structure/fence/door)
	TEST_ASSERT(F.density && C.density, "normal fence and closed door preserve their actual blocking state")
	TEST_ASSERT(!H.density && H.icon_state == "straight_cut3", "a configured large hole is open with its actual cut picture")
	TEST_ASSERT(O.open && !O.density && O.icon_state == "door_opened", "legacy door update opens the non-cuttable mapped door; its parent cut-status callback is a no-op")
	O.update_door_status()
	TEST_ASSERT(!O.density, "the actual later runtime door update still applies the open state")

/datum/unit_test/dq_init_objects_biowaste_start

/datum/unit_test/dq_init_objects_biowaste_start/Run()
	dq_init_objects_fixture_scope()
	var/obj/machinery/recycling/crusher/available = locate(/obj/machinery/recycling/crusher)
	if(!available)
		available = allocate(/obj/machinery/recycling/crusher, test_floor())
	var/obj/structure/biowaste_tank/T = allocate(/obj/structure/biowaste_tank, test_floor())
	var/mob/living/simple_mob/vore/aggressive/corrupthound/monster = T.muffinmonster()
	TEST_ASSERT_EQUAL(T.crusher(), locate(/obj/machinery/recycling/crusher), "the constructor borrows the actual world's first crusher")
	TEST_ASSERT(monster && owner_of(monster) == T && monster.loc == T, "the real declared monster starts owned inside the tank")
	TEST_ASSERT_EQUAL(monster.name, "Activate Muffin Monster", "native init configures the actual starting monster")
	var/obj/belly/B = vore_selected_of(monster)
	TEST_ASSERT(B && B.name == "waste hopper", "actual vore initialization retains the monster's real customized belly")
	qdel(T)
	TEST_ASSERT(QDELETED(monster), "tank destruction still deletes its owned monster")
	TEST_ASSERT(!QDELETED(available), "the borrowed world crusher survives tank destruction")

/datum/unit_test/dq_init_objects_biowaste_deleted_crusher

/datum/unit_test/dq_init_objects_biowaste_deleted_crusher/Run()
	dq_init_objects_fixture_scope()
	var/obj/machinery/recycling/crusher/C = allocate(/obj/machinery/recycling/crusher, test_floor())
	qdel(C)
	var/obj/machinery/recycling/crusher/found = locate(/obj/machinery/recycling/crusher)
	TEST_ASSERT(found && QDELETED(found), "the fixture exposes a deleted crusher before garbage collection")
	var/obj/structure/biowaste_tank/T = allocate(/obj/structure/biowaste_tank, test_floor())
	TEST_ASSERT(!QDELETED(T), "a deleted external crusher does not abort tank construction")
	TEST_ASSERT_NULL(T.crusher(), "a deleted crusher is never adopted as the tank's borrowed link")
	TEST_ASSERT(T.muffinmonster() && owner_of(T.muffinmonster()) == T, "the tank still constructs its actual owned monster")
