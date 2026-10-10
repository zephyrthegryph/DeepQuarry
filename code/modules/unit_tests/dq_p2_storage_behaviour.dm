// Behaviour-preservation tests for the storage domain (phase 2): boxes, backpacks, bags, belts, pill bottles, toolboxes and lockboxes.
// They pin what a player can observe of a storage item through public inputs (clicks, the use-in-hand click, the alt-click, the HUD item
// click, an ID or an emag on a lockbox, time), so the same file passes before and after the storage items move from the legacy
// interactions to the storage() capability.
//
// Rules the tests keep:
//   - Input goes through the click helpers (the real inbox path: the target's and the held item's ops, else the legacy click chain) and the
//     small adapter block below, which is the only place that names today's accessors.
//   - Every input is followed by sb_settle() (kernel time), because a wait may differ between the two implementations.
//   - Nothing here depends on message text, on an op key or on a click result being non-null.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: today's accessors, wrapped. After the conversion only these bodies change.
// ---------------------------------------------------------------------------------------------------------------------

/// What the storage holds, in order.
/proc/sb_items(obj/item/storage/S)
	S.make_contents_real() // starting contents are declared, not made, until somebody looks
	return S.stored_items()

/// How many things count against the storage's count limit now.
/proc/sb_count(obj/item/storage/S)
	return length(sb_items(S))

/// The storage's count limit (null: none).
/proc/sb_slot_limit(obj/item/storage/S)
	return S.storage_slots

/// The storage's space, in storage-cost units.
/proc/sb_space(obj/item/storage/S)
	return S.max_storage_space

/// Narrow a storage to `limit` things (a test tuning a fixture, not a player input).
/proc/sb_set_slot_limit(obj/item/storage/S, limit)
	S.storage_slots = limit

/// The storage's window is open for this viewer.
/proc/sb_is_open(mob/M, obj/item/storage/S)
	return M.s_active == S

/// The storage has any window on anybody's screen.
/proc/sb_has_window(obj/item/storage/S)
	return !!S.hud

/// The storage gathers a whole tile at once (not one item at a time).
/proc/sb_gathers_all(obj/item/storage/S)
	return !!S.collection_mode

/// The person switches the gathering method of the storage.
/proc/sb_toggle_gathering(mob/M, obj/item/storage/S)
	M.drop_item()
	M.put_in_active_hand(S) // the menu entry is for a storage the person carries
	test_menu(M, S, "storage.gather_mode")
	test_time(10 SECONDS)

/// Every item inside, nested storage included.
/proc/sb_all_inside(obj/item/storage/S)
	return S.return_inv()

/// The lockbox is locked.
/proc/sb_locked(obj/item/storage/lockbox/L)
	return !!lock_locked(L)

/// The lockbox's lock is broken for good.
/proc/sb_broken(obj/item/storage/lockbox/L)
	return !!L.broken

/// The pill bottle's label text.
/proc/sb_label(obj/item/storage/pill_bottle/B)
	return B.label_text

/// The briefcase is locked.
/proc/sb_secure_locked(obj/item/storage/secure/S)
	return !!S.locked

/// The quickdraw case draws the first item to the hand instead of opening.
/proc/sb_quickmode(obj/item/storage/quickdraw/Q)
	return !!quickdraw_draws(Q)

/// The trinket box lid is open.
/proc/sb_lid_open(obj/item/storage/trinketbox/T)
	return !!T.open

/// The person writes `text` on the pill bottle's label after a pen was used on it (the prompt the click opened is answered).
/proc/sb_write_label(mob/M, obj/item/storage/pill_bottle/B, text)
	test_answer(M, text)

/// The MRE has been torn open.
/proc/sb_torn_open(obj/item/storage/mre/M)
	return !!M.opened

// ---------------------------------------------------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------------------------------------------------

/// An item of a chosen size that does nothing.
/obj/item/p2_storage_probe
	name = "storage probe"
	w_class = ITEMSIZE_SMALL

/obj/item/p2_storage_probe/tiny
	w_class = ITEMSIZE_TINY

/obj/item/p2_storage_probe/normal
	w_class = ITEMSIZE_NORMAL

/obj/item/p2_storage_probe/large
	w_class = ITEMSIZE_LARGE

/obj/item/p2_storage_probe/huge
	w_class = ITEMSIZE_HUGE

/datum/unit_test/dq_p2_storage
	abstract_type = /datum/unit_test/dq_p2_storage
	var/list/sb_extra

/datum/unit_test/dq_p2_storage/Run()
	test_driver_begin()
	test_rng(1)
	run_gate()
	for(var/atom/A as anything in sb_extra)
		if(!QDELETED(A))
			qdel(A)
	own_turf_contents(run_loc_floor_bottom_left)
	test_driver_end()

/datum/unit_test/dq_p2_storage/proc/run_gate()
	return

/// Time for any wait a click may start.
/datum/unit_test/dq_p2_storage/proc/sb_settle()
	test_time(10 SECONDS)

/// A conscious person with hands.
/datum/unit_test/dq_p2_storage/proc/sb_actor(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/// A thing of `type` on the floor.
/datum/unit_test/dq_p2_storage/proc/sb_make(type, turf/T)
	return allocate(type, T || run_loc_floor_bottom_left)

/// The actor clicks `target` with `held` in the active hand (nothing: an empty hand) and waits. The other hand is left as it is.
/datum/unit_test/dq_p2_storage/proc/sb_click(mob/living/carbon/human/H, atom/target, obj/item/held, gesture = "left=1")
	H.drop_item()
	if(held)
		H.put_in_active_hand(held)
	H.set_use_stance(I_HELP)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, target, null, null, gesture))
	sb_settle()

/// The actor alt-clicks `target` with an empty hand.
/datum/unit_test/dq_p2_storage/proc/sb_alt_click(mob/living/carbon/human/H, atom/target)
	sb_click(H, target, null, "left=1;alt=1")

/// The actor holds `S` in the active hand and uses it (clicks the item itself with an empty other hand).
/datum/unit_test/dq_p2_storage/proc/sb_use_held(mob/living/carbon/human/H, obj/item/S)
	H.drop_item()
	H.put_in_active_hand(S)
	H.set_use_stance(I_HELP)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, S, null, null, "left=1"))
	sb_settle()

/// The actor holds `S` in the other hand and puts `item` into it with the active hand.
/datum/unit_test/dq_p2_storage/proc/sb_put_in_held(mob/living/carbon/human/H, obj/item/storage/S, obj/item/item)
	H.drop_item()
	H.drop_from_inventory(S)
	H.put_in_inactive_hand(S)
	H.put_in_active_hand(item)
	H.set_use_stance(I_HELP)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, S, null, null, "left=1"))
	sb_settle()

/// The actor holds `S` in the other hand and opens it with an empty active hand.
/datum/unit_test/dq_p2_storage/proc/sb_open_held(mob/living/carbon/human/H, obj/item/S)
	sb_empty_hands(H)
	H.put_in_inactive_hand(S)
	H.set_use_stance(I_HELP)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, S, null, null, "left=1"))
	sb_settle()

