// Property registry (code/datums/properties/): aggregators, boot validation,
// per-type tables and instance reads for the converted families.

// ---- Fixtures ----

/obj/item/dq_property_test
	name = "property test item"
	w_class = ITEMSIZE_SMALL
	sharp = TRUE
	MATERIAL_MIX(list(MAT_STEEL = 1000, MAT_CARDBOARD = 500))

/// Same values as its parent, so it must share the parent's interned table.
/obj/item/dq_property_test/twin

/obj/item/dq_property_test/blunt
	sharp = FALSE
	MATERIAL_BULK(MAT_STEEL, 200)

GLOBAL_LIST_INIT(dq_variants_property_test, list(
	"big" = list("w_class" = ITEMSIZE_HUGE),
))

/// A mob whose equipment is set directly, so the test needs no body.
/mob/dq_property_test
	var/list/test_equipped

/mob/dq_property_test/get_equipped_items()
	return test_equipped ? test_equipped.Copy() : list()

/datum/component/dq_property_test
	var/extra_mass = 2

/datum/component/dq_property_test/property_value(id)
	if(id == PROP_MASS)
		return extra_mass

/datum/property_provider/component/dq_test_mass
	property = PROP_MASS
	unit = PROP_UNIT_KILOGRAMS
	component_type = /datum/component/dq_property_test

// Test-only definitions and providers, skipped by the global registry.

/datum/property_def/dq_test_good
	id = "dq_test_good"
	unit = PROP_UNIT_KILOGRAMS
	aggregator = PROP_AGG_SUM
	test_only = TRUE

/datum/property_def/dq_test_bad_unit
	id = "dq_test_bad_unit"
	unit = "furlongs"
	test_only = TRUE

/datum/property_def/tag/dq_test_tag_with_unit
	id = "dq_test_tag_with_unit"
	unit = PROP_UNIT_KELVIN
	test_only = TRUE

/datum/property_def/dq_test_no_aggregator
	id = "dq_test_no_aggregator"
	unit = PROP_UNIT_KELVIN
	test_only = TRUE

/datum/property_def/dq_test_orphan
	id = "dq_test_orphan"
	unit = PROP_UNIT_KELVIN
	test_only = TRUE

/datum/property_provider/type_var/dq_test_base
	property = "dq_test_good"
	applies_to = /obj/item
	unit = PROP_UNIT_KILOGRAMS
	test_only = TRUE

/datum/property_provider/type_var/dq_test_same_root
	property = "dq_test_good"
	applies_to = /obj/item
	unit = PROP_UNIT_KILOGRAMS
	test_only = TRUE

/datum/property_provider/type_var/dq_test_deeper_undeclared
	property = "dq_test_good"
	applies_to = /obj/item/dq_property_test
	unit = PROP_UNIT_KILOGRAMS
	test_only = TRUE

/datum/property_provider/type_var/dq_test_deeper_declared
	property = "dq_test_good"
	applies_to = /obj/item/dq_property_test/blunt
	unit = PROP_UNIT_KILOGRAMS
	overrides = list(/datum/property_provider/type_var/dq_test_base, /datum/property_provider/type_var/dq_test_same_root, /datum/property_provider/type_var/dq_test_deeper_undeclared)
	test_only = TRUE

/datum/property_provider/type_var/dq_test_wrong_unit
	property = "dq_test_bad_unit"
	applies_to = /obj/structure
	unit = PROP_UNIT_KELVIN
	test_only = TRUE

/datum/property_provider/equipment/dq_test_contributes_without_aggregator
	property = "dq_test_no_aggregator"
	unit = PROP_UNIT_KELVIN
	test_only = TRUE

/datum/property_provider/type_var/dq_test_unknown_property
	property = "dq_test_does_not_exist"
	applies_to = /obj
	test_only = TRUE

/datum/property_provider/type_var/tag/dq_test_tag_provider
	property = "dq_test_tag_with_unit"
	applies_to = /obj
	test_only = TRUE

/datum/unit_test/proc/dq_errors_mention(list/errors, text)
	for(var/error in errors)
		if(findtext(error, text))
			return TRUE
	return FALSE

