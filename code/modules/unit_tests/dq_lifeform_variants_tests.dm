// variants(nameof(var), PROC_REF(table)) (code/engine/lifeforms/variants.dm): a variant key's row of vars, applied at preinit.

/obj/item/dq_variants_probe
	name = "variant probe"
	desc = "plain"
	icon_state = "plain"
	/// What the init code saw: the row is applied before it runs.
	var/name_at_init

CAPABILITIES(/obj/item/dq_variants_probe)
	variants(nameof(variant), PROC_REF(variant_table))

/obj/item/dq_variants_probe/Initialize(mapload)
	. = ..()
	name_at_init = name

/obj/item/dq_variants_probe/proc/variant_table()
	var/static/list/rows = list(
		"red" = list("name" = "red probe", "icon_state" = "probe_red"),
		"blank" = list("name" = "", "desc" = "blank probe"),
	)
	return rows

/// A map edit is a key set before the instance initializes; a subtype default stands in for one here.
/obj/item/dq_variants_probe/red
	variant = "red"

/obj/item/dq_variants_probe/blank
	variant = "blank"

/obj/item/dq_variants_probe/unknown
	variant = "no such row"

/datum/unit_test/dq_lifeform_variants

/datum/unit_test/dq_lifeform_variants/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_variants_probe/red/R = allocate(/obj/item/dq_variants_probe/red, T)
	TEST_ASSERT_EQUAL(R.name, "red probe", "the row's name is applied")
	TEST_ASSERT_EQUAL(R.icon_state, "probe_red", "and its icon state")
	TEST_ASSERT_EQUAL(R.desc, "plain", "a var the row does not give is the type's")
	TEST_ASSERT_EQUAL(R.name_at_init, "red probe", "the row is applied before the type's init code reads the instance")

	var/obj/item/dq_variants_probe/blank/B = allocate(/obj/item/dq_variants_probe/blank, T)
	TEST_ASSERT_EQUAL(B.name, "variant probe", "an empty value in the row is skipped")
	TEST_ASSERT_EQUAL(B.desc, "blank probe", "the rest of the row still applies")

	var/obj/item/dq_variants_probe/unknown/U = allocate(/obj/item/dq_variants_probe/unknown, T)
	TEST_ASSERT_EQUAL(U.name, "variant probe", "a key with no row changes nothing")

	var/obj/item/dq_variants_probe/P = allocate(/obj/item/dq_variants_probe, T)
	TEST_ASSERT_EQUAL(P.name, "variant probe", "no key, no row")
	P.variant = "red"
	P.apply_variant()
	TEST_ASSERT_EQUAL(P.name, "red probe", "apply_variant() applies the declared table when the key is set later (a loadout tweak)")