/// The actor holds nothing.
/datum/unit_test/dq_p2_storage/proc/sb_empty_hands(mob/living/carbon/human/H)
	H.drop_item()
	H.swap_hand()
	H.drop_item()
	H.swap_hand()

/// The item is in one of the actor's hands.
/datum/unit_test/dq_p2_storage/proc/sb_in_hands(mob/living/carbon/human/H, obj/item/I)
	return H.is_in_hands(I)

/// Puts `count` probes of `type` into the storage by a person's clicks, one at a time. Returns how many got in.
/datum/unit_test/dq_p2_storage/proc/sb_stuff(mob/living/carbon/human/H, obj/item/storage/S, type, count)
	var/before = sb_count(S)
	for(var/i in 1 to count)
		var/obj/item/I = sb_make(type, get_turf(H))
		sb_click(H, S, I)
	return sb_count(S) - before

// ---------------------------------------------------------------------------------------------------------------------
// Insert and remove
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_storage/insert_and_take_out
/datum/unit_test/dq_p2_storage/insert_and_take_out/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/box/B = sb_make(/obj/item/storage/box)
	var/obj/item/p2_storage_probe/tiny/I = sb_make(/obj/item/p2_storage_probe/tiny)

	// a box on the floor takes what the person clicks it with
	sb_click(H, B, I)
	TEST_ASSERT_EQUAL(I.loc, B, "a clicked box takes the item")
	TEST_ASSERT(I in sb_items(B), "the box lists it")
	TEST_ASSERT(!sb_in_hands(H, I), "it left the hand")

	// a box in the other hand takes it too
	var/obj/item/p2_storage_probe/tiny/J = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_put_in_held(H, B, J)
	TEST_ASSERT_EQUAL(J.loc, B, "a held box takes the item")
	TEST_ASSERT_EQUAL(sb_count(B), 2, "both are in")

	// an empty hand on a held box opens it; the item in it, clicked, comes to the hand
	sb_open_held(H, B)
	TEST_ASSERT(sb_is_open(H, B), "an empty hand on the held box opens it")
	TEST_ASSERT(sb_has_window(B), "its window exists")
	H.drop_from_inventory(B)
	H.put_in_inactive_hand(B)
	H.drop_item()
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, I, null, null, "left=1"))
	sb_settle()
	TEST_ASSERT(sb_in_hands(H, I), "the item clicked inside an open box comes to the hand")
	TEST_ASSERT(!(I in sb_items(B)), "and is no longer listed")
	TEST_ASSERT_EQUAL(sb_count(B), 1, "one is left")

/datum/unit_test/dq_p2_storage/starting_contents
/datum/unit_test/dq_p2_storage/starting_contents/run_gate()
	var/obj/item/storage/toolbox/mechanical/T = sb_make(/obj/item/storage/toolbox/mechanical)
	TEST_ASSERT_EQUAL(sb_count(T), 6, "a mechanical toolbox starts with six tools")
	for(var/obj/item/I as anything in sb_items(T))
		TEST_ASSERT_EQUAL(I.loc, T, "each starting item is inside")
	var/obj/item/storage/toolbox/emergency/E = sb_make(/obj/item/storage/toolbox/emergency)
	TEST_ASSERT_EQUAL(sb_count(E), 4, "an emergency toolbox starts with four things")
	var/obj/item/storage/toolbox/mechanical/emptied = new(run_loc_floor_bottom_left)
	LAZYADD(sb_extra, emptied)
	TEST_ASSERT(sb_count(emptied) > 0, "a plain new toolbox is full too")

// ---------------------------------------------------------------------------------------------------------------------
// Capacity, size and what a storage holds
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_storage/box_space_runs_out
/datum/unit_test/dq_p2_storage/box_space_runs_out/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/box/B = sb_make(/obj/item/storage/box)
	var/obj/item/p2_storage_probe/probe = sb_make(/obj/item/p2_storage_probe)
	var/cost = probe.get_storage_cost()
	var/fits = round(sb_space(B) / cost)
	TEST_ASSERT(fits >= 2, "the fixture box must take at least two probes")
	TEST_ASSERT_EQUAL(sb_stuff(H, B, /obj/item/p2_storage_probe, fits + 2), fits, "a box takes as many as its space allows")
	TEST_ASSERT_EQUAL(sb_count(B), fits, "and no more")
	var/obj/item/p2_storage_probe/extra = sb_make(/obj/item/p2_storage_probe)
	sb_click(H, B, extra)
	TEST_ASSERT(extra.loc != B, "a full box refuses")
	// a smaller item still does not fit when the space is gone
	var/obj/item/p2_storage_probe/tiny/small_one = sb_make(/obj/item/p2_storage_probe/tiny)
	var/left = sb_space(B) - fits * cost
	if(left < small_one.get_storage_cost())
		sb_click(H, B, small_one)
		TEST_ASSERT(small_one.loc != B, "no space left for even a tiny item")

/datum/unit_test/dq_p2_storage/belt_count_limit
/datum/unit_test/dq_p2_storage/belt_count_limit/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/belt/B = sb_make(/obj/item/storage/belt)
	var/limit = sb_slot_limit(B)
	TEST_ASSERT_EQUAL(limit, 7, "a belt has seven slots")
	TEST_ASSERT_EQUAL(sb_stuff(H, B, /obj/item/p2_storage_probe/tiny, limit + 3), limit, "a belt takes only as many as it has slots")
	var/obj/item/p2_storage_probe/tiny/extra = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, B, extra)
	TEST_ASSERT(extra.loc != B, "the next one is refused for count, not space")
	// taking one out frees a slot
	var/obj/item/first = sb_items(B)[1]
	sb_empty_hands(H)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, B, null, null, "left=1"))
	sb_settle()
	H.drop_item()
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, first, null, null, "left=1"))
	sb_settle()
	TEST_ASSERT_EQUAL(sb_count(B), limit - 1, "taking one out frees a slot")
	sb_click(H, B, extra)
	TEST_ASSERT_EQUAL(extra.loc, B, "and the freed slot takes another")

/datum/unit_test/dq_p2_storage/size_limits
/datum/unit_test/dq_p2_storage/size_limits/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/box/B = sb_make(/obj/item/storage/box)
	var/obj/item/p2_storage_probe/normal/N = sb_make(/obj/item/p2_storage_probe/normal)
	sb_click(H, B, N)
	TEST_ASSERT(N.loc != B, "a box (small items) refuses a normal item")
	var/obj/item/storage/backpack/P = sb_make(/obj/item/storage/backpack)
	sb_click(H, P, N)
	TEST_ASSERT_EQUAL(N.loc, P, "a backpack takes a normal item")
	var/obj/item/p2_storage_probe/large/L = sb_make(/obj/item/p2_storage_probe/large)
	sb_click(H, P, L)
	TEST_ASSERT_EQUAL(L.loc, P, "a backpack takes a large item")
	var/obj/item/p2_storage_probe/huge/X = sb_make(/obj/item/p2_storage_probe/huge)
	sb_click(H, P, X)
	TEST_ASSERT(X.loc != P, "a backpack refuses a huge item")
	var/obj/item/storage/toolbox/mechanical/T = sb_make(/obj/item/storage/toolbox/mechanical)
	var/obj/item/p2_storage_probe/large/L2 = sb_make(/obj/item/p2_storage_probe/large)
	sb_click(H, T, L2)
	TEST_ASSERT(L2.loc != T, "a toolbox refuses a large item")
	var/obj/item/storage/bag/trash/trash = sb_make(/obj/item/storage/bag/trash)
	var/obj/item/p2_storage_probe/normal/N2 = sb_make(/obj/item/p2_storage_probe/normal)
	sb_click(H, trash, N2)
	TEST_ASSERT(N2.loc != trash, "a trash bag refuses a normal item")
	var/obj/item/p2_storage_probe/probe = sb_make(/obj/item/p2_storage_probe)
	sb_click(H, trash, probe)
	TEST_ASSERT_EQUAL(probe.loc, trash, "and takes a small one")

