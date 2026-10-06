// Behaviour-preservation tests for the closet domain (phase 2): closets, secure lockers, crates, secure crates, body bags, stasis bags, coffins and graves,
// and the odd closets the family carries (the emergency wall locker, the personal and mind lockers, statues, eggs). They pin what a player can observe through
// public inputs (clicks, alt-clicks, drags, the Resist verb, an occupant's move, damage entry points, time), so the same file passes before and after the
// closets move onto the engine forms.
//
// Rules the tests keep:
//   - Input goes through the click helpers (the real inbox path: the target's and the held item's ops, else the legacy click chain), the Resist verb
//     (`resist()`), an occupant's move (`relaymove`) and the damage entry points; never an op key.
//   - State is read through the adapter block (the only place that names today's accessors) and plain vars (loc, density, name, anchored).
//   - Every input is followed by settle() (kernel time) unless the test is about the wait itself; those assert state at explicit times.
//   - Nothing depends on message text (examine lines excepted: they are state) or on a click result's outcome: the tests assert the state that results.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: today's accessors, wrapped. After the conversion only these bodies change.
// ---------------------------------------------------------------------------------------------------------------------

/// The door is open.
/proc/p2cl_opened(obj/structure/closet/C)
	return !!C.opened

/// The lock is locked (a plain closet has none).
/proc/p2cl_locked(obj/structure/closet/C)
	if(istype(C, /obj/structure/closet/secure_closet) || istype(C, /obj/structure/closet/crate/secure))
		return !!lock_locked(C)
	return FALSE

/// The lock is broken for good (an emag, a blade, a break-out).
/proc/p2cl_broken(obj/structure/closet/C)
	if(istype(C, /obj/structure/closet/secure_closet))
		var/obj/structure/closet/secure_closet/S = C
		return !!S.broken
	if(istype(C, /obj/structure/closet/crate/secure))
		var/obj/structure/closet/crate/secure/S2 = C
		return !!S2.broken
	return FALSE

/// The closet is sealed (welded, or screwed down for a coffin).
/proc/p2cl_sealed(obj/structure/closet/C)
	return !!is_welded(C)

/// Seals or unseals the closet the way a construct's spell or a test fixture would (no tool).
/proc/p2cl_set_sealed(obj/structure/closet/C, on)
	set_welded(C, !!on)
	C.update_icon()

/// Locks or unlocks the closet with no card (a fixture, or a mapper's starting state).
/proc/p2cl_set_locked(obj/structure/closet/C, on)
	C.force_lock(!!on)
	C.update_icon()

/// What the closet holds, declared contents made real first.
/proc/p2cl_contents(obj/structure/closet/C)
	C.latent_materialize_all()
	return C.slot_contents()

/// The crate has been rigged with a cable.
/proc/p2cl_rigged(obj/structure/closet/crate/C)
	return !!C.rigged

/// The crate's anti-tamper setting.
/proc/p2cl_set_tamper_proof(obj/structure/closet/crate/secure/C, level)
	C.tamper_proof = level

/// How many units of room the closet has in all.
/proc/p2cl_capacity(obj/structure/closet/C)
	return C.storage_capacity

/// Sets how much the closet holds (a fixture tuning a type, not a player input).
/proc/p2cl_set_capacity(obj/structure/closet/C, units)
	C.storage_capacity = units

/// The shown icon state of the closet (what a player sees: the lock and the weld).
/proc/p2cl_icon(obj/structure/closet/C)
	return C.icon_state

/// A person inside pushes on the door (a move key): the closet's relaymove.
/proc/p2cl_push(obj/structure/closet/C, mob/living/user)
	C.relaymove(user, NORTH)

/// The person presses Resist.
/proc/p2cl_resist(mob/living/user)
	user.next_click = 0
	COOLDOWN_RESET(user, resist_cooldown)
	user.resist()

/// The registered owner of a personal locker.
/proc/p2cl_owner_name(obj/structure/closet/secure_closet/personal/C)
	return C.registered_name

/// The person uses the Reset Lock verb of a personal locker.
/proc/p2cl_personal_reset(obj/structure/closet/secure_closet/personal/C, mob/living/user)
	test_menu(user, C, "reset_lock")

/// A shot lands on the closet: a projectile of `damage` brute, through the hit entry point.
/proc/p2cl_shoot(obj/structure/closet/C, damage)
	var/obj/item/projectile/bullet/P = new(null)
	P.damage = damage
	C.bullet_act(P)
	qdel(P)

/// The person uses the Devour Occupants verb of the closet they are in.
/proc/p2cl_devour(obj/structure/closet/C, mob/living/user)
	test_menu(user, C, "devour")

/// The person has a question open (a prompt a verb asked them).
/proc/p2cl_has_question(mob/user)
	if(SSrequests.open_for(user))
		return TRUE
	return FALSE

/// The text of the closet's examine.
/proc/p2cl_examine(obj/structure/closet/C, mob/viewer)
	return jointext(C.examine(viewer), "\n")

/// A player's click on `target`, with `held` (when given) in the active hand: the click event a client sends, through the input inbox. `params` is the
/// mouse params ("left=1", "left=1;alt=1").
/proc/p2cl_click(mob/living/actor, atom/target, obj/item/held, params = "left=1", stance = I_HELP)
	if(held && actor.get_active_hand() != held)
		if(actor.get_active_hand())
			actor.drop_item()
		actor.put_in_active_hand(held)
	else if(!held && actor.get_active_hand())
		actor.drop_item()
	actor.set_use_stance(stance)
	actor.next_click = 0
	var/datum/input_event/click/E = new(actor, target, null, "mapwindow.map", params)
	input_submit(E)
	return E.result

/// The actor drags `dragged` onto `over` (a mouse drag: the dragged thing is what the target works with).
/proc/p2cl_drag(mob/living/actor, atom/movable/dragged, atom/over)
	actor.next_click = 0
	test_drag(actor, dragged, over)

/// The person drags a folded-away-able thing (a body bag, a roller bed) onto themselves, as a mouse drag does.
/proc/p2cl_fold(mob/living/actor, obj/structure/closet/body_bag/B)
	test_drag(actor, B, actor)

/// Lets the prompts a type asks the legacy way be answered by the test (they are collected instead of shown). Call once the kernel is on its test clock.
/proc/p2cl_capture_prompts()
	test_prompts_reset()

/// Answers the question `actor` was asked: the engine's request first, else the legacy prompt the click collected. `value` is a text for a text
/// question, TRUE or FALSE for a confirmation.
/proc/p2cl_answer(mob/actor, value, cancel = FALSE)
	var/datum/op_result/result = test_answer(actor, value, cancel ? REQ_CANCELLED : REQ_ANSWERED)
	if(!isnull(result))
		return result
	return null

// ---------------------------------------------------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------------------------------------------------

/// An item of a chosen size that does nothing.
/obj/item/p2_closet_probe
	name = "closet probe"
	w_class = ITEMSIZE_SMALL

/obj/item/p2_closet_probe/tiny
	w_class = ITEMSIZE_TINY

/obj/item/p2_closet_probe/normal
	w_class = ITEMSIZE_NORMAL

/obj/item/p2_closet_probe/large
	w_class = ITEMSIZE_LARGE

/obj/item/p2_closet_probe/huge
	w_class = ITEMSIZE_HUGE

/obj/item/p2_closet_probe/anchored
	anchored = TRUE

/// A closet with a known access, so a test does not depend on a map's.
/obj/structure/closet/secure_closet/p2_test
	name = "test locker"
	req_access = list(ACCESS_ENGINE)

/obj/structure/closet/crate/secure/p2_test
	name = "test secure crate"
	req_access = list(ACCESS_ENGINE)

// ---------------------------------------------------------------------------------------------------------------------
// The base
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_closet
	abstract_type = /datum/unit_test/dq_p2_closet

/datum/unit_test/dq_p2_closet/Run()
	test_driver_begin()
	test_rng(1)
	p2cl_capture_prompts()
	run_gate()
	for(var/dx in 0 to 4)
		for(var/dy in 0 to 4)
			var/turf/T = tile(dx, dy)
			if(T)
				own_turf_contents(T)
	test_driver_end()

/datum/unit_test/dq_p2_closet/proc/run_gate()
	return

/// A turf of the 5x5 room, `dx` and `dy` from its bottom-left corner.
/datum/unit_test/dq_p2_closet/proc/tile(dx, dy)
	return locate(run_loc_floor_bottom_left.x + dx, run_loc_floor_bottom_left.y + dy, run_loc_floor_bottom_left.z)

/// Time for any wait a click may start (longer than any tool action, shorter than a break-out).
/datum/unit_test/dq_p2_closet/proc/settle()
	test_time(10 SECONDS)

/// A conscious person with hands, who cannot be knocked out by the passing of the test's time, wearing an ID with `access` when given.
/datum/unit_test/dq_p2_closet/proc/person(turf/T, list/access)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || tile(1, 2))
	H.enable_godmode()
	// A body nobody plays is put to sleep by its life (SSD): a controller keeps it awake for as long as the test runs.
	var/mob/controller = allocate(/mob/living/simple_mob/e0_fixture, tile(0, 4))
	rel_set(H, nameof(H.teleop), controller)
	if(access)
		var/obj/item/card/id/card = allocate(/obj/item/card/id, H.loc)
		card.access = access
		card.registered_name = "P2 Tester"
		H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
		H.equip_to_slot(card, SLOT_ID_ID)
	return H

/// `thing` in `H`'s active hand, whatever was there put down.
/datum/unit_test/dq_p2_closet/proc/hold(mob/living/carbon/human/H, obj/item/thing)
	if(H.get_active_hand() && H.get_active_hand() != thing)
		H.drop_item()
	H.put_in_active_hand(thing)
	return thing

/// The actor clicks the target with `held` in the active hand (an empty hand when null) and waits.
/datum/unit_test/dq_p2_closet/proc/touch(mob/living/carbon/human/H, atom/target, obj/item/held)
	p2cl_click(H, target, held)
	settle()

/// The actor alt-clicks the target with an empty hand and waits.
/datum/unit_test/dq_p2_closet/proc/alt_touch(mob/living/carbon/human/H, atom/target)
	p2cl_click(H, target, null, "left=1;alt=1")
	settle()

/// A closet-family thing in the middle of the room.
/datum/unit_test/dq_p2_closet/proc/make(type, turf/T)
	return allocate(type, T || tile(2, 2))

/// A zero-speed tool of `type`.
/datum/unit_test/dq_p2_closet/proc/fast(type, turf/T)
	return dq_fast_tool(type, T || tile(1, 2))

/// A lit, fuelled welder at full speed (for the tests that time the weld).
/datum/unit_test/dq_p2_closet/proc/slow_welder(turf/T)
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool, T || tile(1, 2))
	welder.reagents.add_reagent(REAGENT_ID_FUEL, welder.max_fuel)
	welder.setWelding(TRUE)
	return welder

/// A probe of `type` on the turf.
/datum/unit_test/dq_p2_closet/proc/probe(turf/T, type = /obj/item/p2_closet_probe)
	return allocate(type, T)

