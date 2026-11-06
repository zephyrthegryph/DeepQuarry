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

/// Every action figure row makes the figure its row describes, and the loadout picker offers each by its name.
/datum/unit_test/dq_variant_ref_figure_rows

/datum/unit_test/dq_variant_ref_figure_rows/Run()
	var/turf/T = dq_containment_floor()
	var/made = 0
	for(var/key in GLOB.dq_variants_toy_figures)
		var/list/row = GLOB.dq_variants_toy_figures[key]
		var/obj/item/toy/figure/figure = variant_new(variant_ref(/obj/item/toy/figure, key), T)
		TEST_ASSERT_EQUAL(figure.variant, key, "[key] carries its key")
		if(row["toysay"])
			TEST_ASSERT_EQUAL(figure.toysay, row["toysay"], "[key] says its line")
		qdel(figure)
		made++
	TEST_ASSERT(made > 45, "the figure family has its rows ([made])")
	var/datum/gear/G = GLOB.gear_datums["action figure selection"]
	TEST_ASSERT_NOTNULL(G, "the figure picker is in the loadout")
	var/datum/gear_tweak/path/chooser
	var/chooser_index = 0
	for(var/i in 1 to length(G.gear_tweaks))
		if(istype(G.gear_tweaks[i], /datum/gear_tweak/path))
			chooser = G.gear_tweaks[i]
			chooser_index = i
	TEST_ASSERT(chooser_index > 0, "the picker has a type tweak")
	var/list/table = GLOB.dq_variants_toy_figures
	var/picked = 0
	for(var/key in table)
		var/list/row = table[key]
		var/shown = row["name"] || key
		TEST_ASSERT_EQUAL(chooser.valid_paths[shown], variant_ref(/obj/item/toy/figure, key), "[shown] is offered as row [key]")
		picked++
		if(picked > 5)
			break
	var/obj/item/toy/figure/picked_figure = G.spawn_item(T, list("[chooser_index]" = "Action Abe action figure"))
	TEST_ASSERT(istype(picked_figure), "the picker spawns a figure")
	TEST_ASSERT_EQUAL(picked_figure.variant, "abe", "from the row the name picked")
	qdel(picked_figure)

/// Every uniform row makes the jumpsuit its row describes, a row that switches a default off (displays_id, rolled_sleeves, has_sensor) included,
/// and a list a row holds is the instance's own copy.
/datum/unit_test/dq_variant_ref_uniform_rows

/datum/unit_test/dq_variant_ref_uniform_rows/Run()
	var/turf/T = dq_containment_floor()
	var/made = 0
	var/falsey = 0
	for(var/key in GLOB.dq_variants_under_rank)
		var/list/row = GLOB.dq_variants_under_rank[key]
		var/ref = variant_ref(/obj/item/clothing/under/rank, key)
		var/obj/item/clothing/under/rank/suit = variant_new(ref, T)
		TEST_ASSERT_EQUAL(suit.variant, key, "[key] carries its key")
		TEST_ASSERT(variant_is(suit, ref), "[key] is what its reference names")
		for(var/var_name in row)
			if(islist(row[var_name]))
				continue
			TEST_ASSERT_EQUAL(suit.vars[var_name], row[var_name], "[key] has [var_name] as its row says")
			if(!row[var_name])
				falsey++
		qdel(suit)
		made++
	TEST_ASSERT(made > 85, "the uniform family has its rows ([made])")
	TEST_ASSERT(falsey > 0, "some uniform row switches a default off")
	var/obj/item/clothing/under/rank/centcom = variant_new(VARIANT(/obj/item/clothing/under/rank/centcom), T)
	TEST_ASSERT(!centcom.displays_id, "the dress uniform shows no ID")
	TEST_ASSERT(!variant_is(centcom, VARIANT(/obj/item/clothing/under/rank/centcom_captain)), "another row is not this one")
	TEST_ASSERT(variant_is(variant_locate(VARIANT(/obj/item/clothing/under/rank/centcom)), VARIANT(/obj/item/clothing/under/rank/centcom)), "a pinpointer finds a variant by its reference")
	var/obj/item/clothing/under/rank/other = variant_new(VARIANT(/obj/item/clothing/under/rank/centcom), T)
	other.set_item_state_slots_at(slot_w_uniform_str, "changed")
	TEST_ASSERT(centcom.item_state_slots[slot_w_uniform_str] != "changed", "a row's list is not shared between instances")
	qdel(centcom)
	qdel(other)
	var/obj/item/clothing/under/rank/clown = variant_new(VARIANT(/obj/item/clothing/under/rank/clown), T)
	TEST_ASSERT_EQUAL(clown.channel_type(), "/obj/item/clothing/under/rank/clown", "channel data is read under the row's old path")
	qdel(clown)