// ---- Aggregators ----

/datum/unit_test/dq_property_aggregators

/datum/unit_test/dq_property_aggregators/Run()
	// The shared rules are the body factor rules (code/modules/body/factors.dm).
	TEST_ASSERT_EQUAL(PROP_AGG_PRODUCT, BF_RULE_MULT, "PRODUCT should be BF_RULE_MULT")
	TEST_ASSERT_EQUAL(PROP_AGG_SUM, BF_RULE_ADD, "SUM should be BF_RULE_ADD")
	TEST_ASSERT_EQUAL(PROP_AGG_MAX, BF_RULE_MAX, "MAX should be BF_RULE_MAX")
	TEST_ASSERT_EQUAL(PROP_AGG_MIN, BF_RULE_MIN, "MIN should be BF_RULE_MIN")
	TEST_ASSERT_EQUAL(PROP_AGG_OR, BF_RULE_FLAGS, "OR should be BF_RULE_FLAGS")
	// At full scale the factor fold and the property combine agree.
	var/list/acc = body_factor_accumulate(null, alist(BF_AIRWAY = 0.5, BF_PAIN = 3, BF_HASTE = 1), 1)
	TEST_ASSERT(abs(acc[BF_AIRWAY] - dq_property_combine(PROP_AGG_PRODUCT, 1, 0.5)) < 0.0001, "product should match BF_RULE_MULT at scale 1")
	TEST_ASSERT_EQUAL(acc[BF_PAIN], dq_property_combine(PROP_AGG_SUM, 0, 3), "sum should match BF_RULE_ADD")
	TEST_ASSERT_EQUAL(acc[BF_HASTE], dq_property_combine(PROP_AGG_MAX, 0, 1), "max should match BF_RULE_MAX")

	TEST_ASSERT_EQUAL(dq_property_combine(PROP_AGG_SUM, 2, 3), 5, "sum")
	TEST_ASSERT_EQUAL(dq_property_combine(PROP_AGG_PRODUCT, 2, 3), 6, "product")
	TEST_ASSERT_EQUAL(dq_property_combine(PROP_AGG_MAX, 2, 3), 3, "max")
	TEST_ASSERT_EQUAL(dq_property_combine(PROP_AGG_MIN, 2, 3), 2, "min")
	TEST_ASSERT_EQUAL(dq_property_combine(PROP_AGG_OR, 1, 4), 5, "or")
	TEST_ASSERT_EQUAL(dq_property_combine(PROP_AGG_MIN, null, 7), 7, "null is the identity")
	TEST_ASSERT_NULL(dq_property_combine(PROP_AGG_SUM, null, null), "two nulls combine to null")

	// MIN keeps counts, so removing one copy of the minimum keeps it.
	var/datum/property_accumulator/low = new(PROP_AGG_MIN)
	TEST_ASSERT_NULL(low.value(), "an empty accumulator has no value")
	low.add(500)
	low.add(300)
	low.add(300)
	low.add(800)
	TEST_ASSERT_EQUAL(low.value(), 300, "min of 500, 300, 300, 800")
	low.remove(300)
	TEST_ASSERT_EQUAL(low.value(), 300, "one 300 is still held")
	low.remove(300)
	TEST_ASSERT_EQUAL(low.value(), 500, "the minimum rises once every 300 leaves")
	low.remove(500)
	low.remove(800)
	TEST_ASSERT_NULL(low.value(), "empty again")

	var/datum/property_accumulator/high = new(PROP_AGG_MAX)
	high.add(2)
	high.add(4)
	high.remove(4)
	TEST_ASSERT_EQUAL(high.value(), 2, "max falls back after removal")

	var/datum/property_accumulator/total = new(PROP_AGG_SUM)
	total.add(1.5)
	total.add(2)
	total.remove(1.5)
	TEST_ASSERT_EQUAL(total.value(), 2, "sum after removal")

	var/datum/property_accumulator/product = new(PROP_AGG_PRODUCT)
	product.add(2)
	product.add(0)
	product.add(3)
	TEST_ASSERT_EQUAL(product.value(), 0, "a zero makes the product zero")
	product.remove(0)
	TEST_ASSERT_EQUAL(product.value(), 6, "removing the zero restores the product")

	var/datum/property_accumulator/flags = new(PROP_AGG_OR)
	flags.add(1)
	flags.add(1|4)
	flags.remove(1)
	TEST_ASSERT_EQUAL(flags.value(), 5, "bit 1 is still set by the second entry")
	flags.remove(1|4)
	TEST_ASSERT_NULL(flags.value(), "empty once both leave")

