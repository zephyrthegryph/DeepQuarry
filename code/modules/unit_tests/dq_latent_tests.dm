// Latent contents (roadmap C5, doc/rewrite/containment.md §4): generators,
// entries, materialize, collapse, drop policies, blasts, slot-aware state, and
// parity for every rolled-out holder type: materialize(serialize(x)) == x,
// the same contents after open, and the same outcome on destroy.

/// Pens and paper are latent-safe; the containment test item is not.
/obj/structure/closet/dq_latent_test
	starts_with = list(
		/obj/item/pen = 2,
		/obj/item/paper = 1,
		/obj/item/dq_containment_test = 1,
	)

/// "path=count;..." of the things directly in `where`, sorted.
/proc/dq_latent_census(atom/where, list/only)
	var/list/counts = list()
	for(var/atom/movable/thing as anything in where.contents)
		if(only && !(thing in only))
			continue
		if(!isitem(thing))
			continue
		counts["[thing.type]"] = (counts["[thing.type]"] || 0) + 1
	var/list/keys = list()
	for(var/key in counts)
		keys += key
	sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
	. = list()
	for(var/key in keys)
		. += "[key]=[counts[key]]"
	return jointext(., ";")

/// Items on `T` that weren't there in `before`.
/proc/dq_latent_new_items(turf/T, list/before)
	. = list()
	for(var/obj/item/I in T)
		if(!(I in before))
			. += I

/datum/unit_test/dq_latent_closet_declared

/datum/unit_test/dq_latent_closet_declared/Run()
	for(var/obj/item/I in test_floor())
		qdel(I)
	var/obj/structure/closet/dq_latent_test/closet = allocate(/obj/structure/closet/dq_latent_test, test_floor())
	// Declared: only the type that can't be latent exists, and nothing is resolved.
	TEST_ASSERT_EQUAL(length(closet.contents), 1, "only the non-latent item should be real")
	TEST_ASSERT(isnull(closet.ledger), "an untouched closet should have no ledger")
	TEST_ASSERT(closet.has_latent(), "the closet should hold declared contents")
	// Resolved on the first exact question, still with no atoms.
	TEST_ASSERT_EQUAL(closet.latent_count(), 3, "three latent things")
	TEST_ASSERT_EQUAL(length(closet.contents), 1, "resolving creates nothing")
	var/datum/ledger/L = closet.ledger
	var/list/problems = L.verify()
	TEST_ASSERT(!length(problems), "ledger mismatch: [jointext(problems, "; ")]")
	var/expected_used = 0
	for(var/atom/movable/thing as anything in closet.contents)
		expected_used += closet.storage_cost_of(thing)
	expected_used += 2 * closet.storage_cost_of_type(/obj/item/pen) + closet.storage_cost_of_type(/obj/item/paper)
	TEST_ASSERT_EQUAL(closet.slot_used(CONTAINER_SLOT_INTERIOR), expected_used, "entries take capacity")
	var/mass = closet.contents_property(PROP_MASS)
	var/expected_mass = (dq_type_property(/obj/item/pen, PROP_MASS) || 0) * 2 + (dq_type_property(/obj/item/paper, PROP_MASS) || 0) + (dq_property(closet.contents[1], PROP_MASS) || 0)
	TEST_ASSERT(abs((mass || 0) - expected_mass) < 1e-4, "mass counts entries by type: [mass] vs [expected_mass]")
	// Opening materializes everything onto the turf.
	var/turf/T = closet.loc
	var/list/before = T.contents.Copy()
	closet.open()
	var/list/spilled = dq_latent_new_items(T, before)
	TEST_ASSERT_EQUAL(dq_latent_census(T, spilled), "/obj/item/dq_containment_test=1;/obj/item/paper=1;/obj/item/pen=2", "opened contents")
	TEST_ASSERT_EQUAL(closet.latent_count(), 0, "nothing latent after opening")
	for(var/obj/item/I as anything in spilled)
		qdel(I)

/// Materializing is a ledger move: an entry never yields more than its count,
/// and a stale id is refused.
/datum/unit_test/dq_latent_materialize_once

