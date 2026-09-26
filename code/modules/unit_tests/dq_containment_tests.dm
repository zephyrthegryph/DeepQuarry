// Containment ledger and slots (roadmap C1, doc/rewrite/containment.md §2-3):
// a conservation fuzz over every migrated holder type, drop policies, slot
// acceptance, capacity, transactions, entry ids and aggregates.

// ---- Fixtures ----

/obj/item/dq_containment_test
	name = "containment test item"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "whetstone"
	w_class = ITEMSIZE_SMALL
	MATERIAL_BULK(MAT_STEEL, 1000)

/obj/item/dq_containment_test/glass
	w_class = ITEMSIZE_NORMAL
	MATERIAL_BULK(MAT_GLASS, 500)

/obj/item/dq_containment_test/wood
	w_class = ITEMSIZE_TINY
	MATERIAL_BULK(MAT_WOOD, 2000)
	sharp = TRUE

/obj/item/dq_containment_test/anchored
	anchored = TRUE

/// A two-slot holder: a sharp-only "main" slot of three things that spills, and
/// a "pocket" that transfers into whatever holds the box.
/obj/item/dq_containment_box
	name = "containment test box"
	w_class = ITEMSIZE_NORMAL

/datum/om/relation/slot/dq_test_main
	holder = /obj/item/dq_containment_box
	slot_id = "main"
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 3
	accepts = /datum/predicate/dq_test_sharp_only
	drop_policy = SLOT_DROP_SPILL

/datum/om/relation/slot/dq_test_pocket
	holder = /obj/item/dq_containment_box
	slot_id = "pocket"
	drop_policy = SLOT_DROP_TRANSFER
	is_default = TRUE

/datum/predicate/dq_test_sharp_only
	name = "sharp only"
	test_only = TRUE
	spec = list(REQ_TAG(PRED_TARGET, TAG_SHARP))

/// Blocks moves through the pre signals and records what the ledger reported.
/datum/dq_containment_listener
	var/block_insert = FALSE
	var/block_remove = FALSE
	var/list/events = list()

/datum/dq_containment_listener/proc/watch(atom/holder)
	RegisterSignal(holder, COMSIG_SLOT_PRE_INSERT, PROC_REF(on_pre_insert))
	RegisterSignal(holder, COMSIG_SLOT_PRE_REMOVE, PROC_REF(on_pre_remove))
	RegisterSignal(holder, COMSIG_SLOT_INSERTED, PROC_REF(on_inserted))
	RegisterSignal(holder, COMSIG_SLOT_REMOVED, PROC_REF(on_removed))

/datum/dq_containment_listener/proc/on_pre_insert(atom/source, atom/movable/thing, slot_id, mob/actor)
	SIGNAL_HANDLER
	return block_insert ? COMPONENT_SLOT_BLOCK : NONE

/datum/dq_containment_listener/proc/on_pre_remove(atom/source, atom/movable/thing, slot_id, mob/actor)
	SIGNAL_HANDLER
	return block_remove ? COMPONENT_SLOT_BLOCK : NONE

/datum/dq_containment_listener/proc/on_inserted(atom/source, atom/movable/thing, slot_id)
	SIGNAL_HANDLER
	events += "in:[slot_id]"

/datum/dq_containment_listener/proc/on_removed(atom/source, atom/movable/thing, slot_id)
	SIGNAL_HANDLER
	events += "out:[slot_id]"

/// An open floor turf with open floor to its east (the test map has no
/// run_loc landmarks).
/datum/unit_test/proc/dq_containment_floor()
	// Earlier tests leave litter; a closet made closed takes in whatever lies on
	// its turf, so look for a clean pair every time.
	for(var/turf/simulated/floor/T in world)
		var/turf/east = get_step(T, EAST)
		if(T.density || !istype(east, /turf/simulated/floor) || east.density)
			continue
		if((locate(/obj/item) in T) || (locate(/obj/structure) in T) || (locate(/mob) in T))
			continue
		if((locate(/obj/item) in east) || (locate(/obj/structure) in east) || (locate(/mob) in east))
			continue
		return T
	return null

/// Fails with every mismatch the ledger's own verification finds.
/datum/unit_test/proc/dq_verify_ledger(atom/holder, label)
	var/datum/ledger/L = dq_ledger(holder)
	if(!L)
		TEST_FAIL("[label]: [holder] has no ledger")
		return FALSE
	var/list/problems = L.verify()
	for(var/problem in problems)
		TEST_FAIL("[label]: [problem]")
	return !length(problems)

