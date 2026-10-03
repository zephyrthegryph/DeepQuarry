// The gate of the slots and inventory step (doc/rewrite/final_api.html, sections 6, 8, 10, 11): real slot moves scope while_slotted entries, a species
// grants hands() and its other entries through the relation scope, the held, worn and bagged item are providers or carried, slot_transfer() runs
// the remove and insert actions, a type-level every() runs, and on_change watches the far var of a relation hop. Fixtures: code/tests/engine/s1_fixtures.dm.

/datum/unit_test/dq_s1
	abstract_type = /datum/unit_test/dq_s1

/datum/unit_test/dq_s1/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_s1/proc/run_gate()
	return

/// How many of `M`'s providers (held `held`) give every bit of `aff`.
/datum/unit_test/dq_s1/proc/providers_giving(mob/M, aff, obj/item/held = null)
	. = 0
	for(var/datum/prov/V as anything in providers_for(M, held))
		if((V.aff() & aff) == aff)
			.++

// ---------------------------------------------------------------------------------------------------------------------
// 1. Real slot moves: every kind of move scopes the entries, and nothing else does.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_s1/ledger_moves_scope_while_slotted

/datum/unit_test/dq_s1/ledger_moves_scope_while_slotted/run_gate()
	var/turf/T = test_floor()
	var/obj/s1_fixture/rack/rack = allocate(/obj/s1_fixture/rack, T)
	var/obj/item/s1_fixture/gizmo/gizmo = allocate(/obj/item/s1_fixture/gizmo, T)
	TEST_ASSERT_EQUAL(s1_strike(rack), 10, "an empty rack hooks nothing")
	TEST_ASSERT_EQUAL(s1_strike(gizmo), 10, "a loose gizmo has no occupant hook")
	// move_into: the item's hook lands on the holder, the holder's on the item.
	TEST_ASSERT(gizmo.move_into(rack, "s1_main"), "the gizmo goes into the main slot")
	TEST_ASSERT_EQUAL(s1_strike(rack), 11, "ON_HOLDER: the rack has the gizmo's +1 while it is in s1_main")
	TEST_ASSERT_EQUAL(s1_strike(gizmo), 14, "ON_CONTENTS: the gizmo has the rack's +4 while it is in s1_main")
	// A move to another slot of the same holder (reslot) ends both.
	TEST_ASSERT(gizmo.move_into(rack, "s1_side"), "and on to the side slot")
	TEST_ASSERT_EQUAL(s1_strike(rack), 10, "reslot out of s1_main: the rack is unhooked")
	TEST_ASSERT_EQUAL(s1_strike(gizmo), 10, "and so is the gizmo")
	TEST_ASSERT(gizmo.move_into(rack, "s1_main"), "back into main (a reslot into it)")
	TEST_ASSERT_EQUAL(s1_strike(rack), 11, "reslot into s1_main: hooked again")
	// slot_remove.
	TEST_ASSERT(rack.slot_remove(gizmo, T), "taken out to the floor")
	TEST_ASSERT_EQUAL(s1_strike(rack), 10, "slot_remove: unhooked")
	TEST_ASSERT_EQUAL(s1_strike(gizmo), 10, "slot_remove: the gizmo too")
	// A legacy forceMove lands in the default slot (main) and the ledger adopts it.
	gizmo.forceMove(rack)
	TEST_ASSERT_EQUAL(s1_strike(rack), 11, "a legacy forceMove into the default slot hooks the rack")
	// Deleted while slotted.
	qdel(gizmo)
	TEST_ASSERT_EQUAL(s1_strike(rack), 10, "a deleted gizmo leaves nothing behind")

/datum/unit_test/dq_s1/equip_and_unequip_scope_while_slotted