/datum/unit_test/dq_latent_materialize_once/Run()
	var/obj/structure/closet/dq_latent_test/closet = allocate(/obj/structure/closet/dq_latent_test, test_floor())
	var/list/entries = closet.latent_entries()
	var/datum/latent_entry/pens
	for(var/datum/latent_entry/entry as anything in entries)
		if(entry.path == /obj/item/pen)
			pens = entry
	TEST_ASSERT(pens, "a pen entry")
	var/old_id = pens.entry_id()
	var/list/made = closet.latent_materialize(pens, 5)
	TEST_ASSERT_EQUAL(length(made), 2, "only two pens exist")
	TEST_ASSERT(isnull(closet.ledger.latent_find(old_id)), "the old id is stale")
	TEST_ASSERT_EQUAL(length(closet.latent_materialize(pens, 1)), 0, "a spent entry yields nothing")
	for(var/obj/item/pen/P as anything in made)
		TEST_ASSERT_EQUAL(P.loc, closet, "materialized into the holder")
		TEST_ASSERT_EQUAL(closet.ledger.entries[P][LEDGER_E_SLOT], CONTAINER_SLOT_INTERIOR, "into the entry's slot")
	var/list/problems = closet.ledger.verify()
	TEST_ASSERT(!length(problems), "ledger mismatch: [jointext(problems, "; ")]")

/// Collapse: a plain pen goes back into an entry; a referenced one stays real.
/datum/unit_test/dq_latent_collapse

/datum/unit_test/dq_latent_collapse/Run()
	var/obj/structure/closet/closet = allocate(/obj/structure/closet, test_floor())
	var/obj/item/pen/pen = new(closet)
	pen.name = "labelled pen"
	var/refusal = pen.latent_collapse_refusal()
	TEST_ASSERT(!refusal, "a plain pen should collapse: [refusal]")
	TEST_ASSERT(pen.latent_collapse(), "a plain pen should collapse: [GLOB.latent_last_refusal]")
	TEST_ASSERT(QDELETED(pen), "the collapsed pen is gone")
	TEST_ASSERT_EQUAL(closet.latent_count(), 1, "one latent pen")
	var/list/made = closet.latent_materialize_all()
	TEST_ASSERT_EQUAL(length(made), 1, "it comes back")
	var/obj/item/pen/back = made[1]
	TEST_ASSERT_EQUAL(back.name, "labelled pen", "with its state")
	var/datum/dq_state_holder/holder = new
	holder.held = back
	TEST_ASSERT(!back.latent_collapse(), "a referenced pen stays real")
	qdel(holder)
	// Only latent holders take entries.
	var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box)
	var/obj/item/pen/loose = new(box)
	TEST_ASSERT(!loose.latent_collapse(), "a box without latent contents keeps real things")

/// Parity: materialize(serialize(x)) == x for closets holding entries, and the
/// copy opens to the same contents.
/datum/unit_test/dq_latent_closet_round_trip

/datum/unit_test/dq_latent_closet_round_trip/Run()
	for(var/obj/item/I in test_floor())
		qdel(I)
	var/obj/structure/closet/dq_latent_test/closet = allocate(/obj/structure/closet/dq_latent_test, test_floor())
	var/obj/item/pen/marked = new(closet)
	marked.name = "marked pen"
	var/refusal = marked.latent_collapse_refusal()
	TEST_ASSERT(!refusal, "collapse refused: [refusal]")
	TEST_ASSERT(marked.latent_collapse(), "collapse the marked pen: [GLOB.latent_last_refusal]")
	var/list/errors = list()
	var/list/blob = state_serialize(closet, STATE_FULL, errors)
	TEST_ASSERT(blob, "serialize: [jointext(errors, "; ")]")
	TEST_ASSERT(length(blob[STATE_KEY_LATENT]), "the blob carries the entries")
	var/expected = state_canonical(blob)
	for(var/pass in 1 to 2)
		var/list/source = pass == 1 ? blob : json_decode(json_encode(blob))
		errors = list()
		var/obj/structure/closet/copy = state_materialize(source, test_floor(), STATE_FULL, errors)
		TEST_ASSERT(copy, "materialize: [jointext(errors, "; ")]")
		TEST_ASSERT_EQUAL(dq_state_canonical_of(copy, errors), expected, "round trip [pass] changed the closet")
		TEST_ASSERT_EQUAL(copy.latent_count(), closet.latent_count(), "same latent count")
		var/turf/T = copy.loc
		var/list/before = T.contents.Copy()
		copy.open()
		var/list/spilled = dq_latent_new_items(T, before)
		TEST_ASSERT_EQUAL(dq_latent_census(T, spilled), "/obj/item/dq_containment_test=1;/obj/item/paper=1;/obj/item/pen=3", "copy opens to the same contents")
		for(var/obj/item/I as anything in spilled)
			qdel(I)
		qdel(copy)