/datum/unit_test/dq_p2_storage/can_hold_lists
/datum/unit_test/dq_p2_storage/can_hold_lists/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	// a utility belt takes tools only
	var/obj/item/storage/belt/utility/U = sb_make(/obj/item/storage/belt/utility)
	var/obj/item/tool/screwdriver/driver = sb_make(/obj/item/tool/screwdriver)
	var/obj/item/p2_storage_probe/junk = sb_make(/obj/item/p2_storage_probe)
	var/count_before = sb_count(U)
	sb_click(H, U, junk)
	TEST_ASSERT(junk.loc != U, "a tool belt refuses what it was not made for")
	sb_click(H, U, driver)
	TEST_ASSERT_EQUAL(driver.loc, U, "a tool belt takes a screwdriver")
	TEST_ASSERT_EQUAL(sb_count(U), count_before + 1, "and counts it")
	// a medical belt takes pills and bottles, not tools it does not list
	var/obj/item/storage/belt/medical/M = sb_make(/obj/item/storage/belt/medical)
	var/obj/item/reagent_containers/pill/pill = sb_make(/obj/item/reagent_containers/pill)
	var/obj/item/tool/wrench/wrench = sb_make(/obj/item/tool/wrench)
	sb_click(H, M, pill)
	TEST_ASSERT_EQUAL(pill.loc, M, "a medical belt takes a pill")
	sb_click(H, M, wrench)
	TEST_ASSERT(wrench.loc != M, "a medical belt refuses a wrench")
	// a pill bottle takes tiny pills and paper, nothing else
	var/obj/item/storage/pill_bottle/bottle = sb_make(/obj/item/storage/pill_bottle)
	var/obj/item/reagent_containers/pill/pill2 = sb_make(/obj/item/reagent_containers/pill)
	var/obj/item/p2_storage_probe/tiny/tiny_junk = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, bottle, tiny_junk)
	TEST_ASSERT(tiny_junk.loc != bottle, "a pill bottle refuses a tiny thing that is not a pill")
	sb_click(H, bottle, pill2)
	TEST_ASSERT_EQUAL(pill2.loc, bottle, "a pill bottle takes a pill")
	var/obj/item/paper/note = sb_make(/obj/item/paper)
	sb_click(H, bottle, note)
	TEST_ASSERT_EQUAL(note.loc, bottle, "a pill bottle takes paper")
	// a cash bag takes coins
	var/obj/item/storage/bag/cash/cash = sb_make(/obj/item/storage/bag/cash)
	var/obj/item/coin/gold/coin = sb_make(/obj/item/coin/gold)
	sb_click(H, cash, coin)
	TEST_ASSERT_EQUAL(coin.loc, cash, "a cash bag takes a coin")
	var/obj/item/p2_storage_probe/tiny/other = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, cash, other)
	TEST_ASSERT(other.loc != cash, "and nothing else")
	// a bag of holding does not take another one
	var/obj/item/storage/backpack/holding/hold_a = sb_make(/obj/item/storage/backpack/holding)
	var/obj/item/storage/backpack/holding/hold_b = sb_make(/obj/item/storage/backpack/holding)
	sb_click(H, hold_a, hold_b)
	TEST_ASSERT(hold_b.loc != hold_a, "a bag of holding refuses a bag of holding")

// ---------------------------------------------------------------------------------------------------------------------
// Nested storage
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_storage/nested_storage
/datum/unit_test/dq_p2_storage/nested_storage/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/backpack/pack = sb_make(/obj/item/storage/backpack)
	var/obj/item/storage/box/box = sb_make(/obj/item/storage/box)
	var/obj/item/p2_storage_probe/tiny/inner = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, box, inner)
	TEST_ASSERT_EQUAL(inner.loc, box, "the item went in the box")
	sb_click(H, pack, box)
	TEST_ASSERT_EQUAL(box.loc, pack, "a box goes into a backpack")
	TEST_ASSERT(inner in sb_all_inside(pack), "what is in the box is inside the pack too")
	TEST_ASSERT((box in sb_items(pack)) && !(inner in sb_items(pack)), "but the pack lists only the box")
	TEST_ASSERT_EQUAL(inner.storage_depth(pack), 1, "the item is one storage deep from the pack")
	// a container as big as the holder is refused
	var/obj/item/storage/backpack/other_pack = sb_make(/obj/item/storage/backpack)
	sb_click(H, pack, other_pack)
	TEST_ASSERT(other_pack.loc != pack, "a backpack does not go into a backpack")
	var/obj/item/storage/box/other_box = sb_make(/obj/item/storage/box)
	sb_click(H, box, other_box)
	TEST_ASSERT(other_box.loc != box, "a box does not go into a box")
	// a smaller container goes into a bigger one with its contents
	var/obj/item/storage/pill_bottle/bottle = sb_make(/obj/item/storage/pill_bottle)
	var/obj/item/reagent_containers/pill/pill = sb_make(/obj/item/reagent_containers/pill)
	sb_click(H, bottle, pill)
	sb_click(H, pack, bottle)
	TEST_ASSERT_EQUAL(bottle.loc, pack, "a pill bottle goes into a backpack")
	TEST_ASSERT_EQUAL(pill.loc, bottle, "with its pills")
	// moving the outer storage takes everything in it
	var/turf/elsewhere = get_step(run_loc_floor_bottom_left, EAST)
	pack.forceMove(elsewhere)
	TEST_ASSERT_EQUAL(get_turf(pill), elsewhere, "the deepest item moved with the pack")

// ---------------------------------------------------------------------------------------------------------------------
// Quick gather and quick empty
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_storage/quick_gather_takes_the_tile
/datum/unit_test/dq_p2_storage/quick_gather_takes_the_tile/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/pill_bottle/bottle = sb_make(/obj/item/storage/pill_bottle)
	var/turf/T = run_loc_floor_bottom_left
	var/list/pills = list()
	for(var/i in 1 to 3)
		pills += sb_make(/obj/item/reagent_containers/pill, T)
	var/obj/item/p2_storage_probe/junk = sb_make(/obj/item/p2_storage_probe, T)
	TEST_ASSERT(sb_gathers_all(bottle), "a bottle gathers the whole tile by default")
	sb_click(H, pills[1], bottle)
	for(var/obj/item/pill as anything in pills)
		TEST_ASSERT_EQUAL(pill.loc, bottle, "every pill on the tile was gathered")
	TEST_ASSERT(junk.loc == T, "what it cannot hold stays on the floor")
	TEST_ASSERT_EQUAL(sb_count(bottle), 3, "three things in the bottle")

