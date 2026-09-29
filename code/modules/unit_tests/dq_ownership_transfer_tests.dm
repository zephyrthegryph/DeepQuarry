// One-call transfers (doc/rewrite/ownership.md §1.3a, code/datums/ownership/transfer.dm):
// own_set / own_add / own_put take a movable out of a hand, an equip slot, a storage item or
// another holder's owned var, move it into the holder and adopt it, or refuse and change nothing.

/// A holder with no ledger slots (a plain machine-like object).
/obj/own_transfer_test_holder
	name = "test holder"
	var/obj/item/beaker
	var/list/parts
	var/obj/item/kept

OWN(/obj/own_transfer_test_holder, kept, OWN_CONTAINED)

/// Counts dropped() calls.
/obj/item/own_transfer_test_widget
	name = "test widget"
	w_class = ITEMSIZE_SMALL
	var/dropped_count = 0

/obj/item/own_transfer_test_widget/dropped(mob/user, equipping, slot)
	. = ..()
	dropped_count++

/// A storage holder that holds one thing.
/obj/item/storage/own_transfer_test_box
	name = "test box"
	storage_slots = 1
	max_storage_space = ITEMSIZE_COST_NORMAL * 4
	var/obj/item/kept

/datum/unit_test/proc/own_transfer_setup()
	GLOB.refuse_capture = list()
	GLOB.dq_lifecycle_report_capture = list()

/datum/unit_test/proc/own_transfer_teardown()
	GLOB.refuse_capture = null
	GLOB.dq_lifecycle_report_capture = null

/datum/unit_test/proc/own_transfer_reports()
	var/list/capture = GLOB.dq_lifecycle_report_capture
	return length(capture) ? json_encode(capture) : null

// ---- from a hand ----

/datum/unit_test/ownership_transfer_from_hand

/datum/unit_test/ownership_transfer_from_hand/Run()
	own_transfer_setup()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/own_transfer_test_holder/M = allocate(/obj/own_transfer_test_holder, T)
	var/obj/item/own_transfer_test_widget/W = allocate(/obj/item/own_transfer_test_widget, T)
	TEST_ASSERT(H.put_in_hands(W) || H.put_in_l_hand(W), "the widget should go in a hand")
	TEST_ASSERT(H.inventory_slot_id(W), "the widget should be held")
	var/drops = W.dropped_count
	refresh_flush()
	TEST_ASSERT_EQUAL(own_set(M, nameof(M.beaker), W, user = H), W, "own_set from a hand returns the value")
	TEST_ASSERT_EQUAL(W.loc, M, "the widget is inside the holder")
	TEST_ASSERT_EQUAL(M.beaker, W, "the holder's var names it")
	TEST_ASSERT_EQUAL(owner_of(W), M, "the holder owns it")
	TEST_ASSERT_NULL(H.inventory_slot_id(W), "the hand slot cleared")
	TEST_ASSERT(!(W in H.get_all_held_items()), "the mob no longer holds it")
	TEST_ASSERT(W.dropped_count > drops, "dropped() ran on the way out of the hand")
	TEST_ASSERT(M.refresh_queued, "a user's transfer marks the holder changed")
	TEST_ASSERT(!length(GLOB.refuse_capture), "no refusal: [json_encode(GLOB.refuse_capture)]")
	var/reports = own_transfer_reports()
	own_transfer_teardown()
	TEST_ASSERT_NULL(reports, "no ownership reports")

// ---- from an equip slot ----

/datum/unit_test/ownership_transfer_from_equip_slot

/datum/unit_test/ownership_transfer_from_equip_slot/Run()
	own_transfer_setup()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/own_transfer_test_holder/M = allocate(/obj/own_transfer_test_holder, T)
	var/obj/item/clothing/head/hardhat/hat = allocate(/obj/item/clothing/head/hardhat, T)
	TEST_ASSERT(H.equip_to_slot_if_possible(hat, SLOT_ID_HEAD, disable_warning = TRUE), "the hat should equip")
	TEST_ASSERT_EQUAL(own_add(M, nameof(M.parts), hat, user = H), hat, "own_add from an equip slot returns the value")
	TEST_ASSERT_EQUAL(hat.loc, M, "the hat is inside the holder")
	TEST_ASSERT(hat in M.parts, "the holder's list holds it")
	TEST_ASSERT_NULL(H.get_equipped_item(SLOT_ID_HEAD), "the head slot cleared")
	dq_verify_ledger(H, "after taking the hat")
	var/reports = own_transfer_reports()
	own_transfer_teardown()
	TEST_ASSERT_NULL(reports, "no ownership reports")

