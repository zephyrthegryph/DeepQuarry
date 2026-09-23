// Static per-type matter (DEFAULT_MATTER) with copy-on-write instance overrides.
// See code/game/objects/item_matter.dm.

// ---- Fixtures ----

/obj/item/dq_matter_test
	name = "matter test item"
	DEFAULT_MATTER(list(MAT_STEEL = 100, MAT_GLASS = 50))

/// Inherits its parent's table without redeclaring it.
/obj/item/dq_matter_test/child

/obj/item/dq_matter_test/cleared
	DEFAULT_MATTER(null)

/// Whether two matter lists hold the same materials and amounts (within float noise).
/proc/dq_matter_lists_equal(list/a, list/b)
	if(isnull(a) || isnull(b))
		return isnull(a) && isnull(b)
	if(length(a) != length(b))
		return FALSE
	for(var/mat in a)
		if(!(mat in b))
			return FALSE
		if(abs(a[mat] - b[mat]) > 0.001 * max(1, abs(a[mat])))
			return FALSE
	return TRUE

/proc/dq_matter_text(list/L)
	return isnull(L) ? "null" : json_encode(L)

// ---- Every type's default equals its pre-conversion `matter` ----

/datum/unit_test/dq_matter_type_defaults_match_snapshot

/datum/unit_test/dq_matter_type_defaults_match_snapshot/Run()
	var/list/changes = dq_matter_snapshot_changes()
	var/failures = 0
	var/checked = 0
	for(var/path in typesof(/obj/item) - typesof(/obj/item/dq_matter_test))
		var/list/expected = null
		for(var/datum/T = path; T; T = initial(T.parent_type))
			if(T in changes)
				expected = changes[T]
				break
		var/list/actual = dq_type_default_matter(path)
		checked++
		if(!dq_matter_lists_equal(actual, expected))
			if(failures++ < 20)
				TEST_FAIL("[path]: default matter [dq_matter_text(actual)], expected [dq_matter_text(expected)]")
	TEST_ASSERT(checked > 10000, "only [checked] item types were checked")
	TEST_ASSERT(failures == 0, "[failures] item types have a default matter that differs from the pre-conversion snapshot")

// ---- Instances share the type table and copy on write ----

/datum/unit_test/dq_matter_copy_on_write

/datum/unit_test/dq_matter_copy_on_write/Run()
	var/list/type_table = dq_type_default_matter(/obj/item/dq_matter_test)
	TEST_ASSERT(dq_matter_lists_equal(type_table, list(MAT_STEEL = 100, MAT_GLASS = 50)), "the declared table is registered by type")

	var/obj/item/dq_matter_test/a = allocate(/obj/item/dq_matter_test)
	var/obj/item/dq_matter_test/b = allocate(/obj/item/dq_matter_test)
	TEST_ASSERT_NULL(a.matter, "a fresh instance has no override")
	TEST_ASSERT(a.get_matter() == type_table, "a fresh instance reads the shared type table")
	TEST_ASSERT(b.get_matter() == a.get_matter(), "instances of a type share one table")

	var/list/owned = a.own_matter()
	TEST_ASSERT(owned != type_table, "own_matter() copies")
	TEST_ASSERT(a.own_matter() == owned, "a second own_matter() keeps the same private list")
	owned[MAT_STEEL] = 999
	owned[MAT_PLASTIC] = 5
	TEST_ASSERT_EQUAL(a.get_matter()[MAT_STEEL], 999, "the owner sees its edit")
	TEST_ASSERT_EQUAL(b.get_matter()[MAT_STEEL], 100, "another instance is unchanged")
	TEST_ASSERT(!(MAT_PLASTIC in b.get_matter()), "another instance gains no materials")
	TEST_ASSERT_EQUAL(type_table[MAT_STEEL], 100, "the type default is unchanged")
	TEST_ASSERT_EQUAL(length(type_table), 2, "the type default gains no materials")
	var/obj/item/dq_matter_test/c = allocate(/obj/item/dq_matter_test)
	TEST_ASSERT_EQUAL(c.get_matter()[MAT_STEEL], 100, "a new instance still gets the declared default")

	a.set_matter(null)
	TEST_ASSERT(a.get_matter() == type_table, "set_matter(null) returns to the type default")
	a.set_custom_materials(list())
	TEST_ASSERT(islist(a.get_matter()) && !length(a.get_matter()), "custom empty materials mean made of nothing, not the default")

	// Inheritance and clearing.
	var/obj/item/dq_matter_test/child/child = allocate(/obj/item/dq_matter_test/child)
	TEST_ASSERT(child.get_matter() == type_table, "a subtype without a declaration shares its parent's table")
	TEST_ASSERT(dq_type_default_matter(/obj/item/dq_matter_test/child) == type_table, "per-type reads inherit too")
	var/obj/item/dq_matter_test/cleared/cleared = allocate(/obj/item/dq_matter_test/cleared)
	TEST_ASSERT_NULL(cleared.get_matter(), "DEFAULT_MATTER(null) clears the parent's table")
	TEST_ASSERT_NULL(dq_type_default_matter(/obj/item/dq_matter_test/cleared), "and per type")
	TEST_ASSERT_NULL(dq_type_default_matter(/obj/item), "the base item has no matter")

	// Material sheets: one shared table per material, none per stack.
	var/obj/item/stack/material/steel/s1 = allocate(/obj/item/stack/material/steel)
	var/obj/item/stack/material/steel/s2 = allocate(/obj/item/stack/material/steel)
	TEST_ASSERT_NULL(s1.matter, "a sheet stack keeps no list of its own")
	TEST_ASSERT(s1.get_matter() == s2.get_matter(), "steel stacks share one table")
	TEST_ASSERT(dq_matter_lists_equal(s1.get_matter(), s1.material.get_matter()), "a sheet's matter is its material's")
	var/list/sheet_owned = s1.own_matter()
	sheet_owned[MAT_STEEL] = 1
	TEST_ASSERT_EQUAL(s2.get_matter()[MAT_STEEL], SHEET_MATERIAL_AMOUNT, "editing one stack leaves the shared material table alone")