// ---- Validation ----

/datum/unit_test/dq_property_registry_validates

/datum/unit_test/dq_property_registry_validates/Run()
	var/datum/property_registry/registry = dq_property_registry()
	for(var/error in registry.errors)
		TEST_FAIL("property registry: [error]")
	for(var/id in list(PROP_SIZE_CLASS, PROP_MASS, PROP_MELTING_POINT, PROP_IGNITION_POINT, PROP_MAX_HEAT_PROTECTION, TAG_SHARP, TAG_CONDUCTIVE, TAG_FLAMMABLE))
		TEST_ASSERT(registry.defs[id], "[id] should be registered")

	// A registry of broken fixtures reports each problem.
	var/list/defs = list()
	for(var/path in list(/datum/property_def/dq_test_good, /datum/property_def/dq_test_bad_unit, /datum/property_def/tag/dq_test_tag_with_unit, /datum/property_def/dq_test_no_aggregator, /datum/property_def/dq_test_orphan, /datum/property_def/dq_test_good))
		defs += new path
	var/list/providers = list()
	for(var/path in typesof(/datum/property_provider/type_var/dq_test_base, /datum/property_provider/type_var/dq_test_same_root, /datum/property_provider/type_var/dq_test_deeper_undeclared, /datum/property_provider/type_var/dq_test_deeper_declared, /datum/property_provider/type_var/dq_test_wrong_unit, /datum/property_provider/equipment/dq_test_contributes_without_aggregator, /datum/property_provider/type_var/dq_test_unknown_property, /datum/property_provider/type_var/tag/dq_test_tag_provider))
		providers += new path
	var/datum/property_registry/broken = new(defs, providers)
	var/list/errors = broken.errors
	TEST_ASSERT(dq_errors_mention(errors, "dq_test_good is declared twice"), "a duplicate id should be reported")
	TEST_ASSERT(dq_errors_mention(errors, "unknown unit furlongs"), "an unknown unit should be reported")
	TEST_ASSERT(dq_errors_mention(errors, "tag dq_test_tag_with_unit has a unit"), "a tag with a unit should be reported")
	TEST_ASSERT(dq_errors_mention(errors, "dq_test_orphan has no provider"), "a property without a provider should be reported")
	TEST_ASSERT(dq_errors_mention(errors, "both provide dq_test_good for /obj/item"), "two providers on one root should conflict")
	TEST_ASSERT(dq_errors_mention(errors, "dq_test_deeper_undeclared provides dq_test_good for /obj/item/dq_property_test under"), "a deeper provider without overrides should conflict")
	TEST_ASSERT(!dq_errors_mention(errors, "dq_test_deeper_declared provides"), "a deeper provider that declares overrides is not a conflict")
	TEST_ASSERT(dq_errors_mention(errors, "dq_test_wrong_unit yields K but dq_test_bad_unit is in furlongs"), "a unit mismatch should be reported")
	TEST_ASSERT(dq_errors_mention(errors, "contributes to dq_test_no_aggregator, which has no aggregator"), "a contributor without an aggregator should be reported")
	TEST_ASSERT(dq_errors_mention(errors, "unknown property dq_test_does_not_exist"), "a provider for an unknown property should be reported")

/// Every per-type value in the converted families is a number of the right
/// kind and in range, and every state var is saved state.
/datum/unit_test/dq_property_type_values_valid

