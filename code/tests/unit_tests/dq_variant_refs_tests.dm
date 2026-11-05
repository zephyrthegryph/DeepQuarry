// A VARIANT() reference (code/defines/content/variants.dm) stands where a path was: every place that makes a thing from a spawn target takes one
// (variant_new, make, loot tables, supply packs, snack trash, techweb designs), and the trash family that moved into a table is reachable by each.

#define DQ_TRASH_REF VARIANT(/obj/item/trash/popcorn)

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
		var/obj/item/trash/thing = variant_new(variant_ref(/obj/item/trash, key), T)
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
	TEST_ASSERT_EQUAL(snack.trash, "/obj/item/trash/popcorn", "a snack names its trash by reference")
	TEST_ASSERT_EQUAL(snack.trash, DQ_TRASH_REF, "VARIANT() is the old path text")
	TEST_ASSERT_EQUAL(variant_ref(/obj/item/trash, "popcorn"), DQ_TRASH_REF, "variant_ref() builds the same text")
	var/obj/item/trash/wrapper = variant_new(snack.trash, T)
	TEST_ASSERT(dq_trash_row_ok(src, wrapper, "popcorn"), "the snack's trash")
	qdel(wrapper)
	// A techweb design that builds a variant.
	var/found = 0
	for(var/design_id in SSresearch.techweb_designs)
		var/datum/design_techweb/D = SSresearch.techweb_designs[design_id] // a shared round definition: read, never deleted
		if(!istext(D.build_path))
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

/// Every row of every loot table is something loot_emit() can make: a path, an entry datum or a whole VARIANT() reference. A reference that a
/// table flattened into its parts leaves a bare key text behind, which loot_emit() crashes on at the roll.
/datum/unit_test/dq_loot_tables_hold_whole_entries

/datum/unit_test/dq_loot_tables_hold_whole_entries/Run()
	static_entries_ensure("dq_loot_tables_hold_whole_entries")
	var/checked = 0
	for(var/path in GLOB.loot_decls)
		var/datum/loot_decl/decl = GLOB.loot_decls[path]
		for(var/datum/loot_entry/sub/table in list(decl.main_table, decl.unlucky, decl.uncommon, decl.rare))
			checked += dq_loot_table_check(src, path, table)
	TEST_ASSERT(checked > 0, "some loot table has entries")
	// The shared trash table rolls without a runtime: each row of its computed list, one by one.
	var/turf/T = test_floor()
	var/datum/loot_decl/junk = loot_decl_for(/loot/junk/trash)
	TEST_ASSERT_NOTNULL(junk, "the trash table is declared")
	var/rolled = 0
	for(var/datum/loot_entry/sub/types/computed in junk.main_table.entries)
		for(var/entry in computed.entries)
			var/list/direct = list()
			var/list/nested = list()
			loot_emit(entry, T, new /datum/loot_rng(1), direct, nested)
			rolled++
			for(var/atom/A as anything in direct + nested)
				qdel(A)
	TEST_ASSERT(rolled > 0, "the trash table has a computed list")
	own_turf_contents(T)

/// Checks one table and the tables nested in it; returns how many rows it looked at.
/proc/dq_loot_table_check(datum/unit_test/test, path, datum/loot_entry/sub/table)
	. = 0
	if(length(table.entries) != length(table.weights))
		test.Fail("[path]: a table has one weight per entry")
	for(var/entry in table.entries)
		.++
		if(istype(entry, /datum/loot_entry/sub))
			. += dq_loot_table_check(test, path, entry)
			continue
		var/ok = ispath(entry) || istype(entry, /datum/loot_entry) || (istext(entry) && variant_alias_of(entry))
		if(!ok)
			test.Fail("[path]: a table entry that loot_emit() cannot make: [entry]")

/// Every seed packet row makes a packet of the plant its row names, and a vending line for one makes the same packet.
/datum/unit_test/dq_variant_ref_seed_rows

/datum/unit_test/dq_variant_ref_seed_rows/Run()
	var/turf/T = dq_containment_floor()
	var/made = 0
	for(var/key in GLOB.dq_variants_seeds)
		var/list/row = GLOB.dq_variants_seeds[key]
		var/obj/item/seeds/packet = variant_new(variant_ref(/obj/item/seeds, key), T)
		TEST_ASSERT_EQUAL(packet.type, /obj/item/seeds, "[key] is a packet of seeds")
		TEST_ASSERT_EQUAL(packet.variant, key, "[key] carries its key")
		TEST_ASSERT_EQUAL(packet.seed_type, row["seed_type"], "[key] names its plant")
		TEST_ASSERT_NOTNULL(packet.seed(), "[key] has a seed datum")
		qdel(packet)
		made++
	TEST_ASSERT(made > 90, "the seed family has its rows ([made])")
	var/datum/stored_item/vending_product/line = new(null, VARIANT(/obj/item/seeds/appleseed), null, 2)
	var/obj/item/seeds/proto = /obj/item/seeds
	TEST_ASSERT_EQUAL(line.item_name, initial(proto.name), "a vending line for a seed row is named for the parent")
	var/obj/item/seeds/vended = line.materialize(T)
	TEST_ASSERT_EQUAL(vended.seed_type, PLANT_APPLE, "and makes the row's packet")
	qdel(vended)
	qdel(line)

/// Every dispenser cartridge row holds what its row says, at its size.
/datum/unit_test/dq_variant_ref_cartridge_rows

/datum/unit_test/dq_variant_ref_cartridge_rows/Run()
	var/turf/T = dq_containment_floor()
	var/made = 0
	for(var/key in GLOB.dq_variants_chem_cartridges)
		var/list/row = GLOB.dq_variants_chem_cartridges[key]
		var/obj/item/reagent_containers/chem_disp_cartridge/cart = variant_new(variant_ref(/obj/item/reagent_containers/chem_disp_cartridge, key), T)
		TEST_ASSERT_EQUAL(cart.variant, key, "[key] carries its key")
		if(row["spawn_reagent"])
			TEST_ASSERT_EQUAL(cart.spawn_reagent, row["spawn_reagent"], "[key] names its reagent")
			TEST_ASSERT(cart.reagents.total_volume > 0, "[key] comes filled")
		if(row["volume"])
			TEST_ASSERT_EQUAL(cart.volume, row["volume"], "[key] has its size")
		qdel(cart)
		made++
	TEST_ASSERT(made > 150, "the cartridge family has its rows ([made])")

#undef DQ_TRASH_REF
