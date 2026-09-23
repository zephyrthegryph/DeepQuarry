// Composition: per-type material blueprints (templates) with per-instance overrides.
// See code/modules/material_science/material_templates.dm and material_construction.dm.

// ---- Fixtures ----

/obj/item/dq_matter_test
	name = "matter test item"
	MATERIAL_MIX(list(MAT_STEEL = 100, MAT_GLASS = 50))

/// Inherits its parent's mix without redeclaring it.
/obj/item/dq_matter_test/child

/obj/item/dq_matter_test/cleared
	MATERIAL_NONE

/obj/item/dq_matter_test/single
	MATERIAL_BULK(MAT_STEEL, 300)

/obj/item/dq_matter_test/tool
	material_template = /datum/material_template/tool
	material_total = 1000

/// Whether two material lists hold the same materials and amounts (within float noise).
/// Null and empty are the same: made of nothing.
/proc/dq_matter_lists_equal(list/a, list/b)
	if(!length(a) || !length(b))
		return !length(a) && !length(b)
	if(length(a) != length(b))
		return FALSE
	for(var/mat in a)
		if(!(mat in b))
			return FALSE
		if(abs(a[mat] - b[mat]) > 0.001 * max(1, abs(a[mat])))
			return FALSE
	return TRUE

/proc/dq_matter_text(list/L)
	return length(L) ? json_encode(L) : "nothing"

/proc/dq_matter_sum(list/L)
	. = 0
	for(var/mat in L)
		. += L[mat]

// ---- Every type's composition matches its pre-conversion `matter` ----

/datum/unit_test/dq_matter_type_totals_match_snapshot

/// Intentional corrections to the snapshot: type -> its corrected composition, and why.
/proc/dq_matter_snapshot_fixes()
	return list(
		// list(PLASTIC = 500) keyed the string "PLASTIC", which is no material.
		/obj/item/handcuffs/fake = list(MAT_PLASTIC = 500),
	)

/// The construction total a type was already built with before `matter` was merged
/// into blueprints (ensure_material_construction() in Initialize), or null.
/proc/dq_matter_prior_construction_total(path)
	if(ispath(path, /obj/item/cell))
		return 2 * SHEET_MATERIAL_AMOUNT
	if(ispath(path, /obj/item/stack/cable_coil) || ispath(path, /obj/item/tank) || ispath(path, /obj/item/pipe))
		return SHEET_MATERIAL_AMOUNT
	return null

/datum/unit_test/dq_matter_type_totals_match_snapshot/Run()
	var/list/changes = dq_matter_snapshot_changes().Copy()
	var/list/fixes = dq_matter_snapshot_fixes()
	for(var/path in fixes)
		changes[path] = fixes[path]
	var/failures = 0
	var/checked = 0
	var/functional = 0
	var/list/mix_disagreements = list()
	for(var/path in typesof(/obj/item) - typesof(/obj/item/dq_matter_test))
		var/list/expected = null
		for(var/datum/T = path; T; T = initial(T.parent_type))
			if(T in changes)
				expected = changes[T]
				break
		var/list/actual = dq_type_material_totals(path)
		checked++
		var/obj/item/declared = path
		var/template_path = initial(declared.material_template)
		var/is_plain = !template_path || ispath(template_path, /datum/material_template/bulk) || ispath(template_path, /datum/material_template/mix)
		if(is_plain)
			if(!dq_matter_lists_equal(actual, expected) && failures++ < 20)
				TEST_FAIL("[path]: made of [dq_matter_text(actual)], expected [dq_matter_text(expected)]")
			continue
		// A functional blueprint splits a total between its parts; the mix may differ
		// from the old `matter`. Families that already had a real construction keep
		// that construction's total (their physics runs on it); every other type
		// conserves its old `matter` total.
		functional++
		var/construction_total = dq_matter_prior_construction_total(path)
		var/expected_total = isnull(construction_total) ? dq_matter_sum(expected) : construction_total
		if(abs(dq_matter_sum(actual) - expected_total) > 0.001 && failures++ < 20)
			TEST_FAIL("[path]: blueprint total [dq_matter_sum(actual)], expected [expected_total]")
		if(!dq_matter_lists_equal(actual, expected))
			mix_disagreements += "[path]: [dq_matter_text(expected)] -> [dq_matter_text(actual)]"
	log_test("dq_matter: [checked] item types checked, [functional] with functional blueprints, [length(mix_disagreements)] whose material mix changed:")
	for(var/line in mix_disagreements)
		log_test("  [line]")
	TEST_ASSERT(checked > 10000, "only [checked] item types were checked")
	TEST_ASSERT(failures == 0, "[failures] item types differ from the pre-conversion snapshot")

// ---- Blueprints, overrides and copy-on-write ----

/datum/unit_test/dq_matter_blueprints