// ---- Conservation fuzz ----

/datum/unit_test/dq_containment_conservation_fuzz
	var/list/holders = list()
	var/list/things = list()
	var/list/made = list()
	var/turf/floor
	var/moves_done = 0
	var/moves_refused = 0

/datum/unit_test/dq_containment_conservation_fuzz/Run()
	floor = dq_containment_floor()
	var/list/holder_types = list(/obj/structure/closet, /obj/structure/closet/crate, /obj/item/folder, /obj/item/dq_containment_box, /obj/item/storage/backpack)
	for(var/path in holder_types)
		for(var/i in 1 to 3)
			add_holder(path)
	for(var/i in 1 to 12)
		make_thing(null)
	// Mapped-style contents: made straight inside, adopted without a move.
	for(var/atom/H as anything in holders)
		make_thing(H)

	var/list/op_counts = list()
	for(var/step in 1 to 400)
		var/op = pick(
			20; "insert",
			12; "remove",
			12; "transfer",
			6; "legacy_move",
			6; "create_inside",
			5; "destroy_holder",
			4; "destroy_thing",
			5; "open_close"
		)
		op_counts[op] = (op_counts[op] || 0) + 1
		if(!run_op(op, step))
			break
		if(!check_world("step [step] ([op])"))
			break
	for(var/path in holder_types)
		var/seen = FALSE
		for(var/atom/H as anything in holders)
			if(istype(H, path))
				seen = TRUE
		TEST_ASSERT(seen, "the fuzz kept a [path] alive")
	TEST_NOTICE(src, "ops: [json_encode(op_counts)], moves [moves_done], refused [moves_refused]")
	TEST_ASSERT(moves_done >= 25, "the fuzz exercised real moves ([moves_done])")
	TEST_ASSERT(moves_refused >= 5, "the fuzz exercised refusals ([moves_refused])")

/datum/unit_test/dq_containment_conservation_fuzz/Destroy()
	for(var/datum/D as anything in made)
		if(!QDELETED(D))
			qdel(D)
	made = null
	holders = null
	things = null
	return ..()

/datum/unit_test/dq_containment_conservation_fuzz/proc/add_holder(path)
	var/atom/movable/H = new path(floor)
	made += H
	holders += H
	things += H
	if(istype(H, /obj/structure/closet))
		var/obj/structure/closet/C = H
		C.storage_capacity = istype(C, /obj/structure/closet/crate) ? 6 : 200
	return H

/datum/unit_test/dq_containment_conservation_fuzz/proc/make_thing(atom/where)
	var/path
	if(istype(where, /obj/item/folder))
		path = /obj/item/paper
	else
		path = pick(/obj/item/dq_containment_test, /obj/item/dq_containment_test/glass, /obj/item/dq_containment_test/wood, /obj/item/paper)
	var/atom/movable/T = new path(where || floor)
	made += T
	things += T
	return T

/datum/unit_test/dq_containment_conservation_fuzz/proc/live_holders()
	. = list()
	for(var/atom/H as anything in holders)
		if(!QDELETED(H))
			. += H

