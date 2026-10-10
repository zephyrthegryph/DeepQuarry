// Constraints (roadmap P3, doc/rewrite/rules.md §3).
//
// Parity: code/modules/unit_tests/data/dq_constraint_parity.json holds the
// accept/refuse matrices the legacy code produced (can_be_inserted, suit
// `allowed` lists, holster can_hold/slot_flags, mob_can_equip with
// species_restricted and every override), captured before the conversion.
// These tests rebuild the same holders, items and mobs and require the
// constraint path to give the same answer for every cell.
//
//   storage       every /obj/item/storage type x the item set
//   suit storage  every wearable with suit storage x the item set
//   holsters      every holster x the item set
//   equip         every clothing type (plus the item set and the types that
//                 had mob_can_equip overrides) x 22 slots x naked/dressed, for
//                 a human; the species-sensitive items for 38 species.

#define DQ_PARITY_FIXTURE "code/modules/unit_tests/data/dq_constraint_parity.json"
#define DQ_PARITY_REPORT_LIMIT 30

/proc/dq_parity_fixture()
	var/static/list/fixture
	if(!fixture)
		fixture = json_decode(file2text(DQ_PARITY_FIXTURE))
	return fixture

/// A fresh instance of `path` on `T`, or null if it can't be made there.
/proc/dq_parity_make(path, turf/T)
	var/atom/movable/A
	try
		A = new path(T)
	catch
		return null
	var/obj/item/hand/cards = A
	if(istype(cards) && !length(cards.cards))
		// A hand with no cards is gone at its first draw; the legacy fixture held one that stayed, so give it a card to keep.
		cards.cards += new /datum/playingcard()
	if(QDELETED(A) || A.loc != T)
		return null
	return A

/// Instances of the fixture's item set, index-aligned (null where creation failed).
/proc/dq_parity_items(list/names, turf/T)
	. = list()
	for(var/name in names)
		var/path = text2path(name)
		. += path ? dq_parity_make(path, T) : null
		CHECK_TICK

/proc/dq_parity_hex_bit(hex, index)
	var/static/list/values = list("0" = 0, "1" = 1, "2" = 2, "3" = 3, "4" = 4, "5" = 5, "6" = 6, "7" = 7, "8" = 8, "9" = 9, "a" = 10, "b" = 11, "c" = 12, "d" = 13, "e" = 14, "f" = 15)
	var/nibble = values[copytext(hex, round((index - 1) / 4) + 1, round((index - 1) / 4) + 2)]
	return (nibble & (1 << ((index - 1) % 4))) ? 1 : 0

/// Whether `W` gained suit storage it didn't have when the parity fixture was
/// captured (shared by the clothing sweep and the suit-storage parity test).
/proc/dq_parity_gained_suit_storage(obj/item/W)
	if(dq_parity_fixture()["suit"]["[W.type]"])
		return FALSE
	return dq_constraint(W, CONSTRAINT_SUIT_STORAGE) ? TRUE : FALSE

/datum/unit_test/dq_constraint_parity
	abstract_type = /datum/unit_test/dq_constraint_parity
	priority = TEST_LONGER
	is_sweep_test = TRUE
	tier = TEST_TIER_EXHAUSTIVE
	var/mismatches = 0
	var/list/report

/datum/unit_test/dq_constraint_parity/proc/mismatch(text)
	mismatches++
	if(LAZYLEN(report) < DQ_PARITY_REPORT_LIMIT)
		LAZYADD(report, text)

/datum/unit_test/dq_constraint_parity/proc/finish(what, cells)
	if(mismatches)
		TEST_FAIL("[what]: [mismatches] of [cells] cells differ from the legacy answer:\n[jointext(report, "\n")]")
	else
		TEST_NOTICE(src, "[what]: [cells] cells match the legacy answer")