/// Slot assignment survives the serializer (C1 left holders with several slots
/// reloading into the default slot).
/datum/unit_test/dq_latent_slot_round_trip

/datum/unit_test/dq_latent_slot_round_trip/Run()
	var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box)
	var/obj/item/dq_containment_test/wood/sharp = new(test_floor())
	TEST_ASSERT(sharp.move_into(box, "main"), "into the main slot")
	new /obj/item/dq_containment_test(box) // default slot: pocket
	var/list/errors = list()
	var/list/blob = state_serialize(box, STATE_FULL, errors)
	TEST_ASSERT(blob, "serialize: [jointext(errors, "; ")]")
	var/obj/item/dq_containment_box/copy = state_materialize(json_decode(json_encode(blob)), test_floor(), STATE_FULL, errors)
	TEST_ASSERT(copy, "materialize: [jointext(errors, "; ")]")
	TEST_ASSERT_EQUAL(length(copy.slot_contents("main")), 1, "one thing back in main")
	TEST_ASSERT_EQUAL(length(copy.slot_contents("pocket")), 1, "one thing back in the pocket")
	TEST_ASSERT_EQUAL(state_canonical(state_serialize(copy, STATE_FULL)), state_canonical(blob), "same state")
	qdel(copy)

/// Destroying a holder: latent contents come out the same as real ones would.
/datum/unit_test/dq_latent_destroy_parity

/datum/unit_test/dq_latent_destroy_parity/Run()
	var/turf/T = test_floor()
	// A fresh closet swallows loose items on its turf; clear them first.
	for(var/obj/item/I in T)
		qdel(I)
	var/obj/structure/closet/dq_latent_test/latent = new(T)
	var/obj/structure/closet/dq_latent_test/real = new(T)
	real.latent_materialize_all()
	TEST_ASSERT_EQUAL(real.latent_count(), 0, "the reference closet is all real")
	TEST_ASSERT(latent.latent_count() > 0, "the latent closet holds entries")
	var/list/before = T.contents.Copy()
	qdel(latent)
	var/list/from_latent = dq_latent_new_items(T, before)
	before = T.contents.Copy()
	qdel(real)
	var/list/from_real = dq_latent_new_items(T, before)
	TEST_ASSERT_EQUAL(dq_latent_census(T, from_latent), dq_latent_census(T, from_real), "destroy spills the same things")
	TEST_ASSERT_EQUAL(dq_latent_census(T, from_latent), "/obj/item/dq_containment_test=1;/obj/item/paper=1;/obj/item/pen=2", "destroy spills the generator")
	for(var/obj/item/I as anything in from_latent + from_real)
		qdel(I)
	// Nested in another latent holder, spilled entries stay data.
	var/obj/structure/closet/outer = new(T)
	var/obj/structure/closet/dq_latent_test/inner = new(T)
	TEST_ASSERT(inner.move_into(outer), "a closet fits in a closet")
	var/real_items = length(outer.contents)
	qdel(inner)
	TEST_ASSERT_EQUAL(outer.latent_count(), 3, "entries moved into the outer closet as data")
	TEST_ASSERT_EQUAL(length(outer.contents), real_items, "only the real item spilled as an atom")
	qdel(outer)

/// Blasts resolve entries as data, matching what the same things do for real.
/datum/unit_test/dq_latent_blast_parity