// ---- from a storage item ----

/datum/unit_test/ownership_transfer_from_storage

/datum/unit_test/ownership_transfer_from_storage/Run()
	own_transfer_setup()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/own_transfer_test_holder/M = allocate(/obj/own_transfer_test_holder, T)
	var/obj/item/storage/box/B = allocate(/obj/item/storage/box, T)
	var/obj/item/own_transfer_test_widget/W = allocate(/obj/item/own_transfer_test_widget, T)
	TEST_ASSERT(B.insert_item(W), "the widget should go in the box")
	TEST_ASSERT(W in B.slot_contents(CONTAINER_SLOT_STORAGE), "the box's slot lists it")
	TEST_ASSERT_EQUAL(own_put(M, nameof(M.parts), "slot1", W, user = H), W, "own_put from a storage item returns the value")
	TEST_ASSERT_EQUAL(W.loc, M, "the widget is inside the holder")
	TEST_ASSERT_EQUAL(M.parts?["slot1"], W, "the holder's values list holds it under the key")
	TEST_ASSERT(!(W in B.slot_contents(CONTAINER_SLOT_STORAGE)), "the box's slot let it go")
	dq_verify_ledger(B, "after taking from the box")
	var/reports = own_transfer_reports()
	own_transfer_teardown()
	TEST_ASSERT_NULL(reports, "no ownership reports")

// ---- from another holder's owned var ----

/datum/unit_test/ownership_transfer_from_holder

/datum/unit_test/ownership_transfer_from_holder/Run()
	own_transfer_setup()
	var/turf/T = test_floor()
	var/obj/own_transfer_test_holder/first = allocate(/obj/own_transfer_test_holder, T)
	var/obj/own_transfer_test_holder/second = allocate(/obj/own_transfer_test_holder, T)
	var/obj/item/own_transfer_test_widget/W = allocate(/obj/item/own_transfer_test_widget, T)
	// A CONTAINED var takes it off the turf with no user: CONTAINED means "in my contents".
	TEST_ASSERT_EQUAL(own_set(first, nameof(first.kept), W), W, "a CONTAINED var adopts a loose item")
	TEST_ASSERT_EQUAL(W.loc, first, "the CONTAINED var moved it into the holder")
	// No user, but it is inside another holder: taking it is a transfer.
	TEST_ASSERT_EQUAL(own_set(second, nameof(second.beaker), W), W, "own_set from another holder returns the value")
	TEST_ASSERT_EQUAL(W.loc, second, "the widget moved into the new holder")
	TEST_ASSERT_NULL(first.kept, "the old holder's var let it go")
	TEST_ASSERT_EQUAL(owner_of(W), second, "the new holder owns it")
	TEST_ASSERT(!QDELETED(W), "nothing was destroyed on the way")
	// An owned thing left on a turf on purpose stays there (no user, not CONTAINED).
	var/obj/item/own_transfer_test_widget/remote = allocate(/obj/item/own_transfer_test_widget, T)
	TEST_ASSERT_EQUAL(own_add(second, nameof(second.parts), remote), remote, "a remote child is adopted")
	TEST_ASSERT_EQUAL(remote.loc, T, "a remote child is not pulled off its turf")
	var/reports = own_transfer_reports()
	own_transfer_teardown()
	TEST_ASSERT_NULL(reports, "no ownership reports")

// ---- refusals leave everything in place ----

/datum/unit_test/ownership_transfer_refusals