/// Holders from a fixture group, each checked against the item set by `check`.
/datum/unit_test/dq_constraint_parity/proc/run_holders(group, what, check)
	var/turf/T = run_loc_floor_bottom_left
	var/list/fixture = dq_parity_fixture()
	var/list/items = dq_parity_items(fixture["items"], T)
	var/list/patterns = fixture["patterns"]
	var/list/holders = fixture[group]
	var/cells = 0
	for(var/holder_name in sweep_types(holders))
		var/obj/item/holder = dq_parity_make(text2path(holder_name), T)
		if(!holder)
			mismatch("[holder_name]: can't be created any more")
			continue
		// A holder may keep mapped starts_with as latent entries (C5);
		// materialize before clearing so none of it counts against capacity.
		if(holder.has_latent())
			holder.latent_materialize_all()
		for(var/atom/movable/A in contents_of(holder))
			qdel(A)
		var/hex = patterns[holders[holder_name] + 1]
		for(var/i in 1 to length(items))
			var/obj/item/I = items[i]
			if(!I)
				continue
			cells++
			var/expected = dq_parity_hex_bit(hex, i)
			var/actual = call(src, check)(holder, I) ? 1 : 0
			if(actual != expected)
				mismatch("[holder_name] [expected ? "took" : "refused"] [I.type] before, now [actual ? "takes" : "refuses"] it")
		qdel(holder)
		CHECK_TICK
	for(var/obj/item/I as anything in items)
		qdel(I)
	// Deleting the probes drops their removable parts where they lay, as in play
	// (a circuit's attached grenade): those are the test's too.
	own_turf_contents(T)
	finish(what, cells)

/datum/unit_test/dq_constraint_parity/proc/storage_takes(obj/item/storage/S, obj/item/I)
	return I != S && !S.insert_refusal(I, null)

/datum/unit_test/dq_constraint_parity/proc/suit_storage_takes(obj/item/suit, obj/item/I)
	var/datum/predicate/P = dq_constraint(suit, CONSTRAINT_SUIT_STORAGE)
	if(!P)
		return FALSE
	return istype(I, /obj/item/pda) || istype(I, /obj/item/pen) || P.check(null, I, null)

/datum/unit_test/dq_constraint_parity/proc/holster_takes(obj/item/holster, obj/item/I)
	return !dq_constraint_refusal(holster, CONSTRAINT_HOLD, I, null)

/datum/unit_test/dq_constraint_parity/storage/Run()
	run_holders("storage", "storage insert", PROC_REF(storage_takes))

/datum/unit_test/dq_constraint_parity/suit_storage/Run()
	run_holders("suit", "suit storage", PROC_REF(suit_storage_takes))
	// And nothing that had no `allowed` list grew suit storage. Clothing is
	// checked by all_clothing_shall_be_valid, which already builds every
	// clothing type (dq_parity_check_no_new_suit_storage()); rigs are here.
	var/turf/T = run_loc_floor_bottom_left
	var/list/had = dq_parity_fixture()["suit"]
	for(var/path in subtypesof(/obj/item/rig))
		if(had["[path]"])
			continue
		var/obj/item/W = dq_parity_make(path, T)
		if(!W)
			continue
		if(dq_constraint(W, CONSTRAINT_SUIT_STORAGE))
			TEST_FAIL("[path] has suit storage now; it had none")
		qdel(W)
		CHECK_TICK

/// Seventeen holders: cheap enough to stay whole in the normal tier.
/datum/unit_test/dq_constraint_parity/holster
	tier = TEST_TIER_NORMAL
	is_sweep_test = FALSE

/datum/unit_test/dq_constraint_parity/holster/Run()
	run_holders("holster", "holster", PROC_REF(holster_takes))

/// The species whose golden rows the equip parity check covers.
/datum/unit_test/dq_constraint_parity/equip/proc/equip_species()
	return dq_parity_fixture()["equip_species"]

/// Checks every Nth item of the equip item set (1: all of them).
/datum/unit_test/dq_constraint_parity/equip/proc/item_stride()
	return 1