/// `L` is shut inside `C` by `helper`: the closet is opened (when it is shut), `L` stands on its tile, and the helper closes it over them.
/datum/unit_test/dq_p2_closet/proc/shut_in(mob/living/carbon/human/helper, obj/structure/closet/C, mob/living/L)
	if(!p2cl_opened(C))
		touch(helper, C)
		TEST_ASSERT(p2cl_opened(C), "the helper opened the closet")
	if(L.loc != C.loc)
		L.forceMove(C.loc)
	touch(helper, C)
	TEST_ASSERT_EQUAL(L.loc, C, "the closet closed over the person")

/// Opens a closed closet by the click a player makes, and waits.
/datum/unit_test/dq_p2_closet/proc/open_it(mob/living/carbon/human/H, obj/structure/closet/C)
	touch(H, C)
	TEST_ASSERT(p2cl_opened(C), "the closet opened")

/// Closes an open closet by the click a player makes, and waits.
/datum/unit_test/dq_p2_closet/proc/close_it(mob/living/carbon/human/H, obj/structure/closet/C)
	touch(H, C)
	TEST_ASSERT(!p2cl_opened(C), "the closet closed")

// ---------------------------------------------------------------------------------------------------------------------
// The plain closet: open, close, store
// ---------------------------------------------------------------------------------------------------------------------

/// An empty hand opens a closed closet and closes it again; the door is what blocks the tile.
/datum/unit_test/dq_p2_closet/hand_opens_and_closes
/datum/unit_test/dq_p2_closet/hand_opens_and_closes/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/carbon/human/H = person()
	TEST_ASSERT(C.density, "a shut closet blocks the tile")
	touch(H, C)
	TEST_ASSERT(p2cl_opened(C), "an empty hand opens it")
	TEST_ASSERT(!C.density, "an open one does not block")
	touch(H, C)
	TEST_ASSERT(!p2cl_opened(C), "and closes it")
	TEST_ASSERT(C.density, "blocking the tile again")

/// Opening spills what is inside onto the tile; closing takes it back.
/datum/unit_test/dq_p2_closet/closing_stores_and_opening_spills
/datum/unit_test/dq_p2_closet/closing_stores_and_opening_spills/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person()
	open_it(H, C)
	var/obj/item/pen = probe(at)
	var/obj/item/other = probe(at, /obj/item/p2_closet_probe/tiny)
	close_it(H, C)
	TEST_ASSERT_EQUAL(pen.loc, C, "the item on the tile went in")
	TEST_ASSERT_EQUAL(other.loc, C, "so did the other")
	TEST_ASSERT_EQUAL(length(p2cl_contents(C)), 2, "the closet holds both")
	open_it(H, C)
	TEST_ASSERT_EQUAL(pen.loc, at, "opening put the item on the tile")
	TEST_ASSERT_EQUAL(other.loc, at, "and the other")
	TEST_ASSERT_EQUAL(length(p2cl_contents(C)), 0, "and the closet is empty")

/// A person on the tile when it closes goes in; opening lets them out.
/datum/unit_test/dq_p2_closet/closing_takes_a_person_on_the_tile
/datum/unit_test/dq_p2_closet/closing_takes_a_person_on_the_tile/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/mob/living/carbon/human/victim = person(at)
	open_it(H, C)
	TEST_ASSERT_EQUAL(victim.loc, at, "the victim stands on the open closet's tile")
	close_it(H, C)
	TEST_ASSERT_EQUAL(victim.loc, C, "closing took the person in")
	open_it(H, C)
	TEST_ASSERT_EQUAL(victim.loc, at, "opening let them out")

/// An anchored thing is never taken in, and the rest of the tile goes.
/datum/unit_test/dq_p2_closet/closing_leaves_anchored_things
/datum/unit_test/dq_p2_closet/closing_leaves_anchored_things/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person()
	open_it(H, C)
	var/obj/item/bolted = probe(at, /obj/item/p2_closet_probe/anchored)
	var/obj/item/loose = probe(at)
	close_it(H, C)
	TEST_ASSERT_EQUAL(bolted.loc, at, "the anchored item stays")
	TEST_ASSERT_EQUAL(loose.loc, C, "the loose one goes in")

/// A closet holds only so much: what does not fit stays on the tile.
/datum/unit_test/dq_p2_closet/capacity_limits_what_closing_takes
/datum/unit_test/dq_p2_closet/capacity_limits_what_closing_takes/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person()
	p2cl_set_capacity(C, 6)
	open_it(H, C)
	// a small item costs 1 unit (half its size class, rounded up), a normal one 2, a large one 2, a huge one 3
	var/list/small = list()
	for(var/i in 1 to 8)
		small += probe(at, /obj/item/p2_closet_probe/normal)
	close_it(H, C)
	var/inside = 0
	for(var/obj/item/I as anything in small)
		if(I.loc == C)
			inside++
	TEST_ASSERT_EQUAL(inside, 3, "six units hold three normal items (cost 2 each)")
	TEST_ASSERT_EQUAL(length(p2cl_contents(C)), 3, "and the closet agrees")

/// A bigger thing costs more room: one large item fills what three small ones would.
/datum/unit_test/dq_p2_closet/big_items_cost_more_room
/datum/unit_test/dq_p2_closet/big_items_cost_more_room/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person()
	p2cl_set_capacity(C, 6)
	open_it(H, C)
	var/obj/item/big_one = probe(at, /obj/item/p2_closet_probe/huge)
	var/obj/item/big_two = probe(at, /obj/item/p2_closet_probe/huge)
	var/obj/item/big_three = probe(at, /obj/item/p2_closet_probe/huge)
	close_it(H, C)
	var/inside = 0
	for(var/obj/item/I in list(big_one, big_two, big_three))
		if(I.loc == C)
			inside++
	TEST_ASSERT_EQUAL(inside, 2, "six units hold two huge items (cost 3 each)")

/// Another closet standing on the tile stops this one from closing.
/datum/unit_test/dq_p2_closet/another_closet_blocks_closing
/datum/unit_test/dq_p2_closet/another_closet_blocks_closing/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person()
	open_it(H, C)
	make(/obj/structure/closet, at)
	touch(H, C)
	TEST_ASSERT(p2cl_opened(C), "it stays open")

/// An item clicked on an open closet is put down on its tile, not inside.
/datum/unit_test/dq_p2_closet/item_on_an_open_closet_lands_on_the_tile
/datum/unit_test/dq_p2_closet/item_on_an_open_closet_lands_on_the_tile/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person()
	open_it(H, C)
	var/obj/item/pen = probe(H.loc)
	touch(H, C, pen)
	TEST_ASSERT_EQUAL(pen.loc, at, "the item lies on the tile")
	TEST_ASSERT_NULL(H.get_active_hand(), "and out of the hand")
	TEST_ASSERT(p2cl_opened(C), "the closet is still open")

/// An item clicked on a closed closet does nothing (the closet is not opened by it).
/datum/unit_test/dq_p2_closet/item_on_a_closed_closet_does_nothing
/datum/unit_test/dq_p2_closet/item_on_a_closed_closet_does_nothing/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/carbon/human/H = person()
	var/obj/item/pen = probe(H.loc)
	touch(H, C, pen)
	TEST_ASSERT(!p2cl_opened(C), "the closet stays closed")
	TEST_ASSERT_EQUAL(H.get_active_hand(), pen, "and the item stays in the hand")

/// A person dragged onto an open closet is moved onto its tile; onto a closed one, nothing moves.
/datum/unit_test/dq_p2_closet/drag_stuffs_a_person_into_an_open_closet
/datum/unit_test/dq_p2_closet/drag_stuffs_a_person_into_an_open_closet/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/mob/living/carbon/human/victim = person(tile(2, 1))
	p2cl_drag(H, victim, C)
	settle()
	TEST_ASSERT_EQUAL(victim.loc, tile(2, 1), "a closed closet takes nothing")
	open_it(H, C)
	p2cl_drag(H, victim, C)
	settle()
	TEST_ASSERT_EQUAL(victim.loc, at, "an open one draws the person onto its tile")

/// Someone who cannot act cannot stuff a person in.
/datum/unit_test/dq_p2_closet/drag_by_the_incapacitated_does_nothing
/datum/unit_test/dq_p2_closet/drag_by_the_incapacitated_does_nothing/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/mob/living/carbon/human/victim = person(tile(2, 1))
	open_it(H, C)
	H.set_stat(UNCONSCIOUS)
	p2cl_drag(H, victim, C)
	settle()
	TEST_ASSERT_EQUAL(victim.loc, tile(2, 1), "nothing moved")

/// A closet is never dragged into another closet.
/datum/unit_test/dq_p2_closet/a_closet_is_not_dragged_into_a_closet
/datum/unit_test/dq_p2_closet/a_closet_is_not_dragged_into_a_closet/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/obj/structure/closet/other = make(/obj/structure/closet, tile(2, 1))
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, C)
	p2cl_drag(H, other, C)
	settle()
	TEST_ASSERT_EQUAL(other.loc, tile(2, 1), "the other closet did not move")

/// A person inside pushing on the door opens the closet; a closet that cannot open keeps them.
/datum/unit_test/dq_p2_closet/moving_inside_opens_the_door
/datum/unit_test/dq_p2_closet/moving_inside_opens_the_door/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person(at)
	shut_in(person(tile(1, 2)), C, H)
	p2cl_push(C, H)
	settle()
	TEST_ASSERT(p2cl_opened(C), "the push opened the door")
	TEST_ASSERT_EQUAL(H.loc, at, "and let them out")

/// A sealed closet will not open to a push from inside.
/datum/unit_test/dq_p2_closet/moving_inside_a_sealed_closet_goes_nowhere
/datum/unit_test/dq_p2_closet/moving_inside_a_sealed_closet_goes_nowhere/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person(at)
	shut_in(person(tile(1, 2)), C, H)
	p2cl_set_sealed(C, TRUE)
	p2cl_push(C, H)
	settle()
	TEST_ASSERT(!p2cl_opened(C), "the door stays shut")
	TEST_ASSERT_EQUAL(H.loc, C, "and the person stays in")

/// A closet starts with what its type says: the contents are there when asked, and come out when it opens.
/datum/unit_test/dq_p2_closet/starts_with_its_contents
/datum/unit_test/dq_p2_closet/starts_with_its_contents/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet/firecloset, at)
	var/mob/living/carbon/human/H = person()
	var/found = FALSE
	for(var/obj/item/extinguisher/E in p2cl_contents(C))
		found = TRUE
	TEST_ASSERT(found, "a fire closet holds an extinguisher")
	open_it(H, C)
	found = FALSE
	for(var/obj/item/extinguisher/E in at)
		found = TRUE
	TEST_ASSERT(found, "and it comes out when the closet opens")

