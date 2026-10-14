// Pins recorded through real legacy clicks before the machinery wait conversion.
/datum/unit_test/dq_timed_pin/machinery_dismantle
	abstract_type = /datum/unit_test/dq_timed_pin/machinery_dismantle
	var/machine_type
	var/tool_type = /obj/item/tool/screwdriver
	var/duration = 1.5 SECONDS
	var/cancel_drop = FALSE
	var/output_type
	var/output_count = 1
	var/start_text
	var/end_text

/datum/unit_test/dq_timed_pin/machinery_dismantle/run_pin()
	var/mob/living/carbon/human/user = person()
	var/turf/T = get_turf(user)
	var/obj/machinery/M = allocate(machine_type, T)
	var/obj/item/tool = allocate(tool_type, T)
	TEST_ASSERT(user.put_in_active_hand(tool), "The operator holds the actual dismantling tool")
	var/before = 0
	var/list/prior_outputs = contents_of(T, output_type)
	for(var/obj/item/I in prior_outputs)
		if(istype(I, /obj/item/stack))
			var/obj/item/stack/S = I
			before += S.get_amount()
		else
			before++
	test_chat_clear()
	test_click(user, M, tool)
	var/datum/action = running(user)
	TEST_ASSERT_NOTNULL(action, "The real tool click starts timed dismantling")
	TEST_ASSERT(isnull(declared_duration(action)) || declared_duration(action) == duration, "The declared dismantling duration is preserved")
	TEST_ASSERT(said(user, start_text), "The actual start message is sent")
	if(istype(M, /obj/machinery/feeder))
		TEST_ASSERT(M.panel_open, "Feeder panel opens immediately, before timed demolition")
	if(cancel_drop)
		TEST_ASSERT(user.drop_from_inventory(tool), "The actual held tool can be dropped")
	test_time(duration - 0.1 SECONDS)
	TEST_ASSERT(!QDELETED(M), "The machine survives until its full duration")
	test_time(0.2 SECONDS)
	if(cancel_drop)
		TEST_ASSERT(!QDELETED(M), "Dropping the tool cancels without deleting the machine")
		TEST_ASSERT(was_cancelled(action, user), "The timed action really ended cancelled")
		if(istype(M, /obj/machinery/feeder))
			TEST_ASSERT(M.panel_open, "Cancelled feeder demolition keeps its start-time panel change")
	else
		TEST_ASSERT(QDELETED(M), "Completion deletes the actual dismantled machine")
		TEST_ASSERT(said(user, end_text), "The actual completion message is sent")
	var/after = 0
	for(var/obj/item/I in contents_of(T, output_type))
		if(!(I in prior_outputs))
			own(I)
		if(istype(I, /obj/item/stack))
			var/obj/item/stack/S = I
			after += S.get_amount()
		else
			after++
	TEST_ASSERT_EQUAL(after - before, cancel_drop ? 0 : output_count, "Only completed demolition creates the exact refund")
	TEST_ASSERT_EQUAL(user.get_active_hand(), cancel_drop ? null : tool, "Dismantling preserves actual tool custody")

/datum/unit_test/dq_timed_pin/machinery_dismantle/iv_drip
	machine_type = /obj/machinery/iv_drip
	output_type = /obj/item/stack/rods
	output_count = 6
	start_text = "start to dismantle"
	end_text = "dismantle the IV drip"
/datum/unit_test/dq_timed_pin/machinery_dismantle/iv_drip/drop
	cancel_drop = TRUE

/datum/unit_test/dq_timed_pin/machinery_dismantle/feeder
	machine_type = /obj/machinery/feeder
	output_type = /obj/item/stack/material/plastic
	output_count = 4
	start_text = "maintenance hatch"
	end_text = "deconstruct the feeder"
/datum/unit_test/dq_timed_pin/machinery_dismantle/feeder/drop
	cancel_drop = TRUE

/datum/unit_test/dq_timed_pin/machinery_dismantle/doorbell
	machine_type = /obj/machinery/button/doorbell
	tool_type = /obj/item/tool/wrench
	output_type = /obj/item/frame/doorbell
	start_text = "start to unwrench"
	end_text = "unwrench"
/datum/unit_test/dq_timed_pin/machinery_dismantle/doorbell/drop
	cancel_drop = TRUE

/datum/unit_test/dq_timed_pin/machinery_food_scan
	var/cancel_drop = FALSE
/datum/unit_test/dq_timed_pin/machinery_food_scan/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/food_replicator/M = allocate(/obj/machinery/food_replicator, user.loc)
	var/obj/item/reagent_containers/food/snacks/donkpocket/F = allocate(/obj/item/reagent_containers/food/snacks/donkpocket, user.loc)
	TEST_ASSERT(user.put_in_active_hand(F), "The scanned food is physically held")
	TEST_ASSERT(!M.products[F.name], "The exact food has not been registered")
	test_click(user, M, F)
	var/datum/action = running(user)
	TEST_ASSERT_NOTNULL(action, "The actual food click starts the scan")
	TEST_ASSERT(isnull(declared_duration(action)) || declared_duration(action) == 1 SECOND, "Scanning lasts one second")
	if(cancel_drop)
		TEST_ASSERT(user.drop_from_inventory(F), "The actual food can be dropped")
	test_time(0.9 SECONDS)
	TEST_ASSERT(!M.products[F.name], "Scanning does not register food early")
	test_time(0.2 SECONDS)
	if(cancel_drop)
		TEST_ASSERT(was_cancelled(action, user), "Dropping the food cancels the scan")
		TEST_ASSERT(!M.products[F.name], "A cancelled scan adds no recipe")
	else
		TEST_ASSERT_EQUAL(M.products[F.name], F.type, "The completed scan registers the actual food type")
		TEST_ASSERT_EQUAL(user.get_active_hand(), F, "Scanning preserves food custody")
	TEST_ASSERT(!QDELETED(F), "Scanning never consumes the food")