/datum/unit_test/dq_matter_blueprints/Run()
	// A mix: shared by every instance and inherited by a subtype.
	var/obj/item/dq_matter_test/a = allocate(/obj/item/dq_matter_test)
	var/obj/item/dq_matter_test/b = allocate(/obj/item/dq_matter_test)
	var/obj/item/dq_matter_test/child/child = allocate(/obj/item/dq_matter_test/child)
	TEST_ASSERT(dq_matter_lists_equal(a.material_totals(), list(MAT_STEEL = 100, MAT_GLASS = 50)), "a mix item is made of its declared mix, got [dq_matter_text(a.material_totals())]")
	TEST_ASSERT_NULL(a.material_overrides, "a fresh instance stores no overrides")
	TEST_ASSERT_NULL(a.material_mix, "a fresh instance stores no list of its own")
	TEST_ASSERT(a.get_material_template() == b.get_material_template(), "instances share one mix template")
	TEST_ASSERT(child.get_material_template() == a.get_material_template(), "a subtype without a declaration shares its parent's")
	TEST_ASSERT(dq_matter_lists_equal(dq_type_material_totals(/obj/item/dq_matter_test/child), list(MAT_STEEL = 100, MAT_GLASS = 50)), "per-type reads inherit the mix")
	TEST_ASSERT(a.material_totals() != a.material_totals(), "totals are derived on demand, never a shared list")

	// Clearing, and a single plain material with no lists at all.
	var/obj/item/dq_matter_test/cleared/cleared = allocate(/obj/item/dq_matter_test/cleared)
	TEST_ASSERT(!length(cleared.material_totals()), "MATERIAL_NONE clears the parent's composition")
	TEST_ASSERT_NULL(dq_type_material_totals(/obj/item/dq_matter_test/cleared), "and per type")
	TEST_ASSERT_NULL(dq_type_material_totals(/obj/item), "the base item has no composition")
	var/obj/item/dq_matter_test/single/single = allocate(/obj/item/dq_matter_test/single)
	TEST_ASSERT(dq_matter_lists_equal(single.material_totals(), list(MAT_STEEL = 300)), "a bulk item is made of its one material")

	// A functional blueprint: amounts are fraction x total, overrides are per role.
	var/obj/item/dq_matter_test/tool/t1 = allocate(/obj/item/dq_matter_test/tool)
	var/obj/item/dq_matter_test/tool/t2 = allocate(/obj/item/dq_matter_test/tool)
	var/obj/item/dq_matter_test/tool/t3 = allocate(/obj/item/dq_matter_test/tool)
	TEST_ASSERT(dq_matter_lists_equal(t1.material_totals(), list(MAT_STEEL = 700, MAT_PLASTIC = 300)), "the tool blueprint splits 1000 units 70/30, got [dq_matter_text(t1.material_totals())]")
	t1.set_construction_material(MATERIAL_ROLE_GRIP, MAT_WOOD)
	TEST_ASSERT_EQUAL(t1.material_for_role(MATERIAL_ROLE_GRIP)?.name, MAT_WOOD, "the override fills its role")
	TEST_ASSERT(dq_matter_lists_equal(t1.material_totals(), list(MAT_STEEL = 700, MAT_WOOD = 300)), "the override changes the owner's totals")
	TEST_ASSERT(dq_matter_lists_equal(t2.material_totals(), list(MAT_STEEL = 700, MAT_PLASTIC = 300)), "another instance is unchanged")
	TEST_ASSERT_NULL(t2.material_overrides, "another instance gains no overrides")
	TEST_ASSERT(dq_matter_lists_equal(dq_type_material_totals(/obj/item/dq_matter_test/tool), list(MAT_STEEL = 700, MAT_PLASTIC = 300)), "the type blueprint is unchanged")
	t3.set_construction_material(MATERIAL_ROLE_GRIP, MAT_WOOD)
	TEST_ASSERT(t1.material_overrides == t3.material_overrides, "identical overrides share one interned list")
	var/list/shared = t1.material_overrides
	t3.set_construction_material(MATERIAL_ROLE_WORKING, MAT_GOLD)
	TEST_ASSERT(t1.material_overrides == shared && length(shared) == 1, "writing one instance never edits a shared list")
	t1.set_construction_material(MATERIAL_ROLE_GRIP, MAT_PLASTIC)
	TEST_ASSERT_NULL(t1.material_overrides, "going back to the default drops the override")

	// Exact conservation: the last role takes the rounding remainder.
	var/datum/material_template/cell = material_template_singleton(/datum/material_template/cell)
	for(var/total in list(1, 7, 333, 1001, 2 * SHEET_MATERIAL_AMOUNT + 1))
		TEST_ASSERT_EQUAL(dq_matter_sum(cell.role_amounts(total)), total, "cell roles must sum to exactly [total]")

	// Bulk holders: an arbitrary mix is genuine per-instance state.
	var/obj/item/dq_matter_test/single/holder = allocate(/obj/item/dq_matter_test/single)
	holder.add_materials(list(MAT_GLASS = 25))
	TEST_ASSERT(dq_matter_lists_equal(holder.material_totals(), list(MAT_STEEL = 300, MAT_GLASS = 25)), "adding keeps what the item was made of")
	TEST_ASSERT(dq_matter_lists_equal(single.material_totals(), list(MAT_STEEL = 300)), "adding to one item leaves another alone")
	holder.set_material_mix(null)
	TEST_ASSERT(!length(holder.material_totals()), "an empty mix means made of nothing")
	var/obj/item/dq_matter_test/tool/scaled = allocate(/obj/item/dq_matter_test/tool)
	scaled.scale_materials(0.5)
	TEST_ASSERT_EQUAL(dq_matter_sum(scaled.material_totals()), 500, "scaling a blueprint scales its total")

	// Material sheets: made of their material, per sheet, with nothing stored per stack.
	var/obj/item/stack/material/steel/sheet = allocate(/obj/item/stack/material/steel)
	TEST_ASSERT(dq_matter_lists_equal(sheet.material_totals(), sheet.material.get_matter()), "a sheet is made of its material")
	TEST_ASSERT(isnull(sheet.material_mix) && isnull(sheet.material_overrides), "a sheet stack keeps no list of its own")
