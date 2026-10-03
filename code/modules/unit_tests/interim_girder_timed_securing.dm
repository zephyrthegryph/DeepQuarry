/// The actual wrench-secure task keeps a displaced girder movable until completion, then restores its material-derived integrity and cover without spending or refunding sheets.
/datum/unit_test/om/interim_girder_timed_securing/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/girder/girder = allocate(/obj/structure/girder, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	made += list(user, girder, wrench)
	var/datum/material/material_before = girder.girder_material
	var/base_cover = girder.cover
	var/base_integrity = girder.max_integrity
	girder.displace() // Real displaced fixture; this test covers re-securing, not the preceding crowbar task.
	var/datum/construction_graph/graph = construction_graph_of(girder)
	TEST_ASSERT(!girder.anchored && graph.state_of(girder) == "displaced", "the actual girder fixture is displaced and movable")
	var/displaced_integrity = girder.get_integrity()
	var/displaced_cover = girder.cover
	TEST_ASSERT(user.put_in_active_hand(wrench), "the actual actor holds the real securing tool")
	var/datum/interaction/construction/securing
	for(var/datum/interaction/construction/edge as anything in construction_edges_for(girder))
		if(edge.type == /datum/interaction/construction/girder/secure)
			securing = edge
			break
	TEST_ASSERT_NOTNULL(securing, "the actual displaced girder offers its securing edge")
	var/securing_delay = securing.duration_for(user, girder, wrench)
	TEST_ASSERT(securing_delay > 0, "the actual securing edge has a real tool delay")
	TEST_ASSERT(!user.incapacitated(INCAPACITATION_STUNNED | INCAPACITATION_KNOCKOUT), "the actual actor is capable before securing")
	TEST_ASSERT(securing.perform(user, girder, wrench), "the actual securing edge starts its real timed work")
	TEST_ASSERT(LAZYLEN(user.do_afters), "actual securing creates its pending task")
	TEST_ASSERT(!girder.anchored, "pending actual securing does not anchor the girder early")
	TEST_ASSERT_EQUAL(girder.get_integrity(), displaced_integrity, "pending actual securing does not restore integrity early")
	TEST_ASSERT_EQUAL(girder.cover, displaced_cover, "pending actual securing does not restore cover early")
	scheduler_advance((securing_delay + 1 SECOND) / (1 SECOND))
	own_turf_contents(T)
	TEST_ASSERT(!user.incapacitated(INCAPACITATION_STUNNED | INCAPACITATION_KNOCKOUT), "the actual actor stays capable through securing")
	TEST_ASSERT(!LAZYLEN(user.do_afters), "actual securing releases its completed task")
	TEST_ASSERT(girder.anchored && graph.state_of(girder) == "anchored", "actual completion anchors the original girder and restores its construction stage")
	TEST_ASSERT_EQUAL(girder.girder_material, material_before, "actual securing preserves the original material identity")
	TEST_ASSERT_EQUAL(girder.loc, T, "actual securing preserves the original girder's floor")
	TEST_ASSERT_EQUAL(girder.max_integrity, base_integrity, "actual securing preserves the material-derived maximum integrity")
	TEST_ASSERT_EQUAL(girder.get_integrity(), base_integrity, "actual securing restores the displaced girder's integrity")
	TEST_ASSERT_EQUAL(girder.cover, base_cover, "actual securing restores the original projectile cover")
	TEST_ASSERT_EQUAL(user.get_active_hand(), wrench, "actual securing preserves the actor's held wrench")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material)), 0, "actual securing consumes and refunds no material sheets")

