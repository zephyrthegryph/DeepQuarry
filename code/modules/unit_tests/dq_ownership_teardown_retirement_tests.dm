// Declared teardown policies retain products and links without manual disposal overrides.

/datum/unit_test/ownership_teardown_parser_deletes_grid_sets

/datum/unit_test/ownership_teardown_parser_deletes_grid_sets/Run()
	var/map_text = {"\"a\" = (/turf/simulated/floor,/area)
(1,1,1) = {\"
a
\"}"}
	var/datum/parsed_map/parser = allocate(/datum/parsed_map, map_text)
	TEST_ASSERT(length(parser.parsed_bounds), "constructor parsed real map bounds")
	var/datum/grid_set/grid = allocate(/datum/grid_set)
	rel_add(parser, nameof(parser.gridSets), grid)
	TEST_ASSERT_EQUAL(owner_of(grid), parser, "parser owns its grid set")
	qdel(parser)
	TEST_ASSERT(QDELETED(grid), "declared grid-set policy deletes parser data")

/datum/unit_test/ownership_teardown_stock_keeps_handed_out_product

/datum/unit_test/ownership_teardown_stock_keeps_handed_out_product/Run()
	var/turf/T = test_floor()
	var/obj/stock_holder = allocate(/obj, T)
	var/datum/stored_item/record = allocate(/datum/stored_item, stock_holder, /obj/item/pen)
	var/obj/item/pen/inside = allocate(/obj/item/pen, stock_holder)
	var/obj/item/pen/outside = allocate(/obj/item/pen, T)
	rel_add(record, nameof(record.instances), inside)
	rel_add(record, nameof(record.instances), outside)
	TEST_ASSERT_EQUAL(rel_kind(record, nameof(record.instances)), OWNK_REL, "record holds product references, not custody")
	qdel(record)
	TEST_ASSERT(QDELETED(inside), "stock still inside goes with the record")
	TEST_ASSERT(!QDELETED(outside), "a handed-out product survives the record")
	TEST_ASSERT_EQUAL(outside.loc, T, "handed-out product stays on the floor")

/datum/unit_test/ownership_teardown_delivery_spills_parcel

/datum/unit_test/ownership_teardown_delivery_spills_parcel/Run()
	var/turf/T = test_floor()
	var/obj/structure/bigDelivery/package = allocate(/obj/structure/bigDelivery, T)
	var/obj/item/pen/product = allocate(/obj/item/pen, package)
	rel_set(package, nameof(package.wrapped), product)
	TEST_ASSERT_EQUAL(owner_of(product), package, "package owns the wrapped product")
	qdel(package)
	TEST_ASSERT(!QDELETED(product), "wrapped product survives unwrapping")
	TEST_ASSERT_EQUAL(product.loc, T, "wrapped product spills onto the package turf")
	TEST_ASSERT_NULL(owner_of(product), "unwrapped product has no package owner")

/datum/unit_test/ownership_teardown_reference_drops_without_deleting_target

/datum/unit_test/ownership_teardown_reference_drops_without_deleting_target/Run()
	var/turf/T = test_floor()
	var/obj/effect/bmode/buildholder/holder = allocate(/obj/effect/bmode/buildholder, T)
	var/mob/living/simple_mob/target = allocate(/mob/living/simple_mob, T)
	rel_add(holder, nameof(holder.selected_mobs), target)
	TEST_ASSERT_EQUAL(rel_kind(holder, nameof(holder.selected_mobs)), OWNK_REL, "selected mobs are references")
	TEST_ASSERT_NULL(owner_of(target), "selection does not adopt a mob")
	qdel(target)
	TEST_ASSERT_EQUAL(LAZYLEN(holder.selected_mobs), 0, "deleted selected target automatically leaves the reference list")
	qdel(holder)
	TEST_ASSERT(QDELETED(holder), "holder teardown finishes after its selected target is gone")

/datum/unit_test/ownership_teardown_empty_parser

/datum/unit_test/ownership_teardown_empty_parser/Run()
	var/datum/parsed_map/parser = allocate(/datum/parsed_map)
	TEST_ASSERT_NULL(parser.parsed_bounds, "blank parser deliberately has no parsed bounds")
	TEST_ASSERT_NULL(parser.bounds, "blank parser deliberately has no offset bounds")
	TEST_ASSERT_EQUAL(length(parser.gridSets), 0, "blank parser has an empty eager grid list")
	qdel(parser)
	TEST_ASSERT(QDELETED(parser), "blank parser teardown completes without map bounds")
