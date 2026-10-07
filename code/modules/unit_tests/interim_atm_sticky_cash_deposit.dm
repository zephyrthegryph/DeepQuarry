/// Actual account credit must be backed by successful consumption of the original cash.
/datum/unit_test/interim_atm_sticky_cash_deposit/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/atm/machine = allocate(/obj/machinery/atm, T)
	var/datum/money_account/account = allocate(/datum/money_account)
	account.money = 200
	account.owner_name = "Interim cash depositor"
	rel_set(machine, nameof(machine.authenticated_account), account)
	TEST_ASSERT_EQUAL(machine.authenticated_account(), account, "the actual ATM references the real account fixture")
	var/currency_before = SSsupply.currency_created
	set_var(SSsupply, nameof(SSsupply.currency_created), currency_before)
	set_var(SSsupply, nameof(SSsupply.currency_sources), SSsupply.currency_sources.Copy())
	var/obj/item/spacecash/cash = allocate(/obj/item/spacecash, T)
	cash.worth = 75
	TEST_ASSERT(user.put_in_active_hand(cash), "the actor holds the original physical cash")
	add_trait(cash, TRAIT_NODROP, "interim_atm_cash_sticky")
	TEST_ASSERT(user.release_refusal(cash, user), "actual inventory refuses consumption of the sticky cash")
	machine.atm_take_cash(user, cash)
	TEST_ASSERT_EQUAL(account.money, 200, "refused consumption grants no account funds")
	TEST_ASSERT_EQUAL(SSsupply.currency_created, currency_before, "refused physical consumption creates no currency metric")
	TEST_ASSERT_EQUAL(account.total_revenue, 0, "refused consumption records no revenue")
	TEST_ASSERT_EQUAL(LAZYLEN(account.transaction_log), 0, "refused consumption records no transaction")
	TEST_ASSERT(!QDELETED(cash), "refused deposit preserves original cash")
	TEST_ASSERT_EQUAL(user.get_active_hand(), cash, "refused deposit preserves exact original hand")
	TEST_ASSERT_EQUAL(cash.loc, user, "refused deposit preserves inventory containment")
	remove_trait(cash, TRAIT_NODROP, "interim_atm_cash_sticky")
	account.suspended = TRUE
	machine.atm_take_cash(user, cash)
	TEST_ASSERT(!QDELETED(cash), "an account refusing credit must preserve physical cash")
	TEST_ASSERT_EQUAL(user.get_active_hand(), cash, "suspended-account refusal preserves the exact original hand")
	TEST_ASSERT_EQUAL(account.money, 200, "suspended-account refusal preserves account funds")
	TEST_ASSERT_EQUAL(SSsupply.currency_created, currency_before, "suspended-account refusal creates no currency metric")
	TEST_ASSERT_EQUAL(account.total_revenue, 0, "suspended-account refusal records no revenue")
	TEST_ASSERT_EQUAL(LAZYLEN(account.transaction_log), 0, "suspended-account refusal records no transaction")
	account.suspended = FALSE
	machine.atm_take_cash(user, cash)
	TEST_ASSERT(QDELETED(cash), "allowed deposit consumes the exact original cash")
	TEST_ASSERT_NULL(user.get_active_hand(), "allowed consumption clears the actual source hand")
	TEST_ASSERT_EQUAL(SSsupply.currency_created, currency_before + 75, "one successful physical deposit records exactly its currency creation")
	TEST_ASSERT_EQUAL(account.money, 275, "one successful original cash deposit grants exactly its physical value")
	TEST_ASSERT_EQUAL(account.total_revenue, 75, "one successful deposit records exactly the physical cash value as revenue")
	TEST_ASSERT_EQUAL(LAZYLEN(account.transaction_log), 1, "one successful deposit records exactly one real transaction")
