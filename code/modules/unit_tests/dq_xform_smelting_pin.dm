/// The alloys as compiled transformations hold the legacy /datum/alloy table: the same ores, the same sheets (max(1, round(ores * product_mod))), in the
/// same order (the processor walks them in order, so durasteel and plasteel come before steel).
/datum/unit_test/dq_xform_smelting_pin

/datum/unit_test/dq_xform_smelting_pin/Run()
	var/list/expected = list(
		"[MAT_DURASTEEL]" = "[ORE_DIAMOND]=1,[ORE_PLATINUM]=1,[ORE_CARBON]=2,[ORE_HEMATITE]=2 -> /obj/item/stack/material/durasteel x1",
		"[MAT_PLASTEEL]" = "[ORE_PLATINUM]=1,[ORE_CARBON]=2,[ORE_HEMATITE]=2 -> /obj/item/stack/material/plasteel x1",
		"[MAT_STEEL]" = "[ORE_CARBON]=1,[ORE_HEMATITE]=1 -> /obj/item/stack/material/steel x2",
		"[MAT_PGLASS]" = "[ORE_PLATINUM]=1,[ORE_SAND]=2 -> /obj/item/stack/material/glass/phoronglass x3",
		"[MAT_BRONZE]" = "[ORE_COPPER]=2,[ORE_TIN]=1 -> /obj/item/stack/material/bronze x3",
		"[MAT_PLASTITANIUM]" = "[ORE_RUTILE]=1,[ORE_PLATINUM]=1,[ORE_CARBON]=2 -> /obj/item/stack/material/plastitanium x1",
		"[MAT_TITANIUMGLASS]" = "[ORE_RUTILE]=1,[ORE_SAND]=2 -> /obj/item/stack/material/glass/titanium x3",
		"[MAT_PLASTITANIUMGLASS]" = "[ORE_RUTILE]=1,[ORE_SAND]=2,[ORE_PLATINUM]=1,[ORE_CARBON]=2 -> /obj/item/stack/material/glass/plastitanium x6",
	)
	var/list/actual = list()
	for(var/datum/xform/X as anything in xform_rules_in(MEDIUM_ORE_STOCK, REGIME_SMELTING))
		var/list/parts = list()
		for(var/list/take as anything in X.takes)
			parts += "[take[2]]=[take[3]]"
		var/list/product = X.makes[1]
		actual["[X.id]"] = "[jointext(parts, ",")] -> [product[2]] x[product[3]]"
	TEST_ASSERT_EQUAL(jointext(actual, "|"), jointext(expected, "|"), "the smelting rules, in order")
	for(var/id in expected)
		TEST_ASSERT_EQUAL(actual[id], expected[id], "alloy [id]")
