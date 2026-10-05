// Behaviour tests for the vending review findings (rewrite/machines-full): written against the legacy code first, where each pins what the code
// did then, and edited in the commit that changes it, with the change listed in doc/rewrite/intended_changes.md. They reuse the fixture of
// dq_p2_vending_behaviour.dm (the block, p2v_vendor(), p2v_actor(), p2v_id(), press(), touch(), p2v_settle()).

/// A vendor whose premium lighter costs money.
/obj/machinery/vending/p2v_test/premium_priced
	prices = list(/obj/item/pen = 5, /obj/item/flame/lighter = 7)

/// The coin is taken out of the slot while the customer types the PIN for a premium product: nothing is paid and nothing comes out.
/datum/unit_test/dq_p2_vending/mf_coin_gone_during_the_pin_prompt
/datum/unit_test/dq_p2_vending/mf_coin_gone_during_the_pin_prompt/run_gate()
	var/datum/money_account/dept = p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/premium_priced)
	var/mob/living/carbon/human/H = p2v_actor()
	var/mob/living/carbon/human/other = p2v_actor(get_step(p2v_spot(), SOUTH))
	var/obj/item/card/id/C = p2v_id(H, null, 100)
	var/datum/money_account/mine = p2v_account(C)
	mine.security_level = 1
	var/obj/item/coin/gold/coin = allocate(/obj/item/coin/gold, p2v_side_spot())
	touch(H, V, coin)
	TEST_ASSERT_EQUAL(p2v_coin(V), coin, "(the coin is in)")
	p2v_ui(H, V, "vend", list("vend" = p2v_key(V, /obj/item/flame/lighter)))
	p2v_settle(0)
	press(other, V, "remove_coin")
	TEST_ASSERT_NULL(p2v_coin(V), "(someone took the coin out)")
	test_answer(H, mine.remote_access_pin)
	p2v_settle()
	TEST_ASSERT_EQUAL(mine.money, 100, "nothing was paid")
	TEST_ASSERT_EQUAL(dept.money, 0, "nothing was received")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/flame/lighter).get_amount(), 1, "the lighter stays on the shelf")
	TEST_ASSERT(p2v_ready(V), "and the machine is free")

/// The last of a product is bought by someone else while the customer types the PIN: nothing is paid and the machine stays free.
/datum/unit_test/dq_p2_vending/mf_last_one_sold_during_the_pin_prompt
/datum/unit_test/dq_p2_vending/mf_last_one_sold_during_the_pin_prompt/run_gate()
	var/datum/money_account/dept = p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/pen)
	R.amount = 1
	var/mob/living/carbon/human/H = p2v_actor()
	var/mob/living/carbon/human/other = p2v_actor(get_step(p2v_spot(), SOUTH))
	var/obj/item/card/id/C = p2v_id(H, null, 100)
	var/datum/money_account/mine = p2v_account(C)
	mine.security_level = 1
	var/key = p2v_key(V, /obj/item/pen)
	p2v_ui(H, V, "vend", list("vend" = key))
	p2v_settle(0)
	var/obj/item/spacecash/c50/cash = allocate(/obj/item/spacecash/c50, get_turf(other))
	other.put_in_active_hand(cash)
	press(other, V, "vend", list("vend" = key))
	TEST_ASSERT_EQUAL(R.get_amount(), 0, "(the other customer bought the last pen)")
	test_answer(H, mine.remote_access_pin)
	p2v_settle()
	TEST_ASSERT_EQUAL(mine.money, 100, "the customer paid nothing")
	TEST_ASSERT_EQUAL(dept.money, 5, "the vendor was paid once")
	TEST_ASSERT(p2v_ready(V), "and the machine is free")
	TEST_ASSERT_EQUAL(p2v_count_on_floor(V, /obj/item/pen), 1, "one pen came out")

/// The log entry is offered only on a vendor that keeps a log.
/datum/unit_test/dq_p2_vending/mf_check_logs_on_a_vendor_without_logs
/datum/unit_test/dq_p2_vending/mf_check_logs_on_a_vendor_without_logs/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	p2v_id(H, list(ACCESS_CARGO))
	var/datum/op_result/R = p2v_check_logs(H, V)
	p2v_settle()
	TEST_ASSERT(!R || R.outcome != ACT_COMMITTED, "a vendor that keeps no log offers no log entry")

/// A carded customer without the log access asks for the log: refused, with the reason.
/datum/unit_test/dq_p2_vending/mf_check_logs_without_the_access
/datum/unit_test/dq_p2_vending/mf_check_logs_without_the_access/run_gate()
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/logged)
	var/mob/living/carbon/human/H = p2v_actor()
	p2v_id(H, list(ACCESS_CARGO))
	var/datum/op_result/R = p2v_check_logs(H, V)
	p2v_settle()
	TEST_ASSERT(R && R.outcome == ACT_REFUSED, "refused, with the reason")
	TEST_ASSERT_EQUAL(length(GLOB.p2v_log_windows), 0, "no log is shown")

/// A cyborg standing at the vendor presses the coin button: the coin comes out, as for anyone there in person.
/datum/unit_test/dq_p2_vending/mf_cyborg_and_the_coin_button
/datum/unit_test/dq_p2_vending/mf_cyborg_and_the_coin_button/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/coin/gold/coin = allocate(/obj/item/coin/gold, p2v_side_spot())
	touch(H, V, coin)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, get_step(p2v_spot(), SOUTH))
	press(R, V, "remove_coin")
	TEST_ASSERT_NULL(p2v_coin(V), "a cyborg standing at the vendor takes the coin out (it is there in person)")
	TEST_ASSERT_NOTEQUAL(coin.loc, V, "the coin left the machine")

/// The cigarette vendor stocks its extra brand at its price.
/datum/unit_test/dq_p2_vending/mf_cigarette_vendor_stocks_its_extra_brand
/datum/unit_test/dq_p2_vending/mf_cigarette_vendor_stocks_its_extra_brand/run_gate()
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/cigarette)
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/storage/fancy/cigarettes/yw/mauser)
	TEST_ASSERT_NOTNULL(R, "the extra brand has a record")
	TEST_ASSERT_EQUAL(R.get_amount(), 5, "five of it")
	TEST_ASSERT_EQUAL(R.price, 18, "at eighteen")

/// An unbolted vendor turns; a bolted one does not.
/datum/unit_test/dq_p2_vending/mf_vendor_rotates_when_unbolted
/datum/unit_test/dq_p2_vending/mf_vendor_rotates_when_unbolted/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/before = V.dir
	p2v_rotate(H, V)
	TEST_ASSERT_EQUAL(V.dir, before, "a bolted vendor does not turn")
	V.set_anchored(FALSE)
	p2v_rotate(H, V)
	TEST_ASSERT_EQUAL(V.dir, turn(before, 270), "an unbolted one turns clockwise")

/// The vendor turns clockwise for the actor (its menu entry).
/proc/p2v_rotate(mob/actor, obj/machinery/vending/V)
	test_menu(actor, V, "rotatable.clockwise")
	test_time(1 SECOND)