/datum/unit_test/dq_latent_blast_parity/Run()
	for(var/severity in 1 to 3)
		var/obj/structure/closet/dq_latent_test/latent = allocate(/obj/structure/closet/dq_latent_test, test_floor())
		var/obj/structure/closet/dq_latent_test/real = allocate(/obj/structure/closet/dq_latent_test, test_floor())
		var/list/made = real.latent_materialize_all()
		latent.latent_blast(severity)
		for(var/obj/item/I as anything in made)
			I.ex_act(severity)
		var/list/survivors_real = list()
		for(var/obj/item/I in real)
			if(I in made)
				survivors_real += I
		var/list/survived = latent.latent_materialize_all()
		TEST_ASSERT_EQUAL(dq_latent_census(latent, survived), dq_latent_census(real, survivors_real), "severity [severity]: same survivors")

/// Every closet type with a generator: resolving and opening gives what the
/// old starts_with spawn gave, and each serializes and round-trips.
/datum/unit_test/dq_latent_closet_types

/datum/unit_test/dq_latent_closet_types/Run()
	var/list/failures = list()
	var/tested = 0
	var/unserializable = 0
	var/turf/T = test_floor()
	for(var/obj/item/I in T)
		qdel(I)
	for(var/path in subtypesof(/obj/structure/closet))
		if(is_abstract(path) || ispath(path, /obj/structure/closet/dq_latent_test))
			continue
		var/obj/structure/closet/closet = new path(T)
		if(QDELETED(closet))
			continue
		if(!closet.has_latent())
			for(var/atom/movable/thing as anything in closet.contents)
				if(!ismob(thing))
					qdel(thing)
			qdel(closet)
			continue
		tested++
		var/list/generator = closet.latent_generator()
		generator = generator?.Copy()
		// Parity of what C5 changed: the latent entries and the real children's
		// types. Real children that don't serialize (radios, guns) predate C5.
		var/list/errors = list()
		var/list/blob = state_serialize(closet, STATE_FULL, errors)
		if(!blob)
			unserializable++
		else
			var/obj/structure/closet/copy = state_materialize(json_decode(json_encode(blob)), T, STATE_FULL, errors)
			if(!copy)
				failures += "[path]: did not materialize: [jointext(errors, "; ")]"
			else
				var/list/copy_blob = state_serialize(copy, STATE_FULL)
				if(dq_latent_census(closet) != dq_latent_census(copy))
					failures += "[path]: real contents changed: [dq_latent_census(closet)] vs [dq_latent_census(copy)]"
				for(var/atom/movable/thing as anything in copy.contents)
					if(!ismob(thing))
						qdel(thing)
				if(state_canonical(list("l" = blob[STATE_KEY_LATENT])) != state_canonical(list("l" = copy_blob?[STATE_KEY_LATENT])))
					failures += "[path]: latent entries changed in the round trip"
				qdel(copy)
		var/list/problems = closet.ledger?.verify()
		if(length(problems))
			failures += "[path]: [jointext(problems, "; ")]"
		closet.latent_materialize_all()
		if(islist(generator))
			for(var/item_path in generator)
				if(ispath(item_path, /obj/random))
					continue
				var/want = dq_latent_spawn_count(generator[item_path])
				var/have = 0
				for(var/atom/movable/thing as anything in closet.contents)
					if(thing.type == item_path)
						have++
				if(have < want)
					failures += "[path]: [item_path] [have] of [want]"
		for(var/atom/movable/thing as anything in closet.contents)
			if(!ismob(thing))
				qdel(thing)
		qdel(closet)
		for(var/obj/item/I in T)
			qdel(I)
	TEST_ASSERT(tested > 0, "no latent closets found")
	log_test("dq_latent_closet_types: [tested] latent closet types, [unserializable] hold real things that don't serialize")
	if(length(failures))
		TEST_FAIL("[length(failures)] problem(s) across [tested] closet types:\n[jointext(failures, "\n")]")

// ---- Step 2: mapped storage ----