/datum/unit_test/dq_timed_pin/machinery_food_scan/drop
	cancel_drop = TRUE

/datum/unit_test/dq_timed_pin/machinery_supply_deploy
	var/cancel_move = FALSE
/datum/unit_test/dq_timed_pin/machinery_supply_deploy/run_pin()
	var/mob/living/carbon/human/user = person()
	var/turf/T = get_turf(user)
	var/obj/item/supply_beacon/B = allocate(/obj/item/supply_beacon, T)
	TEST_ASSERT(user.put_in_active_hand(B), "The real beacon is held for deployment")
	var/list/prior_outputs = contents_of(T, /obj/machinery/power/supply_beacon)
	var/before = length(prior_outputs)
	test_chat_clear()
	test_click(user, B, B)
	var/datum/action = running(user)
	TEST_ASSERT_NOTNULL(action, "Actual in-hand use starts deployment")
	TEST_ASSERT(said(user, "begins setting up"), "The deployment start is announced")
	TEST_ASSERT(isnull(declared_duration(action)) || declared_duration(action) == 3 SECONDS, "Default deployment lasts three seconds")
	if(cancel_move)
		user.forceMove(get_step(T, EAST))
	test_time(2.9 SECONDS)
	TEST_ASSERT(!QDELETED(B), "The beacon is not consumed before completion")
	test_time(0.2 SECONDS)
	if(cancel_move)
		TEST_ASSERT(was_cancelled(action, user), "Moving cancels deployment")
		TEST_ASSERT(!QDELETED(B), "Cancelled deployment preserves the beacon")
		TEST_ASSERT_EQUAL(user.get_active_hand(), B, "Cancellation preserves beacon custody")
	else
		TEST_ASSERT(QDELETED(B), "Completed deployment consumes the original beacon")
		TEST_ASSERT(said(user, "deploys"), "Completion announces the actual deployment")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/machinery/power/supply_beacon)) - before, cancel_move ? 0 : 1, "Only completion creates the actual machine")
	for(var/obj/machinery/power/supply_beacon/product in contents_of(T, /obj/machinery/power/supply_beacon))
		if(!(product in prior_outputs))
			own(product)
/datum/unit_test/dq_timed_pin/machinery_supply_deploy/move
	cancel_move = TRUE

/datum/unit_test/dq_timed_pin/machinery_cutout_paint
	var/cancel_drop = FALSE
/datum/unit_test/dq_timed_pin/machinery_cutout_paint/New()
	..()
	test_prompts_reset()
/datum/unit_test/dq_timed_pin/machinery_cutout_paint/run_pin()
	var/mob/living/carbon/human/user = person()
	var/turf/T = get_turf(user)
	var/obj/structure/barricade/cutout/C = allocate(/obj/structure/barricade/cutout, T)
	var/obj/item/floor_painter/P = allocate(/obj/item/floor_painter, T)
	TEST_ASSERT(user.put_in_active_hand(P), "The real painter is held")
	var/list/prior_outputs = contents_of(T, /obj/structure/barricade/cutout/clown)
	var/before = length(prior_outputs)
	test_click(user, C, P)
	TEST_ASSERT(istype(SSrequests.open_for(user), /datum/prompt/choice), "The actual paint click opens its choice prompt")
	test_answer(user, "clown")
	var/datum/action = running(user)
	TEST_ASSERT_NOTNULL(action, "The selected real paint choice starts timed work")
	TEST_ASSERT(isnull(declared_duration(action)) || declared_duration(action) == 10 SECONDS, "Painting lasts ten seconds")
	if(cancel_drop)
		TEST_ASSERT(user.drop_from_inventory(P), "The actual painter can be dropped")
	test_time(9.9 SECONDS)
	TEST_ASSERT(!QDELETED(C), "Painting never replaces the original cutout early")
	test_time(0.2 SECONDS)
	if(cancel_drop)
		TEST_ASSERT(was_cancelled(action, user), "Dropping the painter cancels paint work")
		TEST_ASSERT(!QDELETED(C), "Cancelled work preserves the original cutout")
	else
		TEST_ASSERT(QDELETED(C), "Successful painting replaces the actual old cutout")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/structure/barricade/cutout/clown)) - before, cancel_drop ? 0 : 1, "Only completion produces the exact selected cutout variant")
	for(var/obj/structure/barricade/cutout/clown/product in contents_of(T, /obj/structure/barricade/cutout/clown))
		if(!(product in prior_outputs))
			own(product)
	TEST_ASSERT(!QDELETED(P), "Painting preserves its real tool")
/datum/unit_test/dq_timed_pin/machinery_cutout_paint/drop
	cancel_drop = TRUE
