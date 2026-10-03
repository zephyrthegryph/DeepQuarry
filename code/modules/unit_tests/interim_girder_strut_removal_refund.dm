/// The real loose-strut removal edge refunds exactly one reinforcement sheet only after its tool task completes, preserving the original support frame.
/datum/unit_test/om/interim_girder_strut_removal_refund/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/girder/girder = allocate(/obj/structure/girder, T)
	var/obj/item/tool/wirecutters/cutters = allocate(/obj/item/tool/wirecutters, T)
	made += list(user, girder, cutters)
	var/datum/material/frame_material = girder.girder_material
	var/datum/material/reinforcement = get_material_by_name(MAT_PLASTEEL)
	var/unreinforced_cover = girder.cover
	girder.reinf_material = reinforcement
	girder.reinforce_girder()
	// Begin at the graph's real loose-strut state; this test covers removal, not the preceding screwdriver wait.
	girder.state = 1
	var/datum/construction_graph/graph = construction_graph_of(girder)
	TEST_ASSERT_EQUAL(graph.state_of(girder), "struts_loose", "the actual reinforced fixture starts with loose support struts")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material)), 0, "the actual fixture starts without refunded material sheets")
	TEST_ASSERT(user.put_in_active_hand(cutters), "the actual actor holds the real strut-removal tool")
	var/datum/interaction/construction/removal
	for(var/datum/interaction/construction/edge as anything in construction_edges_for(girder))
		if(edge.type == /datum/interaction/construction/girder/remove_struts)
			removal = edge
			break
	TEST_ASSERT_NOTNULL(removal, "the actual loose-strut fixture exposes its removal construction edge")
	var/removal_delay = removal.duration_for(user, girder, cutters)
	TEST_ASSERT(removal_delay > 0, "the actual removal edge has a positive scaled tool delay")
	TEST_ASSERT(!user.incapacitated(INCAPACITATION_STUNNED | INCAPACITATION_KNOCKOUT), "the actual strut-removal actor starts capable")
	TEST_ASSERT(removal.perform(user, girder, cutters), "the actual declared construction edge starts strut removal")
	TEST_ASSERT(LAZYLEN(user.do_afters), "the actual construction edge creates its pending removal task")
	TEST_ASSERT_EQUAL(girder.reinf_material, reinforcement, "pending removal retains the exact actual reinforcement")
	TEST_ASSERT_EQUAL(girder.state, 1, "pending removal retains the loose-strut stage")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material)), 0, "pending removal creates no material refund early")
	scheduler_advance((removal_delay + 1 SECOND) / (1 SECOND))
	own_turf_contents(T)
	TEST_ASSERT(!user.incapacitated(INCAPACITATION_STUNNED | INCAPACITATION_KNOCKOUT), "the actual actor remains capable through the single removal task")
	TEST_ASSERT(!LAZYLEN(user.do_afters), "actual strut removal releases its completed task")
	TEST_ASSERT(!QDELETED(girder), "actual strut removal preserves the original support girder")
	TEST_ASSERT_EQUAL(girder.loc, T, "actual strut removal preserves the original frame's floor")
	TEST_ASSERT_EQUAL(girder.girder_material, frame_material, "actual strut removal preserves the original frame material")
	TEST_ASSERT_NULL(girder.reinf_material, "actual strut removal clears the reinforcement view")
	TEST_ASSERT(girder.anchored, "actual strut removal keeps the original support frame anchored")
	TEST_ASSERT_EQUAL(graph.state_of(girder), "anchored", "actual removal returns to the ordinary anchored construction stage")
	TEST_ASSERT_EQUAL(girder.cover, unreinforced_cover, "actual removal restores the original unreinforced projectile cover")
	var/refunded = 0
	var/other_sheets = 0
	for(var/obj/item/stack/material/sheets as anything in contents_of(T, /obj/item/stack/material))
		if(sheets.type == /obj/item/stack/material/plasteel)
			refunded += sheets.get_amount()
		else
			other_sheets += sheets.get_amount()
	TEST_ASSERT_EQUAL(refunded, 1, "actual strut removal refunds exactly one plasteel reinforcement sheet")
	TEST_ASSERT_EQUAL(other_sheets, 0, "actual strut removal refunds none of the retained frame material")
	TEST_ASSERT_EQUAL(user.get_active_hand(), cutters, "actual removal preserves the original held tool")