/datum/unit_test/dq_s1/equip_and_unequip_scope_while_slotted/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/s1_fixture/charm/charm = allocate(/obj/item/s1_fixture/charm, test_floor())
	var/obj/item/s1_fixture/torch/torch = allocate(/obj/item/s1_fixture/torch, test_floor())
	TEST_ASSERT_EQUAL(s1_strike(H), 10, "a bare human hooks nothing")
	// Held: a charm (worn gear) does nothing in a hand, a torch (held gear) works.
	TEST_ASSERT(H.equip_to_slot_if_possible(charm, SLOT_ID_HAND_R, disable_warning = TRUE), "the charm is picked up")
	TEST_ASSERT_EQUAL(s1_strike(H), 10, "SLOT_ANY_WORN does not match a hand")
	TEST_ASSERT(H.unEquip(charm, TRUE), "dropped again")
	TEST_ASSERT(H.equip_to_slot_if_possible(torch, SLOT_ID_HAND_L, disable_warning = TRUE), "the torch is picked up")
	TEST_ASSERT_EQUAL(s1_strike(H), 13, "SLOT_ANY_HELD: +3 while it is in a hand")
	TEST_ASSERT(H.unEquip(torch, TRUE), "the torch is dropped")
	TEST_ASSERT_EQUAL(s1_strike(H), 10, "dropped: gone in the same step")
	// Worn.
	TEST_ASSERT(H.equip_to_slot_if_possible(charm, SLOT_ID_BELT, disable_warning = TRUE), "the charm goes on the belt")
	TEST_ASSERT_EQUAL(s1_strike(H), 12, "SLOT_ANY_WORN: +2 while it is worn")
	TEST_ASSERT(H.unEquip(charm, TRUE), "taken off")
	TEST_ASSERT_EQUAL(s1_strike(H), 10, "taken off: gone")

/datum/unit_test/dq_s1/belly_insert_and_release_scope_contents

/datum/unit_test/dq_s1/belly_insert_and_release_scope_contents/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/pred = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/prey = allocate(/mob/living/carbon/human, T)
	var/obj/belly/s1_test/one = allocate(/obj/belly/s1_test, pred)
	var/obj/belly/s1_test/two = allocate(/obj/belly/s1_test, pred)
	TEST_ASSERT_EQUAL(s1_strike(prey), 10, "free prey is unhooked")
	TEST_ASSERT(prey.move_into(one, BELLY_SLOT_INTERIOR), "swallowed")
	TEST_ASSERT_EQUAL(s1_strike(prey), 15, "the belly's +5 while inside")
	TEST_ASSERT(one.slot_transfer(prey, two, BELLY_SLOT_INTERIOR), "passed to the second belly")
	TEST_ASSERT_EQUAL(s1_strike(prey), 15, "still inside a belly of that type")
	TEST_ASSERT(two.slot_remove(prey, T), "released")
	TEST_ASSERT_EQUAL(s1_strike(prey), 10, "released: the belly's hook is gone")

// ---------------------------------------------------------------------------------------------------------------------
// 2. hands() through the species, and what else a species declares; the body gates it.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_s1/species_grants_hands_and_other_entries

/datum/unit_test/dq_s1/species_grants_hands_and_other_entries/run_gate()
	var/mob/living/simple_mob/s1_fixture/M = allocate(/mob/living/simple_mob/s1_fixture, test_floor())
	var/datum/s1_species/brawler/brawler = new
	var/datum/s1_species/blob/blob = new
	TEST_ASSERT_EQUAL(providers_giving(M, AFF_MANIPULATE), 0, "a mob with no species has no hands")
	rel_set(M, nameof(M.species), brawler)
	TEST_ASSERT_EQUAL(providers_giving(M, AFF_MANIPULATE | AFF_ATTACK | AFF_HOLD), 1, "the brawler species grants hands()")
	TEST_ASSERT_EQUAL(s1_strike(M), 16, "and its other entries (a hook) with them")
	var/gen = provider_gen_of(M)
	rel_set(M, nameof(M.species), blob)
	TEST_ASSERT_EQUAL(providers_giving(M, AFF_MANIPULATE), 0, "a species that declares nothing takes the hands away in the same step")
	TEST_ASSERT_EQUAL(s1_strike(M), 10, "and the hook")
	TEST_ASSERT(provider_gen_of(M) != gen, "the provider set generation moved with the species")
	rel_set(M, nameof(M.species), brawler)
	TEST_ASSERT_EQUAL(providers_giving(M, AFF_MANIPULATE), 1, "back to brawler: hands again")
	rel_clear(M, nameof(M.species))
	TEST_ASSERT_EQUAL(providers_giving(M, AFF_MANIPULATE), 0, "no species: no hands")
	qdel(brawler)
	qdel(blob)

/datum/unit_test/dq_s1/hands_follow_the_body