/// A closet sizes itself to hold what its type starts with, whatever the declared capacity.
/datum/unit_test/dq_p2_closet/capacity_grows_to_hold_its_start
/datum/unit_test/dq_p2_closet/capacity_grows_to_hold_its_start/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet/firecloset)
	var/mob/living/carbon/human/H = person()
	open_it(H, C)
	var/before = length(C.loc.contents)
	close_it(H, C)
	TEST_ASSERT(length(p2cl_contents(C)) >= 5, "everything it started with fits back in")
	TEST_ASSERT(before >= 5, "and it all lay on the tile when it opened")
	open_it(H, C) // what a closet made for the test holds is its own, so it is let out for the test's cleaning

/// The examine says how full it is.
/datum/unit_test/dq_p2_closet/examine_says_how_full_it_is
/datum/unit_test/dq_p2_closet/examine_says_how_full_it_is/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person()
	TEST_ASSERT(findtext(p2cl_examine(C, H), "empty"), "an empty closet says so")
	open_it(H, C)
	probe(at)
	close_it(H, C)
	TEST_ASSERT(!findtext(p2cl_examine(C, H), "empty"), "one with something in it does not")

// ---------------------------------------------------------------------------------------------------------------------
// Sealing, deconstruction and the wrench
// ---------------------------------------------------------------------------------------------------------------------

/// A lit welder seals a closed closet (it takes two seconds), and a sealed closet will not open by hand.
/datum/unit_test/dq_p2_closet/welder_seals_a_closed_closet
/datum/unit_test/dq_p2_closet/welder_seals_a_closed_closet/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/carbon/human/H = person()
	var/obj/item/weldingtool/welder = slow_welder()
	p2cl_click(H, C, welder)
	test_time(1 SECOND)
	TEST_ASSERT(!p2cl_sealed(C), "not sealed after a second")
	test_time(3 SECONDS)
	TEST_ASSERT(p2cl_sealed(C), "sealed after four")
	touch(H, C)
	TEST_ASSERT(!p2cl_opened(C), "a sealed closet does not open by hand")

/// The welder frees it again.
/datum/unit_test/dq_p2_closet/welder_unseals_a_sealed_closet
/datum/unit_test/dq_p2_closet/welder_unseals_a_sealed_closet/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/carbon/human/H = person()
	var/obj/item/weldingtool/welder = dq_fueled_welder(H.loc)
	touch(H, C, welder)
	TEST_ASSERT(p2cl_sealed(C), "sealed")
	touch(H, C, welder)
	TEST_ASSERT(!p2cl_sealed(C), "unsealed by a second weld")
	touch(H, C)
	TEST_ASSERT(p2cl_opened(C), "and it opens")

/// A welder that is not lit does not seal.
/datum/unit_test/dq_p2_closet/unlit_welder_does_nothing
/datum/unit_test/dq_p2_closet/unlit_welder_does_nothing/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/carbon/human/H = person()
	var/obj/item/weldingtool/welder = dq_fueled_welder(H.loc)
	welder.setWelding(FALSE)
	touch(H, C, welder)
	TEST_ASSERT(!p2cl_sealed(C), "nothing sealed")

/// Opening the closet while the weld is under way ends it.
/datum/unit_test/dq_p2_closet/opening_cancels_a_weld_in_progress
/datum/unit_test/dq_p2_closet/opening_cancels_a_weld_in_progress/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/carbon/human/H = person()
	var/obj/item/weldingtool/welder = slow_welder()
	p2cl_click(H, C, welder)
	test_time(1 SECOND)
	C.open()
	test_time(5 SECONDS)
	TEST_ASSERT(!p2cl_sealed(C), "no weld on an open closet")

/// A lit welder cuts an open closet apart into a sheet of steel.
/datum/unit_test/dq_p2_closet/welder_cuts_an_open_closet_apart
/datum/unit_test/dq_p2_closet/welder_cuts_an_open_closet_apart/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person()
	var/obj/item/weldingtool/welder = dq_fueled_welder(H.loc)
	open_it(H, C)
	touch(H, C, welder)
	TEST_ASSERT(QDELETED(C), "the closet is gone")
	var/sheets = 0
	for(var/obj/item/stack/material/steel/S in at)
		sheets += S.get_amount()
	TEST_ASSERT_EQUAL(sheets, 1, "one sheet of steel lies where it stood")

/// What an open closet held is not lost when it is cut apart: it is already on the tile.
/datum/unit_test/dq_p2_closet/cutting_apart_loses_nothing
/datum/unit_test/dq_p2_closet/cutting_apart_loses_nothing/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person()
	var/obj/item/weldingtool/welder = dq_fueled_welder(H.loc)
	open_it(H, C)
	var/obj/item/pen = probe(at)
	touch(H, C, welder)
	TEST_ASSERT_EQUAL(pen.loc, at, "the item is on the tile")

/// A wrench bolts an open closet to the floor and unbolts it (two seconds each way).
/datum/unit_test/dq_p2_closet/wrench_anchors_an_open_closet
/datum/unit_test/dq_p2_closet/wrench_anchors_an_open_closet/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/carbon/human/H = person()
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, H.loc)
	open_it(H, C)
	TEST_ASSERT(!C.anchored, "a closet starts loose")
	p2cl_click(H, C, wrench)
	test_time(1 SECOND)
	TEST_ASSERT(!C.anchored, "not anchored after a second")
	test_time(4 SECONDS)
	TEST_ASSERT(C.anchored, "anchored after the wait")
	touch(H, C, wrench)
	TEST_ASSERT(!C.anchored, "and the wrench frees it")

/// The bolts cannot be reached while the door is shut.
/datum/unit_test/dq_p2_closet/wrench_does_nothing_to_a_closed_closet
/datum/unit_test/dq_p2_closet/wrench_does_nothing_to_a_closed_closet/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/carbon/human/H = person()
	var/obj/item/tool/wrench/wrench = fast(/obj/item/tool/wrench)
	touch(H, C, wrench)
	TEST_ASSERT(!C.anchored, "still loose")

// ---------------------------------------------------------------------------------------------------------------------
// Resisting out from inside
// ---------------------------------------------------------------------------------------------------------------------

/// A sealed closet: someone inside who resists breaks it open after two minutes.
/datum/unit_test/dq_p2_closet/resisting_breaks_out_of_a_sealed_closet
/datum/unit_test/dq_p2_closet/resisting_breaks_out_of_a_sealed_closet/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person(at)
	shut_in(person(tile(1, 2)), C, H)
	p2cl_set_sealed(C, TRUE)
	p2cl_resist(H)
	test_time(100 SECONDS)
	TEST_ASSERT(!p2cl_opened(C), "still shut after a hundred seconds")
	TEST_ASSERT(p2cl_sealed(C), "and still sealed")
	test_time(30 SECONDS)
	TEST_ASSERT(p2cl_opened(C), "open after two minutes")
	TEST_ASSERT(!p2cl_sealed(C), "the seal is broken")
	TEST_ASSERT_EQUAL(H.loc, at, "and the person is out")

/// A closed closet that is not sealed holds nobody: resisting does nothing (a push opens it).
/datum/unit_test/dq_p2_closet/resisting_in_an_unsealed_closet_does_nothing
/datum/unit_test/dq_p2_closet/resisting_in_an_unsealed_closet_does_nothing/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person(at)
	shut_in(person(tile(1, 2)), C, H)
	p2cl_resist(H)
	test_time(150 SECONDS)
	TEST_ASSERT(!p2cl_opened(C), "resisting does not open an unsealed closet")
	TEST_ASSERT_EQUAL(H.loc, C, "the person is still inside")

/// Whoever is knocked out stops pushing.
/datum/unit_test/dq_p2_closet/the_breakout_stops_when_the_person_is_knocked_out
/datum/unit_test/dq_p2_closet/the_breakout_stops_when_the_person_is_knocked_out/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person(at)
	shut_in(person(tile(1, 2)), C, H)
	p2cl_set_sealed(C, TRUE)
	p2cl_resist(H)
	test_time(30 SECONDS)
	H.set_stat(UNCONSCIOUS)
	test_time(150 SECONDS)
	TEST_ASSERT(!p2cl_opened(C), "the closet stays shut")
	TEST_ASSERT(p2cl_sealed(C), "and sealed")

/// Another resist while one is under way does not start a second.
/datum/unit_test/dq_p2_closet/a_second_resist_does_not_hurry_it
/datum/unit_test/dq_p2_closet/a_second_resist_does_not_hurry_it/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person(at)
	shut_in(person(tile(1, 2)), C, H)
	p2cl_set_sealed(C, TRUE)
	p2cl_resist(H)
	test_time(50 SECONDS)
	p2cl_resist(H)
	test_time(50 SECONDS)
	TEST_ASSERT(!p2cl_opened(C), "a hundred seconds after the first resist it is still shut")
	test_time(30 SECONDS)
	TEST_ASSERT(p2cl_opened(C), "and it opens when the first resist is done")

/// A closet with a longer break-out time takes longer.
/datum/unit_test/dq_p2_closet/the_breakout_time_is_the_closets_own
/datum/unit_test/dq_p2_closet/the_breakout_time_is_the_closets_own/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	C.breakout_time = 1
	var/mob/living/carbon/human/H = person(at)
	shut_in(person(tile(1, 2)), C, H)
	p2cl_set_sealed(C, TRUE)
	p2cl_resist(H)
	test_time(50 SECONDS)
	TEST_ASSERT(!p2cl_opened(C), "shut after fifty seconds")
	test_time(15 SECONDS)
	TEST_ASSERT(p2cl_opened(C), "open after a minute")

// ---------------------------------------------------------------------------------------------------------------------
// Damage
// ---------------------------------------------------------------------------------------------------------------------

/// A closet worn down to nothing spills what it held and is gone.
/datum/unit_test/dq_p2_closet/destroyed_closet_spills_its_contents
/datum/unit_test/dq_p2_closet/destroyed_closet_spills_its_contents/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, C)
	var/obj/item/pen = probe(at)
	close_it(H, C)
	TEST_ASSERT_EQUAL(pen.loc, C, "the item is inside")
	C.take_damage(C.max_integrity * 2, BRUTE, MELEE)
	settle()
	TEST_ASSERT(QDELETED(C), "the closet is destroyed")
	TEST_ASSERT_EQUAL(pen.loc, at, "and the item lies on the tile")

/// A mob that tears at a closet spills it and takes it down.
/datum/unit_test/dq_p2_closet/a_mob_tearing_at_it_destroys_it
/datum/unit_test/dq_p2_closet/a_mob_tearing_at_it_destroys_it/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, C)
	var/obj/item/pen = probe(at)
	close_it(H, C)
	generic_hit(C, H, 50)
	settle()
	TEST_ASSERT(QDELETED(C), "the closet is gone")
	TEST_ASSERT_EQUAL(pen.loc, at, "and its contents lie on the tile")

/// A small nibble does nothing.
/datum/unit_test/dq_p2_closet/a_small_nibble_does_nothing
/datum/unit_test/dq_p2_closet/a_small_nibble_does_nothing/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	generic_hit(C, H, 1)
	settle()
	TEST_ASSERT(!QDELETED(C), "the closet is still there")

// ---------------------------------------------------------------------------------------------------------------------
// The secure locker: the lock
// ---------------------------------------------------------------------------------------------------------------------

