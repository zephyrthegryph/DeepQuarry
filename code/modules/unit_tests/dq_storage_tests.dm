// Storage on slots (roadmap C4, doc/rewrite/containment.md section 8): insert
// and remove through the ledger with the old limits, quick-gather and
// quick-empty, and a HUD that exists only while someone is looking.

/// An item whose size each test sets.
/obj/item/dq_storage_test
	name = "storage test item"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "whetstone"
	w_class = ITEMSIZE_SMALL
	MATERIAL_BULK(MAT_STEEL, 1000)

/datum/unit_test/proc/dq_storage_item(turf/T, size)
	var/obj/item/dq_storage_test/I = allocate(/obj/item/dq_storage_test, T)
	I.w_class = size
	return I

// ---- Insert and remove parity ----

/datum/unit_test/dq_storage_limits

/datum/unit_test/dq_storage_limits/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/storage/box/box = allocate(/obj/item/storage/box, T)
	TEST_ASSERT_EQUAL(box.slot_capacity(), box.max_storage_space, "the slot's capacity is max_storage_space")

	// Size: a box takes pocket-sized things only (its hold constraint).
	var/obj/item/big = dq_storage_item(T, ITEMSIZE_NORMAL)
	var/why = box.insert_refusal(big, null)
	TEST_ASSERT(findtext(why, "too big"), "box refusing a normal item says it's too big, said [why]")
	TEST_ASSERT(!box.insert_item(big), "a refused item doesn't go in")
	TEST_ASSERT_EQUAL(big.loc, T, "a refused item stays put")

	// Space: storage-cost units, counted by the ledger.
	box.max_storage_space = ITEMSIZE_COST_SMALL * 2
	var/obj/item/a = dq_storage_item(T, ITEMSIZE_SMALL)
	var/obj/item/b = dq_storage_item(T, ITEMSIZE_SMALL)
	var/obj/item/c = dq_storage_item(T, ITEMSIZE_TINY)
	TEST_ASSERT(box.insert_item(a), "the first small item goes in")
	TEST_ASSERT(box.insert_item(b), "the second small item goes in")
	TEST_ASSERT_EQUAL(box.slot_used(), ITEMSIZE_COST_SMALL * 2, "the slot counts two small items")
	why = box.insert_refusal(c, null)
	TEST_ASSERT(findtext(why, "no room"), "a full box refuses even a tiny item for space, said [why]")

	// Removal frees the space.
	TEST_ASSERT(box.remove_from_storage(a, T), "an item comes out")
	TEST_ASSERT_EQUAL(a.loc, T, "it lands where asked")
	TEST_ASSERT_EQUAL(box.slot_used(), ITEMSIZE_COST_SMALL, "the slot gave its space back")
	TEST_ASSERT(box.insert_item(c), "the tiny item fits now")
	TEST_ASSERT(box.remove_from_storage(c), "no destination: out onto the floor")
	TEST_ASSERT_EQUAL(c.loc, get_turf(box), "it lands under the box")

	// Count: storage_slots caps the number of things.
	var/obj/item/storage/box/counted = allocate(/obj/item/storage/box, T)
	counted.storage_slots = 2
	counted.max_storage_space = 100
	TEST_ASSERT(counted.insert_item(dq_storage_item(T, ITEMSIZE_TINY)), "slot one")
	TEST_ASSERT(counted.insert_item(dq_storage_item(T, ITEMSIZE_TINY)), "slot two")
	why = counted.insert_refusal(dq_storage_item(T, ITEMSIZE_TINY), null)
	TEST_ASSERT(findtext(why, "is full"), "a third thing is refused by count, said [why]")

	// Whitelists come from the hold constraint on the slot.
	var/obj/item/storage/wallet/wallet = allocate(/obj/item/storage/wallet, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	TEST_ASSERT_EQUAL(wallet.insert_refusal(wrench, null), "it doesn't take that", "wallet refuses a wrench")
	var/obj/item/spacecash/cash = allocate(/obj/item/spacecash, T)
	TEST_ASSERT(wallet.insert_item(cash), "wallet takes cash")

	dq_verify_ledger(box, "box")
	dq_verify_ledger(counted, "counted box")
	dq_verify_ledger(wallet, "wallet")

/datum/unit_test/dq_storage_nested

/datum/unit_test/dq_storage_nested/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/storage/backpack/pack = allocate(/obj/item/storage/backpack, T)
	var/obj/item/storage/box/box = allocate(/obj/item/storage/box, T)
	TEST_ASSERT(pack.insert_item(box), "a box goes in a backpack")
	var/before = pack.contents_property(PROP_MASS) || 0
	var/obj/item/I = dq_storage_item(T, ITEMSIZE_SMALL)
	TEST_ASSERT(box.insert_item(I), "an item goes in the box inside the backpack")
	TEST_ASSERT((pack.contents_property(PROP_MASS) || 0) > before, "the backpack's aggregate mass includes the nested item")
	var/why = box.insert_refusal(pack, null)
	TEST_ASSERT(why, "the backpack can't go inside the box it holds")
	var/obj/item/storage/backpack/other = allocate(/obj/item/storage/backpack, T)
	TEST_ASSERT(pack.insert_refusal(other, null), "a backpack refuses another backpack")
	// Straight from one storage into another.
	var/obj/item/storage/box/second = allocate(/obj/item/storage/box, T)
	TEST_ASSERT(second.insert_item(I), "an item moves from one box into another")
	TEST_ASSERT_EQUAL(I.loc, second, "it is in the second box")
	TEST_ASSERT(!(I in box.slot_contents()), "the first box no longer lists it")
	dq_verify_ledger(pack, "backpack")
	dq_verify_ledger(box, "box")
	dq_verify_ledger(second, "second box")

/datum/unit_test/dq_storage_gather_and_empty

/datum/unit_test/dq_storage_gather_and_empty/Run()
	var/turf/T = dq_containment_floor()
	var/turf/pile = get_step(T, EAST)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/storage/box/box = allocate(/obj/item/storage/box, T)
	box.max_storage_space = 100
	var/list/small = list()
	for(var/i in 1 to 4)
		small += dq_storage_item(pile, ITEMSIZE_SMALL)
	var/obj/item/big = dq_storage_item(pile, ITEMSIZE_NORMAL)

	box.gather_all(pile, user)
	for(var/obj/item/I as anything in small)
		TEST_ASSERT_EQUAL(I.loc, box, "quick-gather took [I]")
	TEST_ASSERT_EQUAL(big.loc, pile, "quick-gather left what doesn't fit")
	TEST_ASSERT_EQUAL(length(box.slot_contents()), 4, "the box lists four things")

	box.drop_contents(user)
	for(var/obj/item/I as anything in small)
		TEST_ASSERT_EQUAL(I.loc, get_turf(box), "quick-empty dropped [I]")
	TEST_ASSERT_EQUAL(box.slot_used(), 0, "the box is empty")

	// From the user's hand, with the user plumbed through.
	var/obj/item/held = dq_storage_item(T, ITEMSIZE_SMALL)
	user.put_in_active_hand(held)
	TEST_ASSERT_EQUAL(held.loc, user, "the item is held")
	TEST_ASSERT(box.insert_item(held, user), "a held item goes in")
	TEST_ASSERT_EQUAL(held.loc, box, "it left the hand")
	TEST_ASSERT(user.get_active_hand() != held, "the hand is empty")
	dq_verify_ledger(box, "box")

// ---- HUD per viewer ----

/datum/unit_test/dq_storage_hud_per_viewer

/datum/unit_test/dq_storage_hud_per_viewer/Run()
	var/turf/T = dq_containment_floor()
	var/baseline = GLOB.storage_hud_count
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human, T)

	var/obj/item/storage/backpack/pack = allocate(/obj/item/storage/backpack, T)
	var/obj/item/storage/box/box = allocate(/obj/item/storage/box, T)
	box.storage_slots = 4
	TEST_ASSERT_NULL(pack.hud, "no HUD before anyone opens the backpack")
	TEST_ASSERT_NULL(box.hud, "no HUD before anyone opens the box")
	TEST_ASSERT_EQUAL(GLOB.storage_hud_count, baseline, "making storage makes no HUD")

	var/obj/item/I = dq_storage_item(T, ITEMSIZE_SMALL)
	pack.insert_item(I)
	pack.open(first)
	var/datum/storage_hud/hud = pack.hud
	TEST_ASSERT_NOTNULL(hud, "opening makes the HUD")
	TEST_ASSERT_EQUAL(GLOB.storage_hud_count, baseline + 1, "one HUD for one open storage")
	TEST_ASSERT_EQUAL(length(hud.backdrop), 3, "the volume bar has start, continue and end")
	TEST_ASSERT(I in hud.shown, "the stored item is shown")
	TEST_ASSERT_EQUAL(length(hud.catchers), 1, "one click catcher per shown item")

	// A change while open lays the HUD out again.
	var/obj/item/J = dq_storage_item(T, ITEMSIZE_SMALL)
	pack.insert_item(J)
	TEST_ASSERT(J in hud.shown, "an item put in while open is shown")
	TEST_ASSERT_EQUAL(length(hud.catchers), 2, "and gets a catcher")
	pack.remove_from_storage(J, T)
	TEST_ASSERT(!(J in hud.shown), "an item taken out is no longer shown")

	// A second viewer shares it.
	pack.open(second)
	TEST_ASSERT_EQUAL(pack.hud, hud, "a second viewer shares the HUD")
	TEST_ASSERT_EQUAL(GLOB.storage_hud_count, baseline + 1, "still one HUD")
	var/list/atoms = hud.screen_atoms()
	pack.close(first)
	TEST_ASSERT_EQUAL(pack.hud, hud, "the HUD stays while someone still looks")
	pack.close(second)
	TEST_ASSERT_NULL(pack.hud, "the last viewer out deletes the HUD")
	TEST_ASSERT_EQUAL(GLOB.storage_hud_count, baseline, "no HUD left")
	for(var/atom/movable/A as anything in atoms)
		TEST_ASSERT(QDELETED(A), "screen object [A] was deleted with the HUD")

	// The boxed layout, and switching storages.
	box.insert_item(dq_storage_item(T, ITEMSIZE_SMALL))
	box.open(first)
	TEST_ASSERT_EQUAL(length(box.hud.backdrop), 1, "boxed storage has one backdrop")
	pack.open(first)
	TEST_ASSERT_NULL(box.hud, "opening another storage closes the first")
	TEST_ASSERT_EQUAL(first.s_active, pack, "the viewer is looking into the backpack")

	// Deleting an open storage deletes its HUD.
	qdel(pack)
	TEST_ASSERT_EQUAL(GLOB.storage_hud_count, baseline, "an open storage takes its HUD with it")
	TEST_ASSERT_NULL(first.s_active, "the viewer isn't left looking at a deleted storage")
