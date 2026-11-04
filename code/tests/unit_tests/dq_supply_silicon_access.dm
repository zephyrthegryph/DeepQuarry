/// A silicon is a silicon whatever its link state: a cyborg with no AI link still gets the supply console's budget and market access.
/datum/unit_test/dq_supply_silicon_access

/datum/unit_test/dq_supply_silicon_access/Run()
	var/turf/T = test_floor()
	var/obj/machinery/computer/supplycomp/console = allocate(/obj/machinery/computer/supplycomp, T)
	console.set_authorization(SUP_ACCEPT_ORDERS)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	TEST_ASSERT_NULL(R.connected_ai, "the cyborg has no AI link")
	TEST_ASSERT(console.can_manage_budget(R, DEPARTMENT_CARGO), "an unlinked cyborg manages the cargo budget")
	TEST_ASSERT(!console.can_manage_budget(R, DEPARTMENT_RESEARCH), "a silicon manages only the cargo budget")
	TEST_ASSERT(console.can_trade_market(R), "an unlinked cyborg trades on the market")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(!console.can_manage_budget(H, DEPARTMENT_CARGO), "a jobless human does not manage the budget")
	TEST_ASSERT(!console.can_trade_market(H), "a jobless human with no card does not trade")