/datum/unit_test/dq_p2_storage/quick_gather_one_at_a_time
/datum/unit_test/dq_p2_storage/quick_gather_one_at_a_time/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/pill_bottle/bottle = sb_make(/obj/item/storage/pill_bottle)
	var/turf/T = run_loc_floor_bottom_left
	var/list/pills = list()
	for(var/i in 1 to 3)
		pills += sb_make(/obj/item/reagent_containers/pill, T)
	sb_toggle_gathering(H, bottle)
	TEST_ASSERT(!sb_gathers_all(bottle), "the method switched")
	sb_click(H, pills[1], bottle)
	TEST_ASSERT_EQUAL(sb_count(bottle), 1, "only the clicked pill was taken")
	var/obj/item/first = pills[1]
	TEST_ASSERT_EQUAL(first.loc, bottle, "the one that was clicked")
	sb_toggle_gathering(H, bottle)
	TEST_ASSERT(sb_gathers_all(bottle), "and it switches back")
	sb_click(H, pills[2], bottle)
	TEST_ASSERT_EQUAL(sb_count(bottle), 3, "the rest were gathered")

/datum/unit_test/dq_p2_storage/quick_gather_stops_when_full
/datum/unit_test/dq_p2_storage/quick_gather_stops_when_full/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/pill_bottle/bottle = sb_make(/obj/item/storage/pill_bottle)
	var/turf/T = run_loc_floor_bottom_left
	var/capacity = round(sb_space(bottle) / ITEMSIZE_COST_TINY)
	var/list/pills = list()
	for(var/i in 1 to capacity + 3)
		pills += sb_make(/obj/item/reagent_containers/pill, T)
	sb_click(H, pills[1], bottle)
	TEST_ASSERT_EQUAL(sb_count(bottle), capacity, "the bottle took what fits")
	var/left_on_floor = 0
	for(var/obj/item/pill as anything in pills)
		if(pill.loc == T)
			left_on_floor++
	TEST_ASSERT_EQUAL(left_on_floor, 3, "the rest stay on the floor")

/datum/unit_test/dq_p2_storage/quick_empty_dumps_the_contents
/datum/unit_test/dq_p2_storage/quick_empty_dumps_the_contents/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/bag/trash/bag = sb_make(/obj/item/storage/bag/trash)
	var/list/things = list()
	for(var/i in 1 to 4)
		var/obj/item/I = sb_make(/obj/item/p2_storage_probe, get_turf(H))
		sb_click(H, bag, I)
		things += I
	TEST_ASSERT_EQUAL(sb_count(bag), 4, "the bag holds four")
	var/turf/T = run_loc_floor_bottom_left
	sb_use_held(H, bag)
	TEST_ASSERT_EQUAL(sb_count(bag), 0, "using the held bag empties it")
	for(var/obj/item/I as anything in things)
		TEST_ASSERT_EQUAL(get_turf(I), T, "each thing is on the floor")
	// a box has no quick-empty: using it only opens it
	var/obj/item/storage/box/box = sb_make(/obj/item/storage/box)
	var/obj/item/p2_storage_probe/tiny/inside = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, box, inside)
	sb_use_held(H, box)
	TEST_ASSERT_EQUAL(inside.loc, box, "a box is not emptied by being used")

// ---------------------------------------------------------------------------------------------------------------------
// The window
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_storage/window_opens_and_closes
/datum/unit_test/dq_p2_storage/window_opens_and_closes/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/backpack/pack = sb_make(/obj/item/storage/backpack)
	var/obj/item/p2_storage_probe/I = sb_make(/obj/item/p2_storage_probe)
	sb_click(H, pack, I)
	TEST_ASSERT(!sb_is_open(H, pack), "nothing is open yet")
	TEST_ASSERT(!sb_has_window(pack), "an unopened storage has no window")
	sb_alt_click(H, pack)
	TEST_ASSERT(sb_is_open(H, pack), "an alt-click opens a storage within reach")
	TEST_ASSERT(sb_has_window(pack), "and builds its window")
	sb_alt_click(H, pack)
	TEST_ASSERT(!sb_is_open(H, pack), "a second alt-click closes it")
	TEST_ASSERT(!sb_has_window(pack), "and drops the window")
	// opening one storage closes the one that was open
	var/obj/item/storage/box/box = sb_make(/obj/item/storage/box)
	sb_alt_click(H, pack)
	sb_alt_click(H, box)
	TEST_ASSERT(sb_is_open(H, box), "the second storage is open")
	TEST_ASSERT(!sb_is_open(H, pack), "the first was closed by it")
	// the window is shared by whoever looks
	var/mob/living/carbon/human/other = sb_actor()
	sb_alt_click(other, box)
	TEST_ASSERT(sb_is_open(H, box) && sb_is_open(other, box), "two people look into the same storage")
	sb_alt_click(H, box)
	TEST_ASSERT(sb_has_window(box), "the window stays while one still looks")
	sb_alt_click(other, box)
	TEST_ASSERT(!sb_has_window(box), "and goes when the last one stops")

/datum/unit_test/dq_p2_storage/picking_up_a_storage_closes_it
/datum/unit_test/dq_p2_storage/picking_up_a_storage_closes_it/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/backpack/pack = sb_make(/obj/item/storage/backpack)
	sb_alt_click(H, pack)
	TEST_ASSERT(sb_is_open(H, pack), "open on the floor")
	var/mob/living/carbon/human/other = sb_actor()
	sb_empty_hands(other)
	sb_click(other, pack, null)
	TEST_ASSERT(sb_in_hands(other, pack), "another person picked it up")
	TEST_ASSERT(!sb_is_open(H, pack), "the first person's window closed")

// ---------------------------------------------------------------------------------------------------------------------
// Lockboxes
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_storage/lockbox_locked_refuses_everything
/datum/unit_test/dq_p2_storage/lockbox_locked_refuses_everything/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/lockbox/L = sb_make(/obj/item/storage/lockbox)
	TEST_ASSERT(sb_locked(L), "a lockbox starts locked")
	var/obj/item/p2_storage_probe/I = sb_make(/obj/item/p2_storage_probe)
	sb_click(H, L, I)
	TEST_ASSERT(I.loc != L, "a locked lockbox takes nothing")
	sb_alt_click(H, L)
	TEST_ASSERT(!sb_is_open(H, L), "a locked lockbox does not open")
	TEST_ASSERT(!sb_has_window(L), "and has no window")
	sb_use_held(H, L)
	TEST_ASSERT(!sb_is_open(H, L), "nor when used in hand")