/datum/unit_test/dq_s1/hands_follow_the_body/run_gate()
	var/mob/living/simple_mob/s1_fixture_handless/M = allocate(/mob/living/simple_mob/s1_fixture_handless, test_floor())
	var/datum/s1_species/brawler/brawler = new
	rel_set(M, nameof(M.species), brawler)
	TEST_ASSERT_EQUAL(providers_giving(M, AFF_MANIPULATE), 0, "a body that cannot hold anything gets no hands from its species")
	qdel(brawler)
	// A real human: the species of every carbon mob grants hands; losing both hands drops the provider and bumps the generation.
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(providers_giving(H, AFF_MANIPULATE | AFF_ATTACK | AFF_HOLD) >= 1, "a human has hands from its species")
	H.hands_refresh()
	var/gen = provider_gen_of(H)
	var/obj/item/organ/external/left = H.get_organ(BP_L_HAND)
	var/obj/item/organ/external/right = H.get_organ(BP_R_HAND)
	left.droplimb(clean = TRUE, disintegrate = DROPLIMB_EDGE)
	TEST_ASSERT(providers_giving(H, AFF_MANIPULATE) >= 1, "one hand left: still hands")
	right.droplimb(clean = TRUE, disintegrate = DROPLIMB_EDGE)
	TEST_ASSERT_EQUAL(providers_giving(H, AFF_MANIPULATE), 0, "no hand left: the provider is gone")
	TEST_ASSERT(provider_gen_of(H) != gen, "limb loss bumped the provider set generation")
	qdel(left)
	qdel(right)

// ---------------------------------------------------------------------------------------------------------------------
// 3. Providers and carried().
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_s1/held_and_worn_items_provide

/datum/unit_test/dq_s1/held_and_worn_items_provide/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/s1_fixture/spear/spear = allocate(/obj/item/s1_fixture/spear, test_floor())
	var/obj/item/s1_fixture/gauntlet/gauntlet = allocate(/obj/item/s1_fixture/gauntlet, test_floor())
	var/base_attack = providers_giving(H, AFF_ATTACK)
	TEST_ASSERT_EQUAL(providers_giving(H, AFF_ATTACK, spear), base_attack + 1, "the held spear is one more provider")
	var/datum/prov/best = null
	for(var/datum/prov/V as anything in providers_for(H, spear))
		if(V.source == spear)
			best = V
	TEST_ASSERT_NOTNULL(best, "its provider names the spear as the source")
	TEST_ASSERT_EQUAL(best.reach(), 2, "with its own reach")
	var/datum/prov/chosen = reach_pick_provider(providers_for(H, spear), spear)
	TEST_ASSERT_EQUAL(chosen.source, spear, "the held item's provider performs the op before the hand")
	TEST_ASSERT_EQUAL(providers_giving(H, AFF_ATTACK), base_attack, "not held: no spear provider")
	// Worn: its provider is the wearer's while it is worn.
	var/manip = providers_giving(H, AFF_MANIPULATE)
	var/gen = provider_gen_of(H)
	TEST_ASSERT(H.equip_to_slot_if_possible(gauntlet, SLOT_ID_BELT, disable_warning = TRUE), "the gauntlet is worn")
	TEST_ASSERT_EQUAL(providers_giving(H, AFF_MANIPULATE), manip + 1, "worn: the gauntlet provides")
	TEST_ASSERT(provider_gen_of(H) != gen, "wearing it moved the provider set generation")
	TEST_ASSERT(H.unEquip(gauntlet, TRUE), "taken off")
	TEST_ASSERT_EQUAL(providers_giving(H, AFF_MANIPULATE), manip, "taken off: it provides no more")

/datum/unit_test/dq_s1/carried_covers_held_worn_and_bagged

/datum/unit_test/dq_s1/carried_covers_held_worn_and_bagged/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/s1_fixture/trinket/item = allocate(/obj/item/s1_fixture/trinket, T)
	var/obj/item/storage/box/box = allocate(/obj/item/storage/box, T)
	var/obj/item/storage/box/outer = allocate(/obj/item/storage/box, T)
	var/datum/act/op/A = take(/datum/act/op)
	A.actor = H
	A.target = item
	var/datum/entry/part/req/carried/R = carried()
	TEST_ASSERT(!R.holds(A), "on the floor: not carried")
	TEST_ASSERT(H.equip_to_slot_if_possible(item, SLOT_ID_HAND_R, disable_warning = TRUE), "picked up")
	TEST_ASSERT(R.holds(A), "held: carried")
	TEST_ASSERT(H.unEquip(item, TRUE, box), "put into the box")
	TEST_ASSERT(!R.holds(A), "in a box on the floor: not carried")
	TEST_ASSERT(H.equip_to_slot_if_possible(box, SLOT_ID_HAND_L, disable_warning = TRUE), "the box is picked up")
	TEST_ASSERT(R.holds(A), "bagged in a held box: carried")
	TEST_ASSERT(H.unEquip(box, TRUE, outer), "the box goes into another box")
	TEST_ASSERT(!R.holds(A), "two boxes down on the floor: not carried")
	TEST_ASSERT(H.equip_to_slot_if_possible(outer, SLOT_ID_BELT, disable_warning = TRUE) || H.equip_to_slot_if_possible(outer, SLOT_ID_HAND_R, disable_warning = TRUE), "the outer box is carried")
	TEST_ASSERT(R.holds(A), "bagged two deep in something carried: carried")
	A.release()