/datum/unit_test/dq_containment_conservation_fuzz/proc/run_op(op, step)
	var/list/live = live_holders()
	switch(op)
		if("insert", "transfer", "legacy_move")
			var/atom/movable/T = pick(things)
			var/atom/H = pick(live)
			var/slot = istype(H, /obj/item/dq_containment_box) ? pick("main", "pocket") : null
			var/in_holder = !isturf(T.loc)
			if(op == "transfer" && !in_holder)
				return TRUE
			if(op == "insert" && in_holder)
				return TRUE
			if(op == "legacy_move")
				for(var/atom/A = H; A; A = A.loc)
					if(A == T)
						return TRUE
				T.forceMove(H)
				return TRUE
			var/atom/before = T.loc
			var/why = dq_ledger_refusal(T, H, slot)
			var/moved = (op == "transfer") ? before.slot_transfer(T, H, slot) : T.move_into(H, slot)
			if(moved)
				moves_done++
			else
				moves_refused++
			if(!moved)
				if(T.loc != before)
					TEST_FAIL("step [step]: a refused move ([why]) moved [T] from [before] to [T.loc]")
					return FALSE
				if(!why)
					TEST_FAIL("step [step]: [T] into [H] failed with no reason")
					return FALSE
			else if(T.loc != H)
				TEST_FAIL("step [step]: [T] reported moved into [H] but is in [T.loc]")
				return FALSE
		if("remove")
			var/atom/movable/T = pick(things)
			var/atom/source = T.loc
			if(isturf(source) || !source)
				return TRUE
			if(!source.slot_remove(T, floor))
				TEST_FAIL("step [step]: couldn't remove [T] from [source]")
				return FALSE
			if(T.loc != floor)
				TEST_FAIL("step [step]: removed [T] is in [T.loc]")
				return FALSE
		if("create_inside")
			make_thing(pick(live))
		if("destroy_holder")
			var/atom/movable/H = pick(live)
			if(!destroy_holder(H, step))
				return FALSE
			add_holder(H.type)
		if("destroy_thing")
			var/atom/movable/T = pick(things)
			if(T in holders)
				return TRUE
			things -= T
			qdel(T)
		if("open_close")
			var/list/closets = list()
			for(var/obj/structure/closet/C in live)
				if(isturf(C.loc))
					closets += C
			if(!length(closets))
				return TRUE
			var/obj/structure/closet/C = pick(closets)
			var/list/inside = C.slot_contents(CONTAINER_SLOT_INTERIOR)
			if(!C.open())
				C.close()
				return TRUE
			for(var/atom/movable/T as anything in inside)
				if(!QDELETED(T) && T.loc != C.loc) // stacks may merge on landing
					TEST_FAIL("step [step]: opening [C] left [T] in [T.loc]")
					return FALSE
			C.close()
	return TRUE

/// Destroys a holder and checks each slot's drop policy was applied.
/datum/unit_test/dq_containment_conservation_fuzz/proc/destroy_holder(atom/movable/H, step)
	var/datum/ledger/L = dq_ledger(H)
	var/atom/drop = H.drop_location()
	var/atom/parent = H.loc
	var/list/expected = list()
	for(var/datum/om/relation/slot/def as anything in L.defs)
		for(var/atom/movable/T as anything in H.slot_contents(def.id))
			expected[T] = def.drop_policy
	holders -= H
	things -= H
	qdel(H)
	// A delete policy takes nested holders with it (a folder in a bag).
	for(var/atom/movable/nested as anything in holders.Copy())
		if(QDELETED(nested))
			holders -= nested
			things -= nested
			add_holder(nested.type)
	for(var/atom/movable/T as anything in expected)
		switch(expected[T])
			if(SLOT_DROP_DELETE)
				if(!QDELETED(T))
					TEST_FAIL("step [step]: [T] outlived [H] despite a delete policy")
					return FALSE
				things -= T
				holders -= T
			if(SLOT_DROP_SPILL)
				if(QDELETED(T) || T.loc != drop)
					TEST_FAIL("step [step]: [T] should have spilled to [drop], is [QDELETED(T) ? "deleted" : "in [T.loc]"]")
					return FALSE
			if(SLOT_DROP_TRANSFER)
				if(QDELETED(T) || (T.loc != parent && T.loc != drop))
					TEST_FAIL("step [step]: [T] should have transferred to [parent] or spilled to [drop], is [QDELETED(T) ? "deleted" : "in [T.loc]"]")
					return FALSE
	return TRUE

/// Nothing lost, nothing listed twice, every ledger sound.
/datum/unit_test/dq_containment_conservation_fuzz/proc/check_world(label)
	. = TRUE
	for(var/atom/H as anything in holders)
		if(QDELETED(H))
			TEST_FAIL("[label]: [H] is deleted but still counted as a holder")
			return FALSE
		if(!dq_verify_ledger(H, label))
			. = FALSE
	for(var/atom/movable/T as anything in things.Copy())
		if(QDELETED(T))
			things -= T
			continue
		if(!T.loc)
			TEST_FAIL("[label]: [T] was lost to nullspace")
			return FALSE
		var/listed = 0
		for(var/atom/H as anything in holders)
			if(H.ledger?.entries[T])
				listed++
		var/expect = (T.loc in holders) ? 1 : 0
		if(listed != expect)
			TEST_FAIL("[label]: [T] in [T.loc] is listed by [listed] ledgers, expected [expect]")
			return FALSE

// ---- Drop policies ----

