// Stock slots (roadmap C9, code/datums/containment/stock.dm): vending and
// smartfridge stock is a record per product with a latent count. Real items
// exist only once vended, or while their state is their own.

/obj/machinery/vending/dq_stock_test
	name = "stock test vendor"
	products = list(/obj/item/dq_containment_test = 5, /obj/item/dq_containment_test/glass = 3)
	contraband = list(/obj/item/dq_containment_test/wood = 2)
	premium = list(/obj/item/dq_containment_test/anchored = 1)
	prices = list(/obj/item/dq_containment_test/glass = 7)

/// Items of exactly `path` inside `holder`.
/datum/unit_test/proc/dq_stock_count_in(atom/holder, path)
	. = 0
	for(var/atom/movable/A as anything in holder.contents)
		if(A.type == path && !QDELETED(A))
			.++

/datum/unit_test/proc/dq_stock_record(list/records, path)
	for(var/datum/stored_item/R as anything in records)
		if(R.item_path == path)
			return R
	return null

// ---- Vending: vend, restock, deconstruct ----

/datum/unit_test/dq_stock_vending
	var/list/made = list()

/datum/unit_test/dq_stock_vending/Destroy()
	for(var/datum/D as anything in made)
		if(!QDELETED(D))
			qdel(D)
	made = null
	return ..()

/datum/unit_test/dq_stock_vending/Run()
	var/turf/floor = dq_containment_floor()
	TEST_ASSERT_NOTNULL(floor, "a clean floor")
	var/obj/machinery/vending/dq_stock_test/V = new(floor)
	made += V
	var/path = /obj/item/dq_containment_test

	// Records and their deltas.
	TEST_ASSERT_EQUAL(length(V.product_records), 4, "one record per product")
	var/datum/stored_item/vending_product/R = dq_stock_record(V.product_records, path)
	var/datum/stored_item/vending_product/G = dq_stock_record(V.product_records, /obj/item/dq_containment_test/glass)
	var/datum/stored_item/vending_product/W = dq_stock_record(V.product_records, /obj/item/dq_containment_test/wood)
	var/datum/stored_item/vending_product/P = dq_stock_record(V.product_records, /obj/item/dq_containment_test/anchored)
	TEST_ASSERT_EQUAL(R.get_amount(), 5, "stock count")
	TEST_ASSERT_EQUAL(G.price, 7, "price delta")
	TEST_ASSERT_EQUAL(W.category, CAT_HIDDEN, "contraband delta")
	TEST_ASSERT_EQUAL(P.category, CAT_COIN, "premium delta")
	TEST_ASSERT(V.has_prices && V.has_premium, "prices and premium flags")

	// tgui data lists normal stock only until hacked.
	var/list/data = V.tgui_data(null)
	TEST_ASSERT_EQUAL(length(data["products"]), 2, "normal products listed")
	V.categories |= CAT_HIDDEN
	data = V.tgui_data(null)
	TEST_ASSERT_EQUAL(length(data["products"]), 3, "contraband listed once hacked")
	var/list/first = data["products"][1]
	TEST_ASSERT_EQUAL(first["amount"], 5, "tgui amount")

	// Done-when: nothing is materialized, before or after a vend.
	TEST_ASSERT_EQUAL(dq_stock_count_in(V, path), 0, "no product exists inside at boot")
	var/obj/item/vended = R.get_product(floor)
	made += vended
	TEST_ASSERT(istype(vended, path) && vended.loc == floor, "vending made one real item on the floor")
	TEST_ASSERT_EQUAL(R.get_amount(), 4, "vending took one")
	TEST_ASSERT_EQUAL(dq_stock_count_in(V, path), 0, "vending did not materialize the rest")

	// Restock by cartridge adds to the count and creates nothing.
	V.refill_inventory()
	TEST_ASSERT_EQUAL(R.get_amount(), 9, "cartridge restock added the product's refill amount")
	TEST_ASSERT_EQUAL(dq_stock_count_in(V, path), 0, "restock created nothing")

	// Stocking an item identical to a fresh one folds it into the count.
	var/obj/item/fresh = new path(floor)
	TEST_ASSERT(state_can_serialize(fresh), "the fixture serializes")
	TEST_ASSERT(R.add_product(fresh), "stocked a fresh item")
	TEST_ASSERT(QDELETED(fresh), "a fresh item collapsed into the count")
	TEST_ASSERT_EQUAL(R.get_amount(), 10, "count after stocking")

	// An item with state of its own stays real, in the stock slot.
	var/obj/item/marked = new path(floor)
	made += marked
	marked.desc = "a unique one"
	TEST_ASSERT(R.add_product(marked), "stocked a marked item")
	TEST_ASSERT(!QDELETED(marked) && marked.loc == V, "a unique item stays real inside")
	TEST_ASSERT(marked in V.slot_contents(CONTAINER_SLOT_STOCK), "and sits in the stock slot")
	TEST_ASSERT_EQUAL(R.get_amount(), 11, "count includes the real one")
	TEST_ASSERT_EQUAL(V.slot_used(CONTAINER_SLOT_STOCK), 1 + 10 + 6 + 2 + 1, "stock units: real plus latent (glass was refilled too)")
	var/obj/item/back = R.get_product(floor)
	TEST_ASSERT(back == marked, "the unique item comes back out as itself")

	// Destroying the vendor deletes stock, as before: nothing spills.
	var/obj/item/kept = new path(floor)
	kept.desc = "another unique one"
	R.add_product(kept)
	var/before = dq_stock_count_in(floor, path)
	qdel(V)
	TEST_ASSERT(QDELETED(kept), "a real stocked item went with the vendor")
	TEST_ASSERT_EQUAL(dq_stock_count_in(floor, path), before, "destroying the vendor spilled nothing")