// ---------------------------------------------------------------------------------------------------------------------
// slot_transfer(): the remove and insert actions with their hooks, an actor, and an admin authority to force.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_s1/slot_transfer_runs_both_actions

/datum/unit_test/dq_s1/slot_transfer_runs_both_actions/run_gate()
	var/turf/T = test_floor()
	var/obj/s1_fixture/rack/rack = allocate(/obj/s1_fixture/rack, T)
	var/obj/s1_fixture/picky/picky = allocate(/obj/s1_fixture/picky, T)
	var/obj/item/s1_fixture/gizmo/gizmo = allocate(/obj/item/s1_fixture/gizmo, T)
	var/obj/item/s1_fixture/trinket/trinket = allocate(/obj/item/s1_fixture/trinket, T)
	var/mob/living/carbon/human/steward = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(gizmo.move_into(rack, "s1_main"), "setup: the gizmo is in the rack")
	TEST_ASSERT(trinket.move_into(rack, "s1_side"), "setup: the trinket too")
	// The insert needs() of the receiving holder refuses a trinket; the remove never ended committed.
	var/datum/act_plan/picky_plan = act_plan_for(picky, /datum/act/insert)
	TEST_ASSERT_EQUAL(length(picky_plan.needs), 2, "the picky rack has two insert needs hooks")
	TEST_ASSERT(!rack.slot_transfer(trinket, picky), "the picky rack takes only gizmos (landed in [trinket.loc], reason [GLOB.act_last_reason])")
	TEST_ASSERT_EQUAL(trinket.loc, rack, "refused: nothing moved")
	TEST_ASSERT_EQUAL(GLOB.act_last_reason, /datum/msg/s1/no_trinkets, "the reason is the requirement's")
	TEST_ASSERT_EQUAL(rack.removed_heard, 0, "a refused transfer publishes no removal")
	TEST_ASSERT_EQUAL(picky.inserted_heard, 0, "and no insertion")
	// A gizmo is right, but only the steward may.
	picky.steward = steward
	TEST_ASSERT(!rack.slot_transfer(gizmo, picky), "no actor: the steward's rule refuses")
	TEST_ASSERT(!rack.slot_transfer(gizmo, picky, null, allocate(/mob/living/carbon/human, T)), "another actor: refused")
	TEST_ASSERT_EQUAL(gizmo.loc, rack, "still in the rack")
	TEST_ASSERT(rack.slot_transfer(gizmo, picky, null, steward), "the steward moves it")
	TEST_ASSERT_EQUAL(gizmo.loc, picky, "it moved")
	TEST_ASSERT_EQUAL(rack.removed_heard, 1, "the rack heard the removal")
	TEST_ASSERT_EQUAL(picky.inserted_heard, 1, "the picky rack heard the insertion")
	TEST_ASSERT_EQUAL(s1_strike(rack), 10, "the move ended the rack-side scope")
	// The source's own remove needs() (welded) refuses a transfer out of it as well.
	picky.welded = TRUE
	var/obj/s1_fixture/rack/second = allocate(/obj/s1_fixture/rack, T)
	TEST_ASSERT(!picky.slot_transfer(gizmo, second, null, steward), "welded in: the remove is refused")
	TEST_ASSERT_EQUAL(gizmo.loc, picky, "still there")
	// Forced: an admin authority skips the requirements and the ledger's refusals but still runs the actions and their notices.
	picky.steward = null
	var/obj/item/s1_fixture/gizmo/other = allocate(/obj/item/s1_fixture/gizmo, T)
	TEST_ASSERT(trinket.move_into(rack, "s1_side") || trinket.loc == rack, "setup")
	TEST_ASSERT(!picky.slot_transfer(gizmo, second, null, steward, AUTH_PHYSICAL), "an ordinary authority forces nothing")
	var/removed_before = picky.removed_heard
	TEST_ASSERT(picky.slot_transfer(gizmo, second, null, steward, AUTH_ADMIN), "AUTH_ADMIN forces it out of the welded rack")
	TEST_ASSERT_EQUAL(gizmo.loc, second, "it moved")
	TEST_ASSERT_EQUAL(picky.removed_heard, removed_before + 1, "the removal notice still went out")
	// Into a full one-slot picky rack, past the insert needs() and the capacity.
	picky.welded = FALSE
	TEST_ASSERT(other.move_into(picky), "fill the picky rack's one place")
	TEST_ASSERT(!rack.slot_transfer(trinket, picky), "full and picky: refused")
	TEST_ASSERT(rack.slot_transfer(trinket, picky, null, null, AUTH_ADMIN), "forced past needs() and capacity")
	TEST_ASSERT_EQUAL(trinket.loc, picky, "the trinket is in")
	TEST_ASSERT_EQUAL(picky.slot_used(null), 2, "over capacity: the ledger took it")