/datum/unit_test/dq_containment_drop_policies

/datum/unit_test/dq_containment_drop_policies/Run()
	var/turf/T = dq_containment_floor()
	// Spill: a closet's contents land where it stood.
	var/obj/structure/closet/closet = allocate(/obj/structure/closet, T)
	var/obj/item/dq_containment_test/a = allocate(/obj/item/dq_containment_test, closet)
	var/obj/item/dq_containment_test/b = allocate(/obj/item/dq_containment_test/glass, closet)
	TEST_ASSERT_EQUAL(length(closet.slot_contents(CONTAINER_SLOT_INTERIOR)), 2, "items made inside are adopted")
	qdel(closet)
	TEST_ASSERT(!QDELETED(a) && a.loc == T, "spill: the first item is on the floor")
	TEST_ASSERT(!QDELETED(b) && b.loc == T, "spill: the second item is on the floor")

	// Delete: a folder takes its pages with it.
	var/obj/item/folder/folder = allocate(/obj/item/folder, T)
	var/obj/item/paper/page = allocate(/obj/item/paper, T)
	TEST_ASSERT(page.move_into(folder), "paper goes in a folder")
	qdel(folder)
	TEST_ASSERT(QDELETED(page), "delete: the page went with the folder")

	// Spill into a holder: a box inside a closet spills its main slot into the
	// closet (the closet allows drops), and transfers its pocket there too.
	var/obj/structure/closet/outer = allocate(/obj/structure/closet, T)
	var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box, T)
	var/obj/item/dq_containment_test/wood/knife = allocate(/obj/item/dq_containment_test/wood, T)
	var/obj/item/dq_containment_test/pocketed = allocate(/obj/item/dq_containment_test, T)
	TEST_ASSERT(knife.move_into(box, "main"), "sharp thing into main")
	TEST_ASSERT(pocketed.move_into(box, "pocket"), "anything into the pocket")
	TEST_ASSERT(box.move_into(outer), "box into closet")
	qdel(box)
	TEST_ASSERT(!QDELETED(pocketed) && pocketed.loc == outer, "transfer: the pocket went into the closet")
	TEST_ASSERT(!QDELETED(knife) && knife.loc == outer, "spill: the main slot dropped into the closet")
	dq_verify_ledger(outer, "after the box was destroyed")

	// Transfer with nowhere to transfer to spills.
	var/obj/item/dq_containment_box/loose_box = allocate(/obj/item/dq_containment_box, T)
	var/obj/item/dq_containment_test/c = allocate(/obj/item/dq_containment_test, T)
	TEST_ASSERT(c.move_into(loose_box, "pocket"), "into the pocket")
	qdel(loose_box)
	TEST_ASSERT(!QDELETED(c) && c.loc == T, "transfer with no holder around falls back to spilling")


// ---- Acceptance, capacity and transactions ----

/datum/unit_test/dq_containment_slot_acceptance

