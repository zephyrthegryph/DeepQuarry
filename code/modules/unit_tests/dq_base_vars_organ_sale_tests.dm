// The retired nullable item health was never body/organ damage. Preserve existing sale behavior.
/datum/unit_test/dq_base_vars_organ_sale

/datum/unit_test/dq_base_vars_organ_sale/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/datum/sellable/organ/S = allocate(/datum/sellable/organ)
	var/obj/item/organ/internal/liver/replicant/O = allocate(/obj/item/organ/internal/liver/replicant, test_floor())
	var/obj/structure/closet/crate/freezer/F = allocate(/obj/structure/closet/crate/freezer, test_floor())
	TEST_ASSERT_EQUAL(S.sell_error(O), "Error: Product was improperly packaged. Send contents in freezer crate to preserve contents for transport.", "the actual packaging refusal is unchanged")
	O.forceMove(F)
	TEST_ASSERT_NULL(S.sell_error(O), "a real packaged healthy replicant organ remains accepted")
	TEST_ASSERT_EQUAL(S.calculate_sell_value(O), O.supply_conversion_value, "the actual organ value still comes from its declared conversion value")
	O.bruise()
	TEST_ASSERT(O.is_bruised(), "the real organ condition changed through its existing condition API")
	TEST_ASSERT_NULL(S.sell_error(O), "actual organ damage never updated the retired nullable health guard; preserve that old acceptance")
	O.forceMove(test_floor())
	TEST_ASSERT(S.sell_error(O), "real packaging refusal still applies to a damaged organ outside the freezer")
