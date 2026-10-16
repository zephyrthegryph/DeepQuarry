// Real subscriptions and owned handler factories on the next item cohort.
/datum/unit_test/dq_init_items_subscriptions
	abstract_type = /datum/unit_test/dq_init_items_subscriptions

/datum/unit_test/dq_init_items_subscriptions/intercom
/datum/unit_test/dq_init_items_subscriptions/intercom/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/area/A = get_area(T)
	var/before = observer_count(A, /datum/notice/observer_apc)
	var/obj/item/radio/intercom/I = allocate(/obj/item/radio/intercom, T)
	TEST_ASSERT_EQUAL(observer_count(A, /datum/notice/observer_apc), before + 1, "the actual intercom subscribes once to its real area's power notices")
	TEST_ASSERT_EQUAL(I.on, A.powered(EQUIP), "the real initial switch follows the actual channel power")
	TEST_ASSERT(length(I.broadcast_tiles), "the real initial radio cache contains the intercom's actual broadcast area")
	qdel(I)
	TEST_ASSERT_EQUAL(observer_count(A, /datum/notice/observer_apc), before, "deleting the actual intercom releases its area observer")

/datum/unit_test/dq_init_items_subscriptions/motiontracker
/datum/unit_test/dq_init_items_subscriptions/motiontracker/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/before = observer_count(SSmotiontracker, /datum/notice/movable_motiontracker)
	var/obj/item/motiontracker/M = allocate(/obj/item/motiontracker, H)
	TEST_ASSERT(H.has_motiontracking(), "a tracker constructed inside the real human subscribes its carrier")
	TEST_ASSERT_EQUAL(observer_count(SSmotiontracker, /datum/notice/movable_motiontracker), before + 2, "the actual device and its real carrier each subscribe once")
	M.forceMove(T)
	TEST_ASSERT(!H.has_motiontracking(), "moving the real tracker out releases its carrier's subscription")
	TEST_ASSERT_EQUAL(observer_count(SSmotiontracker, /datum/notice/movable_motiontracker), before + 1, "the tracker still has its own observer after leaving the carrier")
	qdel(M)
	TEST_ASSERT_EQUAL(observer_count(SSmotiontracker, /datum/notice/movable_motiontracker), before, "deletion releases the actual tracker observer too")

/datum/unit_test/dq_init_items_subscriptions/ghosttrap
/datum/unit_test/dq_init_items_subscriptions/ghosttrap/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/ghost_trap/T = allocate(/obj/item/ghost_trap, test_floor())
	var/datum/experiment_handler/H = T.experiment_handler
	TEST_ASSERT_NOTNULL(H, "the actual trap creates its real experiment handler before construction returns")
	TEST_ASSERT_EQUAL(owner_of(H), T, "the handler retains the trap's existing declared ownership")
	TEST_ASSERT_EQUAL(H.owner, T, "the real handler binds back to its exact trap")
	TEST_ASSERT_EQUAL(length(H.allowed_experiments), 1, "the actual handler admits only its declared experiment")
	TEST_ASSERT(/datum/experiment/ghost_capture in H.allowed_experiments, "the actual handler accepts the real ghost-capture experiment")
	TEST_ASSERT(H.config_flags & EXPERIMENT_CONFIG_ALWAYS_ACTIVE, "the actual handler keeps its always-active flag")
	TEST_ASSERT_EQUAL(observer_count(T, /datum/notice/world_ghost_captured), 1, "the actual handler registers exactly one ghost-capture listener")
	TEST_ASSERT_EQUAL(observer_count(T, /datum/notice/world_wight_captured), 1, "the actual handler registers exactly one wight-capture listener")
	qdel(T)
	TEST_ASSERT(QDELETED(H), "deleting the real trap still deletes its owned experiment handler")