/datum/unit_test/dq_containment_slot_acceptance/Run()
	var/turf/T = dq_containment_floor()
	// Closets first: a closet made closed takes in whatever lies on its turf.
	var/obj/structure/closet/closet = allocate(/obj/structure/closet, T)
	var/obj/structure/closet/crate/crate = allocate(/obj/structure/closet/crate, T)
	var/obj/item/folder/folder = allocate(/obj/item/folder, T)
	var/obj/item/paper/page = allocate(/obj/item/paper, T)
	var/obj/item/dq_containment_test/item = allocate(/obj/item/dq_containment_test, T)

	// The predicate decides, with its reason.
	TEST_ASSERT_EQUAL(dq_ledger_refusal(item, folder), "only paper, photos and bundles fit", "folder refuses a non-paper item")
	TEST_ASSERT(!item.move_into(folder), "the refused move fails")
	TEST_ASSERT_EQUAL(item.loc, T, "a refused move changes nothing")
	TEST_ASSERT_NULL(dq_ledger_refusal(page, folder), "paper fits")
	TEST_ASSERT(page.move_into(folder), "paper goes in")
	TEST_ASSERT_EQUAL(dq_ledger_refusal(page, folder), "it is already there", "no double insert")

	// Closets refuse what is fastened down.
	var/obj/item/dq_containment_test/anchored/bolted = allocate(/obj/item/dq_containment_test/anchored, T)
	TEST_ASSERT_EQUAL(dq_ledger_refusal(bolted, closet), "it is fastened down", "anchored things stay out")

	// Capacity: a crate holds storage_capacity objects.
	crate.storage_capacity = 2
	var/obj/item/dq_containment_test/one = allocate(/obj/item/dq_containment_test, T)
	var/obj/item/dq_containment_test/two = allocate(/obj/item/dq_containment_test, T)
	var/obj/item/dq_containment_test/three = allocate(/obj/item/dq_containment_test, T)
	TEST_ASSERT(one.move_into(crate) && two.move_into(crate), "two fit")
	TEST_ASSERT_EQUAL(crate.slot_used(), 2, "two units used")
	TEST_ASSERT_EQUAL(dq_ledger_refusal(three, crate), "there's no room for it", "the third doesn't")
	TEST_ASSERT_EQUAL(three.loc, T, "and stays put")

	// Box: a multi-slot holder. Main takes sharp things, three at most.
	var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box, T)
	TEST_ASSERT_EQUAL(dq_ledger_refusal(item, box, "main"), "must be sharp", "main is sharp-only")
	TEST_ASSERT_NULL(dq_ledger_refusal(item, box), "the default slot is the pocket")
	TEST_ASSERT_EQUAL(dq_ledger_refusal(item, box, "lid"), "[box] has no lid", "unknown slot")

	// Nothing goes inside itself.
	TEST_ASSERT(box.move_into(closet), "box into closet")
	TEST_ASSERT_EQUAL(dq_ledger_refusal(closet, box), "it can't go inside itself", "closet into the box it holds")
	TEST_ASSERT_EQUAL(dq_ledger_refusal(closet, closet), "it can't go inside itself", "closet into itself")

	// Moving between two slots of one holder.
	var/obj/item/dq_containment_test/wood/knife = allocate(/obj/item/dq_containment_test/wood, T)
	TEST_ASSERT(knife.move_into(box, "pocket"), "knife into the pocket")
	var/pocket_id = box.slot_entry_id(knife)
	TEST_ASSERT(knife.move_into(box, "main"), "knife from pocket to main")
	TEST_ASSERT_EQUAL(knife.loc, box, "still in the box")
	var/list/main = box.slot_contents("main")
	TEST_ASSERT(length(main) == 1 && main[1] == knife, "listed in main")
	TEST_ASSERT_EQUAL(length(box.slot_contents("pocket")), 0, "pocket is empty")
	TEST_ASSERT_NULL(box.slot_find_entry(pocket_id), "the pocket entry id is stale")
	TEST_ASSERT_EQUAL(box.slot_find_entry(box.slot_entry_id(knife)), knife, "the new id finds it")

	// Pre signals block, and a block leaves everything in place.
	var/datum/dq_containment_listener/listener = allocate(/datum/dq_containment_listener)
	listener.watch(crate)
	listener.block_remove = TRUE
	TEST_ASSERT(!crate.slot_remove(one, T), "a blocked removal fails")
	TEST_ASSERT_EQUAL(one.loc, crate, "and leaves it inside")
	TEST_ASSERT_EQUAL(dq_ledger_refusal(one, folder), "it won't come out", "both sides are checked before anything moves")
	listener.block_remove = FALSE
	TEST_ASSERT(crate.slot_remove(one, T), "unblocked removal")
	listener.block_insert = TRUE
	TEST_ASSERT_EQUAL(dq_ledger_refusal(three, crate), "it won't go in", "a blocked insert")
	TEST_ASSERT(!three.move_into(crate), "and the move fails")
	listener.block_insert = FALSE
	TEST_ASSERT(three.move_into(crate), "room again")
	TEST_ASSERT_EQUAL(jointext(listener.events, ","), "out:[CONTAINER_SLOT_INTERIOR],in:[CONTAINER_SLOT_INTERIOR]", "inserted and removed signals")

	// Legacy moves are still accounted for, in the default slot.
	var/obj/item/dq_containment_test/legacy = allocate(/obj/item/dq_containment_test, T)
	legacy.forceMove(box)
	var/list/pocket = box.slot_contents("pocket")
	TEST_ASSERT(length(pocket) == 1 && pocket[1] == legacy, "forceMove lands in the default slot")
	dq_verify_ledger(box, "after a legacy move")

	// Closets end to end: close scoops the floor within capacity, open dumps.
	// On a turf of its own, since a closet won't close next to other closets.
	var/turf/B = get_step(T, EAST)
	var/obj/structure/closet/locker = allocate(/obj/structure/closet, B)
	locker.open()
	locker.storage_capacity = 2
	var/obj/item/dq_containment_test/small1 = allocate(/obj/item/dq_containment_test, B)
	var/obj/item/dq_containment_test/small2 = allocate(/obj/item/dq_containment_test, B)
	var/obj/item/dq_containment_test/small3 = allocate(/obj/item/dq_containment_test, B)
	locker.close()
	var/inside = (small1.loc == locker) + (small2.loc == locker) + (small3.loc == locker)
	TEST_ASSERT_EQUAL(inside, 2, "close stores up to storage_capacity")
	locker.open()
	TEST_ASSERT(small1.loc == B && small2.loc == B && small3.loc == B, "open dumps everything")
	dq_verify_ledger(locker, "after open")

