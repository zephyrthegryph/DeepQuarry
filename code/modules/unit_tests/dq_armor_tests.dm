// Interned armour, deterministic soak, sharp-to-blunt, material response and
// shields (doc/rewrite/damage.md §4, roadmap D2).

/// A shield that always blocks what comes at it from the front.
/obj/item/shield/dq_test_always
	base_block_chance = 100

/// A shield that never blocks.
/obj/item/shield/dq_test_never
	base_block_chance = 0

/// Identical values give the same datum, however they are written.
/datum/unit_test/dq_armor_interning

/datum/unit_test/dq_armor_interning/Run()
	var/datum/armor/A = dq_armor(list(MELEE = 40, BULLET = 30))
	TEST_ASSERT_EQUAL(A, dq_armor(list(BULLET = 30, MELEE = 40, LASER = 0)), "key order and zero entries don't make a new datum")
	TEST_ASSERT_EQUAL(A, dq_armor(list("melee" = "40", "bullet" = "30")), "numbers given as text intern the same")
	TEST_ASSERT_EQUAL(A, dq_armor_from_spec("bullet=30;melee=40"), "a spec with the same values is the same datum")
	TEST_ASSERT_EQUAL(A, dq_armor_from_spec("melee=40;bullet=30;laser=0"), "a spec with an explicit zero is the same datum")
	TEST_ASSERT(A != dq_armor(list(MELEE = 40, BULLET = 31)), "different values are a different datum")
	TEST_ASSERT_EQUAL(A.canonical, "melee=40;bullet=30", "canonical text keeps the key order")
	TEST_ASSERT_EQUAL(dq_armor(null), dq_armor_none(), "no values is the empty armour")
	TEST_ASSERT_EQUAL(dq_armor_from_spec(""), dq_armor_none(), "an empty spec is the empty armour")
	TEST_ASSERT(dq_armor_none().is_empty(), "the empty armour has nothing")
	TEST_ASSERT_EQUAL(A.with(LASER, 20), dq_armor(list(MELEE = 40, BULLET = 30, LASER = 20)), "with() interns its result")
	TEST_ASSERT_EQUAL(A.with(BULLET, 0), dq_armor(list(MELEE = 40)), "with() a zero drops the key")
	TEST_ASSERT_EQUAL(A.add(dq_armor(list(MELEE = 5, BIO = 10))), dq_armor(list(MELEE = 45, BULLET = 30, BIO = 10)), "add() sums key by key")
	TEST_ASSERT_EQUAL(A.add(dq_armor_none()), A, "adding nothing is the same armour")
	var/datum/armor/flat = dq_armor_from_spec("melee=20;melee_flat=3")
	TEST_ASSERT_EQUAL(flat.value(MELEE), 20, "the percent part reads")
	TEST_ASSERT_EQUAL(flat.flat_value(MELEE), 3, "the flat part reads")
	TEST_ASSERT_EQUAL(flat, dq_armor(list("melee_flat" = 3, MELEE = 20)), "flats intern too")

	// Instances of a type share their type's datum; an instance change is its own.
	var/obj/item/clothing/suit/armor/vest/first = allocate(/obj/item/clothing/suit/armor/vest)
	var/obj/item/clothing/suit/armor/vest/second = allocate(/obj/item/clothing/suit/armor/vest)
	TEST_ASSERT_EQUAL(first.get_armor(), second.get_armor(), "two vests share one armour datum")
	TEST_ASSERT_EQUAL(first.get_armor(), dq_armor_from_spec(initial(first.armor_spec)), "a vest's armour is its type's")
	first.set_armor_value(MELEE, 5)
	TEST_ASSERT_EQUAL(first.get_armor().value(MELEE), 5, "set_armor_value() changes the instance")
	TEST_ASSERT_EQUAL(second.get_armor(), dq_armor_from_spec(initial(second.armor_spec)), "and not its twin")
	first.set_armor(second.get_armor())
	TEST_ASSERT_NULL(first.armor_override, "setting the type's own armour drops the override")
	first.set_armor_value(MELEE, 5)
	first.set_armor(null)
	TEST_ASSERT_EQUAL(first.get_armor(), second.get_armor(), "set_armor(null) restores the type's armour")