/obj/item/storage/box/dq_latent_test
	starts_with = list(
		/obj/item/pen = list(2),
		/obj/item/paper = list(1),
		/obj/item/dq_containment_test = list(1),
	)

/obj/structure/closet/dq_latent_storage_test
	starts_with = list(/obj/item/storage/box/dq_latent_test = 2)

/// A mapped box keeps its latent-safe contents as data until used, and using
/// it gives the same contents the old spawn did.
/datum/unit_test/dq_latent_storage_declared

/datum/unit_test/dq_latent_storage_declared/Run()
	var/obj/item/storage/box/dq_latent_test/box = allocate(/obj/item/storage/box/dq_latent_test, test_floor())
	TEST_ASSERT_EQUAL(length(box.contents), 1, "only the non-latent item is real")
	TEST_ASSERT(box.has_latent(), "the rest is declared")
	TEST_ASSERT(box.max_storage_space >= dq_type_storage_cost(/obj/item/pen) * 2 + dq_type_storage_cost(/obj/item/paper), "sized for its declared contents")
	var/list/errors = list()
	var/list/blob = state_serialize(box, STATE_FULL, errors)
	TEST_ASSERT(blob, "serialize: [jointext(errors, "; ")]")
	var/obj/item/storage/box/copy = state_materialize(json_decode(json_encode(blob)), test_floor(), STATE_FULL, errors)
	TEST_ASSERT(copy, "materialize: [jointext(errors, "; ")]")
	TEST_ASSERT_EQUAL(state_canonical(state_serialize(copy, STATE_FULL)), state_canonical(blob), "round trip")
	box.make_contents_real()
	copy.make_contents_real()
	TEST_ASSERT_EQUAL(dq_latent_census(box), "/obj/item/dq_containment_test=1;/obj/item/paper=1;/obj/item/pen=2", "used box contents")
	TEST_ASSERT_EQUAL(dq_latent_census(copy), dq_latent_census(box), "the copy holds the same")
	qdel(copy)

/// Picking a box up makes its contents real, so mob inventory code sees them.
/datum/unit_test/dq_latent_storage_pickup

/datum/unit_test/dq_latent_storage_pickup/Run()
	var/obj/item/storage/box/dq_latent_test/box = allocate(/obj/item/storage/box/dq_latent_test, test_floor())
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(H.put_in_active_hand(box), "picked up")
	TEST_ASSERT(!box.has_latent(), "nothing latent once held")
	TEST_ASSERT_EQUAL(length(box.contents), 4, "all four things are real")

/// Boxes as entries in a closet: nothing exists until the closet opens, then
/// the boxes come out with their own contents declared.
/datum/unit_test/dq_latent_storage_in_closet

/datum/unit_test/dq_latent_storage_in_closet/Run()
	var/turf/T = test_floor()
	for(var/obj/item/I in T)
		qdel(I)
	var/obj/structure/closet/dq_latent_storage_test/closet = allocate(/obj/structure/closet/dq_latent_storage_test, T)
	TEST_ASSERT_EQUAL(length(closet.contents), 0, "the boxes are latent")
	var/list/before = T.contents.Copy()
	closet.open()
	var/list/spilled = dq_latent_new_items(T, before)
	TEST_ASSERT_EQUAL(dq_latent_census(T, spilled), "/obj/item/storage/box/dq_latent_test=2", "two boxes come out")
	for(var/obj/item/storage/box/dq_latent_test/box in spilled)
		box.make_contents_real()
		TEST_ASSERT_EQUAL(dq_latent_census(box), "/obj/item/dq_containment_test=1;/obj/item/paper=1;/obj/item/pen=2", "each box holds its contents")
		qdel(box)

// ---- Step 3: lights ----

/// A fixture holds its bulb and emergency cell as data; making them real gives
/// the same bulb and cell an eager fixture would have had.
/datum/unit_test/dq_latent_light_parts