// ---- Aggregates ----

/datum/unit_test/dq_containment_aggregates

/datum/unit_test/dq_containment_aggregates/Run()
	var/turf/T = dq_containment_floor()
	var/obj/structure/closet/closet = allocate(/obj/structure/closet, T)
	var/obj/item/dq_containment_test/steel = allocate(/obj/item/dq_containment_test, T)
	var/obj/item/dq_containment_test/wood/wood = allocate(/obj/item/dq_containment_test/wood, T)
	var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box, T)

	TEST_ASSERT_NULL(closet.contents_property(PROP_MASS), "empty: no mass")
	TEST_ASSERT(steel.move_into(closet), "steel in")
	TEST_ASSERT_EQUAL(closet.contents_property(PROP_MASS), PROPERTY(steel, PROP_MASS), "mass is the item's")
	TEST_ASSERT_NOTNULL(closet.contents_property(PROP_HEAT_CAPACITY), "heat capacity from steel")
	TEST_ASSERT(!closet.contents_has_tag(TAG_SHARP), "nothing sharp yet")

	// Nested: wood goes in a box, the box in the closet. The closet sees both.
	TEST_ASSERT(box.move_into(closet), "box in")
	TEST_ASSERT(wood.move_into(box, "main"), "wood into the box inside the closet")
	var/expected_mass = PROPERTY(steel, PROP_MASS) + PROPERTY(wood, PROP_MASS)
	TEST_ASSERT(abs(closet.contents_property(PROP_MASS) - expected_mass) < 1e-6, "nested mass rolls up: [closet.contents_property(PROP_MASS)] vs [expected_mass]")
	TEST_ASSERT(closet.contents_has_tag(TAG_SHARP), "a sharp thing in a nested box counts")
	TEST_ASSERT(closet.contents_has_tag(TAG_FLAMMABLE), "wood is flammable")
	var/wood_ignition = PROPERTY(wood, PROP_IGNITION_POINT)
	TEST_ASSERT_NOTNULL(wood_ignition, "wood has an ignition point")
	TEST_ASSERT_EQUAL(closet.contents_property(PROP_IGNITION_POINT), wood_ignition, "minimum threshold is the wood's")
	var/steel_melt = PROPERTY(steel, PROP_MELTING_POINT)
	var/wood_melt = PROPERTY(wood, PROP_MELTING_POINT)
	var/expected_min_melt = isnull(wood_melt) ? steel_melt : min(steel_melt, wood_melt)
	TEST_ASSERT_EQUAL(closet.contents_property(PROP_MELTING_POINT), expected_min_melt, "lowest melting point")
	dq_verify_ledger(closet, "nested")

	// Removing from the inner holder updates the outer one.
	TEST_ASSERT(box.slot_remove(wood, T), "wood out of the box")
	TEST_ASSERT_EQUAL(closet.contents_property(PROP_MASS), PROPERTY(steel, PROP_MASS), "mass drops back")
	TEST_ASSERT(!closet.contents_has_tag(TAG_SHARP), "the sharp flag clears")
	TEST_ASSERT_NULL(closet.contents_property(PROP_IGNITION_POINT), "no ignition point left")
	TEST_ASSERT_EQUAL(closet.contents_property(PROP_MELTING_POINT), steel_melt, "the minimum recomputes when the lowest leaves")
	dq_verify_ledger(closet, "after removal")

	// Entry ids are stable while a thing stays, and stale once it leaves.
	var/id = closet.slot_entry_id(steel)
	TEST_ASSERT_NOTNULL(id, "steel has an entry id")
	TEST_ASSERT_EQUAL(closet.slot_find_entry(id), steel, "the id finds it")
	TEST_ASSERT(closet.slot_remove(steel, T), "steel out")
	TEST_ASSERT(steel.move_into(closet), "and back in")
	TEST_ASSERT_NULL(closet.slot_find_entry(id), "the old id is stale")
	TEST_ASSERT_NOTEQUAL(closet.slot_entry_id(steel), id, "a new id")

	// The serializer numbers children in ledger order.
	var/list/order = state_children(closet)
	var/datum/ledger/L = dq_ledger(closet)
	TEST_ASSERT_EQUAL(jointext(order, ","), jointext(L.ordered(), ","), "state children follow the ledger")
	TEST_ASSERT_EQUAL(order[length(order)], steel, "the re-inserted item is numbered last")

