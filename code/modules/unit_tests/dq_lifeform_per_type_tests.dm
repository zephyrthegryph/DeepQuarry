// per_type(nameof(var), PROC_REF(build)) (code/engine/lifeforms/per_type.dm): one lazily built, read-only table per type.

GLOBAL_VAR_INIT(dq_per_type_builds, 0)

/obj/item/dq_per_type_probe
	name = "per_type probe"
	var/list/menu = null
	var/list/seen_at_init = null

CAPABILITIES(/obj/item/dq_per_type_probe)
	per_type(nameof(menu), PROC_REF(build_menu))

/obj/item/dq_per_type_probe/Initialize(mapload)
	. = ..()
	seen_at_init = menu

/obj/item/dq_per_type_probe/proc/build_menu()
	GLOB.dq_per_type_builds++
	return list("soup" = 2, "bread" = 1, "[type]" = 0)

/// A subtype gets its own table (its build reads its own type).
/obj/item/dq_per_type_probe/sub

/datum/unit_test/dq_lifeform_per_type

/datum/unit_test/dq_lifeform_per_type/Run()
	var/turf/T = dq_containment_floor()
	var/builds_before = GLOB.dq_per_type_builds
	var/had_table = !isnull(per_type_table(/obj/item/dq_per_type_probe, "menu"))
	var/obj/item/dq_per_type_probe/A = allocate(/obj/item/dq_per_type_probe, T)
	var/obj/item/dq_per_type_probe/B = allocate(/obj/item/dq_per_type_probe, T)
	TEST_ASSERT_NOTNULL(A.seen_at_init, "the table is bound before the type's init code runs")
	TEST_ASSERT(A.menu == B.menu, "every instance of the type shares one table")
	TEST_ASSERT_EQUAL(GLOB.dq_per_type_builds - builds_before, had_table ? 0 : 1, "the table is built once, by the first instance")
	TEST_ASSERT_EQUAL(per_type_table(/obj/item/dq_per_type_probe, "menu"), A.menu, "per_type_table() answers the built table")
	var/obj/item/dq_per_type_probe/sub/C = allocate(/obj/item/dq_per_type_probe/sub, T)
	TEST_ASSERT(C.menu != A.menu, "a subtype has its own table")
	TEST_ASSERT_EQUAL(C.menu["[/obj/item/dq_per_type_probe/sub]"], 0, "built from the subtype's own instance")