/// A secure locker starts locked: it does not open to an empty hand of someone without the access.
/datum/unit_test/dq_p2_closet/locker_starts_locked_and_refuses_strangers
/datum/unit_test/dq_p2_closet/locker_starts_locked_and_refuses_strangers/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	var/mob/living/carbon/human/stranger = person(tile(1, 2), list(ACCESS_SECURITY))
	TEST_ASSERT(p2cl_locked(C), "a secure locker starts locked")
	touch(stranger, C)
	TEST_ASSERT(p2cl_locked(C), "a stranger's hand leaves it locked")
	TEST_ASSERT(!p2cl_opened(C), "and shut")
	var/mob/living/carbon/human/nobody = person(tile(3, 2))
	touch(nobody, C)
	TEST_ASSERT(p2cl_locked(C), "someone with no ID leaves it locked too")

/// The right access unlocks it by hand, then the hand opens and closes it.
/datum/unit_test/dq_p2_closet/locker_hand_unlocks_then_opens
/datum/unit_test/dq_p2_closet/locker_hand_unlocks_then_opens/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2), list(ACCESS_ENGINE))
	touch(H, C)
	TEST_ASSERT(!p2cl_locked(C), "the hand unlocked it")
	TEST_ASSERT(!p2cl_opened(C), "without opening it")
	touch(H, C)
	TEST_ASSERT(p2cl_opened(C), "the next touch opens it")
	touch(H, C)
	TEST_ASSERT(!p2cl_opened(C), "and the next closes it")
	TEST_ASSERT(!p2cl_locked(C), "leaving it unlocked")

/// An alt-click locks and unlocks a closed locker for someone with the access.
/datum/unit_test/dq_p2_closet/alt_click_toggles_the_lock
/datum/unit_test/dq_p2_closet/alt_click_toggles_the_lock/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2), list(ACCESS_ENGINE))
	alt_touch(H, C)
	TEST_ASSERT(!p2cl_locked(C), "an alt-click unlocked it")
	alt_touch(H, C)
	TEST_ASSERT(p2cl_locked(C), "and locked it again")
	var/mob/living/carbon/human/stranger = person(tile(3, 2), list(ACCESS_SECURITY))
	alt_touch(stranger, C)
	TEST_ASSERT(p2cl_locked(C), "a stranger's alt-click does nothing")

/// The lock cannot be reached while the door is open.
/datum/unit_test/dq_p2_closet/the_lock_is_out_of_reach_when_open
/datum/unit_test/dq_p2_closet/the_lock_is_out_of_reach_when_open/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2), list(ACCESS_ENGINE))
	touch(H, C)
	touch(H, C)
	TEST_ASSERT(p2cl_opened(C), "open")
	alt_touch(H, C)
	TEST_ASSERT(!p2cl_locked(C), "an alt-click on an open locker does not lock it")

/// An ID card in hand works the lock; so does any other item for someone whose own ID has the access.
/datum/unit_test/dq_p2_closet/an_id_in_hand_toggles_the_lock
/datum/unit_test/dq_p2_closet/an_id_in_hand_toggles_the_lock/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/card/id/card = allocate(/obj/item/card/id, H.loc)
	card.access = list(ACCESS_ENGINE)
	card.registered_name = "P2 Tester"
	touch(H, C, card)
	TEST_ASSERT(!p2cl_locked(C), "the card in hand unlocked it")
	touch(H, C, card)
	TEST_ASSERT(p2cl_locked(C), "and locked it")

/// The wrong card in hand does nothing.
/datum/unit_test/dq_p2_closet/the_wrong_card_does_nothing
/datum/unit_test/dq_p2_closet/the_wrong_card_does_nothing/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/card/id/card = allocate(/obj/item/card/id, H.loc)
	card.access = list(ACCESS_SECURITY)
	card.registered_name = "P2 Tester"
	touch(H, C, card)
	TEST_ASSERT(p2cl_locked(C), "still locked")

/// Any item at all clicked on a closed locker works the lock for someone wearing an ID with the access.
/datum/unit_test/dq_p2_closet/any_item_works_the_lock_for_an_authorised_wearer
/datum/unit_test/dq_p2_closet/any_item_works_the_lock_for_an_authorised_wearer/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2), list(ACCESS_ENGINE))
	var/obj/item/pen = probe(H.loc)
	touch(H, C, pen)
	TEST_ASSERT(!p2cl_locked(C), "an item in the hand of an authorised person unlocks it")
	touch(H, C, pen)
	TEST_ASSERT(p2cl_locked(C), "and locks it")
	var/mob/living/carbon/human/stranger = person(tile(3, 2), list(ACCESS_SECURITY))
	var/obj/item/other = probe(stranger.loc)
	touch(stranger, C, other)
	TEST_ASSERT(p2cl_locked(C), "an item in a stranger's hand does nothing")

/// A locked locker will not open by any means a player has: the hand of a stranger, a push from inside.
/datum/unit_test/dq_p2_closet/a_locked_locker_does_not_open
/datum/unit_test/dq_p2_closet/a_locked_locker_does_not_open/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	TEST_ASSERT(!C.open(), "open() refuses")
	TEST_ASSERT(!p2cl_opened(C), "shut")

/// An EMP can flip the lock, spring a locker, or scramble its access.
/datum/unit_test/dq_p2_closet/emp_can_toggle_the_lock
/datum/unit_test/dq_p2_closet/emp_can_toggle_the_lock/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	C.emp_protection_flags |= EMP_PROTECT_WIRES | EMP_PROTECT_CONTENTS
	test_rng(1234)
	var/flipped = FALSE
	for(var/i in 1 to 300)
		C.emp_act(1)
		settle()
		if(!p2cl_locked(C))
			flipped = TRUE
			break
	TEST_ASSERT(flipped, "a strong EMP unlocks a locker sometimes")

/// A strong EMP can spring a locker open, or scramble the access it asks for.
/datum/unit_test/dq_p2_closet/emp_can_scramble_the_access
/datum/unit_test/dq_p2_closet/emp_can_scramble_the_access/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	C.emp_protection_flags |= EMP_PROTECT_WIRES | EMP_PROTECT_CONTENTS
	test_rng(4321)
	var/scrambled = FALSE
	for(var/i in 1 to 80)
		if(p2cl_opened(C))
			C.close()
		p2cl_set_locked(C, TRUE)
		C.emp_act(1)
		test_time(1 SECONDS)
		if(!(ACCESS_ENGINE in C.req_access) || length(C.req_access) != 1)
			scrambled = TRUE
			break
	TEST_ASSERT(scrambled, "a strong EMP changes the access a locked locker wants sometimes")

// ---------------------------------------------------------------------------------------------------------------------
// The secure locker: emag, blade and breaking open
// ---------------------------------------------------------------------------------------------------------------------

/// An emag breaks the lock open for good.
/datum/unit_test/dq_p2_closet/emag_breaks_the_lock
/datum/unit_test/dq_p2_closet/emag_breaks_the_lock/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/card/emag/emag = allocate(/obj/item/card/emag, H.loc)
	touch(H, C, emag)
	TEST_ASSERT(p2cl_broken(C), "the emag broke the lock")
	TEST_ASSERT(!p2cl_locked(C), "and unlocked it")
	touch(H, C)
	TEST_ASSERT(p2cl_opened(C), "the locker opens")
	touch(H, C)
	TEST_ASSERT(!p2cl_opened(C), "and closes")

/// A broken lock cannot be locked again, by any hand or card.
/datum/unit_test/dq_p2_closet/a_broken_lock_cannot_be_locked
/datum/unit_test/dq_p2_closet/a_broken_lock_cannot_be_locked/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2), list(ACCESS_ENGINE))
	var/obj/item/card/emag/emag = allocate(/obj/item/card/emag, H.loc)
	touch(H, C, emag)
	alt_touch(H, C)
	TEST_ASSERT(!p2cl_locked(C), "an alt-click does not lock a broken locker")
	var/obj/item/card/id/card = allocate(/obj/item/card/id, H.loc)
	card.access = list(ACCESS_ENGINE)
	card.registered_name = "P2 Tester"
	touch(H, C, card)
	TEST_ASSERT(!p2cl_locked(C), "nor does a card")

/// A second emag changes nothing and costs no use.
/datum/unit_test/dq_p2_closet/a_second_emag_costs_nothing
/datum/unit_test/dq_p2_closet/a_second_emag_costs_nothing/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/card/emag/emag = allocate(/obj/item/card/emag, H.loc)
	var/uses = emag.uses
	touch(H, C, emag)
	TEST_ASSERT_EQUAL(emag.uses, uses - 1, "the first use is paid")
	touch(H, C, emag)
	TEST_ASSERT_EQUAL(emag.uses, uses - 1, "the second is not")
	TEST_ASSERT(p2cl_broken(C), "and it is still broken")

/// An energy blade slices a closed locker's lock open.
/datum/unit_test/dq_p2_closet/a_blade_slices_the_lock_open
/datum/unit_test/dq_p2_closet/a_blade_slices_the_lock_open/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/melee/energy/blade/blade = allocate(/obj/item/melee/energy/blade, H.loc)
	rel_set(blade, nameof(blade.creator), H) // a blade that was not made by the one holding it goes away at once
	touch(H, C, blade)
	TEST_ASSERT(p2cl_broken(C), "the blade broke the lock")
	TEST_ASSERT(!p2cl_locked(C), "and unlocked it")

/// A locked locker with someone inside: resisting breaks the lock and opens it, sealed or not.
/datum/unit_test/dq_p2_closet/resisting_breaks_a_locked_locker_open
/datum/unit_test/dq_p2_closet/resisting_breaks_a_locked_locker_open/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test, at)
	var/mob/living/carbon/human/H = person(at)
	var/mob/living/carbon/human/other = person(tile(1, 2), list(ACCESS_ENGINE))
	touch(other, C)
	touch(other, C)
	TEST_ASSERT(p2cl_opened(C), "an authorised person opened it")
	touch(other, C)
	TEST_ASSERT_EQUAL(H.loc, C, "the person is in")
	alt_touch(other, C)
	TEST_ASSERT(p2cl_locked(C), "locked with them inside")
	p2cl_resist(H)
	test_time(100 SECONDS)
	TEST_ASSERT(!p2cl_opened(C), "still shut after a hundred seconds")
	test_time(30 SECONDS)
	TEST_ASSERT(p2cl_opened(C), "open after two minutes")
	TEST_ASSERT(p2cl_broken(C), "the lock is broken")
	TEST_ASSERT(!p2cl_locked(C), "and open")

/// A person inside cannot reach the lock.
/datum/unit_test/dq_p2_closet/the_lock_is_out_of_reach_from_inside
/datum/unit_test/dq_p2_closet/the_lock_is_out_of_reach_from_inside/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test, at)
	var/mob/living/carbon/human/other = person(tile(1, 2), list(ACCESS_ENGINE))
	touch(other, C)
	touch(other, C)
	var/mob/living/carbon/human/H = person(at, list(ACCESS_ENGINE))
	touch(other, C)
	TEST_ASSERT_EQUAL(H.loc, C, "the person is in")
	alt_touch(H, C)
	TEST_ASSERT(!p2cl_locked(C), "an alt-click from inside does nothing")