/// Every 50-stack spawner row resolves to a full stack of the type its row names, made from a reference; a type written as two blocks is one row.
/datum/unit_test/dq_variant_ref_fiftyspawner_rows

/datum/unit_test/dq_variant_ref_fiftyspawner_rows/Run()
	var/turf/T = dq_containment_floor()
	var/made = 0
	for(var/key in GLOB.dq_variants_fiftyspawner)
		var/list/row = GLOB.dq_variants_fiftyspawner[key]
		var/stack_type = row["type_to_spawn"]
		TEST_ASSERT(ispath(stack_type, /obj/item/stack), "[key] names a stack type")
		variant_new(variant_ref(/obj/fiftyspawner, key), T)
		var/obj/item/stack/found = locate(stack_type) in T
		TEST_ASSERT_NOTNULL(found, "[key] made its stack")
		TEST_ASSERT_EQUAL(found.type, stack_type, "[key] made exactly the stack its row names")
		TEST_ASSERT_EQUAL(found.get_amount(), found.max_amount, "[key] made a full stack")
		qdel(found)
		made++
	TEST_ASSERT(made > 70, "the spawner family has its rows ([made])")
	TEST_ASSERT_EQUAL(GLOB.dq_variants_fiftyspawner["bcarpet"]["name"], "stack of black carpet", "the later of a type's two blocks wins")

/// Every circuit board row makes the board its row describes, each with a frame type of its own, and a machine that names its circuit by
/// reference keeps it as data until something needs the board, then makes the row's board.
/datum/unit_test/dq_variant_ref_circuitboard_rows

/datum/unit_test/dq_variant_ref_circuitboard_rows/Run()
	var/turf/T = dq_containment_floor()
	var/made = 0
	var/typed_frames = 0
	for(var/key in GLOB.dq_variants_circuitboards)
		var/list/row = GLOB.dq_variants_circuitboards[key]
		var/ref = variant_ref(/obj/item/circuitboard, key)
		var/obj/item/circuitboard/board = variant_new(ref, T)
		TEST_ASSERT_EQUAL(board.variant, key, "[key] carries its key")
		TEST_ASSERT(variant_is(board, ref), "[key] is what its reference names")
		if(row["build_path"])
			TEST_ASSERT_EQUAL(board.build_path, row["build_path"], "[key] builds what its row says")
		if(ispath(row["board_type"], /datum/frame/frame_types))
			typed_frames++
			TEST_ASSERT_EQUAL(board.board_type?:type, row["board_type"], "[key] has the frame type its row names")
			var/obj/item/circuitboard/twin = variant_new(ref, T)
			TEST_ASSERT(twin.board_type != board.board_type, "[key]: two boards own two frame types")
			qdel(twin)
		qdel(board)
		made++
	TEST_ASSERT(made > 160, "the circuit board family has its rows ([made])")
	TEST_ASSERT(typed_frames > 100, "most rows name a frame type ([typed_frames])")
	var/obj/item/circuitboard/burnt = own(variant_new(VARIANT(/obj/item/circuitboard/broken), T))
	TEST_ASSERT(edible_trash_item(burnt), "a burnt out board is still edible trash")
	TEST_ASSERT_EQUAL(burnt.board_type, "other", "and keeps the text its row gives for a frame type")
	var/obj/item/circuitboard/sound_board = own(variant_new(VARIANT(/obj/item/circuitboard/autolathe), T))
	TEST_ASSERT(!edible_trash_item(sound_board), "any other board is not")
	var/obj/machinery/computer/message_monitor/console = allocate(/obj/machinery/computer/message_monitor, T)
	TEST_ASSERT_EQUAL(initial(console.circuit), VARIANT(/obj/item/circuitboard/message_monitor), "a machine names its circuit by reference")
	var/obj/item/circuitboard/board = console.circuit
	TEST_ASSERT(istype(board), "the circuit is a real board")
	TEST_ASSERT(variant_is(board, VARIANT(/obj/item/circuitboard/message_monitor)), "and is the row's board")
	TEST_ASSERT(islist(dq_type_var(VARIANT(/obj/item/circuitboard/autolathe), "req_components")), "a reference's parts are read from its row")
	TEST_ASSERT_EQUAL(dq_type_var(VARIANT(/obj/item/circuitboard/autolathe), "build_path"), /obj/machinery/autolathe, "and its machine too")

#undef DQ_TRASH_REF
