// The storage capability (code/datums/capabilities/library/storage.dm).

/// The capability entry with this id on A, or null.
/proc/dxs_entry(atom/A, id)
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(E.id == id)
			return E
	return null

/// Whether A's applied look carries the overlay `name`.
/proc/dxs_has_layer(atom/A, name)
	return dx_look_shows(A, name) ? TRUE : FALSE

/// A tool belt: tools and medical things, two at most, up to normal size.
/obj/cap_fixture/storage_belt/capabilities()
	. = ..()
	. += cap_storage(holds = HOLDS_TOOLS | HOLDS_MEDICAL, slots = 2, max_w_class = ITEMSIZE_NORMAL, max_total = ITEMSIZE_COST_NORMAL * 7, use_sound = FALSE)

/// Anything small, little space; locked by the lock bit.
/obj/cap_fixture/storage_lockbox/capabilities()
	. = ..()
	. += cap_storage(max_total = ITEMSIZE_COST_SMALL * 2, locked_by = LOCK, use_sound = FALSE)

/// Medical only, with an exception for plain test items named "exception".
/obj/cap_fixture/storage_picky/capabilities()
	. = ..()
	. += cap_storage(holds = HOLDS_MEDICAL, can_hold_proc = PROC_REF(storage_exception), use_sound = FALSE)

/obj/cap_fixture/storage_picky/proc/storage_exception(obj/item/I, mob/user)
	if(I.name == "exception")
		return TRUE
	return null

/obj/item/cap_fixture_item
	name = "test item"
	w_class = ITEMSIZE_SMALL

/obj/item/cap_fixture_item/medical
	name = "test medkit"
	storage_class = HOLDS_MEDICAL

/obj/item/cap_fixture_item/large
	name = "test crate"
	w_class = ITEMSIZE_LARGE
	storage_class = HOLDS_MEDICAL

