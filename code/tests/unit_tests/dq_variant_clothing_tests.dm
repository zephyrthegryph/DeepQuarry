// The clothing families that are one type plus a row table: every row makes the garment it names (the old path keeps resolving for maps and saves), and the
// garment is made of what its slot is made of.

/datum/unit_test/dq_variant_clothing_rows_apply

/datum/unit_test/dq_variant_clothing_rows_apply/Run()
	var/turf/T = dq_containment_floor()
	var/checked = 0
	for(var/parent in GLOB.dq_variant_tables)
		if(!ispath(parent, /obj/item/clothing))
			continue
		var/list/table = dq_variant_table(parent)
		TEST_ASSERT(length(table), "[parent] is registered but has no rows")
		for(var/key in table)
			var/list/row = table[key]
			var/obj/item/clothing/made = variant_new(variant_ref(parent, key), T)
			TEST_ASSERT(made, "[variant_ref(parent, key)] makes nothing")
			TEST_ASSERT_EQUAL(made.type, parent, "[variant_ref(parent, key)] is the parent type with a row")
			if(!isnull(row["name"]))
				TEST_ASSERT_EQUAL(made.name, row["name"], "[variant_ref(parent, key)] takes the name its row gives")
			if(!isnull(row["icon_state"]))
				TEST_ASSERT_EQUAL(made.icon_state, row["icon_state"], "[variant_ref(parent, key)] takes the icon state its row gives")
			TEST_ASSERT(length(made.material_totals()), "[variant_ref(parent, key)] is made of nothing, so it cannot be recycled")
			qdel(made)
			checked++
	TEST_ASSERT(checked > 400, "only [checked] clothing rows were checked")