/datum/unit_test/dq_p2_storage/lockbox_id_unlocks_and_locks
/datum/unit_test/dq_p2_storage/lockbox_id_unlocks_and_locks/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/lockbox/L = sb_make(/obj/item/storage/lockbox)
	var/obj/item/card/id/wrong = sb_make(/obj/item/card/id)
	wrong.access = list()
	sb_click(H, L, wrong)
	TEST_ASSERT(sb_locked(L), "an ID without the access leaves it locked")
	var/obj/item/card/id/right = sb_make(/obj/item/card/id)
	right.access = list(ACCESS_ARMORY)
	sb_click(H, L, right)
	TEST_ASSERT(!sb_locked(L), "an ID with the access unlocks it")
	var/obj/item/p2_storage_probe/tiny/I = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, L, I)
	TEST_ASSERT_EQUAL(I.loc, L, "an unlocked lockbox takes items")
	sb_alt_click(H, L)
	TEST_ASSERT(sb_is_open(H, L), "and opens")
	// locking it again shuts the window
	sb_click(H, L, right)
	TEST_ASSERT(sb_locked(L), "the same ID locks it again")
	TEST_ASSERT(!sb_is_open(H, L), "locking closes the window")
	var/obj/item/p2_storage_probe/tiny/J = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, L, J)
	TEST_ASSERT(J.loc != L, "and it takes nothing again")
	TEST_ASSERT_EQUAL(I.loc, L, "what was inside stays inside")

/datum/unit_test/dq_p2_storage/lockbox_emag_breaks_the_lock
/datum/unit_test/dq_p2_storage/lockbox_emag_breaks_the_lock/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/lockbox/L = sb_make(/obj/item/storage/lockbox)
	var/obj/item/card/emag/emag = sb_make(/obj/item/card/emag)
	sb_click(H, L, emag)
	TEST_ASSERT(sb_broken(L), "an emag breaks the lock")
	TEST_ASSERT(!sb_locked(L), "and leaves it open")
	var/obj/item/p2_storage_probe/tiny/I = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, L, I)
	TEST_ASSERT_EQUAL(I.loc, L, "a broken lockbox takes items")
	sb_alt_click(H, L)
	TEST_ASSERT(sb_is_open(H, L), "and opens")
	// an ID cannot lock a broken box
	var/obj/item/card/id/right = sb_make(/obj/item/card/id)
	right.access = list(ACCESS_ARMORY)
	sb_click(H, L, right)
	TEST_ASSERT(!sb_locked(L), "a broken lockbox cannot be locked")
	// emagging again changes nothing and does not wreck it
	sb_click(H, L, emag)
	TEST_ASSERT(sb_broken(L) && !sb_locked(L), "a second emag leaves it as it was")
	TEST_ASSERT_EQUAL(I.loc, L, "with its contents")

// ---------------------------------------------------------------------------------------------------------------------
// Destruction
// ---------------------------------------------------------------------------------------------------------------------

/// A box holding three tiny probes and a pill bottle with a pill, opened by `H`. Returns list(box, things, bottle, pill).
/datum/unit_test/dq_p2_storage/proc/sb_loaded_box(mob/living/carbon/human/H)
	var/obj/item/storage/box/B = sb_make(/obj/item/storage/box)
	var/list/things = list()
	for(var/i in 1 to 3)
		var/obj/item/I = sb_make(/obj/item/p2_storage_probe/tiny, get_turf(H))
		sb_click(H, B, I)
		things += I
	var/obj/item/storage/pill_bottle/bottle = sb_make(/obj/item/storage/pill_bottle)
	sb_click(H, B, bottle)
	var/obj/item/reagent_containers/pill/pill = sb_make(/obj/item/reagent_containers/pill)
	sb_click(H, bottle, pill)
	sb_alt_click(H, B)
	return list(B, things, bottle, pill)

/datum/unit_test/dq_p2_storage/destroying_a_storage_closes_its_window
/datum/unit_test/dq_p2_storage/destroying_a_storage_closes_its_window/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/list/made = sb_loaded_box(H)
	var/obj/item/storage/box/B = made[1]
	TEST_ASSERT(sb_is_open(H, B), "the box is open when it goes")
	qdel(B)
	sb_settle()
	TEST_ASSERT(!H.s_active, "the viewer has nothing open any more")

/// Deleting a storage deletes what is inside it (the slot's drop policy), nested storage included.
/datum/unit_test/dq_p2_storage/qdel_deletes_the_contents
/datum/unit_test/dq_p2_storage/qdel_deletes_the_contents/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/list/made = sb_loaded_box(H)
	var/obj/item/storage/box/B = made[1]
	var/list/things = made[2]
	var/obj/item/bottle = made[3]
	var/obj/item/pill = made[4]
	qdel(B)
	sb_settle()
	for(var/obj/item/I as anything in things)
		TEST_ASSERT(QDELETED(I), "contents go with the box")
	TEST_ASSERT(QDELETED(bottle) && QDELETED(pill), "nested storage and what it holds go too")

/// Taking a storage apart (disassembled) puts what is inside it on the floor where it stood.
/datum/unit_test/dq_p2_storage/deconstructing_a_storage_drops_its_contents
/datum/unit_test/dq_p2_storage/deconstructing_a_storage_drops_its_contents/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/list/made = sb_loaded_box(H)
	var/obj/item/storage/box/B = made[1]
	var/list/things = made[2]
	var/obj/item/bottle = made[3]
	var/obj/item/pill = made[4]
	var/turf/T = get_turf(B)
	B.deconstruct(TRUE)
	sb_settle()
	TEST_ASSERT(QDELETED(B), "the box is gone")
	for(var/obj/item/I as anything in things)
		TEST_ASSERT(!QDELETED(I), "contents survive")
		TEST_ASSERT_EQUAL(get_turf(I), T, "and land where it stood")
	TEST_ASSERT(!QDELETED(bottle) && get_turf(bottle) == T, "a nested bottle lands too")
	TEST_ASSERT_EQUAL(pill.loc, bottle, "with what is in it")
	TEST_ASSERT(!H.s_active, "and the window is closed")

/// Smashing a storage (not disassembled) follows the slot's drop policy, like deleting it.
/datum/unit_test/dq_p2_storage/smashing_a_storage_follows_its_drop_policy
/datum/unit_test/dq_p2_storage/smashing_a_storage_follows_its_drop_policy/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/list/made = sb_loaded_box(H)
	var/obj/item/storage/box/B = made[1]
	var/list/things = made[2]
	B.deconstruct(FALSE)
	sb_settle()
	TEST_ASSERT(QDELETED(B), "the box is gone")
	for(var/obj/item/I as anything in things)
		TEST_ASSERT(QDELETED(I), "contents go with a smashed box")

/datum/unit_test/dq_p2_storage/spill_drops_everything
/datum/unit_test/dq_p2_storage/spill_drops_everything/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/backpack/pack = sb_make(/obj/item/storage/backpack)
	var/list/things = list()
	for(var/i in 1 to 3)
		var/obj/item/I = sb_make(/obj/item/p2_storage_probe/tiny, get_turf(H))
		sb_click(H, pack, I)
		things += I
	pack.spill()
	TEST_ASSERT_EQUAL(sb_count(pack), 0, "a spilled pack is empty")
	for(var/obj/item/I as anything in things)
		TEST_ASSERT(I.loc != pack && !QDELETED(I), "each thing was dropped")

