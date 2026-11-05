// Admin spawn by variant (code/content/admin/spawn_menu.dm, admin.dm): the spawn picker lists the old paths of collapsed families, and a
// spawn of one makes the parent with its row.

/datum/unit_test/dq_admin_spawn_variants

/datum/unit_test/dq_admin_spawn_variants/Run()
	var/list/names = variant_alias_names()
	TEST_ASSERT(length(names) > 100, "the picker lists the old paths of collapsed families ([length(names)])")
	var/list/trash_row = GLOB.dq_variants_trash["popcorn"]
	TEST_ASSERT_EQUAL(names["/obj/item/trash/popcorn"], trash_row["name"], "an old path is listed under its row's name")
	TEST_ASSERT(("/obj/structure/sign/department/medbay" in names), "a sign row is listed")

	var/list/target = admin_spawn_target("/obj/item/trash/popcorn")
	TEST_ASSERT(islist(target), "an old path resolves to a reference")
	TEST_ASSERT_EQUAL(target[1], /obj/item/trash, "to the parent")
	TEST_ASSERT_EQUAL(target[2], "popcorn", "and the row")
	TEST_ASSERT_EQUAL(admin_spawn_target("/obj/item/pen"), /obj/item/pen, "a live path resolves as before")
	TEST_ASSERT_EQUAL(admin_spawn_target("/turf/space"), /turf/space, "a turf path resolves too")
	TEST_ASSERT_NULL(admin_spawn_target("/datum/unit_test"), "a path that is not an atom is refused")
	TEST_ASSERT_NULL(admin_spawn_target("/obj/item/no/such/thing"), "a path that names nothing is refused")
	TEST_ASSERT_NULL(admin_spawn_target(null), "no text, no target")

	var/turf/T = dq_containment_floor()
	var/obj/item/trash/made = variant_new(target, T)
	TEST_ASSERT_EQUAL(made.name, trash_row["name"], "the spawn has its row's name")
	TEST_ASSERT_EQUAL(made.variant, "popcorn", "and its key")
	qdel(made)