// ---------------------------------------------------------------------------------------------------------------------
// The secure locker: how it looks
// ---------------------------------------------------------------------------------------------------------------------

/// The picture follows the lock and the weld.
/datum/unit_test/dq_p2_closet/the_picture_follows_the_lock
/datum/unit_test/dq_p2_closet/the_picture_follows_the_lock/run_gate()
	var/obj/structure/closet/secure_closet/C = make(/obj/structure/closet/secure_closet/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2), list(ACCESS_ENGINE))
	var/locked_picture = p2cl_icon(C)
	alt_touch(H, C)
	var/unlocked_picture = p2cl_icon(C)
	TEST_ASSERT_NOTEQUAL(locked_picture, unlocked_picture, "unlocking changes the picture")
	alt_touch(H, C)
	TEST_ASSERT_EQUAL(p2cl_icon(C), locked_picture, "locking brings it back")
	p2cl_set_sealed(C, TRUE)
	TEST_ASSERT_NOTEQUAL(p2cl_icon(C), locked_picture, "welding changes it")
	var/obj/item/card/emag/emag = allocate(/obj/item/card/emag, H.loc)
	p2cl_set_sealed(C, FALSE)
	touch(H, C, emag)
	TEST_ASSERT_NOTEQUAL(p2cl_icon(C), locked_picture, "a broken lock looks different")
	TEST_ASSERT_NOTEQUAL(p2cl_icon(C), unlocked_picture, "from an unlocked one")

/// Opening shows the open picture; closing brings the closed one back.
/datum/unit_test/dq_p2_closet/the_picture_follows_the_door
/datum/unit_test/dq_p2_closet/the_picture_follows_the_door/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/carbon/human/H = person()
	var/shut = p2cl_icon(C)
	open_it(H, C)
	TEST_ASSERT_NOTEQUAL(p2cl_icon(C), shut, "open looks different")
	close_it(H, C)
	TEST_ASSERT_EQUAL(p2cl_icon(C), shut, "closed looks as it did")

// ---------------------------------------------------------------------------------------------------------------------
// Crates
// ---------------------------------------------------------------------------------------------------------------------

/// A crate opens and closes by hand like a closet.
/datum/unit_test/dq_p2_closet/crate_hand_opens_and_closes
/datum/unit_test/dq_p2_closet/crate_hand_opens_and_closes/run_gate()
	var/obj/structure/closet/crate/C = make(/obj/structure/closet/crate)
	var/mob/living/carbon/human/H = person()
	touch(H, C)
	TEST_ASSERT(p2cl_opened(C), "opened")
	touch(H, C)
	TEST_ASSERT(!p2cl_opened(C), "closed")

/// A crate takes objects but never people, and leaves the dense, the anchored and the closets.
/datum/unit_test/dq_p2_closet/crate_takes_objects_not_people
/datum/unit_test/dq_p2_closet/crate_takes_objects_not_people/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/crate/C = make(/obj/structure/closet/crate, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/mob/living/carbon/human/bystander = person(at)
	open_it(H, C)
	var/obj/structure/closet/neighbour = make(/obj/structure/closet, at)
	var/obj/item/pen = probe(at)
	var/obj/item/bolted = probe(at, /obj/item/p2_closet_probe/anchored)
	close_it(H, C)
	TEST_ASSERT_EQUAL(pen.loc, C, "the item went in")
	TEST_ASSERT_EQUAL(bolted.loc, at, "the anchored one stayed")
	TEST_ASSERT_EQUAL(bystander.loc, at, "the person stayed")
	TEST_ASSERT_EQUAL(neighbour.loc, at, "and the closet stayed")

/// A crate counts objects, not sizes: each costs one unit.
/datum/unit_test/dq_p2_closet/crate_counts_objects
/datum/unit_test/dq_p2_closet/crate_counts_objects/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/crate/C = make(/obj/structure/closet/crate, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	p2cl_set_capacity(C, 4)
	open_it(H, C)
	var/list/things = list()
	for(var/i in 1 to 6)
		things += probe(at, /obj/item/p2_closet_probe/large)
	close_it(H, C)
	var/inside = 0
	for(var/obj/item/I as anything in things)
		if(I.loc == C)
			inside++
	TEST_ASSERT_EQUAL(inside, 4, "four units hold four things whatever their size")

/// A crate closes even when something stands in the way of a closet.
/datum/unit_test/dq_p2_closet/crate_closes_with_a_closet_beside_it
/datum/unit_test/dq_p2_closet/crate_closes_with_a_closet_beside_it/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/crate/C = make(/obj/structure/closet/crate, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, C)
	make(/obj/structure/closet, at)
	close_it(H, C)

/// A sealed crate holds fast; resisting from inside breaks it open after two minutes.
/datum/unit_test/dq_p2_closet/crate_welds_shut_and_holds
/datum/unit_test/dq_p2_closet/crate_welds_shut_and_holds/run_gate()
	var/obj/structure/closet/crate/C = make(/obj/structure/closet/crate)
	var/mob/living/carbon/human/H = person()
	var/obj/item/weldingtool/welder = dq_fueled_welder(H.loc)
	touch(H, C, welder)
	TEST_ASSERT(p2cl_sealed(C), "welded")
	touch(H, C)
	TEST_ASSERT(!p2cl_opened(C), "a welded crate does not open")
	touch(H, C, welder)
	TEST_ASSERT(!p2cl_sealed(C), "and the welder frees it")

/// A cable rigs a closed crate, once.
/datum/unit_test/dq_p2_closet/cable_rigs_a_crate
/datum/unit_test/dq_p2_closet/cable_rigs_a_crate/run_gate()
	var/obj/structure/closet/crate/C = make(/obj/structure/closet/crate)
	var/mob/living/carbon/human/H = person()
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, H.loc, 10)
	touch(H, C, coil)
	TEST_ASSERT(p2cl_rigged(C), "the crate is rigged")
	TEST_ASSERT_EQUAL(coil.get_amount(), 9, "using one length")
	touch(H, C, coil)
	TEST_ASSERT_EQUAL(coil.get_amount(), 9, "a second length is not used")

/// Wirecutters cut the rigging away; on a crate that is not rigged they open it.
/datum/unit_test/dq_p2_closet/wirecutters_cut_the_rigging
/datum/unit_test/dq_p2_closet/wirecutters_cut_the_rigging/run_gate()
	var/obj/structure/closet/crate/C = make(/obj/structure/closet/crate)
	var/mob/living/carbon/human/H = person()
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, H.loc, 10)
	touch(H, C, coil)
	var/obj/item/tool/wirecutters/cutters = fast(/obj/item/tool/wirecutters, H.loc)
	touch(H, C, cutters)
	TEST_ASSERT(!p2cl_rigged(C), "the rigging is cut")
	TEST_ASSERT(!p2cl_opened(C), "without opening the crate")
	touch(H, C, cutters)
	TEST_ASSERT(p2cl_opened(C), "on a plain crate the cutters open it")

/// An electropack goes into a rigged crate.
/datum/unit_test/dq_p2_closet/an_electropack_goes_into_a_rigged_crate
/datum/unit_test/dq_p2_closet/an_electropack_goes_into_a_rigged_crate/run_gate()
	var/obj/structure/closet/crate/C = make(/obj/structure/closet/crate)
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/electropack/pack = allocate(/obj/item/radio/electropack, H.loc)
	touch(H, C, pack)
	TEST_ASSERT_NOTEQUAL(pack.loc, C, "an unrigged crate does not take it")
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, H.loc, 10)
	touch(H, C, coil)
	touch(H, C, pack)
	TEST_ASSERT_EQUAL(pack.loc, C, "a rigged crate takes it")

/// An item clicked on an open crate lies on its tile; a grab is not dropped in.
/datum/unit_test/dq_p2_closet/item_on_an_open_crate_lands_on_the_tile
/datum/unit_test/dq_p2_closet/item_on_an_open_crate_lands_on_the_tile/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/crate/C = make(/obj/structure/closet/crate, at)
	var/mob/living/carbon/human/H = person()
	open_it(H, C)
	var/obj/item/pen = probe(H.loc)
	touch(H, C, pen)
	TEST_ASSERT_EQUAL(pen.loc, at, "the item lies on the crate's tile")

/// A freezer crate keeps organs fresh while they are inside.
/datum/unit_test/dq_p2_closet/freezer_crate_preserves_organs
/datum/unit_test/dq_p2_closet/freezer_crate_preserves_organs/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/crate/freezer/C = make(/obj/structure/closet/crate/freezer, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, C)
	var/obj/item/organ/internal/heart/heart = allocate(/obj/item/organ/internal/heart, at)
	close_it(H, C)
	TEST_ASSERT_EQUAL(heart.loc, C, "the organ is in the freezer")
	TEST_ASSERT(heart.preserved, "and is preserved")
	open_it(H, C)
	TEST_ASSERT(!heart.preserved, "it spoils again when it comes out")

/// A large crate takes one big structure standing on its tile when it closes.
/datum/unit_test/dq_p2_closet/large_crate_takes_one_big_thing
/datum/unit_test/dq_p2_closet/large_crate_takes_one_big_thing/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/crate/large/C = make(/obj/structure/closet/crate/large, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, C)
	var/obj/structure/table/one = allocate(/obj/structure/table, at)
	one.set_anchored(FALSE)
	close_it(H, C)
	TEST_ASSERT_EQUAL(one.loc, C, "the loose structure went in")

// ---------------------------------------------------------------------------------------------------------------------
// Secure crates
// ---------------------------------------------------------------------------------------------------------------------

/// A secure crate starts locked; the right ID unlocks it, then a hand opens it.
/datum/unit_test/dq_p2_closet/secure_crate_unlocks_with_the_access
/datum/unit_test/dq_p2_closet/secure_crate_unlocks_with_the_access/run_gate()
	var/obj/structure/closet/crate/secure/C = make(/obj/structure/closet/crate/secure/p2_test)
	var/mob/living/carbon/human/stranger = person(tile(1, 2), list(ACCESS_SECURITY))
	var/mob/living/carbon/human/H = person(tile(3, 2), list(ACCESS_ENGINE))
	TEST_ASSERT(p2cl_locked(C), "starts locked")
	touch(stranger, C)
	TEST_ASSERT(p2cl_locked(C), "a stranger leaves it locked")
	touch(H, C)
	TEST_ASSERT(!p2cl_locked(C), "the right access unlocks it")
	TEST_ASSERT(!p2cl_opened(C), "without opening it")
	touch(H, C)
	TEST_ASSERT(p2cl_opened(C), "the next touch opens it")

/// An item in the hand of an authorised wearer works the crate's lock.
/datum/unit_test/dq_p2_closet/secure_crate_item_works_the_lock
/datum/unit_test/dq_p2_closet/secure_crate_item_works_the_lock/run_gate()
	var/obj/structure/closet/crate/secure/C = make(/obj/structure/closet/crate/secure/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2), list(ACCESS_ENGINE))
	var/obj/item/pen = probe(H.loc)
	touch(H, C, pen)
	TEST_ASSERT(!p2cl_locked(C), "unlocked by an item")
	touch(H, C, pen)
	TEST_ASSERT(p2cl_locked(C), "and locked by it")