// ---------------------------------------------------------------------------------------------------------------------
// Types with their own handling of a click
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_storage/pocketed_storage_comes_to_the_hand
/datum/unit_test/dq_p2_storage/pocketed_storage_comes_to_the_hand/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/pill_bottle/bottle = sb_make(/obj/item/storage/pill_bottle)
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/black(H), SLOT_ID_UNIFORM)
	TEST_ASSERT(H.equip_to_slot_if_possible(bottle, SLOT_ID_POCKET_L), "the fixture bottle fits a pocket")
	sb_empty_hands(H)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, bottle, null, null, "left=1"))
	sb_settle()
	TEST_ASSERT(sb_in_hands(H, bottle), "an empty hand on a pocketed storage takes it to the hand")
	TEST_ASSERT(!sb_is_open(H, bottle), "and does not open it")

/datum/unit_test/dq_p2_storage/box_folds_only_when_empty
/datum/unit_test/dq_p2_storage/box_folds_only_when_empty/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/box/full = sb_make(/obj/item/storage/box)
	var/obj/item/p2_storage_probe/tiny/I = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, full, I)
	sb_use_held(H, full)
	TEST_ASSERT(!QDELETED(full), "a box with something in it is not folded")
	var/obj/item/storage/box/empty_box = sb_make(/obj/item/storage/box)
	sb_use_held(H, empty_box)
	TEST_ASSERT(QDELETED(empty_box), "an empty box used in hand folds flat")
	var/found = FALSE
	for(var/obj/item/stack/material/cardboard/C in range(1, H))
		found = TRUE
	for(var/obj/item/stack/material/cardboard/C in H.contents)
		found = TRUE
	TEST_ASSERT(found, "and cardboard is left")

/datum/unit_test/dq_p2_storage/pill_bottle_is_labelled_with_a_pen
/datum/unit_test/dq_p2_storage/pill_bottle_is_labelled_with_a_pen/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/pill_bottle/bottle = sb_make(/obj/item/storage/pill_bottle)
	var/obj/item/pen/pen = sb_make(/obj/item/pen)
	var/before = bottle.name
	sb_click(H, bottle, pen)
	sb_write_label(H, bottle, "aspirin")
	sb_settle()
	TEST_ASSERT_EQUAL(sb_label(bottle), "aspirin", "the label was written")
	TEST_ASSERT(findtext(bottle.name, "aspirin"), "and shows in the name")
	TEST_ASSERT(pen.loc != bottle, "the pen was not put in the bottle")
	TEST_ASSERT(bottle.name != before, "the name changed")

/datum/unit_test/dq_p2_storage/matchbox_strikes_instead_of_taking
/datum/unit_test/dq_p2_storage/matchbox_strikes_instead_of_taking/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/box/matches/M = sb_make(/obj/item/storage/box/matches)
	var/obj/item/flame/match/match = sb_make(/obj/item/flame/match)
	sb_click(H, M, match)
	TEST_ASSERT(match.loc != M, "a match clicked on the box is struck, not put back")
	var/obj/item/p2_storage_probe/tiny/other = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, M, other)
	TEST_ASSERT(other.loc != M, "and the box takes nothing but matches")

/datum/unit_test/dq_p2_storage/crayon_box_refuses_the_mime_and_rainbow_crayons
/datum/unit_test/dq_p2_storage/crayon_box_refuses_the_mime_and_rainbow_crayons/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/fancy/crayons/box = sb_make(/obj/item/storage/fancy/crayons)
	for(var/obj/item/I as anything in sb_items(box))
		qdel(I)
	sb_settle()
	TEST_ASSERT_EQUAL(sb_count(box), 0, "the box was emptied for the test")
	var/obj/item/pen/crayon/red = sb_make(/obj/item/pen/crayon)
	sb_click(H, box, red)
	TEST_ASSERT_EQUAL(red.loc, box, "an ordinary crayon goes in")
	var/obj/item/pen/crayon/mime/mime = sb_make(/obj/item/pen/crayon/mime)
	sb_click(H, box, mime)
	TEST_ASSERT(mime.loc != box, "the mime crayon does not")
	var/obj/item/pen/crayon/rainbow/rainbow = sb_make(/obj/item/pen/crayon/rainbow)
	sb_click(H, box, rainbow)
	TEST_ASSERT(rainbow.loc != box, "the rainbow crayon does not")

/datum/unit_test/dq_p2_storage/quickdraw_case_draws_or_opens
/datum/unit_test/dq_p2_storage/quickdraw_case_draws_or_opens/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/quickdraw/syringe_case/case = sb_make(/obj/item/storage/quickdraw/syringe_case)
	TEST_ASSERT(sb_quickmode(case), "a syringe case starts in quickdraw mode")
	var/count = sb_count(case)
	TEST_ASSERT(count > 0, "and starts loaded")
	sb_empty_hands(H)
	H.put_in_inactive_hand(case)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, case, null, null, "left=1"))
	sb_settle()
	TEST_ASSERT_EQUAL(sb_count(case), count - 1, "an empty hand on the carried case draws one thing out")
	TEST_ASSERT(!sb_is_open(H, case), "without opening it")
	// the alt-click switches the mode
	sb_alt_click(H, case)
	TEST_ASSERT(!sb_quickmode(case), "an alt-click on the carried case switches the mode off")
	sb_alt_click(H, case)
	TEST_ASSERT(sb_quickmode(case), "and on again")

/datum/unit_test/dq_p2_storage/laundry_basket_needs_two_hands
/datum/unit_test/dq_p2_storage/laundry_basket_needs_two_hands/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/laundry_basket/B = sb_make(/obj/item/storage/laundry_basket)
	var/obj/item/p2_storage_probe/busy = sb_make(/obj/item/p2_storage_probe)
	sb_empty_hands(H)
	H.put_in_inactive_hand(busy)
	H.next_click = 0
	var/datum/op_result/refused = test_click(H, B)
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "the real lift operation refuses an occupied second hand")
	TEST_ASSERT_EQUAL(refused?.reason, MSG(two_hands/other_hand), "lifting retains the established other-hand refusal")
	sb_settle()
	TEST_ASSERT(!sb_in_hands(H, B), "with the other hand full the basket is not lifted")
	sb_empty_hands(H)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, B, null, null, "left=1"))
	sb_settle()
	TEST_ASSERT(sb_in_hands(H, B), "with both hands free it is")
	TEST_ASSERT(istype(H.get_inactive_hand(), /obj/item/storage/laundry_basket/offhand), "and the other hand holds the second grip")

/datum/unit_test/dq_p2_storage/trinket_box_lid_toggles
/datum/unit_test/dq_p2_storage/trinket_box_lid_toggles/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/trinketbox/T = sb_make(/obj/item/storage/trinketbox)
	TEST_ASSERT(!sb_lid_open(T), "closed to start with")
	sb_use_held(H, T)
	TEST_ASSERT(sb_lid_open(T), "used in hand it opens")
	sb_use_held(H, T)
	TEST_ASSERT(!sb_lid_open(T), "and closes again")