/datum/unit_test/dq_constraint_parity/equip/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/list/fixture = dq_parity_fixture()
	var/list/names = fixture["equip_items"]
	var/list/sensitive = fixture["equip_sensitive"]
	var/list/rows = fixture["equip"]
	var/stride = item_stride()
	// Items are made on first use, index-aligned with the fixture (FALSE where
	// creation failed), so a shard or a representative only builds the items it
	// checks. A shard owns item index i when sweep_owns(i - 1): every species'
	// cells for one item land in the same shard.
	var/list/items = new /list(length(names))
	var/cells = 0
	// Bit order of the golden masks (the old numeric slot order).
	var/static/list/golden_order = list(SLOT_ID_HAND_L, SLOT_ID_HAND_R, SLOT_ID_BACK, SLOT_ID_BELT, SLOT_ID_ID, SLOT_ID_SUIT_STORAGE, SLOT_ID_POCKET_L, SLOT_ID_POCKET_R, SLOT_ID_EYES, SLOT_ID_MASK, SLOT_ID_GLOVES, SLOT_ID_HEAD, SLOT_ID_SHOES, SLOT_ID_SUIT, SLOT_ID_UNIFORM, SLOT_ID_EAR_L, SLOT_ID_EAR_R, SLOT_ID_LEGS, SLOT_ID_TIE, SLOT_ID_HANDCUFFED, SLOT_ID_LEGCUFFED, SLOT_ID_IN_BACKPACK)
	for(var/species_name in equip_species())
		if(!rows["[species_name]|naked"])
			TEST_FAIL("[species_name] has no golden equip rows")
			continue
		var/mob/living/carbon/human/H = new(T, species_name)
		var/everything = species_name == SPECIES_HUMAN
		for(var/state in list("naked", "dressed"))
			if(state == "dressed")
				H.equip_to_slot(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
				H.equip_to_slot(new /obj/item/clothing/suit/storage/hazardvest(H), SLOT_ID_SUIT)
				H.equip_to_slot(new /obj/item/clothing/gloves/black(H), SLOT_ID_GLOVES)
				H.equip_to_slot(new /obj/item/clothing/shoes/black(H), SLOT_ID_SHOES)
				H.equip_to_slot(new /obj/item/storage/backpack(H), SLOT_ID_BACK)
			var/list/masks = splittext(rows["[species_name]|[state]"], ",")
			var/list/indices = everything ? null : sensitive
			var/count = everything ? length(names) : length(indices)
			for(var/n in 1 to count)
				var/index = everything ? n : indices[n] + 1
				if(((index - 1) % stride) || !sweep_owns(index - 1))
					continue
				var/obj/item/I = items[index]
				if(isnull(I))
					var/path = text2path(names[index])
					I = (path && dq_parity_make(path, T)) || FALSE
					// Off the turf once made: with thousands of probes piled on one
					// turf every later move scanned them all (doMove was a third of
					// this test). equip_refusal() doesn't read the item's loc.
					if(I && !QDELETED(I))
						I.moveToNullspace()
					items[index] = I
				if(!I)
					continue
				// Self-deleting items (shoes/none): the legacy backpack took a
				// deleted item; the storage slot (C4) refuses it.
				if(QDELETED(I))
					continue
				var/expected = text2num(masks[n], 36)
				var/actual = 0
				for(var/slot in 1 to length(golden_order))
					if(!I.equip_refusal(H, golden_order[slot], TRUE))
						actual |= (1 << (slot - 1))
				cells += length(golden_order)
				if(actual != expected)
					var/list/diff = list()
					for(var/slot in 1 to length(golden_order))
						var/bit = 1 << (slot - 1)
						if((actual & bit) != (expected & bit))
							diff += "slot [golden_order[slot]] [(expected & bit) ? "took" : "refused"]"
					mismatch("[species_name] [state] [I.type]: [jointext(diff, ", ")] before")
			// Once per state, as before: a CHECK_TICK per item yielded to the MC
			// thousands of times and made the run half again as long.
			CHECK_TICK
		qdel(H)
	for(var/obj/item/I in items)
		qdel(I)
	// Deleting the probes drops their removable parts where they lay, as in
	// play (a stun glove's cell, a circuit's attached grenade): clear them.
	for(var/atom/movable/salvage in contents_of(T))
		if(!istype(salvage, /obj/effect/landmark))
			qdel(salvage)
	TEST_ASSERT(cells > 0 || GLOB.dq_test_shard_count > 1, "no equip cells were checked")
	finish("equip", cells)

// ---- Normal-tier representatives of the exhaustive parity sweeps ----
// Each checks a fixed, curated subset of its sweep with the same code, so an
// integration merge still catches an obviously broken constraint path; the
// exhaustive sweeps run in CI and nightly (doc/testing.md "Tiers").

/datum/unit_test/dq_constraint_parity/equip/representative
	tier = TEST_TIER_NORMAL
	is_sweep_test = FALSE

/datum/unit_test/dq_constraint_parity/equip/representative/equip_species()
	// A human (the full item set), a small-framed and a vox body plan (their
	// species-sensitive items), and a non-humanoid.
	return list(SPECIES_HUMAN, SPECIES_TESHARI, SPECIES_VOX, SPECIES_MONKEY)

/datum/unit_test/dq_constraint_parity/equip/representative/item_stride()
	return 23

/datum/unit_test/dq_constraint_parity/storage/representative
	tier = TEST_TIER_NORMAL
	is_sweep_test = FALSE

/datum/unit_test/dq_constraint_parity/storage/representative/curated_types()
	return list(
		/obj/item/storage/backpack,
		/obj/item/storage/backpack/holding,
		/obj/item/storage/belt/utility,
		/obj/item/storage/box,
		/obj/item/storage/toolbox,
		/obj/item/storage/wallet,
		/obj/item/storage/pill_bottle,
		/obj/item/storage/briefcase,
		/obj/item/storage/secure/briefcase,
		/obj/item/storage/backpack/dufflebag,
		/obj/item/storage/fancy/cigarettes,
		/obj/item/storage/firstaid,
	)

/datum/unit_test/dq_constraint_parity/suit_storage/representative
	tier = TEST_TIER_NORMAL
	is_sweep_test = FALSE

/datum/unit_test/dq_constraint_parity/suit_storage/representative/curated_types()
	return list(
		/obj/item/clothing/suit/storage/hazardvest,
		/obj/item/clothing/suit/armor/vest,
		/obj/item/clothing/suit/space/void,
		/obj/item/clothing/suit/storage/toggle/labcoat,
		/obj/item/clothing/suit/bio_suit,
		/obj/item/clothing/suit/fire,
		/obj/item/clothing/suit/space,
		/obj/item/clothing/suit/storage/apron,
	)

// ---- The constraint API ----

/datum/unit_test/dq_constraint_reasons/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/storage/wallet/wallet = allocate(/obj/item/storage/wallet, T)
	var/obj/item/storage/pill_bottle/bottle = allocate(/obj/item/storage/pill_bottle, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/obj/item/storage/box/box = allocate(/obj/item/storage/box, T)
	var/obj/item/storage/toolbox/toolbox = allocate(/obj/item/storage/toolbox, T)

	// Holders give a reason, from one path.
	TEST_ASSERT_EQUAL(wallet.insert_refusal(wrench, null), "it doesn't take that", "wallet refusing a wrench")
	TEST_ASSERT_NOTNULL(bottle.insert_refusal(wrench, null), "pill bottle refusing a wrench")
	var/too_big = box.insert_refusal(toolbox, null)
	TEST_ASSERT(findtext(too_big, "too big"), "box refusing a toolbox should say it's too big, said [too_big]")
	TEST_ASSERT_NULL(toolbox.insert_refusal(wrench, null), "toolbox taking a wrench")

	// The same answer through the storage slot: its refusal is the storage capability's.
	var/datum/relation_definition/slot/storage/def = dq_slot_def(/datum/relation_definition/slot/storage)
	TEST_ASSERT_EQUAL(def.refusal(wallet, wrench, null), wallet.insert_refusal(wrench, null), "slot_def and storage give the same reason")
	var/obj/item/spacecash/cash = allocate(/obj/item/spacecash, T)
	TEST_ASSERT_NULL(def.refusal(wallet, cash, null), "slot_def takes cash into a wallet")

	// Instance overrides: an exact-fit box takes only what it was fitted for.
	var/obj/item/storage/box/fitted = allocate(/obj/item/storage/box, T)
	for(var/atom/movable/A in fitted)
		qdel(A)
	new /obj/item/pen(fitted)
	fitted.make_exact_fit()
	var/obj/item/paper/paper = allocate(/obj/item/paper, T)
	TEST_ASSERT_NOTNULL(fitted.insert_refusal(paper, null), "exact-fit box refuses paper")
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(!findtext(fitted.insert_refusal(pen, null), "take that"), "exact-fit box takes another pen as far as its type goes (it is full)")
	TEST_ASSERT_NULL(box.insert_refusal(paper, null), "a plain box still takes paper")

/datum/unit_test/dq_constraint_equip_reasons/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/teshari = allocate(/mob/living/carbon/human, T, SPECIES_TESHARI)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)

	// Pockets need a jumpsuit, then take small things.
	TEST_ASSERT_EQUAL(pen.equip_refusal(H, SLOT_ID_POCKET_L, TRUE), "you need a jumpsuit first", "pocket without a jumpsuit")
	H.equip_to_slot(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	TEST_ASSERT_NULL(pen.equip_refusal(H, SLOT_ID_POCKET_L, TRUE), "pen into a pocket")
	var/obj/item/storage/toolbox/toolbox = allocate(/obj/item/storage/toolbox, T)
	TEST_ASSERT_EQUAL(toolbox.equip_refusal(H, SLOT_ID_POCKET_L, TRUE), "too big for a pocket", "toolbox into a pocket")

	// The slot tag (the old slot_flags check) gives a reason too.
	TEST_ASSERT(findtext(wrench.equip_refusal(H, SLOT_ID_HEAD, TRUE), "worn on the head"), "wrench on the head")

	// Suit storage asks the worn suit.
	TEST_ASSERT_EQUAL(pen.equip_refusal(H, SLOT_ID_SUIT_STORAGE, TRUE), "you need a suit first", "suit storage without a suit")

	// Fit: Teshari-only goggles refuse a human with a reason, and fit a Teshari.
	var/obj/item/clothing/glasses/aerogelgoggles/goggles = allocate(/obj/item/clothing/glasses/aerogelgoggles, T)
	TEST_ASSERT_EQUAL(dq_constraint_refusal(goggles, CONSTRAINT_FIT, goggles, H), "it only fits Teshari", "Teshari goggles on a human")
	TEST_ASSERT_NULL(dq_constraint_refusal(goggles, CONSTRAINT_FIT, goggles, teshari), "Teshari goggles on a Teshari")

	// Refitting changes one instance only.
	var/obj/item/clothing/suit/space/void/refit = allocate(/obj/item/clothing/suit/space/void, T)
	var/obj/item/clothing/suit/space/void/stock = allocate(/obj/item/clothing/suit/space/void, T)
	refit.restrict_fit(list(SPECIES_TESHARI))
	TEST_ASSERT_NOTNULL(dq_constraint_refusal(refit, CONSTRAINT_FIT, refit, H), "suit refitted for a Teshari refuses a human")
	TEST_ASSERT_NULL(LAZYACCESS(stock.constraint_overrides, CONSTRAINT_FIT), "the stock suit keeps its type's fit")
	refit.restrict_fit(null)
	TEST_ASSERT_NULL(dq_constraint(refit, CONSTRAINT_FIT), "restrict_fit(null) fits anyone")

/// Every constraint declaration compiles (no unknown types, units or tags).
/datum/unit_test/dq_constraint_declarations_compile
	is_sweep_test = TRUE
	tier = TEST_TIER_EXHAUSTIVE

/// Normal tier: the item constraints of a fixed set of holders and wearables
/// (every declared equip_slot predicate is still checked in full). The whole
/// fixture runs in CI and nightly.
/datum/unit_test/dq_constraint_declarations_compile/representative
	is_sweep_test = FALSE
	tier = TEST_TIER_NORMAL

/datum/unit_test/dq_constraint_declarations_compile/representative/curated_types()
	return list(
		/obj/item/storage/backpack,
		/obj/item/storage/box,
		/obj/item/storage/toolbox,
		/obj/item/storage/wallet,
		/obj/item/storage/belt/utility,
		/obj/item/clothing/suit/storage/hazardvest,
		/obj/item/clothing/suit/space/void,
		/obj/item/clothing/suit/armor/vest,
		/obj/item/clothing/glasses/aerogelgoggles,
		/obj/item/clothing/under/color/grey,
		/obj/item/clothing/shoes/black,
		/obj/item/clothing/gloves/black,
	)

/datum/unit_test/dq_constraint_declarations_compile/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/list/kinds = list(CONSTRAINT_HOLD, CONSTRAINT_SUIT_STORAGE, CONSTRAINT_FIT, CONSTRAINT_EQUIP)
	var/checked = 0
	// The types the parity fixture could create: every storage, suit and
	// equip type that initializes cleanly on a bare floor.
	var/list/fixture = dq_parity_fixture()
	var/list/names = list()
	for(var/group in list("storage", "suit", "holster"))
		names |= fixture[group]
	names |= fixture["equip_items"]
	for(var/name in sweep_types(names))
		var/path = text2path(name)
		if(!path)
			continue
		var/obj/item/I = dq_parity_make(path, T)
		if(!I)
			continue
		for(var/kind in kinds)
			var/datum/predicate/P = dq_constraint(I, kind)
			if(P && P.errors)
				TEST_FAIL("[path] [kind]: [jointext(P.errors, "; ")]")
			checked++
		for(var/atom/movable/A in I)
			qdel(A)
		qdel(I)
		CHECK_TICK
	for(var/path in subtypesof(/datum/predicate/equip_slot))
		var/datum/predicate/equip_slot/declared = path
		if(!initial(declared.slot))
			continue
		var/datum/predicate/P = dq_predicate(path)
		if(P.errors)
			TEST_FAIL("[path]: [jointext(P.errors, "; ")]")
	TEST_NOTICE(src, "[checked] item constraints compiled")

#undef DQ_PARITY_FIXTURE
#undef DQ_PARITY_REPORT_LIMIT