/// An alt-click is not the secure crate's lock: its hand toggles, its verb locks.
/datum/unit_test/dq_p2_closet/secure_crate_locked_does_not_open
/datum/unit_test/dq_p2_closet/secure_crate_locked_does_not_open/run_gate()
	var/obj/structure/closet/crate/secure/C = make(/obj/structure/closet/crate/secure/p2_test)
	TEST_ASSERT(!C.open(), "open() refuses a locked crate")
	TEST_ASSERT(!p2cl_opened(C), "shut")

/// An emag breaks a secure crate's lock for good.
/datum/unit_test/dq_p2_closet/secure_crate_emag
/datum/unit_test/dq_p2_closet/secure_crate_emag/run_gate()
	var/obj/structure/closet/crate/secure/C = make(/obj/structure/closet/crate/secure/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/card/emag/emag = allocate(/obj/item/card/emag, H.loc)
	touch(H, C, emag)
	TEST_ASSERT(p2cl_broken(C), "broken")
	TEST_ASSERT(!p2cl_locked(C), "unlocked")
	touch(H, C)
	TEST_ASSERT(p2cl_opened(C), "and it opens")

/// A broken crate lock stays open: nothing locks it.
/datum/unit_test/dq_p2_closet/secure_crate_broken_lock_stays_open
/datum/unit_test/dq_p2_closet/secure_crate_broken_lock_stays_open/run_gate()
	var/obj/structure/closet/crate/secure/C = make(/obj/structure/closet/crate/secure/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2), list(ACCESS_ENGINE))
	var/obj/item/card/emag/emag = allocate(/obj/item/card/emag, H.loc)
	touch(H, C, emag)
	var/obj/item/pen = probe(H.loc)
	touch(H, C, pen)
	TEST_ASSERT(!p2cl_locked(C), "an item does not lock it")

/// An energy blade emags a secure crate.
/datum/unit_test/dq_p2_closet/secure_crate_blade
/datum/unit_test/dq_p2_closet/secure_crate_blade/run_gate()
	var/obj/structure/closet/crate/secure/C = make(/obj/structure/closet/crate/secure/p2_test)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/melee/energy/blade/blade = allocate(/obj/item/melee/energy/blade, H.loc)
	rel_set(blade, nameof(blade.creator), H) // a blade that was not made by the one holding it goes away at once
	touch(H, C, blade)
	TEST_ASSERT(p2cl_broken(C), "the blade broke the lock")

/// A secure crate needs to be locked and sealed to hold someone in; either alone and the push opens... nothing: resisting does nothing.
/datum/unit_test/dq_p2_closet/secure_crate_breakout_needs_lock_and_seal
/datum/unit_test/dq_p2_closet/secure_crate_breakout_needs_lock_and_seal/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/crate/secure/C = make(/obj/structure/closet/crate/secure/p2_test, at)
	var/mob/living/carbon/human/other = person(tile(1, 2), list(ACCESS_ENGINE))
	touch(other, C)
	touch(other, C)
	var/obj/item/p2_closet_probe/pen = probe(at)
	close_it(other, C)
	TEST_ASSERT_EQUAL(pen.loc, C, "the item is in")
	// locked but not sealed: a crate does not hold.
	p2cl_set_locked(C, TRUE)
	p2cl_set_sealed(C, FALSE)
	TEST_ASSERT(!C.req_breakout(), "locked alone does not hold")
	p2cl_set_sealed(C, TRUE)
	TEST_ASSERT(C.req_breakout(), "locked and sealed holds")
	p2cl_set_locked(C, FALSE)
	TEST_ASSERT(!C.req_breakout(), "sealed alone does not")

/// An EMP can spring a secure crate's lock.
/datum/unit_test/dq_p2_closet/secure_crate_emp
/datum/unit_test/dq_p2_closet/secure_crate_emp/run_gate()
	var/obj/structure/closet/crate/secure/C = make(/obj/structure/closet/crate/secure/p2_test)
	C.emp_protection_flags |= EMP_PROTECT_WIRES | EMP_PROTECT_CONTENTS
	test_rng(777)
	var/unlocked = FALSE
	for(var/i in 1 to 300)
		C.emp_act(1)
		settle()
		if(!p2cl_locked(C))
			unlocked = TRUE
			break
	TEST_ASSERT(unlocked, "an EMP unlocks a secure crate sometimes")

// ---------------------------------------------------------------------------------------------------------------------
// The personal locker
// ---------------------------------------------------------------------------------------------------------------------

/// The first card swiped on a personal locker claims it; others are refused.
/datum/unit_test/dq_p2_closet/personal_locker_is_claimed_by_the_first_card
/datum/unit_test/dq_p2_closet/personal_locker_is_claimed_by_the_first_card/run_gate()
	var/obj/structure/closet/secure_closet/personal/C = make(/obj/structure/closet/secure_closet/personal)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/card/id/mine = allocate(/obj/item/card/id, H.loc)
	mine.registered_name = "Alice"
	touch(H, C, mine)
	TEST_ASSERT_EQUAL(p2cl_owner_name(C), "Alice", "the swiper owns it")
	var/was_locked = p2cl_locked(C)
	var/mob/living/carbon/human/other = person(tile(3, 2))
	var/obj/item/card/id/theirs = allocate(/obj/item/card/id, other.loc)
	theirs.registered_name = "Bob"
	touch(other, C, theirs)
	TEST_ASSERT_EQUAL(p2cl_owner_name(C), "Alice", "and still does")
	TEST_ASSERT_EQUAL(p2cl_locked(C), was_locked, "a stranger's card changes nothing")
	touch(H, C, mine)
	TEST_ASSERT_NOTEQUAL(p2cl_locked(C), was_locked, "the owner's card toggles the lock")

/// Reset Lock frees a personal locker for the next card.
/datum/unit_test/dq_p2_closet/personal_locker_resets
/datum/unit_test/dq_p2_closet/personal_locker_resets/run_gate()
	var/obj/structure/closet/secure_closet/personal/C = make(/obj/structure/closet/secure_closet/personal)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/card/id/mine = allocate(/obj/item/card/id, H.loc)
	mine.registered_name = "Alice"
	touch(H, C, mine)
	if(p2cl_locked(C))
		touch(H, C, mine)
	TEST_ASSERT_EQUAL(p2cl_owner_name(C), "Alice", "owned")
	p2cl_personal_reset(C, H)
	settle()
	TEST_ASSERT(p2cl_owner_name(C) == null, "nobody owns it after a reset")
	TEST_ASSERT(p2cl_locked(C), "and it is locked")

/// A mind locker lets only its owner's mind in, and is gone once opened.
/datum/unit_test/dq_p2_closet/mind_locker_is_for_its_owner
/datum/unit_test/dq_p2_closet/mind_locker_is_for_its_owner/run_gate()
	var/mob/living/carbon/human/owner = person(tile(1, 2))
	var/datum/mind/owner_mind = allocate(/datum/mind, "p2 owner")
	owner_mind.transfer_to(owner)
	var/obj/structure/closet/secure_closet/mind/C = allocate(/obj/structure/closet/secure_closet/mind, tile(2, 2), owner_mind)
	var/mob/living/carbon/human/other = person(tile(3, 2))
	TEST_ASSERT(!C.allowed(other), "somebody else is not let in")
	TEST_ASSERT(C.allowed(owner), "the owner is")

// ---------------------------------------------------------------------------------------------------------------------
// Body bags
// ---------------------------------------------------------------------------------------------------------------------

/// A folded bag used in hand unfolds into a body bag on the floor.
/datum/unit_test/dq_p2_closet/folded_bag_unfolds
/datum/unit_test/dq_p2_closet/folded_bag_unfolds/run_gate()
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/bodybag/folded = allocate(/obj/item/bodybag, H.loc)
	hold(H, folded)
	p2cl_click(H, folded, folded)
	settle()
	TEST_ASSERT(QDELETED(folded), "the folded bag is used up")
	var/found = FALSE
	for(var/obj/structure/closet/body_bag/B in H.loc)
		found = TRUE
	TEST_ASSERT(found, "a body bag stands where the person did")

/// A bag takes a person lying on its tile, and an empty one folds up when its owner drags it onto themselves.
/datum/unit_test/dq_p2_closet/bag_folds_up_when_empty
/datum/unit_test/dq_p2_closet/bag_folds_up_when_empty/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/body_bag/B = make(/obj/structure/closet/body_bag, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	p2cl_fold(H, B)
	settle()
	TEST_ASSERT(QDELETED(B), "the bag folded away")
	var/found = FALSE
	for(var/obj/item/bodybag/folded in at)
		found = TRUE
	TEST_ASSERT(found, "a folded bag lies where it stood")

/// A bag with something in it will not fold.
/datum/unit_test/dq_p2_closet/bag_with_contents_will_not_fold
/datum/unit_test/dq_p2_closet/bag_with_contents_will_not_fold/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/body_bag/B = make(/obj/structure/closet/body_bag, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, B)
	probe(at)
	close_it(H, B)
	p2cl_fold(H, B)
	settle()
	TEST_ASSERT(!QDELETED(B), "the bag stays")

/// An open bag will not fold either.
/datum/unit_test/dq_p2_closet/open_bag_will_not_fold
/datum/unit_test/dq_p2_closet/open_bag_will_not_fold/run_gate()
	var/obj/structure/closet/body_bag/B = make(/obj/structure/closet/body_bag)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, B)
	p2cl_fold(H, B)
	settle()
	TEST_ASSERT(!QDELETED(B), "the bag stays")

/// A body bag never blocks the tile, shut or open.
/datum/unit_test/dq_p2_closet/bag_never_blocks
/datum/unit_test/dq_p2_closet/bag_never_blocks/run_gate()
	var/obj/structure/closet/body_bag/B = make(/obj/structure/closet/body_bag)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	TEST_ASSERT(!B.density, "a closed bag does not block")
	open_it(H, B)
	TEST_ASSERT(!B.density, "an open one does not either")
	close_it(H, B)
	TEST_ASSERT(!B.density, "nor after closing")

/// A bag holds one person, not two.
/datum/unit_test/dq_p2_closet/bag_holds_one_person
/datum/unit_test/dq_p2_closet/bag_holds_one_person/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/body_bag/B = make(/obj/structure/closet/body_bag, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, B)
	var/mob/living/carbon/human/one = person(at)
	var/mob/living/carbon/human/two = person(at)
	close_it(H, B)
	var/inside = 0
	if(one.loc == B)
		inside++
	if(two.loc == B)
		inside++
	TEST_ASSERT_EQUAL(inside, 1, "one person fits")