/datum/unit_test/ownership_transfer_refusals/Run()
	own_transfer_setup()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/own_transfer_test_holder/M = allocate(/obj/own_transfer_test_holder, T)

	// NODROP: stuck to the hand.
	var/obj/item/own_transfer_test_widget/W = allocate(/obj/item/own_transfer_test_widget, T)
	TEST_ASSERT(H.put_in_hands(W) || H.put_in_l_hand(W), "the widget should go in a hand")
	var/slot = H.inventory_slot_id(W)
	add_trait(W, TRAIT_NODROP, "own_transfer_test")
	TEST_ASSERT_NULL(own_set(M, nameof(M.beaker), W, user = H), "a NODROP item is refused")
	TEST_ASSERT_EQUAL(W.loc, H, "the refused item stays on the mob")
	TEST_ASSERT_EQUAL(H.inventory_slot_id(W), slot, "the refused item stays in its hand")
	TEST_ASSERT_NULL(M.beaker, "the holder's var is untouched")
	TEST_ASSERT_NULL(owner_of(W), "nothing adopted it")
	var/list/told = GLOB.refuse_capture
	TEST_ASSERT(length(told) == 1 && told[1][1] == H && findtext(told[1][2], "stuck"), "the user is told it's stuck: [json_encode(told)]")
	remove_trait(W, TRAIT_NODROP, "own_transfer_test")
	told.Cut()

	// can_unequip: an item that can't be removed.
	W.canremove = FALSE
	TEST_ASSERT_NULL(own_set(M, nameof(M.beaker), W, user = H), "an item that can't be removed is refused")
	TEST_ASSERT_EQUAL(H.inventory_slot_id(W), slot, "it stays in its hand")
	TEST_ASSERT(length(told) == 1 && findtext(told[1][2], "take off"), "the user is told why: [json_encode(told)]")
	W.canremove = TRUE
	told.Cut()

	// Storage refusal: the destination box is full.
	var/obj/item/storage/own_transfer_test_box/box = allocate(/obj/item/storage/own_transfer_test_box, T)
	var/obj/item/own_transfer_test_widget/filler = allocate(/obj/item/own_transfer_test_widget, T)
	TEST_ASSERT(box.insert_item(filler), "the filler should go in the box")
	TEST_ASSERT_NULL(own_set(box, nameof(box.kept), W, user = H), "a full box refuses")
	TEST_ASSERT_EQUAL(H.inventory_slot_id(W), slot, "the item refused by the box stays in its hand")
	TEST_ASSERT_NULL(box.kept, "the box's var is untouched")
	TEST_ASSERT(length(told) == 1 && findtext(told[1][2], "full"), "the user is told the box is full: [json_encode(told)]")
	told.Cut()

	// Once allowed, the same call goes through, into the box's storage slot.
	own_take(box, nameof(box.kept))
	box.remove_from_storage(filler, T)
	TEST_ASSERT_EQUAL(own_set(box, nameof(box.kept), W, user = H), W, "the box takes it once there's room")
	TEST_ASSERT(W in box.slot_contents(CONTAINER_SLOT_STORAGE), "it landed in the box's storage slot")
	TEST_ASSERT_NULL(H.inventory_slot_id(W), "and left the hand")
	var/reports = own_transfer_reports()
	own_transfer_teardown()
	TEST_ASSERT_NULL(reports, "no ownership reports")

// ---- review 2 M8: every accessor write marks the holder changed ----

/datum/unit_test/ownership_accessors_mark_changed

/datum/unit_test/ownership_accessors_mark_changed/Run()
	var/turf/T = test_floor()
	var/obj/own_transfer_test_holder/M = allocate(/obj/own_transfer_test_holder, T)
	var/obj/item/own_transfer_test_widget/W = allocate(/obj/item/own_transfer_test_widget, T)
	refresh_flush()
	TEST_ASSERT(!M.refresh_queued, "flushed")
	own_set(M, nameof(M.beaker), W, into = TRUE)
	TEST_ASSERT(M.refresh_queued, "own_set without a user marks the holder changed")
	refresh_flush()
	TEST_ASSERT_EQUAL(own_take(M, nameof(M.beaker)), W, "own_take returns it")
	TEST_ASSERT(M.refresh_queued, "own_take marks the holder changed")
	refresh_flush()
	own_add(M, nameof(M.parts), W)
	TEST_ASSERT(M.refresh_queued, "own_add marks the holder changed")
	refresh_flush()
	own_remove(M, nameof(M.parts), W)
	TEST_ASSERT(M.refresh_queued, "own_remove marks the holder changed")