/// Every declared spec parses to known keys: a typo would silently armour nothing.
/datum/unit_test/dq_armor_specs_parse

/datum/unit_test/dq_armor_specs_parse/Run()
	var/list/known = dq_armor_keys()
	var/checked = 0
	for(var/path in typesof(/obj, /mob/living))
		var/atom/prototype = path
		var/spec = initial(prototype.armor_spec)
		if(!spec)
			continue
		checked++
		var/list/values = params2list(spec)
		for(var/key in values)
			var/base_key = key
			var/base_length = length(key) - length(ARMOR_FLAT_SUFFIX)
			if(base_length > 0 && copytext(key, base_length + 1) == ARMOR_FLAT_SUFFIX)
				base_key = copytext(key, 1, base_length + 1)
			TEST_ASSERT(base_key in known, "[path] declares unknown armour key [key] in \"[spec]\"")
			TEST_ASSERT(!isnull(text2num(values[key])), "[path] declares a non-number for [key] in \"[spec]\"")
	TEST_ASSERT(checked > 500, "the converted armour specs should all be checked ([checked])")

/// The soak, row by row: points, penetration, flat soak and what gets through.
/datum/unit_test/dq_armor_mitigation_table

/datum/unit_test/dq_armor_mitigation_table/Run()
	// spec, key, amount, penetration, expected left
	var/list/rows = list(
		list("", MELEE, 10, 0, 10),
		list("melee=40", MELEE, 10, 0, 6),
		list("melee=40", BULLET, 10, 0, 10),
		list("melee=40", MELEE, 10, 20, 8),
		list("melee=40", MELEE, 10, 40, 10),
		list("melee=40", MELEE, 10, 100, 10),
		list("melee=80", MELEE, 100, 0, 20),
		list("melee=100", MELEE, 50, 0, 0),
		list("melee=150", MELEE, 50, 0, 0),
		list("melee=150", MELEE, 50, 70, 10),
		list("melee=-20", MELEE, 10, 0, 10),
		list("melee=50;melee_flat=2", MELEE, 10, 0, 3),
		list("melee=50;melee_flat=10", MELEE, 10, 0, 0),
		list("melee=50;melee_flat=2", MELEE, 10, 50, 9),
		list("melee_flat=4", MELEE, 10, 0, 6),
		list("laser=25;fire=90", FIRE, 20, 0, 20 * (100 - dq_armor_average_percent(90)) / 100),
		list("acid=50", ACID, 8, 0, 4),
		list("cold=30", ARMOR_COLD, 10, 0, 7),
	)
	for(var/list/row as anything in rows)
		var/datum/armor/A = dq_armor_from_spec(row[1])
		var/left = A.soak_key(row[2], row[3], row[4])
		TEST_ASSERT(dq_near(left, row[5]), "\"[row[1]]\" against [row[3]] [row[2]] at [row[4]] penetration should leave [row[5]], left [left]")

	// Material armour tables: every material's makeshift armour soaks by its own numbers.
	for(var/name in GLOB.name_to_material)
		var/datum/material/M = GLOB.name_to_material[name]
		var/points = calculate_material_armor(M.protectiveness)
		var/datum/armor/A = dq_armor(list(MELEE = points))
		TEST_ASSERT(dq_near(A.soak_key(MELEE, 100, 0), 100 - dq_armor_average_percent(clamp(points, 0, 100))), "[name] armour ([points]) should soak by its points")

/// Deterministic soak equals the average of the old +/-25% roll, for every
/// armour value and penetration; the old roll is enumerated exactly.
/datum/unit_test/dq_armor_parity_with_old_roll