/datum/unit_test/dq_latent_light_parts/Run()
	var/obj/machinery/light/L = allocate(/obj/machinery/light, test_floor())
	TEST_ASSERT(L.latent_bulb, "a new fixture's bulb is latent")
	TEST_ASSERT(isnull(L.installed_light), "no bulb atom yet")
	var/expect_cell = L.start_with_cell && !L.no_emergency
	TEST_ASSERT_EQUAL(!!L.has_cell(), !!expect_cell, "the cell is declared")
	TEST_ASSERT(isnull(L.cell), "no cell atom yet")
	for(var/atom/movable/thing as anything in L.contents)
		TEST_ASSERT(!istype(thing, /obj/item/light) && !istype(thing, /obj/item/cell), "no parts in contents: [thing.type]")
	var/latent_charge = L.latent_cell_charge
	L.status = LIGHT_BURNED
	L.switchcount = 7
	var/obj/item/light/B = L.bulb()
	TEST_ASSERT(istype(B, L.light_type), "bulb() makes the fitted type")
	TEST_ASSERT_EQUAL(B.loc, L, "inside the fixture")
	TEST_ASSERT_EQUAL(B.status, LIGHT_BURNED, "with the fixture's status")
	TEST_ASSERT_EQUAL(B.switchcount, 7, "and switch count")
	TEST_ASSERT_EQUAL(L.bulb(), B, "only once")
	if(expect_cell)
		var/obj/item/cell/C = L.emergency_cell()
		TEST_ASSERT(istype(C, /obj/item/cell/emergency_light), "emergency_cell() makes the cell")
		TEST_ASSERT_EQUAL(C.charge, latent_charge, "with the declared charge")
		var/obj/item/cell/emergency_light/eager = new(L.loc)
		TEST_ASSERT_EQUAL(C.charge, eager.charge, "the same charge an eager cell gets here")
		qdel(eager)
		TEST_ASSERT_EQUAL(L.emergency_cell(), C, "only once")

/// Emergency power runs off a latent cell and makes it real only when drawn on.
/datum/unit_test/dq_latent_light_emergency

/datum/unit_test/dq_latent_light_emergency/Run()
	var/obj/machinery/light/L = allocate(/obj/machinery/light, test_floor())
	if(!L.has_cell())
		return
	L.latent_cell_charge = 100
	L.status = LIGHT_OK
	TEST_ASSERT(L.has_emergency_power(0.2), "a charged latent cell gives emergency power")
	TEST_ASSERT(isnull(L.cell), "checking doesn't materialize")
	L.stat |= NOPOWER
	if(L.turned_off())
		return
	L.use_emergency_power(1)
	TEST_ASSERT(L.cell, "drawing on it does")
	TEST_ASSERT(abs(L.cell.charge - 99) < 0.01, "from the declared charge: [L.cell.charge]")

// ---- Step 4: ammo ----

/// A mapped magazine holds its rounds as a count; handling it gives the same
/// rounds an eager one has, and the count survives the serializer.
/datum/unit_test/dq_latent_magazine_rounds

/datum/unit_test/dq_latent_magazine_rounds/Run()
	var/obj/item/ammo_magazine/m380/latent = allocate(/obj/item/ammo_magazine/m380, test_floor())
	TEST_ASSERT(latent.latent_rounds > 0, "a magazine on the floor keeps a count")
	TEST_ASSERT_EQUAL(length(latent.contents), 0, "and no casing atoms")
	TEST_ASSERT_EQUAL(latent.ammo_count(), latent.max_ammo, "counting them all")
	var/list/errors = list()
	var/list/blob = state_serialize(latent, STATE_FULL, errors)
	TEST_ASSERT(blob, "serialize: [jointext(errors, "; ")]")
	var/obj/item/ammo_magazine/copy = state_materialize(json_decode(json_encode(blob)), test_floor(), STATE_FULL, errors)
	TEST_ASSERT(copy, "materialize: [jointext(errors, "; ")]")
	TEST_ASSERT_EQUAL(state_canonical(state_serialize(copy, STATE_FULL)), state_canonical(blob), "round trip")
	var/obj/item/storage/box/holder = allocate(/obj/item/storage/box, test_floor())
	var/obj/item/ammo_magazine/m380/eager = new(holder)
	eager.make_rounds_real()
	for(var/obj/item/ammo_magazine/M as anything in list(latent, copy))
		M.make_rounds_real()
		TEST_ASSERT_EQUAL(M.latent_rounds, 0, "all real")
		TEST_ASSERT_EQUAL(dq_latent_census(M), dq_latent_census(eager), "same rounds as an eager magazine")
		TEST_ASSERT_EQUAL(length(M.stored_ammo), length(eager.stored_ammo), "all loaded")
	// Moving into something that isn't a latent holder makes them real.
	var/obj/item/ammo_magazine/m380/moved = allocate(/obj/item/ammo_magazine/m380, test_floor())
	var/obj/item/dq_containment_box/plain = allocate(/obj/item/dq_containment_box, test_floor())
	moved.forceMove(plain)
	TEST_ASSERT_EQUAL(moved.latent_rounds, 0, "moving into a plain holder makes rounds real")
	TEST_ASSERT_EQUAL(length(moved.stored_ammo), moved.max_ammo, "all of them")
	qdel(copy)