/// The large bag holds a dozen.
/datum/unit_test/dq_p2_closet/large_bag_holds_a_dozen
/datum/unit_test/dq_p2_closet/large_bag_holds_a_dozen/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/body_bag/large/B = make(/obj/structure/closet/body_bag/large, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, B)
	var/list/people = list()
	for(var/i in 1 to 13)
		people += allocate(/mob/living/carbon/human, at)
	close_it(H, B)
	var/inside = 0
	for(var/mob/living/carbon/human/P as anything in people)
		if(P.loc == B)
			inside++
	TEST_ASSERT_EQUAL(inside, 11, "eleven fit (the capacity is one short of a dozen)")

/// A pen labels a bag: the person types the label; wirecutters cut it off.
/datum/unit_test/dq_p2_closet/pen_labels_a_bag
/datum/unit_test/dq_p2_closet/pen_labels_a_bag/run_gate()
	var/obj/structure/closet/body_bag/B = make(/obj/structure/closet/body_bag)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/pen/pen = allocate(/obj/item/pen, H.loc)
	p2cl_click(H, B, pen)
	test_time(1 SECOND)
	p2cl_answer(H, "Bob")
	settle()
	TEST_ASSERT_EQUAL(B.name, "body bag - Bob", "the bag is labelled")
	var/obj/item/tool/wirecutters/cutters = fast(/obj/item/tool/wirecutters, H.loc)
	touch(H, B, cutters)
	TEST_ASSERT_EQUAL(B.name, "body bag", "the cutters take the label off")

/// An empty label leaves the bag as it was.
/datum/unit_test/dq_p2_closet/empty_label_leaves_the_name
/datum/unit_test/dq_p2_closet/empty_label_leaves_the_name/run_gate()
	var/obj/structure/closet/body_bag/B = make(/obj/structure/closet/body_bag)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/pen/pen = allocate(/obj/item/pen, H.loc)
	p2cl_click(H, B, pen)
	test_time(1 SECOND)
	p2cl_answer(H, "")
	settle()
	TEST_ASSERT_EQUAL(B.name, "body bag", "unchanged")

/// A bag can be pushed out of from inside: a person in it who moves opens it (it is never sealed).
/datum/unit_test/dq_p2_closet/occupant_opens_a_bag
/datum/unit_test/dq_p2_closet/occupant_opens_a_bag/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/body_bag/B = make(/obj/structure/closet/body_bag, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, B)
	var/mob/living/carbon/human/victim = person(at)
	close_it(H, B)
	TEST_ASSERT_EQUAL(victim.loc, B, "the person is zipped in")
	p2cl_push(B, victim)
	settle()
	TEST_ASSERT(p2cl_opened(B), "pushing opens the bag")

// ---------------------------------------------------------------------------------------------------------------------
// Stasis bags
// ---------------------------------------------------------------------------------------------------------------------

/// A stasis bag takes only people, and uses itself up when someone is zipped in.
/datum/unit_test/dq_p2_closet/stasis_bag_takes_only_people
/datum/unit_test/dq_p2_closet/stasis_bag_takes_only_people/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/body_bag/cryobag/B = make(/obj/structure/closet/body_bag/cryobag, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, B)
	var/obj/item/pen = probe(at)
	var/mob/living/carbon/human/victim = person(at)
	close_it(H, B)
	TEST_ASSERT_EQUAL(victim.loc, B, "the person is in")
	TEST_ASSERT_EQUAL(pen.loc, at, "the item is left outside")
	TEST_ASSERT(B.used, "the bag is used up")

/// Opening a used stasis bag asks first, and a yes opens it and leaves a used bag behind.
/datum/unit_test/dq_p2_closet/used_stasis_bag_asks_before_opening
/datum/unit_test/dq_p2_closet/used_stasis_bag_asks_before_opening/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/body_bag/cryobag/B = make(/obj/structure/closet/body_bag/cryobag, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, B)
	var/mob/living/carbon/human/victim = person(at)
	close_it(H, B)
	p2cl_click(H, B)
	test_time(1 SECOND)
	TEST_ASSERT(!p2cl_opened(B), "it asks and stays shut")
	p2cl_answer(H, FALSE)
	settle()
	TEST_ASSERT(!p2cl_opened(B), "a no leaves it shut")
	p2cl_click(H, B)
	test_time(1 SECOND)
	p2cl_answer(H, TRUE)
	settle()
	TEST_ASSERT_EQUAL(victim.loc, at, "a yes lets the person out")
	var/found = FALSE
	for(var/obj/item/usedcryobag/U in at)
		found = TRUE
	TEST_ASSERT(found, "and a used bag is left behind")
	TEST_ASSERT(QDELETED(B), "in place of the bag")

/// A fresh stasis bag opens without asking.
/datum/unit_test/dq_p2_closet/fresh_stasis_bag_opens_freely
/datum/unit_test/dq_p2_closet/fresh_stasis_bag_opens_freely/run_gate()
	var/obj/structure/closet/body_bag/cryobag/B = make(/obj/structure/closet/body_bag/cryobag)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	touch(H, B)
	TEST_ASSERT(p2cl_opened(B), "opens")
	touch(H, B)
	TEST_ASSERT(!p2cl_opened(B), "closes")