/datum/unit_test/dq_armor_parity_with_old_roll/Run()
	var/worst = 0
	for(var/points in 0 to 120)
		for(var/penetration in list(0, 5, 15, 30))
			var/datum/armor/A = dq_armor(list(MELEE = points))
			var/new_kept = A.soak_key(MELEE, 1, penetration)
			var/old_kept = dq_old_armor_kept(points, penetration)
			var/difference = abs(new_kept - old_kept)
			if(clamp(points - penetration, 0, 100) >= 100)
				TEST_ASSERT_EQUAL(new_kept, 0, "[points] armour at [penetration] penetration should stop everything")
			else
				worst = max(worst, difference)
				TEST_ASSERT(difference < 0.0001, "[points] armour at [penetration] penetration: fixed soak keeps [new_kept], the old roll kept [old_kept] on average")
	// Worked examples: at 40 the roll never clipped, at 90 the clamp shaved its top.
	TEST_ASSERT(dq_near(dq_armor_average_percent(40), 40), "40 armour soaks 40%")
	TEST_ASSERT(dq_near(dq_armor_average_percent(90), 90 - 78 / 45), "90 armour soaks the old roll's average, [dq_armor_average_percent(90)]%")
	log_world("dq_armor_parity: worst difference below full protection [worst]")

/// The old armour stage's average share kept of a hit: armour less
/// penetration, then every outcome of rand(-spread, spread) equally likely.
/datum/unit_test/proc/dq_old_armor_kept(points, penetration)
	var/armor = penetration >= 100 ? 0 : clamp(points - penetration, 0, 100)
	if(armor <= 0)
		return 1
	var/spread = round(armor * 0.25)
	var/total = 0
	for(var/step in -spread to spread)
		var/rolled = clamp(armor + step, 0, 100)
		total += rolled >= 100 ? 0 : (100 - rolled) / 100
	return total / (2 * spread + 1)

/// The one sharp-to-blunt rule, and injure()'s armour stage using it.
/datum/unit_test/dq_armor_sharp_to_blunt
	var/landed_kind

/datum/unit_test/dq_armor_sharp_to_blunt/proc/on_explained(mob/living/source, incoming_kind, kind, list/stages, zone, atom/injury_source, flags)
	SIGNAL_HANDLER
	landed_kind = kind

/datum/unit_test/dq_armor_sharp_to_blunt/Run()
	TEST_ASSERT(!dq_armor_turns_edge(INJURY_CUT, 0), "no armour turns no edge")
	TEST_ASSERT(dq_armor_turns_edge(INJURY_CUT, 100), "full armour turns every edge")
	TEST_ASSERT(dq_armor_turns_edge(INJURY_PIERCE, 100), "full armour turns every point")
	TEST_ASSERT(!dq_armor_turns_edge(INJURY_BLUNT, 100), "blunt trauma has no edge to turn")
	TEST_ASSERT(!dq_armor_turns_edge(INJURY_BURN, 100), "a burn has no edge to turn")

	var/datum/armor/plate = dq_armor(list(MELEE = 100, BULLET = 40))
	var/list/soaked = plate.soak(INJURY_CUT, 10, 0)
	TEST_ASSERT_EQUAL(soaked[ARMOR_SOAK_KIND], INJURY_BLUNT, "a cut into full melee armour lands as blunt trauma")
	TEST_ASSERT_EQUAL(soaked[ARMOR_SOAK_AMOUNT], 0, "and full armour stops it")
	soaked = plate.soak(INJURY_CUT, 10, 100)
	TEST_ASSERT_EQUAL(soaked[ARMOR_SOAK_KIND], INJURY_CUT, "full penetration keeps the edge")
	TEST_ASSERT_EQUAL(soaked[ARMOR_SOAK_AMOUNT], 10, "and the whole cut")
	soaked = dq_armor_none().soak(INJURY_PIERCE, 10, 0)
	TEST_ASSERT_EQUAL(soaked[ARMOR_SOAK_KIND], INJURY_PIERCE, "no armour keeps the point")
	soaked = plate.soak(INJURY_BLUNT, 10, 0, -50)
	TEST_ASSERT(dq_near(soaked[ARMOR_SOAK_AMOUNT], 5), "a -50 body factor bonus takes armour off ([soaked[ARMOR_SOAK_AMOUNT]])")
	TEST_ASSERT_EQUAL(soaked[ARMOR_SOAK_PROTECTION], 50, "and the protection reports what was left")

	// Through injure(): the stage records the incoming cut and the landed blunt trauma.
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/clothing/suit/armor/vest/vest = allocate(/obj/item/clothing/suit/armor/vest)
	vest.set_armor(dq_armor(list(MELEE = 99)))
	TEST_ASSERT(H.equip_to_slot_if_possible(vest, slot_wear_suit, disable_warning = TRUE), "the vest should equip")
	RegisterSignal(H, COMSIG_LIVING_INJURY_EXPLAINED, PROC_REF(on_explained))
	var/turned = 0
	for(var/i in 1 to 20)
		landed_kind = null
		H.injure(INJURY_CUT, 1, BP_TORSO, flags = INJURE_ARMORED | INJURE_SILENT)
		if(landed_kind == INJURY_BLUNT)
			turned++
	TEST_ASSERT(turned >= 15, "99 melee armour should turn nearly every cut ([turned] of 20)")
	landed_kind = null
	H.injure(INJURY_CUT, 1, BP_HEAD, flags = INJURE_ARMORED | INJURE_SILENT)
	TEST_ASSERT_EQUAL(landed_kind, INJURY_CUT, "a cut where the vest doesn't reach keeps its edge")
	UnregisterSignal(H, COMSIG_LIVING_INJURY_EXPLAINED)

