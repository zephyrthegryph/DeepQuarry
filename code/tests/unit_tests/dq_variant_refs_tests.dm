// A VARIANT() reference (code/defines/content/variants.dm) stands where a path was: every place that makes a thing from a spawn target takes one
// (variant_new, make, loot tables, supply packs, snack trash, techweb designs), and the trash family that moved into a table is reachable by each.

#define DQ_TRASH_REF VARIANT(/obj/item/trash, "popcorn")

/// Asserts that `thing` is the trash row `key` made: its parent type and the row's vars.
/proc/dq_trash_row_ok(datum/unit_test/test, obj/item/trash/thing, key)
	if(!istype(thing))
		test.Fail("[key] did not make trash")
		return FALSE
	var/list/row = dq_variant_vars(/obj/item/trash, key)
	for(var/var_name in row)
		if(!row[var_name])
			continue
		if(thing.vars[var_name] != row[var_name])
			test.Fail("trash [key] has [var_name] = [thing.vars[var_name]], its row says [row[var_name]]")
			return FALSE
	return TRUE

/datum/unit_test/dq_variant_ref_trash_rows

/datum/unit_test/dq_variant_ref_trash_rows/Run()
	var/turf/T = dq_containment_floor()
	var/made = 0
	for(var/key in GLOB.dq_variants_trash)
		var/obj/item/trash/thing = variant_new(VARIANT(/obj/item/trash, key), T)
		dq_trash_row_ok(src, thing, key)
		TEST_ASSERT_EQUAL(thing.variant, key, "[key] carries its key")
		qdel(thing)
		made++
	TEST_ASSERT(made > 50, "the trash family has its rows ([made])")

/datum/unit_test/dq_variant_ref_consumers

/datum/unit_test/dq_variant_ref_consumers/Run()
	var/turf/T = dq_containment_floor()
	// variant_new() keeps the constructor arguments (trash takes its age positionally).
	var/obj/item/trash/aged = variant_new(DQ_TRASH_REF, T, 7)
	TEST_ASSERT(dq_trash_row_ok(src, aged, "popcorn"), "variant_new with an argument")
	TEST_ASSERT_EQUAL(aged.age, 7, "the constructor argument reached the type")
	qdel(aged)
	// make() takes a reference as the type.
	var/obj/item/trash/by_make = make(DQ_TRASH_REF, at = T)
	TEST_ASSERT(dq_trash_row_ok(src, by_make, "popcorn"), "make() with a reference")
	TEST_ASSERT_EQUAL(by_make.variant, "popcorn", "make() set the key")
	qdel(by_make)
	// A loot table entry.
	var/list/direct = list()
	loot_emit(DQ_TRASH_REF, T, null, direct, list())
	TEST_ASSERT_EQUAL(length(direct), 1, "a loot entry made one thing")
	TEST_ASSERT(dq_trash_row_ok(src, direct[1], "popcorn"), "a loot entry that is a reference")
	qdel(direct[1])
	// Supply packs and the other spawn lists.
	var/obj/item/trash/spawned = spawn_with_variant(DQ_TRASH_REF, T, null)
	TEST_ASSERT(dq_trash_row_ok(src, spawned, "popcorn"), "spawn_with_variant with a reference")
	qdel(spawned)
	// Snack trash.
	var/obj/item/reagent_containers/food/snacks/popcorn/snack = allocate(/obj/item/reagent_containers/food/snacks/popcorn, T)
	TEST_ASSERT(islist(snack.trash), "a snack names its trash by reference")
	var/obj/item/trash/wrapper = variant_new(snack.trash, T)
	TEST_ASSERT(dq_trash_row_ok(src, wrapper, "popcorn"), "the snack's trash")
	qdel(wrapper)
	// A techweb design that builds a variant.
	var/found = 0
	for(var/design_id in SSresearch.techweb_designs)
		var/datum/design_techweb/D = SSresearch.techweb_designs[design_id] // a shared round definition: read, never deleted
		if(!islist(D.build_path))
			continue
		var/obj/item/product = D.create_item(T)
		TEST_ASSERT_NOTNULL(product, "[D.type] builds its product")
		TEST_ASSERT_EQUAL(product.type, saved_type_path(D.build_path), "[D.type] builds the parent type")
		TEST_ASSERT_NOTNULL(D.get_description(), "[D.type] describes itself")
		qdel(product)
		found++
	TEST_ASSERT(found > 0, "a design builds a variant")
	// The maintenance junk list holds the variants.
	var/list/refs = variant_refs(/obj/item/trash, except = list("syndi_cakes"))
	TEST_ASSERT_EQUAL(length(refs), length(GLOB.dq_variants_trash) - 1, "variant_refs() lists every row but the excluded")

#undef DQ_TRASH_REF