// ---- J2: spill and transfer are real ledger transactions ----

/datum/unit_test/dq_containment_j2_forced_spill

/datum/unit_test/dq_containment_j2_forced_spill/Run()
	var/turf/T = dq_containment_floor()
	var/obj/structure/closet/closet = allocate(/obj/structure/closet, T)
	var/obj/item/dq_containment_test/steel = allocate(/obj/item/dq_containment_test, T)
	closet.open()
	TEST_ASSERT(steel.move_into(closet), "steel in")
	closet.close()

	// A blocked pre-remove would normally refuse the move; the forced spill
	// must not be refusable, so it still leaves.
	var/datum/dq_containment_listener/listener = allocate(/datum/dq_containment_listener)
	listener.watch(closet)
	listener.block_remove = TRUE
	listener.block_insert = TRUE
	qdel(closet)
	TEST_ASSERT(QDELETED(closet), "closet with a blocking listener still deletes")
	TEST_ASSERT_EQUAL(steel.loc, T, "steel spilled to the drop location despite the blocks")
	TEST_ASSERT_EQUAL(jointext(listener.events, ","), "out:[CONTAINER_SLOT_INTERIOR]", "the forced move still fires the commit signals")

/datum/unit_test/dq_containment_j2_forced_transfer

/datum/unit_test/dq_containment_j2_forced_transfer/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_containment_box/outer = allocate(/obj/item/dq_containment_box, T)
	var/obj/item/dq_containment_box/inner = allocate(/obj/item/dq_containment_box, T)
	TEST_ASSERT(inner.move_into(outer, "pocket"), "the inner box into the outer one's pocket")
	var/obj/item/dq_containment_test/wood/knife = allocate(/obj/item/dq_containment_test/wood, T)
	// "pocket" is the slot with SLOT_DROP_TRANSFER; "main" spills instead.
	TEST_ASSERT(knife.move_into(inner, "pocket"), "knife into the inner box's transferring slot")
	TEST_ASSERT_EQUAL(inner.loc, outer, "the inner box is inside the outer one")
	qdel(inner)
	TEST_ASSERT_EQUAL(knife.loc, outer, "SLOT_DROP_TRANSFER moved the knife into the outer box's default slot")
	dq_verify_ledger(outer, "after a forced transfer")

// ---- J4: keyed slots ----

/// A single keyed slot: unlimited capacity, keyed on the item's name.
/obj/item/dq_containment_test/keyed
	name = "keyed test item"

/obj/item/dq_containment_test/keyed/slot_key()
	return name

/obj/item/dq_containment_keyring
	name = "keyring"
	w_class = ITEMSIZE_NORMAL

/datum/om/relation/slot/dq_test_keyed
	holder = /obj/item/dq_containment_keyring
	slot_id = "keyed"
	is_default = TRUE
	keyed = TRUE

/datum/unit_test/dq_containment_j4_keyed_slots