/// The worn protection cache holds combined, interned armour per part.
/datum/unit_test/dq_armor_worn_cache_combines

/datum/unit_test/dq_armor_worn_cache_combines/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/clothing/suit/armor/vest/vest = allocate(/obj/item/clothing/suit/armor/vest)
	vest.body_parts_covered = UPPER_TORSO
	vest.set_armor(dq_armor(list(MELEE = 30, BULLET = 20)))
	var/obj/item/clothing/under/color/grey/uniform = allocate(/obj/item/clothing/under/color/grey)
	uniform.body_parts_covered = UPPER_TORSO | LOWER_TORSO
	uniform.set_armor(dq_armor(list(MELEE = 5, BIO = 10)))
	TEST_ASSERT(H.equip_to_slot_if_possible(uniform, slot_w_uniform, disable_warning = TRUE), "the uniform should equip")
	TEST_ASSERT(H.equip_to_slot_if_possible(vest, slot_wear_suit, disable_warning = TRUE), "the vest should equip")
	TEST_ASSERT_EQUAL(H.body.worn_armor_set(UPPER_TORSO), dq_armor(list(MELEE = 35, BULLET = 20, BIO = 10)), "the torso holds both layers, interned")
	TEST_ASSERT_EQUAL(H.body.worn_armor_set(LOWER_TORSO), uniform.get_armor(), "the groin holds the uniform alone, the same datum")
	TEST_ASSERT_EQUAL(H.body.worn_armor_set(HEAD), dq_armor_none(), "the head holds nothing")
	TEST_ASSERT_EQUAL(H.injury_armor_set(BP_TORSO), H.body.worn_armor_set(UPPER_TORSO), "the armour stage soaks with the cached torso armour")
	TEST_ASSERT_EQUAL(H.armor_against(INJURY_BLUNT, BP_TORSO, 10), 25, "armor_against stays a 0-100 protection value")
	vest.set_armor_value(MELEE, 50)
	TEST_ASSERT_EQUAL(H.body.worn_armor_set(UPPER_TORSO).value(MELEE), 55, "changing worn armour in place refreshes the cache")

/// Objects: innate armour and material response reduce integrity damage.
/datum/unit_test/dq_armor_object_mitigation