/datum/unit_test/dq_p2_storage/mre_tears_open_when_used
/datum/unit_test/dq_p2_storage/mre_tears_open_when_used/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/mre/menu10/M = sb_make(/obj/item/storage/mre/menu10)
	TEST_ASSERT(!sb_torn_open(M), "sealed to start with")
	sb_use_held(H, M)
	TEST_ASSERT(sb_torn_open(M), "using it tears it open")
	TEST_ASSERT(sb_is_open(H, M), "and shows what is inside")

/datum/unit_test/dq_p2_storage/secure_briefcase_locked_refuses
/datum/unit_test/dq_p2_storage/secure_briefcase_locked_refuses/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/secure/briefcase/S = sb_make(/obj/item/storage/secure/briefcase)
	TEST_ASSERT(sb_secure_locked(S), "a secure briefcase starts locked")
	var/obj/item/p2_storage_probe/tiny/I = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, S, I)
	TEST_ASSERT(I.loc != S, "a locked briefcase takes nothing")
	sb_alt_click(H, S)
	TEST_ASSERT(!sb_is_open(H, S), "does not open by alt-click")
	sb_open_held(H, S)
	TEST_ASSERT(!sb_is_open(H, S), "nor held in the hand")
	S.locked = 0
	sb_click(H, S, I)
	TEST_ASSERT_EQUAL(I.loc, S, "an unlocked briefcase takes items")
	sb_open_held(H, S)
	TEST_ASSERT(sb_is_open(H, S), "and opens")

/datum/unit_test/dq_p2_storage/secure_briefcase_emag_opens_it_after_a_moment
/datum/unit_test/dq_p2_storage/secure_briefcase_emag_opens_it_after_a_moment/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/secure/briefcase/S = sb_make(/obj/item/storage/secure/briefcase)
	var/obj/item/card/emag/emag = sb_make(/obj/item/card/emag)
	sb_click(H, S, emag)
	sb_settle()
	TEST_ASSERT(!sb_secure_locked(S), "the emag shorts the lock out")
	var/obj/item/p2_storage_probe/tiny/I = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, S, I)
	TEST_ASSERT_EQUAL(I.loc, S, "and the briefcase takes items")

/datum/unit_test/dq_p2_storage/light_replacer_takes_good_bulbs_from_a_box
/datum/unit_test/dq_p2_storage/light_replacer_takes_good_bulbs_from_a_box/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/box/lights/bulbs/B = sb_make(/obj/item/storage/box/lights/bulbs)
	var/obj/item/lightreplacer/R = sb_make(/obj/item/lightreplacer)
	R.uses = 0
	var/count = sb_count(B)
	TEST_ASSERT(count > 2, "the box starts with bulbs")
	sb_click(H, B, R)
	TEST_ASSERT(R.uses > 0, "the replacer took bulbs")
	TEST_ASSERT(sb_count(B) < count, "out of the box")
	TEST_ASSERT(R.loc != B, "and was not itself put in")

/datum/unit_test/dq_p2_storage/vial_box_is_a_lockbox
/datum/unit_test/dq_p2_storage/vial_box_is_a_lockbox/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/lockbox/vials/L = sb_make(/obj/item/storage/lockbox/vials)
	TEST_ASSERT(sb_locked(L), "locked to start with")
	var/obj/item/card/id/right = sb_make(/obj/item/card/id)
	right.access = list(ACCESS_VIROLOGY)
	sb_click(H, L, right)
	TEST_ASSERT(!sb_locked(L), "the right ID unlocks it")
	var/obj/item/reagent_containers/glass/beaker/vial/vial = sb_make(/obj/item/reagent_containers/glass/beaker/vial)
	sb_click(H, L, vial)
	TEST_ASSERT_EQUAL(vial.loc, L, "it takes a vial")
	var/obj/item/p2_storage_probe/tiny/junk = sb_make(/obj/item/p2_storage_probe/tiny)
	sb_click(H, L, junk)
	TEST_ASSERT(junk.loc != L, "and nothing else")

// ---------------------------------------------------------------------------------------------------------------------
// The types that add ops to the storage ones declare cleanly
// ---------------------------------------------------------------------------------------------------------------------

/// Every type that has ops of its own beside the storage ones builds its table: an op clash between them is a declaration error that a type
/// no other test clicks would hide.
/datum/unit_test/dq_p2_storage/declared_types
/datum/unit_test/dq_p2_storage/declared_types/run_gate()
	var/list/types = list(/obj/item/storage/backpack/holding, /obj/item/storage/backpack/holding/duffle, /obj/item/storage/backpack/dufflebag, /obj/item/storage/backpack/parachute, 		/obj/item/storage/belt, /obj/item/storage/bible, /obj/item/storage/box, /obj/item/storage/box/matches, /obj/item/storage/fancy/crayons, /obj/item/storage/fancy/markers, 		/obj/item/storage/laundry_basket, /obj/item/storage/lockbox, /obj/item/storage/lockbox/vials, /obj/item/storage/mre, /obj/item/storage/mrebag, 		/obj/item/storage/pill_bottle, /obj/item/storage/quickdraw/syringe_case, /obj/item/storage/secure/briefcase, /obj/item/storage/secure/safe, /obj/item/storage/trinketbox)
	for(var/path in types)
		var/datum/type_table/T = table_of_type(path)
		TEST_ASSERT(!isnull(T), "[path] builds a table")

// ---------------------------------------------------------------------------------------------------------------------
// What the bots make of a storage item
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_storage/toolbox_and_tiles_make_a_floorbot_kit
/datum/unit_test/dq_p2_storage/toolbox_and_tiles_make_a_floorbot_kit/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/toolbox/mechanical/T = sb_make(/obj/item/storage/toolbox/mechanical)
	for(var/obj/item/spilled as anything in sb_items(T))
		LAZYADD(sb_extra, spilled)
	T.spill()
	var/obj/item/stack/tile/floor/tiles = new(run_loc_floor_bottom_left, 10)
	LAZYADD(sb_extra, tiles)
	sb_click(H, T, tiles)
	TEST_ASSERT_EQUAL(tiles.amount, 0, "an empty toolbox takes ten tiles for a floorbot kit")
	var/found = FALSE
	for(var/obj/item/toolbox_tiles/kit in range(1, H))
		found = TRUE
	for(var/obj/item/toolbox_tiles/kit in H.contents)
		found = TRUE
	TEST_ASSERT(found, "the kit is where the person is")

/datum/unit_test/dq_p2_storage/toolbox_with_tools_is_not_a_floorbot_kit
/datum/unit_test/dq_p2_storage/toolbox_with_tools_is_not_a_floorbot_kit/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/toolbox/mechanical/T = sb_make(/obj/item/storage/toolbox/mechanical)
	var/obj/item/stack/tile/floor/tiles = new(run_loc_floor_bottom_left, 10)
	LAZYADD(sb_extra, tiles)
	sb_click(H, T, tiles)
	TEST_ASSERT(!QDELETED(T), "a toolbox with tools in it is not turned into a kit")
	var/found = FALSE
	for(var/obj/item/toolbox_tiles/kit in range(1, H))
		found = TRUE
	for(var/obj/item/toolbox_tiles/kit in H.contents)
		found = TRUE
	TEST_ASSERT(!found, "no kit was made")