/datum/unit_test/dq_containment_j4_keyed_slots/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_containment_keyring/ring = allocate(/obj/item/dq_containment_keyring, T)
	var/obj/item/dq_containment_test/keyed/red = allocate(/obj/item/dq_containment_test/keyed, T)
	red.name = "red key"
	var/obj/item/dq_containment_test/keyed/red2 = allocate(/obj/item/dq_containment_test/keyed, T)
	red2.name = "red key"
	var/obj/item/dq_containment_test/keyed/blue = allocate(/obj/item/dq_containment_test/keyed, T)
	blue.name = "blue key"

	TEST_ASSERT(red.move_into(ring), "the first red key goes in")
	TEST_ASSERT_EQUAL(ring.slot_lookup("keyed", "red key"), red, "O(1) lookup finds it by key")
	TEST_ASSERT_EQUAL(dq_ledger_refusal(red2, ring), "[red] already has that", "a duplicate key is refused")
	TEST_ASSERT(!red2.move_into(ring), "and the move fails")
	TEST_ASSERT(blue.move_into(ring), "an unrelated key still goes in")
	dq_verify_ledger(ring, "with two distinct keys")

	// Rekeying: renaming red frees its old key and claims the new one.
	red.name = "renamed key"
	red.ledger_rekey()
	TEST_ASSERT_NULL(ring.slot_lookup("keyed", "red key"), "the old key is gone")
	TEST_ASSERT_EQUAL(ring.slot_lookup("keyed", "renamed key"), red, "the new key resolves")
	TEST_ASSERT(red2.move_into(ring), "the freed key can be reused by another thing")
	dq_verify_ledger(ring, "after a rekey")

	// Leaving frees the key.
	TEST_ASSERT(ring.slot_remove(blue, T), "blue leaves")
	TEST_ASSERT_NULL(ring.slot_lookup("keyed", "blue key"), "its key is freed")
	dq_verify_ledger(ring, "after a removal")

// ---- J6: thing-side commit hooks ----

/obj/item/dq_containment_test/hooked
	name = "hooked test item"
	has_slot_hooks = TRUE
	sharp = TRUE // so it can enter the box's sharp-only "main" slot too
	var/list/log = list()

/obj/item/dq_containment_test/hooked/on_slotted(atom/holder, slot_id)
	log += "on:[holder]:[slot_id]"

/obj/item/dq_containment_test/hooked/on_unslotted(atom/holder, slot_id)
	log += "off:[holder]:[slot_id]"

/datum/unit_test/dq_containment_j6_commit_hooks

/datum/unit_test/dq_containment_j6_commit_hooks/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box, T)
	var/obj/item/dq_containment_test/hooked/thing = allocate(/obj/item/dq_containment_test/hooked, T)
	var/obj/item/dq_containment_test/plain = allocate(/obj/item/dq_containment_test, T)

	TEST_ASSERT(thing.move_into(box, "pocket"), "into the pocket")
	TEST_ASSERT_EQUAL(jointext(thing.log, ","), "on:[box]:pocket", "on_slotted fires on insert")

	thing.log.Cut()
	TEST_ASSERT(thing.move_into(box, "main"), "reslot from pocket to the sharp-only main slot")
	TEST_ASSERT_EQUAL(jointext(thing.log, ","), "off:[box]:pocket,on:[box]:main", "reslot fires leave-then-enter, on the same move")

	thing.log.Cut()
	TEST_ASSERT(box.slot_remove(thing, T), "out of the box entirely")
	TEST_ASSERT_EQUAL(jointext(thing.log, ","), "off:[box]:main", "on_unslotted fires on removal")

	// A type that never overrides the hooks (has_slot_hooks stays FALSE)
	// pays no proc call: nothing to observe, but this must not runtime.
	TEST_ASSERT(plain.move_into(box, "pocket"), "an unhooked item moves normally")
	TEST_ASSERT(box.slot_remove(plain, T), "and leaves normally")

// ---- J8: slot_item ----

/datum/unit_test/dq_containment_j8_slot_item

/datum/unit_test/dq_containment_j8_slot_item/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box, T)
	TEST_ASSERT_NULL(box.slot_item("pocket"), "empty slot: null")
	var/obj/item/dq_containment_test/wood/knife = allocate(/obj/item/dq_containment_test/wood, T)
	TEST_ASSERT(knife.move_into(box, "main"), "knife into main")
	TEST_ASSERT_EQUAL(box.slot_item("main"), knife, "slot_item returns the one thing in it")
	var/obj/item/dq_containment_test/wood/knife2 = allocate(/obj/item/dq_containment_test/wood, T)
	TEST_ASSERT(knife2.move_into(box, "main"), "a second sharp item into main")
	TEST_ASSERT_EQUAL(box.slot_item("main"), knife, "slot_item still returns the first (insertion order)")
	TEST_ASSERT_NULL(box.slot_item("lid"), "an unknown slot: null, not a runtime")