/datum/unit_test/dq_armor_object_mitigation/Run()
	var/obj/item/clothing/suit/armor/vest/vest = allocate(/obj/item/clothing/suit/armor/vest)
	vest.set_armor(dq_armor(list(MELEE = 50, BULLET = 25)))
	var/before = vest.get_integrity()
	vest.take_damage(10, BRUTE, MELEE, FALSE)
	var/expected = round(10 * 0.5 * vest.impact_factor(DAMAGE_BLUNT), DAMAGE_PRECISION)
	TEST_ASSERT(dq_near(before - vest.get_integrity(), expected), "50 melee armour halves a blow to the vest ([before - vest.get_integrity()] vs [expected])")
	before = vest.get_integrity()
	vest.take_damage(10, BRUTE, MELEE, FALSE, armour_penetration = 30)
	expected = round(10 * 0.8 * vest.impact_factor(DAMAGE_BLUNT), DAMAGE_PRECISION)
	TEST_ASSERT(dq_near(before - vest.get_integrity(), expected), "30 penetration leaves 20 of the 50 ([before - vest.get_integrity()] vs [expected])")
	before = vest.get_integrity()
	vest.deal_damage(DAMAGE_PIERCE, 20)
	expected = round(20 * 0.75 * vest.impact_factor(DAMAGE_PIERCE), DAMAGE_PRECISION)
	TEST_ASSERT(dq_near(before - vest.get_integrity(), expected), "a packet's pierce meets bullet armour ([before - vest.get_integrity()] vs [expected])")
	TEST_ASSERT_EQUAL(GLOB.incoming_damage_kind, 0, "the delivered kind is cleared after the packet")

	// Containment paths read the same datum.
	TEST_ASSERT(dq_near(dq_path_armor(vest, MELEE), 0.5), "paths see half of a blow stopped")
	TEST_ASSERT(dq_near(dq_path_armor(vest, MELEE, 50), 0), "and none once penetration beats it")

/// Material response per material: harder, stronger, tougher and more
/// heat-proof than steel resists more; steel and softer resist nothing extra.
/datum/unit_test/dq_armor_material_response

/datum/unit_test/dq_armor_material_response/Run()
	var/datum/material/steel = GLOB.name_to_material[MAT_STEEL]
	var/datum/impact_response/steel_response = dq_impact_response_for_material(steel)
	for(var/kind in 1 to DAMAGE_KIND_COUNT)
		TEST_ASSERT_EQUAL(steel_response.factor(kind), 1, "steel is the reference: [kind] passes unchanged")
	for(var/soft in list(MAT_WOOD, MAT_GLASS, MAT_PLASTIC, MAT_CARDBOARD))
		var/datum/impact_response/soft_response = dq_impact_response_for_material(GLOB.name_to_material[soft])
		for(var/kind in 1 to DAMAGE_KIND_COUNT)
			TEST_ASSERT(soft_response.factor(kind) == 1, "[soft] never takes more than it did ([kind]: [soft_response.factor(kind)])")

	// Table: every material's factors follow from its numbers.
	for(var/name in GLOB.name_to_material)
		var/datum/material/M = GLOB.name_to_material[name]
		var/datum/impact_response/R = dq_impact_response_for_material(M)
		var/blunt = clamp((M.hardness - 60) / 200, 0, 0.5)
		var/cut = clamp((M.yield_strength - 300) / 1500, 0, 0.5)
		var/tough = clamp((M.fracture_toughness - 25) / 200, 0, 0.5)
		var/heat = isnull(M.melting_point) ? 0 : clamp((M.melting_point - 1800) / 8000, 0, 0.5)
		TEST_ASSERT(dq_near(R.factor(DAMAGE_BLUNT), 1 - blunt), "[name] blunt factor")
		TEST_ASSERT(dq_near(R.factor(DAMAGE_BLAST), 1 - blunt), "[name] blast factor")
		TEST_ASSERT(dq_near(R.factor(DAMAGE_SHARP), 1 - cut), "[name] sharp factor")
		TEST_ASSERT(dq_near(R.factor(DAMAGE_PIERCE), 1 - (cut + tough) / 2), "[name] pierce factor")
		TEST_ASSERT(dq_near(R.factor(DAMAGE_THERMAL), 1 - heat), "[name] thermal factor")
		TEST_ASSERT_EQUAL(R.factor(DAMAGE_SHOCK), 1, "[name] doesn't resist shock by strength")
		TEST_ASSERT_EQUAL(R, dq_impact_response_for_material(M), "[name]'s response is interned")

	var/datum/material/plasteel = GLOB.name_to_material[MAT_PLASTEEL]
	TEST_ASSERT(dq_impact_response_for_material(plasteel).factor(DAMAGE_BLUNT) < 1, "plasteel shrugs off some of a blow")
	TEST_ASSERT(dq_impact_response_for_material(plasteel).factor(DAMAGE_THERMAL) < 1, "plasteel resists heat")

	// On a real object: a plasteel knife loses less to a blow than a steel one.
	var/obj/item/material/knife/steel_knife = allocate(/obj/item/material/knife, null, MAT_STEEL)
	var/obj/item/material/knife/plasteel_knife = allocate(/obj/item/material/knife, null, MAT_PLASTEEL)
	TEST_ASSERT_EQUAL(steel_knife.impact_factor(DAMAGE_BLUNT), 1, "a steel knife takes a blow in full")
	var/before = plasteel_knife.get_integrity()
	plasteel_knife.deal_damage(DAMAGE_BLUNT, 10)
	var/expected = round(10 * dq_impact_response_for_material(plasteel).factor(DAMAGE_BLUNT), DAMAGE_PRECISION)
	TEST_ASSERT(dq_near(before - plasteel_knife.get_integrity(), expected), "a plasteel knife takes [expected] of a 10 blow, took [before - plasteel_knife.get_integrity()]")

	// Items read the same numbers through P1 properties.
	var/obj/item/dq_armor_steel_probe/probe = allocate(/obj/item/dq_armor_steel_probe)
	TEST_ASSERT_EQUAL(PROPERTY(probe, PROP_HARDNESS), steel.hardness, "an item's hardness is its material's")
	TEST_ASSERT_EQUAL(PROPERTY(probe, PROP_YIELD_STRENGTH), steel.yield_strength, "an item's yield strength is its material's")
	TEST_ASSERT_EQUAL(PROPERTY(probe, PROP_FRACTURE_TOUGHNESS), steel.fracture_toughness, "an item's toughness is its material's")
	TEST_ASSERT_EQUAL(probe.impact_response(), steel_response, "and its response is steel's")

