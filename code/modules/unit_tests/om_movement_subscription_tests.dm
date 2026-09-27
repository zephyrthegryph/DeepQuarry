/datum/unit_test/om_connect_containers_movement_subscriptions
	needs_test_block = FALSE

/datum/unit_test/om_connect_containers_movement_subscriptions/Run()
	var/obj/owner = new
	var/obj/item/tracked = new
	var/obj/inner = new
	var/obj/outer = new
	var/obj/other = new
	var/datum/component/connect_containers/connector = owner.AddComponent(/datum/component/connect_containers, tracked, list())
	TEST_ASSERT_NOTNULL(connector, "container connector starts")
	TEST_ASSERT(connector.Observed(tracked, COMSIG_MOVABLE_MOVED, TYPE_PROC_REF(/datum/component/connect_containers, on_moved)), "tracked movement is observed")
	TEST_ASSERT(tracked.forceMove(inner), "tracked item enters inner container")
	TEST_ASSERT(connector.Observed(inner, COMSIG_MOVABLE_MOVED, TYPE_PROC_REF(/datum/component/connect_containers, on_moved)), "inner container movement is observed")
	TEST_ASSERT(inner.forceMove(outer), "inner enters outer container")
	TEST_ASSERT(connector.Observed(outer, COMSIG_MOVABLE_MOVED, TYPE_PROC_REF(/datum/component/connect_containers, on_moved)), "outer container movement is observed")
	TEST_ASSERT(inner.forceMove(other), "inner changes outer container")
	TEST_ASSERT(!connector.Observed(outer, COMSIG_MOVABLE_MOVED, TYPE_PROC_REF(/datum/component/connect_containers, on_moved)), "old ancestor observation ends")
	TEST_ASSERT(connector.Observed(other, COMSIG_MOVABLE_MOVED, TYPE_PROC_REF(/datum/component/connect_containers, on_moved)), "new ancestor movement is observed")
	qdel(tracked)
	TEST_ASSERT(QDELETED(connector), "tracked deletion ends connector and subscriptions")
	qdel(owner)
	qdel(inner)
	qdel(outer)
	qdel(other)
