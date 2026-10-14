/// Actual hand deflation refunds one folded wall only after its real timer and does not restart when requested twice.
/datum/unit_test/om/interim_inflatable_timed_deflation_refund/run_om(list/made)
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.enable_godmode()
	var/obj/structure/inflatable/wall = allocate(/obj/structure/inflatable, T)
	TEST_ASSERT(wall.density && wall.anchored, "the actual inflated wall blocks movement and is anchored")
	TEST_ASSERT(!wall.deflating, "the actual inflated wall starts outside deflation")
	TEST_ASSERT(!user.incapacitated(), "the actual actor is capable of requesting deflation")
	var/initial_refunds = 0
	for(var/obj/item/inflatable/I in contents_of(T))
		initial_refunds++
	TEST_ASSERT_EQUAL(initial_refunds, 0, "the actual fixture begins without a folded-wall refund")
	wall.deflate_by(user)
	TEST_ASSERT(wall.deflating, "the real public deflate interaction enters the deflating state")
	scheduler_advance((2 SECONDS) / (1 SECOND))
	TEST_ASSERT(!QDELETED(wall), "the actual wall remains before its five-second deflation completes")
	TEST_ASSERT(wall.density, "the actual pending wall still blocks movement")
	var/early_refunds = 0
	for(var/obj/item/inflatable/I in contents_of(T))
		own(I)
		early_refunds++
	TEST_ASSERT_EQUAL(early_refunds, 0, "the actual pending deflation emits no early folded-wall refund")
	wall.deflate_by(user)
	scheduler_advance((4 SECONDS) / (1 SECOND))
	var/list/refunds = list()
	for(var/obj/item/inflatable/I in contents_of(T))
		own(I)
		refunds += I
	TEST_ASSERT(QDELETED(wall), "the original wall is consumed after its initial deflation deadline despite the repeated request")
	TEST_ASSERT_EQUAL(length(refunds), 1, "the actual deflation creates exactly one folded-wall refund")
	var/obj/item/inflatable/refund = refunds[1]
	TEST_ASSERT_EQUAL(refund.type, /obj/item/inflatable, "deflation refunds the actual intact folded-wall type")
	TEST_ASSERT_EQUAL(refund.loc, T, "the actual refund rests on the original wall's turf")
	TEST_ASSERT_EQUAL(refund.deploy_path, /obj/structure/inflatable, "the refunded intact wall can deploy the same actual structure type")
	TEST_ASSERT_NULL(user.get_active_hand(), "deflation does not invent a held refund")
	TEST_ASSERT(!user.incapacitated(), "the actual safe fixture remains capable through the real timer")