// ---- Step 5: pill bottles ----

/// A mapped pill bottle is ordinary latent storage: its pills stay declared
/// until picked up, and round-trip through the serializer the same as the
/// step 2 fixture box.
/datum/unit_test/dq_latent_pill_bottle_declared

/datum/unit_test/dq_latent_pill_bottle_declared/Run()
	var/obj/item/storage/pill_bottle/antitox/bottle = allocate(/obj/item/storage/pill_bottle/antitox, test_floor())
	TEST_ASSERT_EQUAL(length(bottle.contents), 0, "the pills are latent")
	TEST_ASSERT(bottle.has_latent(), "declared, not rolled")
	var/list/errors = list()
	var/list/blob = state_serialize(bottle, STATE_FULL, errors)
	TEST_ASSERT(blob, "serialize: [jointext(errors, "; ")]")
	var/obj/item/storage/pill_bottle/copy = state_materialize(json_decode(json_encode(blob)), test_floor(), STATE_FULL, errors)
	TEST_ASSERT(copy, "materialize: [jointext(errors, "; ")]")
	TEST_ASSERT_EQUAL(state_canonical(state_serialize(copy, STATE_FULL)), state_canonical(blob), "round trip")
	bottle.make_contents_real()
	copy.make_contents_real()
	TEST_ASSERT_EQUAL(dq_latent_census(bottle), "/obj/item/reagent_containers/pill/antitox=14", "all fourteen pills")
	TEST_ASSERT_EQUAL(dq_latent_census(copy), dq_latent_census(bottle), "the copy holds the same")
	qdel(copy)

/// Picking a bottle up makes its pills real, same as any other latent storage.
/datum/unit_test/dq_latent_pill_bottle_pickup

/datum/unit_test/dq_latent_pill_bottle_pickup/Run()
	var/obj/item/storage/pill_bottle/antitox/bottle = allocate(/obj/item/storage/pill_bottle/antitox, test_floor())
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(H.put_in_active_hand(bottle), "picked up")
	TEST_ASSERT(!bottle.has_latent(), "nothing latent once held")
	TEST_ASSERT_EQUAL(length(bottle.contents), 14, "all fourteen pills are real")

/// The ChemMaster reads a loaded bottle's .contents directly (chem_master.dm);
/// loading a still-latent bottle must make its pills real first.
/datum/unit_test/dq_latent_pill_bottle_chem_master

/datum/unit_test/dq_latent_pill_bottle_chem_master/Run()
	var/turf/T = test_floor()
	var/obj/item/storage/pill_bottle/antitox/bottle = allocate(/obj/item/storage/pill_bottle/antitox, T)
	TEST_ASSERT(bottle.has_latent(), "declared on the floor")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/chem_master/master = allocate(/obj/machinery/chem_master, T)
	master.attackby(bottle, H)
	TEST_ASSERT_EQUAL(master.loaded_pill_bottle, bottle, "the bottle loaded")
	TEST_ASSERT(!bottle.has_latent(), "nothing latent once loaded")
	TEST_ASSERT_EQUAL(length(bottle.contents), 14, "its pills are real")
	qdel(master)