// ---- Smartfridge: insert, stack, vend, deconstruct ----

/datum/unit_test/dq_stock_smartfridge
	var/list/made = list()

/datum/unit_test/dq_stock_smartfridge/Destroy()
	for(var/datum/D as anything in made)
		if(!QDELETED(D))
			qdel(D)
	made = null
	return ..()

/datum/unit_test/dq_stock_smartfridge/Run()
	var/turf/floor = dq_containment_floor()
	TEST_ASSERT_NOTNULL(floor, "a clean floor")
	var/obj/machinery/smartfridge/F = new(floor)
	made += F
	var/path = /obj/item/dq_containment_test

	for(var/i in 1 to 4)
		F.stock(new path(floor))
	TEST_ASSERT_EQUAL(length(F.item_records), 1, "identical items share a record")
	var/datum/stored_item/R = F.item_records[1]
	TEST_ASSERT_EQUAL(R.amount, 4, "identical items collapsed into a count")
	TEST_ASSERT_EQUAL(dq_stock_count_in(F, path), 0, "no identical item stays real")
	TEST_ASSERT_EQUAL(F.stored_count(), 4, "fill level counts latent items")

	// Unique state stays real in the same record.
	var/obj/item/marked = new path(floor)
	marked.desc = "scratched"
	F.stock(marked)
	TEST_ASSERT(marked.loc == F && (marked in R.instances), "unique item stays real")
	TEST_ASSERT(marked in F.slot_contents(CONTAINER_SLOT_STOCK), "in the stock slot")
	TEST_ASSERT_EQUAL(R.get_amount(), 5, "record count")
	var/list/data = F.tgui_data(null)
	var/list/row = data["contents"][1]
	TEST_ASSERT_EQUAL(row["amount"], 5, "tgui amount")

	F.vend(R, 1)
	TEST_ASSERT(marked.loc == floor, "the real one vends first")
	var/before = dq_stock_count_in(floor, path)
	F.vend(R, 2)
	TEST_ASSERT_EQUAL(dq_stock_count_in(floor, path), before + 2, "vending two made two")
	TEST_ASSERT_EQUAL(R.get_amount(), 2, "two left")
	for(var/obj/item/I in floor)
		if(I.type == path)
			made += I
	TEST_ASSERT_EQUAL(dq_stock_count_in(F, path), 0, "vending did not materialize the rest")

	// Items that can't collapse (contents, processing) stay real.
	var/obj/item/busy = new path(floor)
	made += busy
	new /obj/item/paper(busy)
	F.stock(busy)
	TEST_ASSERT(!QDELETED(busy) && busy.loc == F, "an item with contents stays real")

	// Deconstruction spills the stock, latent copies made real.
	before = dq_stock_count_in(floor, path)
	qdel(F)
	TEST_ASSERT_EQUAL(dq_stock_count_in(floor, path), before + 3, "destroying the fridge spilled two latent and one real")
	TEST_ASSERT(busy.loc == floor, "the real one spilled")
	for(var/obj/item/I in floor)
		if(I.type == path)
			made += I

// ---- Stacks: sheets fold regardless of amount ----

/datum/unit_test/dq_stock_sheets
	var/list/made = list()

/datum/unit_test/dq_stock_sheets/Destroy()
	for(var/datum/D as anything in made)
		if(!QDELETED(D))
			qdel(D)
	made = null
	return ..()

/datum/unit_test/dq_stock_sheets/Run()
	var/turf/floor = dq_containment_floor()
	TEST_ASSERT_NOTNULL(floor, "a clean floor")
	var/obj/machinery/smartfridge/sheets/F = new(floor)
	made += F
	// Material stacks don't serialize yet (their recipes list has no codec), so
	// they stay real; a stack type that does serialize folds into the count.
	var/obj/item/stack/material/steel/probe = new(null, 10)
	var/collapses = state_can_serialize(probe)
	F.stock(probe)
	F.stock(new /obj/item/stack/material/steel(null, 30))
	var/datum/stored_item/stack/R = F.item_records[1]
	TEST_ASSERT_EQUAL(R.get_amount(), 40, "sheets counted")
	TEST_ASSERT_EQUAL(dq_stock_count_in(F, /obj/item/stack/material/steel), collapses ? 0 : 2, "stacks collapse only when they serialize")
	F.vend(R, 25)
	var/obj/item/stack/material/steel/S = locate() in floor
	made += S
	TEST_ASSERT(S && S.get_amount() == 25, "vended one stack of 25")
	TEST_ASSERT_EQUAL(R.get_amount(), 15, "15 left")