/// A plain steel item for property reads.
/obj/item/dq_armor_steel_probe
	name = "steel probe"
	MATERIAL_BULK(MAT_STEEL, 500)

/// Shields: the block check is one step for any living holder.
/datum/unit_test/dq_armor_shield_blocks

/datum/unit_test/dq_armor_shield_blocks/Run()
	var/turf/floor = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, floor)
	var/turf/front = get_step(floor, NORTH)
	var/turf/behind = get_step(floor, SOUTH)
	TEST_ASSERT(front && behind, "the test floor needs neighbours")
	var/mob/living/carbon/human/ahead = allocate(/mob/living/carbon/human, front)
	var/mob/living/carbon/human/sneak = allocate(/mob/living/carbon/human, behind)
	H.set_dir(NORTH)

	TEST_ASSERT_EQUAL(H.check_shields(10, null, ahead, BP_TORSO, "the test"), 0, "no shield blocks nothing")
	var/obj/item/shield/dq_test_always/shield = allocate(/obj/item/shield/dq_test_always)
	TEST_ASSERT(H.put_in_hands(shield), "the shield should go in a hand")
	TEST_ASSERT(H.check_shields(10, null, ahead, BP_TORSO, "the test") > 0, "a held shield blocks a hit from the front")
	TEST_ASSERT_EQUAL(H.check_shields(10, null, sneak, BP_TORSO, "the test"), 0, "but not from behind")

	H.drop_from_inventory(shield, floor)
	var/obj/item/shield/dq_test_never/useless = allocate(/obj/item/shield/dq_test_never)
	TEST_ASSERT(H.put_in_hands(useless), "the useless shield should go in a hand")
	TEST_ASSERT_EQUAL(H.check_shields(10, null, ahead, BP_TORSO, "the test"), 0, "a shield that fails its block roll blocks nothing")

	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, floor)
	TEST_ASSERT_EQUAL(M.check_shields(10, null, ahead, null, "the test"), 0, "any living holder runs the step")