// ---------------------------------------------------------------------------------------------------------------------
// 4. Type-level every().
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_s1/type_level_every_runs

/datum/unit_test/dq_s1/type_level_every_runs/run_gate()
	var/obj/s1_fixture/ticker/fast/F = allocate(/obj/s1_fixture/ticker/fast, test_floor())
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(F.ticks, 3, "every(1 SECOND) ran three times in three seconds")
	TEST_ASSERT_EQUAL(F.last_dt, 1 SECOND, "A.dt is the interval")
	TEST_ASSERT(F.last_holder_was_me && F.last_source_was_me, "A.holder and A.source are the instance")
	TEST_ASSERT_EQUAL(F.slow_ticks, 0, "the gated every(when = powered) did not run while unpowered")
	TEST_ASSERT_EQUAL(F.fast_ticks, 3 SECONDS / 5, "a subtype's own every() runs beside the parent's")
	F.powered = TRUE
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(F.slow_ticks, 2, "powered: the gated work resumes at its own cadence")
	TEST_ASSERT_EQUAL(F.ticks, 7, "the ungated one never stopped")
	var/ticks = F.ticks
	qdel(F)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(ticks, 7, "(a deleted instance runs nothing: no runtime)")

// ---------------------------------------------------------------------------------------------------------------------
// 5. on_change across a relation hop.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_s1/on_change_watches_the_far_var

/datum/unit_test/dq_s1/on_change_watches_the_far_var/run_gate()
	var/turf/T = test_floor()
	var/obj/s1_fixture/terminal/one = allocate(/obj/s1_fixture/terminal, T)
	var/obj/s1_fixture/terminal/two = allocate(/obj/s1_fixture/terminal, T)
	var/obj/s1_fixture/meter/M = allocate(/obj/s1_fixture/meter, T)
	rel_set(M, nameof(M.terminal), one)
	test_drain()
	var/base = M.changes_seen
	one.set_charge(5)
	test_drain()
	TEST_ASSERT_EQUAL(M.changes_seen, base + 1, "the far var's own change fired the hook")
	TEST_ASSERT_EQUAL(M.seen_charge, 5, "and it read the new value")
	one.set_charge(6)
	one.set_charge(7)
	test_drain()
	TEST_ASSERT_EQUAL(M.changes_seen, base + 2, "two writes before the drain: one run")
	TEST_ASSERT_EQUAL(M.seen_charge, 7, "with the last value")
	// Rewriting the relation still fires (the far value differs), and the old end no longer reaches the meter.
	rel_set(M, nameof(M.terminal), two)
	test_drain()
	TEST_ASSERT_EQUAL(M.changes_seen, base + 3, "the relation rewrite re-read the far var")
	one.set_charge(9)
	test_drain()
	TEST_ASSERT_EQUAL(M.changes_seen, base + 3, "a write on the old far end is not the meter's business")
	two.set_charge(4)
	test_drain()
	TEST_ASSERT_EQUAL(M.changes_seen, base + 4, "the new far end is watched")
	// A hook granted at runtime watches the same way and stops with its activation.
	var/obj/s1_fixture/bare_meter/B = allocate(/obj/s1_fixture/bare_meter, T)
	rel_set(B, nameof(B.terminal), one)
	var/datum/capability/hook/def = hook_capability_of(list(on_change("terminal.charge", ANY, then(TYPE_PROC_REF(/obj/s1_fixture/bare_meter, charge_changed)))), FALSE)
	TEST_ASSERT_NOTNULL(grant(B, def, source = src), "granted")
	one.set_charge(20)
	test_drain()
	TEST_ASSERT_EQUAL(B.changes_seen, 1, "an activation's hook sees the far var change")
	revoke(B, def, source = src)
	one.set_charge(21)
	test_drain()
	TEST_ASSERT_EQUAL(B.changes_seen, 1, "revoked: it does not")