/datum/unit_test/dq_property_type_values_valid/Run()
	var/datum/property_registry/registry = dq_property_registry()
	var/failures = 0
	for(var/id in registry.base_providers)
		for(var/datum/property_provider/provider as anything in registry.base_providers[id])
			if(provider.state_var)
				var/datum/sample = allocate(provider.applies_to)
				TEST_ASSERT(dq_property_state_has_var(sample, provider.state_var), "[provider.type] reads [provider.state_var], which is not saved state on [provider.applies_to]")
			for(var/path in typesof(provider.applies_to))
				if(registry.base_provider(path, id) != provider)
					continue
				var/error = registry.check_value(id, provider.type_value(path, null))
				if(error && failures++ < 20)
					TEST_FAIL("[path]: [error]")
	TEST_ASSERT(failures == 0, "[failures] per-type values are invalid")

// ---- Families ----

/datum/unit_test/dq_property_item_families

/datum/unit_test/dq_property_item_families/Run()
	var/path = /obj/item/dq_property_test
	var/datum/material/steel = GLOB.name_to_material[MAT_STEEL]
	var/datum/material/cardboard = GLOB.name_to_material[MAT_CARDBOARD]

	// Per-type values, with no instance.
	TEST_ASSERT_EQUAL(dq_type_property(path, PROP_SIZE_CLASS), ITEMSIZE_SMALL, "size class comes from initial(w_class)")
	TEST_ASSERT(dq_type_has_tag(path, TAG_SHARP), "sharp comes from initial(sharp)")
	// Matter-derived values per type, from the declared blueprint and total.
	TEST_ASSERT(abs(dq_type_property(path, PROP_MASS) - 1.5) < 0.0001, "per-type mass: 1000 + 500 matter units is 1.5 kg, got [dq_type_property(path, PROP_MASS)]")
	TEST_ASSERT_EQUAL(dq_type_property(path, PROP_MELTING_POINT), min(steel.melting_point, cardboard.melting_point), "per-type melting point is the lowest material's")
	TEST_ASSERT_EQUAL(dq_type_property(path, PROP_IGNITION_POINT), cardboard.ignition_point, "per-type ignition point comes from the cardboard")
	TEST_ASSERT(dq_type_has_tag(path, TAG_FLAMMABLE), "per type, cardboard makes it flammable")
	TEST_ASSERT(abs(dq_type_property(/obj/item/dq_property_test/twin, PROP_MASS) - 1.5) < 0.0001, "a subtype inherits its parent's per-type matter")
	TEST_ASSERT(abs(dq_type_property(/obj/item/dq_property_test/blunt, PROP_MASS) - 0.2) < 0.0001, "a subtype's own declaration wins, got [dq_type_property(/obj/item/dq_property_test/blunt, PROP_MASS)]")
	TEST_ASSERT(!dq_type_has_tag(/obj/item/dq_property_test/blunt, TAG_FLAMMABLE), "per type, steel alone is not flammable")
	TEST_ASSERT_EQUAL(dq_type_has_tag(/obj/item/dq_property_test/blunt, TAG_CONDUCTIVE), steel.conductive ? TRUE : FALSE, "per-type conductive follows the material")
	var/obj/item/dq_property_test/probe = allocate(path)
	TEST_ASSERT(abs(PROPERTY(probe, PROP_MASS) - 1.5) < 0.0001, "1000 + 500 matter units is 1.5 kg, got [PROPERTY(probe, PROP_MASS)]")
	TEST_ASSERT_EQUAL(PROPERTY(probe, PROP_MELTING_POINT), min(steel.melting_point, cardboard.melting_point), "melting point is the lowest material's")
	TEST_ASSERT_EQUAL(PROPERTY(probe, PROP_IGNITION_POINT), cardboard.ignition_point, "ignition point comes from the cardboard")
	TEST_ASSERT(HAS_TAG(probe, TAG_FLAMMABLE), "cardboard makes it flammable")
	var/obj/item/dq_property_test/blunt/blunt = allocate(/obj/item/dq_property_test/blunt)
	TEST_ASSERT(!HAS_TAG(blunt, TAG_FLAMMABLE), "steel alone is not flammable")
	TEST_ASSERT_EQUAL(HAS_TAG(blunt, TAG_CONDUCTIVE), steel.conductive ? TRUE : FALSE, "conductive follows the material")
	TEST_ASSERT(!dq_type_has_tag(/obj/item/dq_property_test/blunt, TAG_SHARP), "the blunt subtype is not sharp")
	TEST_ASSERT_EQUAL(dq_type_property(/obj/item/tool/screwdriver, PROP_SIZE_CLASS), /obj/item/tool/screwdriver::w_class, "a real item reads its w_class")

	// Interning: equal values share one table.
	var/datum/property_registry/registry = dq_property_registry()
	TEST_ASSERT(registry.type_table(path, null) == registry.type_table(/obj/item/dq_property_test/twin, null), "identical types share an interned table")
	TEST_ASSERT(registry.type_table(path, null) != registry.type_table(/obj/item/dq_property_test/blunt, null), "different types do not")

	// Variants override type values.
	GLOB.dq_variant_tables[path] = "dq_variants_property_test"
	TEST_ASSERT_EQUAL(dq_type_property(path, PROP_SIZE_CLASS, "big"), ITEMSIZE_HUGE, "the big variant overrides w_class")
	TEST_ASSERT_EQUAL(dq_type_property(path, PROP_SIZE_CLASS, "missing"), ITEMSIZE_SMALL, "an unknown variant keeps the type value")
	var/obj/item/dq_property_test/variant_item = allocate(path)
	variant_item.variant = "big"
	variant_item.w_class = ITEMSIZE_HUGE
	TEST_ASSERT_EQUAL(PROPERTY(variant_item, PROP_SIZE_CLASS), ITEMSIZE_HUGE, "an instance of the variant reads its state")
	GLOB.dq_variant_tables -= path

	// Instances read saved state, and per-type values don't change.
	var/obj/item/dq_property_test/item = allocate(path)
	TEST_ASSERT_EQUAL(PROPERTY(item, PROP_SIZE_CLASS), ITEMSIZE_SMALL, "an unchanged instance matches its type")
	item.w_class = ITEMSIZE_LARGE
	item.sharp = FALSE
	TEST_ASSERT_EQUAL(PROPERTY(item, PROP_SIZE_CLASS), ITEMSIZE_LARGE, "instance state overrides the type value")
	TEST_ASSERT(!HAS_TAG(item, TAG_SHARP), "a blunted instance is not sharp")
	TEST_ASSERT_EQUAL(dq_type_property(path, PROP_SIZE_CLASS), ITEMSIZE_SMALL, "the per-type value is unchanged")
	item.set_material_mix(list(MAT_STEEL = 3000))
	TEST_ASSERT(abs(PROPERTY(item, PROP_MASS) - 3) < 0.0001, "instance matter drives instance mass")
	TEST_ASSERT(!HAS_TAG(item, TAG_FLAMMABLE), "without cardboard the instance is not flammable")

	// Component contributors fold in with the aggregator.
	item.AddComponent(/datum/component/dq_property_test)
	TEST_ASSERT(abs(PROPERTY(item, PROP_MASS) - 5) < 0.0001, "the component adds 2 kg, got [PROPERTY(item, PROP_MASS)]")

	// Equipment contributors: a mob's mass sums what it holds.
	var/mob/dq_property_test/M = allocate(/mob/dq_property_test)
	TEST_ASSERT_NULL(PROPERTY(M, PROP_MASS), "a mob with nothing equipped has no mass value")
	var/obj/item/dq_property_test/held = allocate(path)
	M.test_equipped = list(held, item)
	TEST_ASSERT(abs(PROPERTY(M, PROP_MASS) - 6.5) < 0.0001, "equipped 1.5 kg and 5 kg items sum to 6.5 kg, got [PROPERTY(M, PROP_MASS)]")

	// Container-style aggregates.
	TEST_ASSERT_EQUAL(dq_property_aggregate(PROP_SIZE_CLASS, list(item, held)), ITEMSIZE_LARGE, "size aggregates with max")
	TEST_ASSERT_EQUAL(dq_property_aggregate(PROP_MELTING_POINT, list(item, held)), min(steel.melting_point, cardboard.melting_point), "melting point aggregates with min")