/// A syringe clicked on a closed stasis bag is loaded; a screwdriver takes it out again while the bag is unused.
/datum/unit_test/dq_p2_closet/stasis_bag_takes_a_syringe
/datum/unit_test/dq_p2_closet/stasis_bag_takes_a_syringe/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/body_bag/cryobag/B = make(/obj/structure/closet/body_bag/cryobag, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/reagent_containers/syringe/syringe = allocate(/obj/item/reagent_containers/syringe, H.loc)
	touch(H, B, syringe)
	TEST_ASSERT_EQUAL(B.syringe, syringe, "the syringe is loaded")
	TEST_ASSERT_NOTEQUAL(syringe.loc, H.loc, "it is out of the person's hands")
	var/obj/item/tool/screwdriver/driver = fast(/obj/item/tool/screwdriver, H.loc)
	touch(H, B, driver)
	TEST_ASSERT_NULL(B.syringe, "the screwdriver took it out")
	TEST_ASSERT_EQUAL(syringe.loc, at, "onto the floor")

/// A folded stasis bag unfolds into a stasis bag, keeping a syringe it carried.
/datum/unit_test/dq_p2_closet/folded_stasis_bag_unfolds
/datum/unit_test/dq_p2_closet/folded_stasis_bag_unfolds/run_gate()
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/bodybag/cryobag/folded = allocate(/obj/item/bodybag/cryobag, H.loc)
	hold(H, folded)
	p2cl_click(H, folded, folded)
	settle()
	var/found = FALSE
	for(var/obj/structure/closet/body_bag/cryobag/B in H.loc)
		found = TRUE
	TEST_ASSERT(found, "a stasis bag stands on the floor")

// ---------------------------------------------------------------------------------------------------------------------
// Coffins and graves
// ---------------------------------------------------------------------------------------------------------------------

/// A coffin is sealed with a screwdriver, not a welder.
/datum/unit_test/dq_p2_closet/coffin_is_screwed_shut
/datum/unit_test/dq_p2_closet/coffin_is_screwed_shut/run_gate()
	var/obj/structure/closet/coffin/C = make(/obj/structure/closet/coffin)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/weldingtool/welder = dq_fueled_welder(H.loc)
	touch(H, C, welder)
	TEST_ASSERT(!p2cl_sealed(C), "a welder does not seal a coffin")
	var/obj/item/tool/screwdriver/driver = fast(/obj/item/tool/screwdriver, H.loc)
	touch(H, C, driver)
	TEST_ASSERT(p2cl_sealed(C), "a screwdriver does")
	touch(H, C)
	TEST_ASSERT(!p2cl_opened(C), "a sealed coffin does not open")
	touch(H, C, driver)
	TEST_ASSERT(!p2cl_sealed(C), "and the screwdriver frees it")

/// A welder still cuts an open coffin apart.
/datum/unit_test/dq_p2_closet/welder_cuts_an_open_coffin_apart
/datum/unit_test/dq_p2_closet/welder_cuts_an_open_coffin_apart/run_gate()
	var/obj/structure/closet/coffin/C = make(/obj/structure/closet/coffin)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/weldingtool/welder = dq_fueled_welder(H.loc)
	open_it(H, C)
	touch(H, C, welder)
	TEST_ASSERT(QDELETED(C), "the coffin is cut apart")

/// A grave starts open; a shovel fills it in (it takes four seconds) and it then holds like a sealed closet.
/datum/unit_test/dq_p2_closet/grave_fills_in_with_a_shovel
/datum/unit_test/dq_p2_closet/grave_fills_in_with_a_shovel/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/grave/G = make(/obj/structure/closet/grave, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/mob/living/carbon/human/victim = person(at)
	TEST_ASSERT(p2cl_opened(G), "a grave starts open")
	var/obj/item/shovel/shovel = allocate(/obj/item/shovel, H.loc)
	p2cl_click(H, G, shovel)
	test_time(2 SECONDS)
	TEST_ASSERT(p2cl_opened(G), "still open after two seconds")
	test_time(10 SECONDS)
	TEST_ASSERT(!p2cl_opened(G), "filled in after the work")
	TEST_ASSERT(p2cl_sealed(G), "and sealed")
	TEST_ASSERT_EQUAL(victim.loc, G, "with the person in it")

/// A shovel unearths a filled grave.
/datum/unit_test/dq_p2_closet/shovel_unearths_a_grave
/datum/unit_test/dq_p2_closet/shovel_unearths_a_grave/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/grave/G = make(/obj/structure/closet/grave, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/mob/living/carbon/human/victim = person(at)
	var/obj/item/shovel/shovel = allocate(/obj/item/shovel, H.loc)
	touch(H, G, shovel)
	test_time(10 SECONDS)
	TEST_ASSERT(!p2cl_opened(G), "filled in")
	touch(H, G, shovel)
	test_time(10 SECONDS)
	TEST_ASSERT(p2cl_opened(G), "dug out again")
	TEST_ASSERT_EQUAL(victim.loc, at, "and the person is out")

/// A grave of nothing disappears when it is smoothed over in combat mode.
/datum/unit_test/dq_p2_closet/smoothing_over_an_empty_grave_removes_it
/datum/unit_test/dq_p2_closet/smoothing_over_an_empty_grave_removes_it/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/grave/G = make(/obj/structure/closet/grave, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/shovel/shovel = allocate(/obj/item/shovel, H.loc)
	touch(H, G, shovel)
	test_time(10 SECONDS)
	TEST_ASSERT(!p2cl_opened(G), "filled in")
	hold(H, shovel)
	H.set_use_stance(I_HURT)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, G, null, "mapwindow.map", "left=1"))
	test_time(10 SECONDS)
	TEST_ASSERT(QDELETED(G), "an empty grave smoothed over is gone")

// ---------------------------------------------------------------------------------------------------------------------
// The emergency wall locker
// ---------------------------------------------------------------------------------------------------------------------

/// An emergency wall locker hands out its supplies twice and then runs dry.
/datum/unit_test/dq_p2_closet/emergency_locker_dispenses_twice
/datum/unit_test/dq_p2_closet/emergency_locker_dispenses_twice/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/walllocker/emerglocker/C = make(/obj/structure/closet/walllocker/emerglocker, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	touch(H, C)
	var/after_one = 0
	for(var/obj/item/tank/emergency/oxygen/T in at)
		after_one++
	TEST_ASSERT_EQUAL(after_one, 1, "one set came out")
	touch(H, C)
	touch(H, C)
	var/after_all = 0
	for(var/obj/item/tank/emergency/oxygen/T in at)
		after_all++
	TEST_ASSERT_EQUAL(after_all, 2, "and a second, then nothing")
	TEST_ASSERT(!p2cl_opened(C), "the locker never opens")

// ---------------------------------------------------------------------------------------------------------------------
// Statues
// ---------------------------------------------------------------------------------------------------------------------

/// A statue holds its person until it is broken, and breaking it frees (and hurts) them.
/datum/unit_test/dq_p2_closet/statue_holds_its_person
/datum/unit_test/dq_p2_closet/statue_holds_its_person/run_gate()
	var/turf/at = tile(2, 2)
	var/mob/living/carbon/human/victim = person(at)
	var/obj/structure/closet/statue/S = allocate(/obj/structure/closet/statue, at, victim)
	TEST_ASSERT_EQUAL(victim.loc, S, "the person is in the statue")
	var/mob/living/carbon/human/H = person(tile(1, 2))
	touch(H, S)
	TEST_ASSERT(!p2cl_opened(S), "a statue does not open")
	TEST_ASSERT_EQUAL(victim.loc, S, "the person is still in it")
	S.release()
	TEST_ASSERT_EQUAL(victim.loc, at, "releasing frees them")
	TEST_ASSERT(QDELETED(S), "and the statue is gone")

/// Eggs are cut open by a welder.
/datum/unit_test/dq_p2_closet/egg_is_cut_open_by_a_welder
/datum/unit_test/dq_p2_closet/egg_is_cut_open_by_a_welder/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/secure_closet/egg/E = make(/obj/structure/closet/secure_closet/egg, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/weldingtool/welder = dq_fueled_welder(H.loc)
	touch(H, E, welder)
	TEST_ASSERT(QDELETED(E), "the egg is gone")

// ---------------------------------------------------------------------------------------------------------------------
// More of the plain closet: a weapon, what lies under it at the start, the people-less wall locker, the hidden verb
// ---------------------------------------------------------------------------------------------------------------------

/// A weapon swung at a closet in combat mode wears it down.
/datum/unit_test/dq_p2_closet/a_weapon_in_combat_mode_hits_the_closet
/datum/unit_test/dq_p2_closet/a_weapon_in_combat_mode_hits_the_closet/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	dq_give_zone_sel(H)
	var/obj/item/tool/crowbar/bar = allocate(/obj/item/tool/crowbar, H.loc)
	bar.force = 40 // enough to get through the sheet metal
	var/before = C.get_integrity()
	p2cl_click(H, C, bar, "left=1", I_HURT)
	settle()
	TEST_ASSERT(C.get_integrity() < before, "the closet took damage")

/// A closet put over loose things on its tile takes them in when it starts.
/datum/unit_test/dq_p2_closet/a_closet_made_over_loose_items_takes_them
/datum/unit_test/dq_p2_closet/a_closet_made_over_loose_items_takes_them/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/item/pen = probe(at)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	settle()
	TEST_ASSERT_EQUAL(pen.loc, C, "the loose item is in the closet")

/// A wall locker takes no people.
/datum/unit_test/dq_p2_closet/a_wall_locker_takes_no_people
/datum/unit_test/dq_p2_closet/a_wall_locker_takes_no_people/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/walllocker/C = make(/obj/structure/closet/walllocker, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	open_it(H, C)
	var/mob/living/carbon/human/bystander = person(at)
	var/obj/item/pen = probe(at)
	close_it(H, C)
	TEST_ASSERT_EQUAL(bystander.loc, at, "the person stays out")
	TEST_ASSERT_EQUAL(pen.loc, C, "the item goes in")

/// A wall locker never blocks the tile, shut or open.
/datum/unit_test/dq_p2_closet/a_wall_locker_never_blocks
/datum/unit_test/dq_p2_closet/a_wall_locker_never_blocks/run_gate()
	var/obj/structure/closet/walllocker/C = make(/obj/structure/closet/walllocker)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	TEST_ASSERT(!C.density, "a wall locker does not block")
	TEST_ASSERT(C.CanPass(H, get_turf(C)), "and lets a person through")
	open_it(H, C)
	TEST_ASSERT(!C.density, "open it does not either")

/// The hidden verb of a closet asks the occupant who to eat, and only offers devourable occupants.
/datum/unit_test/dq_p2_closet/devour_occupants_asks_for_a_victim
/datum/unit_test/dq_p2_closet/devour_occupants_asks_for_a_victim/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/helper = person(tile(1, 2))
	var/mob/living/carbon/human/pred = person(at)
	var/mob/living/carbon/human/prey = person(at)
	prey.devourable = FALSE
	open_it(helper, C)
	pred.forceMove(at)
	prey.forceMove(at)
	close_it(helper, C)
	TEST_ASSERT_EQUAL(pred.loc, C, "the predator is inside")
	p2cl_devour(C, pred)
	test_time(1 SECOND)
	TEST_ASSERT(!p2cl_has_question(pred), "no question while nobody inside can be eaten")
	prey.devourable = TRUE
	p2cl_devour(C, pred)
	test_time(1 SECOND)
	TEST_ASSERT(p2cl_has_question(pred), "the predator is asked whom to eat")

/// Someone outside the closet cannot use it.
/datum/unit_test/dq_p2_closet/devour_occupants_needs_the_user_inside
/datum/unit_test/dq_p2_closet/devour_occupants_needs_the_user_inside/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/helper = person(tile(1, 2))
	var/mob/living/carbon/human/prey = person(at)
	prey.devourable = TRUE
	open_it(helper, C)
	prey.forceMove(at)
	close_it(helper, C)
	p2cl_devour(C, helper)
	test_time(1 SECOND)
	TEST_ASSERT(!p2cl_has_question(helper), "somebody outside is not asked")

// ---------------------------------------------------------------------------------------------------------------------
// Anti-tamper
// ---------------------------------------------------------------------------------------------------------------------

/// A locked crate with the strict anti-tamper blows itself up when a shot would break it.
/datum/unit_test/dq_p2_closet/tamper_proof_crate_goes_off
/datum/unit_test/dq_p2_closet/tamper_proof_crate_goes_off/run_gate()
	var/obj/structure/closet/crate/secure/C = make(/obj/structure/closet/crate/secure/p2_test)
	p2cl_set_tamper_proof(C, 2)
	TEST_ASSERT(p2cl_locked(C), "locked")
	p2cl_shoot(C, 9999)
	settle()
	TEST_ASSERT(QDELETED(C), "the crate is gone")

/// A shot too weak to break it does what shots do.
/datum/unit_test/dq_p2_closet/tamper_proof_crate_survives_a_weak_shot
/datum/unit_test/dq_p2_closet/tamper_proof_crate_survives_a_weak_shot/run_gate()
	var/obj/structure/closet/crate/secure/C = make(/obj/structure/closet/crate/secure/p2_test)
	p2cl_set_tamper_proof(C, 2)
	var/before = C.get_integrity()
	p2cl_shoot(C, 1)
	settle()
	TEST_ASSERT(!QDELETED(C), "the crate is still there")
	TEST_ASSERT(C.get_integrity() < before, "and it took the damage")

/// An unlocked crate has no anti-tamper: the shot wears it down.
/datum/unit_test/dq_p2_closet/unlocked_crate_has_no_anti_tamper
/datum/unit_test/dq_p2_closet/unlocked_crate_has_no_anti_tamper/run_gate()
	var/obj/structure/closet/crate/secure/C = make(/obj/structure/closet/crate/secure/p2_test)
	p2cl_set_tamper_proof(C, 2)
	p2cl_set_locked(C, FALSE)
	var/before = C.get_integrity()
	p2cl_shoot(C, 10)
	settle()
	TEST_ASSERT(!QDELETED(C), "the crate stands")
	TEST_ASSERT(C.get_integrity() < before, "and is damaged")

// ---------------------------------------------------------------------------------------------------------------------
// Wrapping paper
// ---------------------------------------------------------------------------------------------------------------------

/// Package wrap wraps a shut closet or crate into a parcel (and seals a closet inside it); an open one it leaves alone.
/datum/unit_test/dq_p2_closet/wrapping_paper_wraps_a_closed_crate
/datum/unit_test/dq_p2_closet/wrapping_paper_wraps_a_closed_crate/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/crate/C = make(/obj/structure/closet/crate, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/packageWrap/paper = allocate(/obj/item/packageWrap, H.loc)
	touch(H, C, paper)
	TEST_ASSERT(istype(C.loc, /obj/structure/bigDelivery), "the crate is inside a parcel")
	TEST_ASSERT_EQUAL(paper.amount, 22, "three sheets of paper went")

/datum/unit_test/dq_p2_closet/wrapping_paper_seals_a_wrapped_closet
/datum/unit_test/dq_p2_closet/wrapping_paper_seals_a_wrapped_closet/run_gate()
	var/turf/at = tile(2, 2)
	var/obj/structure/closet/C = make(/obj/structure/closet, at)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/packageWrap/paper = allocate(/obj/item/packageWrap, H.loc)
	touch(H, C, paper)
	TEST_ASSERT(istype(C.loc, /obj/structure/bigDelivery), "the closet is inside a parcel")
	TEST_ASSERT(p2cl_sealed(C), "and sealed")
	var/obj/structure/bigDelivery/parcel = C.loc
	parcel.unwrap()
	TEST_ASSERT_EQUAL(C.loc, at, "unwrapping puts it back on the floor")
	TEST_ASSERT(!p2cl_sealed(C), "unsealed")

/datum/unit_test/dq_p2_closet/wrapping_paper_leaves_an_open_closet_alone
/datum/unit_test/dq_p2_closet/wrapping_paper_leaves_an_open_closet_alone/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/carbon/human/H = person(tile(1, 2))
	var/obj/item/packageWrap/paper = allocate(/obj/item/packageWrap, H.loc)
	open_it(H, C)
	touch(H, C, paper)
	TEST_ASSERT(!istype(C.loc, /obj/structure/bigDelivery), "an open closet is not wrapped")
	TEST_ASSERT_EQUAL(paper.amount, 25, "no paper is used")

/// A cyborg opens and closes a closet with no module in hand.
/datum/unit_test/dq_p2_closet/a_cyborg_opens_a_closet
/datum/unit_test/dq_p2_closet/a_cyborg_opens_a_closet/run_gate()
	var/obj/structure/closet/C = make(/obj/structure/closet)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, tile(1, 2))
	R.enable_godmode()
	p2cl_click(R, C, null)
	settle()
	TEST_ASSERT(p2cl_opened(C), "the cyborg opened it")
	p2cl_click(R, C, null)
	settle()
	TEST_ASSERT(!p2cl_opened(C), "and shut it")