/datum/unit_test/dq_p2_storage/robot_arm_and_medkit_make_a_medibot_assembly
/datum/unit_test/dq_p2_storage/robot_arm_and_medkit_make_a_medibot_assembly/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/firstaid/fire/kit = sb_make(/obj/item/storage/firstaid/fire)
	var/obj/item/robot_parts/l_arm/arm = sb_make(/obj/item/robot_parts/l_arm)
	sb_click(H, kit, arm)
	TEST_ASSERT(!QDELETED(kit), "a kit with things in it is not built on")
	TEST_ASSERT(!QDELETED(arm), "and the arm is kept")
	for(var/obj/item/spilled as anything in sb_items(kit))
		LAZYADD(sb_extra, spilled)
	kit.spill()
	sb_click(H, kit, arm)
	TEST_ASSERT(QDELETED(kit), "an empty kit and a robot arm make an assembly")
	var/found = FALSE
	for(var/obj/item/firstaid_arm_assembly/assembly in range(1, H))
		found = TRUE
	for(var/obj/item/firstaid_arm_assembly/assembly in H.contents)
		found = TRUE
	TEST_ASSERT(found, "the assembly is where the person is")

// ---------------------------------------------------------------------------------------------------------------------
// What a storage looks like
// ---------------------------------------------------------------------------------------------------------------------

/// The icon state the thing shows now.
/proc/sb_icon(atom/A)
	return A.icon_state

/datum/unit_test/dq_p2_storage/trash_bag_shows_how_full_it_is
/datum/unit_test/dq_p2_storage/trash_bag_shows_how_full_it_is/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/bag/trash/bag = sb_make(/obj/item/storage/bag/trash)
	bag.update_icon()
	sb_settle()
	TEST_ASSERT_EQUAL(sb_icon(bag), "trashbag0", "an empty bag shows no trash")
	var/obj/item/p2_storage_probe/junk = sb_make(/obj/item/p2_storage_probe)
	sb_click(H, bag, junk)
	TEST_ASSERT_EQUAL(sb_icon(bag), "trashbag1", "one thing shows some trash")
	sb_stuff(H, bag, /obj/item/p2_storage_probe, 8)
	TEST_ASSERT_EQUAL(sb_icon(bag), "trashbag2", "nine things show more")

/datum/unit_test/dq_p2_storage/boxed_goods_show_how_many_are_left
/datum/unit_test/dq_p2_storage/boxed_goods_show_how_many_are_left/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/fancy/candle_box/B = sb_make(/obj/item/storage/fancy/candle_box)
	B.update_icon()
	sb_settle()
	var/count = sb_count(B)
	TEST_ASSERT(count > 0, "the box starts with candles")
	TEST_ASSERT_EQUAL(sb_icon(B), "[B.icon_type]box[count]", "the box shows how many")
	sb_empty_hands(H)
	H.put_in_inactive_hand(B)
	sb_open_held(H, B)
	var/obj/item/first = sb_items(B)[1]
	H.drop_item()
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, first, null, null, "left=1"))
	sb_settle()
	TEST_ASSERT_EQUAL(sb_icon(B), "[B.icon_type]box[count - 1]", "and one fewer after one comes out")

/datum/unit_test/dq_p2_storage/lockbox_shows_its_lock
/datum/unit_test/dq_p2_storage/lockbox_shows_its_lock/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/lockbox/L = sb_make(/obj/item/storage/lockbox)
	L.update_icon()
	sb_settle()
	TEST_ASSERT_EQUAL(sb_icon(L), "lockbox+l", "locked")
	var/obj/item/card/id/right = sb_make(/obj/item/card/id)
	right.access = list(ACCESS_ARMORY)
	sb_click(H, L, right)
	TEST_ASSERT_EQUAL(sb_icon(L), "lockbox", "unlocked")
	var/obj/item/card/emag/emag = sb_make(/obj/item/card/emag)
	sb_click(H, L, emag)
	TEST_ASSERT_EQUAL(sb_icon(L), "lockbox+b", "broken")

/datum/unit_test/dq_p2_storage/laundry_basket_shows_when_it_is_full
/datum/unit_test/dq_p2_storage/laundry_basket_shows_when_it_is_full/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/laundry_basket/B = sb_make(/obj/item/storage/laundry_basket)
	B.update_icon()
	sb_settle()
	TEST_ASSERT_EQUAL(sb_icon(B), "laundry-empty", "empty")
	var/obj/item/p2_storage_probe/I = sb_make(/obj/item/p2_storage_probe)
	sb_click(H, B, I)
	TEST_ASSERT_EQUAL(sb_icon(B), "laundry-full", "full of laundry")

/// A matched storage.put_in candidate checks its requirement again if the slot's rules change.
/datum/unit_test/dq_p2_storage/fits_requirement_keeps_its_exact_refusal
/datum/unit_test/dq_p2_storage/fits_requirement_keeps_its_exact_refusal/run_gate()
	var/mob/living/carbon/human/H = sb_actor()
	var/obj/item/storage/box/B = sb_make(/obj/item/storage/box)
	var/obj/item/p2_storage_probe/first = sb_make(/obj/item/p2_storage_probe)
	TEST_ASSERT(H.put_in_active_hand(first), "the first input is held")
	var/datum/op_result/inserted = test_click(H, B, first)
	TEST_ASSERT_EQUAL(inserted?.key, "storage.put_in", "the real click selected the insertion candidate")
	TEST_ASSERT_EQUAL(inserted?.outcome, ACT_COMMITTED, "a fitting item passed the actual requirement")
	TEST_ASSERT_EQUAL(first.loc, B, "the insertion committed real containment")
	var/obj/item/p2_storage_probe/next = sb_make(/obj/item/p2_storage_probe)
	TEST_ASSERT(H.put_in_active_hand(next), "the second input is held")
	var/datum/op_resolution/R = own(op_resolve(H, B, next, ORIGIN_CLICK, AUTH_PHYSICAL, GESTURE_CLICK))
	var/datum/op_cand/insertion
	for(var/datum/op_cand/C as anything in R.ordered)
		if(C.oplan.key == "storage.put_in" && op_cand_when(R, C))
			insertion = C
	TEST_ASSERT_NOTNULL(insertion, "a genuine insertion candidate matched before its rules changed")
	if(!insertion)
		return
	TEST_ASSERT_NULL(op_cand_require_reason(R, insertion), "the matched candidate initially allows")
	storage_restrict(B, list(/obj/item/stack/tile), null)
	var/before_count = sb_count(B)
	var/why = op_cand_require_reason(R, insertion)
	TEST_ASSERT_EQUAL(why, "\The [next] won't go in 	he [B]: it doesn't take that.", "the same candidate now refuses with the original formatted reason")
	TEST_ASSERT_EQUAL(next.loc, H, "the refused requirement kept the input in the actor's hand")
	TEST_ASSERT_EQUAL(sb_count(B), before_count, "requirement inspection made no containment change")
