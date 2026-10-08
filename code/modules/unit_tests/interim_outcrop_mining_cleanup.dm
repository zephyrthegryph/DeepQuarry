/// Real outcrop mining preserves its four-second wait, exact ore family, bounded yield and original actor/tool identities.
/datum/unit_test/om/interim_outcrop_mining_cleanup
	var/outcrop_type = /obj/structure/outcrop
	var/ore_type = /obj/item/ore/glass
	var/minimum = 5
	var/maximum = 10

/datum/unit_test/om/interim_outcrop_mining_cleanup/diamond
	outcrop_type = /obj/structure/outcrop/diamond
	ore_type = /obj/item/ore/diamond
	minimum = 2
	maximum = 4

/datum/unit_test/om/interim_outcrop_mining_cleanup/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	actor.enable_godmode()
	var/obj/structure/outcrop/outcrop = allocate(outcrop_type, T)
	var/obj/item/pickaxe/tool = allocate(/obj/item/pickaxe, T)
	TEST_ASSERT(actor.put_in_active_hand(tool), "The real capable actor holds its original pickaxe")
	TEST_ASSERT_EQUAL(outcrop.outcropdrop, ore_type, "The actual existing outcrop subtype retains its canonical ore family")
	TEST_ASSERT_EQUAL(outcrop.mindrop, minimum, "The actual existing outcrop retains its original minimum yield")
	TEST_ASSERT_EQUAL(outcrop.upperdrop, maximum, "The actual existing outcrop retains its original maximum yield")
	var/list/before = turf_contents_of_type(T, /obj/item/ore)
	TEST_ASSERT_NOTNULL(perform_op(actor, outcrop, "pickaxe", tool, ORIGIN_CLICK, AUTH_PHYSICAL), "The actual public pickaxe mining op starts its original timed work")
	scheduler_advance((3.9 SECONDS) / (1 SECOND))
	TEST_ASSERT(!QDELETED(outcrop) && outcrop.loc == T, "The actual outcrop survives until its original four-second mining deadline")
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/item/ore)), length(before), "The actual timed mining produces no ore before its original deadline")
	scheduler_advance((0.2 SECONDS) / (1 SECOND))
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(outcrop), "The actual completed pickaxe callback consumes the original outcrop")
	var/list/ore = turf_contents_of_type(T, /obj/item/ore) - before
	TEST_ASSERT(length(ore) >= minimum && length(ore) <= maximum, "The actual completed mining retains its original bounded nonzero yield")
	for(var/obj/item/ore/product in ore)
		TEST_ASSERT_EQUAL(product.type, ore_type, "Every actual mining product has the exact canonical ore type")
		TEST_ASSERT(!QDELETED(product) && product.loc == T, "Every actual original ore product survives on the mining floor")
	TEST_ASSERT(!QDELETED(actor) && actor.loc == T && !actor.incapacitated(), "The actual completed mining preserves the original capable actor")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), tool, "Actual completed mining preserves the original held pickaxe")

/datum/unit_test/om/interim_outcrop_maul_cleanup/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	actor.enable_godmode()
	var/obj/structure/outcrop/diamond/outcrop = allocate(/obj/structure/outcrop/diamond, T)
	var/obj/item/melee/shock_maul/loaded/tool = allocate(/obj/item/melee/shock_maul/loaded, T)
	var/obj/item/cell/cell = tool.get_cell()
	TEST_ASSERT(cell && !QDELETED(cell), "The actual loaded maul owns its real original battery")
	var/charge = cell.charge
	TEST_ASSERT(actor.put_in_active_hand(tool), "The real capable actor holds its original loaded maul")
	TEST_ASSERT(!tool.status, "The actual loaded maul starts powered off")
	var/list/before = turf_contents_of_type(T, /obj/item/ore)
	TEST_ASSERT_EQUAL(test_op_handler(outcrop, "interaction_item", actor, tool), OP_PASS, "The actual unpowered maul mining interaction handles its original refusal")
	TEST_ASSERT(!QDELETED(outcrop), "The actual unpowered refusal preserves the original outcrop")
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/item/ore)), length(before), "The actual unpowered refusal creates no ore product")
	TEST_ASSERT_EQUAL(cell.charge, charge, "The actual unpowered refusal spends no original battery charge")
	TEST_ASSERT(test_op_handler(tool, "interaction_self", actor, tool), "The actual public maul self-use begins charging")
	scheduler_advance((1.9 SECONDS) / (1 SECOND))
	TEST_ASSERT(!tool.status, "The actual maul remains off until its original charging deadline")
	scheduler_advance((0.2 SECONDS) / (1 SECOND))
	TEST_ASSERT(tool.status && tool.wielded, "The real charge callback powers and wields the original maul using the actor's actual free second hand")
	cell.refresh_material_discharge()
	TEST_ASSERT(cell.check_charge(tool.hitcost), "the actual charged original battery can deliver one hit")
	var/charge_before_hit = cell.charge
	var/credit_before_hit = cell.material_discharge_credit
	var/efficiency_before_hit = cell.material_delivery_efficiency(tool.hitcost)
	TEST_ASSERT(credit_before_hit >= tool.hitcost && efficiency_before_hit > 0 && efficiency_before_hit <= 1, "the actual original battery has positive valid delivery capacity and efficiency")
	TEST_ASSERT_EQUAL(test_op_handler(outcrop, "interaction_item", actor, tool), OP_PASS, "The actual powered and wielded maul mines the original outcrop")
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(outcrop), "The real maul pulverization consumes the original outcrop")
	var/list/ore = turf_contents_of_type(T, /obj/item/ore) - before
	TEST_ASSERT(length(ore) >= 2 && length(ore) <= 4, "The actual diamond pulverization retains its original bounded nonzero yield")
	for(var/obj/item/ore/product in ore)
		TEST_ASSERT_EQUAL(product.type, /obj/item/ore/diamond, "Each actual pulverization product retains the canonical diamond ore type")
		TEST_ASSERT(!QDELETED(product) && product.loc == T, "Each actual original ore product survives on the mining floor")
	TEST_ASSERT_EQUAL(tool.get_cell(), cell, "The actual pulverization preserves the exact installed original battery")
	TEST_ASSERT(abs(credit_before_hit - cell.material_discharge_credit - tool.hitcost) < 0.01, "The actual pulverization delivers exactly one hit's original discharge allowance")
	TEST_ASSERT(abs(charge_before_hit - cell.charge - tool.hitcost / efficiency_before_hit) < 0.01, "The actual original battery pays the delivered hit energy and its real conductor loss")
	TEST_ASSERT(!tool.status, "The actual pulverization turns off the original maul after discharge")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), tool, "The actual pulverization preserves the original held maul")