/// The category rule: tools by quality, medical by storage_class, others refused; size and count.
/datum/unit_test/dx_cap_storage_categories/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/storage_belt/belt = allocate(/obj/cap_fixture/storage_belt, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/obj/item/cap_fixture_item/medical/kit = allocate(/obj/item/cap_fixture_item/medical, T)
	var/obj/item/cap_fixture_item/plain = allocate(/obj/item/cap_fixture_item, T)
	var/obj/item/cap_fixture_item/large/big = allocate(/obj/item/cap_fixture_item/large, T)
	var/obj/item/cap_fixture_item/medical/kit2 = allocate(/obj/item/cap_fixture_item/medical, T)
	var/datum/interaction/capability/put_in = dxs_entry(belt, "storage:put_in")
	TEST_ASSERT_NOTNULL(put_in, "storage offers Put in")
	TEST_ASSERT_EQUAL(put_in.category, INTERACTION_CAT_INSERT, "Put in is an insert")
	TEST_ASSERT_EQUAL(put_in.why_not(H, belt, plain), "\the [belt] can't hold \the [plain]", "an item with no category is refused")
	TEST_ASSERT_EQUAL(put_in.why_not(H, belt, big), "\the [big] is too big for \the [belt]", "a large item is refused")
	TEST_ASSERT_NULL(put_in.why_not(H, belt, screwdriver), "a tool fits by its tool quality")
	TEST_ASSERT(H.put_in_active_hand(screwdriver), "the human holds the screwdriver")
	TEST_ASSERT_EQUAL(try_interaction(H, belt, screwdriver, INPUT_ACTION_USE), INTERACTION_TRY_RAN, "the held screwdriver goes in through the resolver")
	TEST_ASSERT_EQUAL(screwdriver.loc, belt, "the screwdriver is inside")
	TEST_ASSERT(!H.is_in_hands(screwdriver), "and out of the hand")
	var/datum/ledger/L = dq_ledger(belt)
	var/list/entry = L.entries[screwdriver]
	TEST_ASSERT_EQUAL(entry?[LEDGER_E_SLOT], CONTAINER_SLOT_STORAGE, "the ledger has it in the storage slot")
	TEST_ASSERT(put_in.perform(H, belt, kit), "a medical item fits by storage_class")
	TEST_ASSERT_EQUAL(kit.loc, belt, "the kit is inside")
	TEST_ASSERT_EQUAL(put_in.why_not(H, belt, kit2), "\the [belt] is full", "the count limit refuses a third")
	TEST_ASSERT("It holds 2 things." in caps_examine(belt, H), "examine counts the contents")

/// Take out into the hand, Empty out onto the floor, and the empty-state gating.
/datum/unit_test/dx_cap_storage_take_and_empty/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/storage_belt/belt = allocate(/obj/cap_fixture/storage_belt, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/datum/interaction/capability/take_out = dxs_entry(belt, "storage:take_out")
	var/datum/interaction/capability/empty_out = dxs_entry(belt, "storage:empty_out")
	TEST_ASSERT_NOTNULL(take_out, "storage offers Take out")
	TEST_ASSERT_NOTNULL(empty_out, "storage offers Empty out")
	TEST_ASSERT_EQUAL(take_out.why_not(H, belt, null), "it's empty", "Take out refuses while empty")
	TEST_ASSERT_EQUAL(empty_out.why_not(H, belt, null), "it's empty", "Empty out refuses while empty")
	TEST_ASSERT("It is empty." in caps_examine(belt, H), "examine says it is empty")
	TEST_ASSERT(storage_insert(belt, screwdriver, H), "storage_insert(src) puts the screwdriver in")
	TEST_ASSERT(storage_insert(belt, wrench, H), "and the wrench")
	TEST_ASSERT_NULL(take_out.why_not(H, belt, null), "Take out is available with contents")
	var/list/choices = cap_storage_choices(belt, H)
	TEST_ASSERT_EQUAL(length(choices), 2, "both things are choices")
	TEST_ASSERT(cap_storage_take_out(belt, H, choice = screwdriver.name, cap = cap_of(belt, /datum/capability/storage)), "the form's handler takes the screwdriver out")
	TEST_ASSERT(H.is_in_hands(screwdriver), "the screwdriver is in the hand")
	TEST_ASSERT_EQUAL(cap_storage_take_out(belt, H, choice = "no such thing", cap = cap_of(belt, /datum/capability/storage)), UI_REFUSED, "a stale choice is refused")
	TEST_ASSERT(empty_out.perform(H, belt, null), "Empty out runs")
	TEST_ASSERT_EQUAL(wrench.loc, T, "the wrench lands on the floor")
	TEST_ASSERT(!length(storage_items(belt)), "nothing is left inside")

/// locked_by = LOCK, the capacity in units, and the ledger refusal message.
/datum/unit_test/dx_cap_storage_locked_and_space/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/storage_lockbox/box = allocate(/obj/cap_fixture/storage_lockbox, T)
	var/obj/item/cap_fixture_item/one = allocate(/obj/item/cap_fixture_item, T)
	var/obj/item/cap_fixture_item/two = allocate(/obj/item/cap_fixture_item, T)
	var/datum/interaction/capability/put_in = dxs_entry(box, "storage:put_in")
	cap_set(box, CAP_LOCKED, TRUE)
	TEST_ASSERT_EQUAL(put_in.why_not(H, box, one), "it's locked", "a locked storage refuses")
	TEST_ASSERT(!put_in.perform(H, box, one), "the refused insert does not run")
	TEST_ASSERT_EQUAL(one.loc, T, "and the item stays out")
	cap_set(box, CAP_LOCKED, FALSE)
	TEST_ASSERT(put_in.perform(H, box, one), "unlocked, it goes in")
	TEST_ASSERT_EQUAL(box.slot_capacity(CONTAINER_SLOT_STORAGE), ITEMSIZE_COST_SMALL * 2, "the slot's capacity is the capability's max_total")
	TEST_ASSERT_EQUAL(box.slot_used(CONTAINER_SLOT_STORAGE), ITEMSIZE_COST_SMALL, "one small item's cost is used")
	box.hold_max_total = ITEMSIZE_COST_SMALL
	TEST_ASSERT_EQUAL(put_in.why_not(H, box, two), "there's no room for it", "a per-instance hold_max_total overrides the default")
	box.hold_max_total = null
	TEST_ASSERT_NULL(put_in.why_not(H, box, two), "back to the default, there is room")

/// can_hold_proc exceptions and the per-instance hold_mask / hold_slots overrides (H1).
/datum/unit_test/dx_cap_storage_overrides/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/storage_picky/picky = allocate(/obj/cap_fixture/storage_picky, T)
	var/obj/item/cap_fixture_item/plain = allocate(/obj/item/cap_fixture_item, T)
	var/obj/item/cap_fixture_item/special = allocate(/obj/item/cap_fixture_item, T)
	var/obj/item/cap_fixture_item/medical/kit = allocate(/obj/item/cap_fixture_item/medical, T)
	special.name = "exception"
	TEST_ASSERT_NOTNULL(storage_refusal(picky, plain, H), "a plain item is refused by the medical rule")
	TEST_ASSERT_NULL(storage_refusal(picky, special, H), "the holder's can_hold_proc lets its exception in")
	TEST_ASSERT_NULL(storage_refusal(picky, kit, H), "a medical item fits")
	picky.hold_mask = HOLDS_ANY
	TEST_ASSERT_NULL(storage_refusal(picky, plain, H), "a per-instance hold_mask replaces the capability's holds")
	picky.hold_slots = 0
	TEST_ASSERT_EQUAL(storage_refusal(picky, plain, H), "\the [picky] is full", "a per-instance hold_slots replaces the count limit")

/// Destroying the holder spills its contents through the slot's drop policy.
/datum/unit_test/dx_cap_storage_spill/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/cap_fixture/storage_lockbox/box = allocate(/obj/cap_fixture/storage_lockbox, T)
	var/obj/item/cap_fixture_item/one = allocate(/obj/item/cap_fixture_item, T)
	TEST_ASSERT(storage_insert(box, one, null), "the item goes in with no user")
	qdel(box)
	TEST_ASSERT(!QDELETED(one), "the contents survive the holder")
	TEST_ASSERT_EQUAL(one.loc, T, "and land where the holder was")
