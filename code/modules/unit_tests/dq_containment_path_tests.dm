// Containment propagation paths (roadmap C2, doc/rewrite/containment.md §3.2):
// heat and damage reach a holder's contents per its slots' exposure, its
// insulation and armour, and the layers further out; sealed slots block gas.

// ---- Fixtures ----

/// Records what reaches it instead of taking it.
/obj/item/dq_path_probe
	name = "path probe"
	w_class = ITEMSIZE_SMALL
	var/list/damage_taken
	var/hottest_fire = 0

/obj/item/dq_path_probe/Initialize(mapload)
	. = ..()
	damage_taken = new /list(DAMAGE_KIND_COUNT)
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		damage_taken[i] = 0

/obj/item/dq_path_probe/receive_damage(datum/damage_packet/packet)
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		damage_taken[i] += packet.amounts[i]
	return 0

/obj/item/dq_path_probe/fire_act(exposed_temperature, exposed_volume)
	hottest_fire = max(hottest_fire, exposed_temperature)

/// A probe that also covers what is under it: half insulation, half armour.
/obj/item/dq_path_probe/padded
	name = "padded path probe"
	insulation = 0.5
	armor = list("melee" = 50, "bullet" = 50, "laser" = 50, "energy" = 50, "bomb" = 50, "bio" = 50, "rad" = 50)

/// A bag: one internal slot with the default damage shares.
/obj/item/dq_path_bag
	name = "path test bag"
	w_class = ITEMSIZE_NORMAL
	max_integrity = 10000

/obj/item/dq_path_bag/slot_def_types()
	var/static/list/types = list(/datum/slot_def/dq_path_bag_interior)
	return types

/datum/slot_def/dq_path_bag_interior
	id = "interior"
	exposure = SLOT_EXPOSURE_INTERNAL

/// The same bag lined with armour.
/obj/item/dq_path_bag/armored
	armor = list("melee" = 50, "bullet" = 50, "laser" = 50, "energy" = 50, "bomb" = 50, "bio" = 50, "rad" = 50)

/// A canister-like holder with a sealed slot and an internal one.
/obj/item/dq_path_sealed
	name = "path test flask"

/obj/item/dq_path_sealed/slot_def_types()
	var/static/list/types = list(/datum/slot_def/dq_path_sealed_inner, /datum/slot_def/dq_path_bag_interior)
	return types

/datum/slot_def/dq_path_sealed_inner
	id = "sealed"
	exposure = SLOT_EXPOSURE_SEALED

/// A wearer-like holder with three worn layers that every hit reaches.
/obj/item/dq_path_mannequin
	name = "path test mannequin"
	max_integrity = 10000

/obj/item/dq_path_mannequin/slot_def_types()
	// Declared inner first on purpose: layer order, not declaration order, counts.
	var/static/list/types = list(/datum/slot_def/dq_path_layer/undersuit, /datum/slot_def/dq_path_layer/suit, /datum/slot_def/dq_path_layer/uniform)
	return types

/datum/slot_def/dq_path_layer
	exposure = SLOT_EXPOSURE_EXTERNAL
	damage_transmission = list(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)

/datum/slot_def/dq_path_layer/undersuit
	id = "undersuit"
	layer = SLOT_LAYER_UNDERSUIT

/datum/slot_def/dq_path_layer/uniform
	id = "uniform"
	layer = SLOT_LAYER_UNIFORM

/datum/slot_def/dq_path_layer/suit
	id = "suit"
	layer = SLOT_LAYER_SUIT

/obj/structure/closet/dq_path_freezer
	name = "path test freezer"
	insulation = 0.9

#define DQ_PATH_CLOSE(a, b) (abs((a) - (b)) < 0.01)

// ---- Heat ----

/datum/unit_test/dq_path_fire_closet_insulation

/datum/unit_test/dq_path_fire_closet_insulation/Run()
	var/turf/floor = dq_containment_floor()
	var/obj/structure/closet/closet = allocate(/obj/structure/closet, floor)
	var/obj/structure/closet/dq_path_freezer/freezer = allocate(/obj/structure/closet/dq_path_freezer, get_step(floor, EAST))
	var/obj/item/dq_path_probe/in_closet = allocate(/obj/item/dq_path_probe, floor)
	var/obj/item/dq_path_probe/in_freezer = allocate(/obj/item/dq_path_probe, floor)
	TEST_ASSERT(in_closet.move_into(closet), "the probe goes into the closet")
	TEST_ASSERT(in_freezer.move_into(freezer), "the probe goes into the freezer")

	var/ambient = dq_heat_path_ambient(closet)
	var/fire = ambient + 1000
	closet.fire_act(fire, CELL_VOLUME)
	freezer.fire_act(fire, CELL_VOLUME)
	TEST_ASSERT(DQ_PATH_CLOSE(dq_path_step(closet, in_closet, PATH_EFFECT_HEAT), 0.5), "a closet lets half the heat through ([dq_path_step(closet, in_closet, PATH_EFFECT_HEAT)])")
	TEST_ASSERT(DQ_PATH_CLOSE(in_closet.hottest_fire, ambient + 500), "the closet's contents saw half the fire's excess ([in_closet.hottest_fire - ambient] K over [ambient])")
	TEST_ASSERT(DQ_PATH_CLOSE(in_freezer.hottest_fire, ambient + 100), "the freezer's contents saw a tenth of it ([in_freezer.hottest_fire - ambient] K)")
	TEST_ASSERT(in_freezer.hottest_fire < in_closet.hottest_fire, "better insulation protects better")

	// A fire no hotter than the room reaches nobody.
	var/obj/item/dq_path_probe/cold = allocate(/obj/item/dq_path_probe, floor)
	cold.move_into(closet)
	closet.fire_act(ambient - 10, CELL_VOLUME)
	TEST_ASSERT_EQUAL(cold.hottest_fire, 0, "no exposure below ambient")

	// The heat domain's coupling goes through the same path.
	TEST_ASSERT(DQ_PATH_CLOSE(in_closet.heat_path_conductance(2), 1), "a heat body in the closet couples at half its conductance")
	TEST_ASSERT_EQUAL(closet.heat_path_conductance(2), 2, "the closet itself couples to its turf unchanged")

/datum/unit_test/dq_path_fire_nested

/datum/unit_test/dq_path_fire_nested/Run()
	var/turf/floor = dq_containment_floor()
	var/obj/structure/closet/closet = allocate(/obj/structure/closet, floor)
	var/obj/item/folder/folder = allocate(/obj/item/folder, floor)
	var/obj/item/paper/page = allocate(/obj/item/paper, floor)
	TEST_ASSERT(page.move_into(folder), "the page goes in the folder")
	TEST_ASSERT(folder.move_into(closet), "the folder goes in the closet")
	var/expected = 0.5 * 0.9
	TEST_ASSERT(DQ_PATH_CLOSE(dq_path_share(page, closet, PATH_EFFECT_HEAT), expected), "closet then folder: [dq_path_share(page, closet, PATH_EFFECT_HEAT)] of the heat reaches the page")
	TEST_ASSERT_EQUAL(dq_path_share(page, get_turf(closet), PATH_EFFECT_HEAT), 0, "a turf is not on the slot path")

// ---- Damage ----

/datum/unit_test/dq_path_weapon_hit_bag

/datum/unit_test/dq_path_weapon_hit_bag/Run()
	var/turf/floor = dq_containment_floor()
	var/obj/item/dq_path_bag/bag = allocate(/obj/item/dq_path_bag, floor)
	var/obj/item/dq_path_probe/probe = allocate(/obj/item/dq_path_probe, floor)
	TEST_ASSERT(probe.move_into(bag), "the probe goes in the bag")

	bag.deal_damage(DAMAGE_BLUNT, 20)
	TEST_ASSERT_EQUAL(probe.damage_taken[DAMAGE_BLUNT], 0, "a blunt blow on the bag stays on the bag")
	bag.deal_damage(DAMAGE_SHARP, 20)
	TEST_ASSERT_EQUAL(probe.damage_taken[DAMAGE_SHARP], 0, "a cut stays on the bag")
	bag.deal_damage(DAMAGE_PIERCE, 20)
	TEST_ASSERT(DQ_PATH_CLOSE(probe.damage_taken[DAMAGE_PIERCE], 10), "half a stab goes through ([probe.damage_taken[DAMAGE_PIERCE]])")
	bag.deal_damage(DAMAGE_CORROSIVE, 20)
	TEST_ASSERT(DQ_PATH_CLOSE(probe.damage_taken[DAMAGE_CORROSIVE], 5), "a quarter of the acid seeps in ([probe.damage_taken[DAMAGE_CORROSIVE]])")
	bag.deal_damage(DAMAGE_THERMAL, 20)
	TEST_ASSERT_EQUAL(probe.damage_taken[DAMAGE_THERMAL], 0, "burns reach contents through the heat path, not as damage")

	// Armour on the holder attenuates what passes.
	var/obj/item/dq_path_bag/armored/armored = allocate(/obj/item/dq_path_bag/armored, floor)
	var/obj/item/dq_path_probe/lined = allocate(/obj/item/dq_path_probe, floor)
	TEST_ASSERT(lined.move_into(armored), "the probe goes in the armoured bag")
	armored.deal_damage(DAMAGE_PIERCE, 20)
	TEST_ASSERT(DQ_PATH_CLOSE(lined.damage_taken[DAMAGE_PIERCE], 5), "the lining halves what gets through ([lined.damage_taken[DAMAGE_PIERCE]])")
	// Penetration cuts through the lining too.
	armored.deal_damage(DAMAGE_PIERCE, 20, penetration = 100)
	TEST_ASSERT(DQ_PATH_CLOSE(lined.damage_taken[DAMAGE_PIERCE], 15), "an armour-piercing stab ignores the lining ([lined.damage_taken[DAMAGE_PIERCE]])")

	// A point hit lands on one thing, not on everything in the bag.
	var/obj/item/dq_path_bag/crowded = allocate(/obj/item/dq_path_bag, floor)
	var/list/probes = list()
	for(var/i in 1 to 3)
		var/obj/item/dq_path_probe/P = allocate(/obj/item/dq_path_probe, floor)
		TEST_ASSERT(P.move_into(crowded), "probe [i] goes in")
		probes += P
	crowded.deal_damage(DAMAGE_PIERCE, 20)
	var/hit = 0
	for(var/obj/item/dq_path_probe/P as anything in probes)
		if(P.damage_taken[DAMAGE_PIERCE] > 0)
			hit++
	TEST_ASSERT_EQUAL(hit, 1, "one stab, one thing stabbed")

/datum/unit_test/dq_path_weapon_hit_closet

/datum/unit_test/dq_path_weapon_hit_closet/Run()
	var/turf/floor = dq_containment_floor()
	var/obj/structure/closet/closet = allocate(/obj/structure/closet, floor)
	var/obj/item/dq_path_bag/bag = allocate(/obj/item/dq_path_bag, floor)
	var/obj/item/dq_path_probe/probe = allocate(/obj/item/dq_path_probe, floor)
	TEST_ASSERT(probe.move_into(bag), "the probe goes in the bag")
	TEST_ASSERT(bag.move_into(closet), "the bag goes in the closet")

	closet.deal_damage(DAMAGE_BLUNT, 20)
	TEST_ASSERT_EQUAL(probe.damage_taken[DAMAGE_BLUNT], 0, "kicking the closet leaves the bag's contents alone")
	closet.deal_damage(DAMAGE_PIERCE, 40)
	// Closet 0.25, then bag 0.5.
	TEST_ASSERT(DQ_PATH_CLOSE(probe.damage_taken[DAMAGE_PIERCE], 5), "a round through the closet and the bag keeps an eighth ([probe.damage_taken[DAMAGE_PIERCE]])")

	// Through the real weapon entry point.
	var/obj/item/material/knife/knife = allocate(/obj/item/material/knife, floor)
	var/before = probe.damage_taken.Copy()
	closet.receive_weapon_hit(knife, null)
	var/reached = 0
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		reached += probe.damage_taken[i] - before[i]
	var/expected = 0
	var/datum/damage_packet/model = damage_packet(knife)
	model.add_split(knife.injury_kind, knife.injury_kinds, knife.force)
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		expected += model.amounts[i] * dq_path_share(probe, closet, PATH_EFFECT_DAMAGE, i, knife.armor_penetration)
	model.release()
	TEST_ASSERT(DQ_PATH_CLOSE(reached, expected), "a [knife] hit reaches [reached], expected [expected] (kind [knife.injury_kind])")

	// Living things aren't on the closet's damage path (C8 occupants).
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, floor)
	H.forceMove(closet)
	TEST_ASSERT_EQUAL(dq_path_step(closet, H, PATH_EFFECT_DAMAGE, DAMAGE_PIERCE), 0, "no damage path to a mob in a closet")
	TEST_ASSERT_EQUAL(dq_path_step(closet, H, PATH_EFFECT_HEAT), 0, "no heat path to a mob in a closet")
	H.forceMove(floor)

// ---- Gas ----

/datum/unit_test/dq_path_sealed_blocks_gas

/datum/unit_test/dq_path_sealed_blocks_gas/Run()
	var/turf/floor = dq_containment_floor()
	var/obj/item/dq_path_sealed/flask = allocate(/obj/item/dq_path_sealed, floor)
	var/obj/item/dq_path_probe/sealed_in = allocate(/obj/item/dq_path_probe, floor)
	var/obj/item/dq_path_probe/open_in = allocate(/obj/item/dq_path_probe, floor)
	TEST_ASSERT(sealed_in.move_into(flask, "sealed"), "a probe goes in the sealed slot")
	TEST_ASSERT(open_in.move_into(flask, "interior"), "a probe goes in the open slot")
	TEST_ASSERT_EQUAL(dq_path_step(flask, sealed_in, PATH_EFFECT_GAS), 0, "the sealed slot blocks gas")
	TEST_ASSERT_EQUAL(dq_path_step(flask, open_in, PATH_EFFECT_GAS), 1, "the internal slot shares the air")
	var/turf/east = get_step(floor, EAST)
	var/obj/structure/closet/closet = allocate(/obj/structure/closet, east)
	var/obj/item/dq_path_probe/closeted = allocate(/obj/item/dq_path_probe, east)
	TEST_ASSERT(closeted.move_into(closet), "a probe goes in the closet")
	TEST_ASSERT_EQUAL(dq_path_step(closet, closeted, PATH_EFFECT_GAS), 1, "a closet is not airtight")
	// Nested: gas stops at the first seal.
	TEST_ASSERT(flask.move_into(closet), "the flask goes in the closet")
	TEST_ASSERT_EQUAL(dq_path_share(sealed_in, closet, PATH_EFFECT_GAS), 0, "no gas past the seal from the closet")
	TEST_ASSERT_EQUAL(dq_path_share(open_in, closet, PATH_EFFECT_GAS), 1, "gas reaches the flask's open slot")
	// Sealed slots take the conservative sealed damage shares: no acid.
	flask.forceMove(floor)
	flask.deal_damage(DAMAGE_CORROSIVE, 20)
	TEST_ASSERT_EQUAL(sealed_in.damage_taken[DAMAGE_CORROSIVE], 0, "acid stays out of the seal")
	TEST_ASSERT(open_in.damage_taken[DAMAGE_CORROSIVE] > 0, "acid seeps into the open slot")

// ---- Layers ----

/datum/unit_test/dq_path_worn_layers

/datum/unit_test/dq_path_worn_layers/Run()
	var/turf/floor = dq_containment_floor()
	var/obj/item/dq_path_mannequin/wearer = allocate(/obj/item/dq_path_mannequin, floor)
	var/obj/item/dq_path_probe/padded/undersuit = allocate(/obj/item/dq_path_probe/padded, floor)
	var/obj/item/dq_path_probe/padded/uniform = allocate(/obj/item/dq_path_probe/padded, floor)
	var/obj/item/dq_path_probe/padded/suit = allocate(/obj/item/dq_path_probe/padded, floor)
	TEST_ASSERT(undersuit.move_into(wearer, "undersuit"), "undersuit on")
	TEST_ASSERT(uniform.move_into(wearer, "uniform"), "uniform on")

	// Two layers: the uniform covers the undersuit.
	TEST_ASSERT(DQ_PATH_CLOSE(dq_path_step(wearer, uniform, PATH_EFFECT_HEAT), 1), "the outer layer takes the full heat")
	TEST_ASSERT(DQ_PATH_CLOSE(dq_path_step(wearer, undersuit, PATH_EFFECT_HEAT), 0.5), "the uniform halves the heat on the undersuit")

	TEST_ASSERT(suit.move_into(wearer, "suit"), "suit on")
	TEST_ASSERT(DQ_PATH_CLOSE(dq_path_step(wearer, suit, PATH_EFFECT_HEAT), 1), "the suit is outermost now")
	TEST_ASSERT(DQ_PATH_CLOSE(dq_path_step(wearer, uniform, PATH_EFFECT_HEAT), 0.5), "the suit halves the uniform's heat")
	TEST_ASSERT(DQ_PATH_CLOSE(dq_path_step(wearer, undersuit, PATH_EFFECT_HEAT), 0.25), "suit and uniform quarter the undersuit's heat")

	var/ambient = dq_heat_path_ambient(wearer)
	wearer.fire_act(ambient + 800, CELL_VOLUME)
	TEST_ASSERT(DQ_PATH_CLOSE(suit.hottest_fire - ambient, 800), "suit saw [suit.hottest_fire - ambient] K")
	TEST_ASSERT(DQ_PATH_CLOSE(uniform.hottest_fire - ambient, 400), "uniform saw [uniform.hottest_fire - ambient] K")
	TEST_ASSERT(DQ_PATH_CLOSE(undersuit.hottest_fire - ambient, 200), "undersuit saw [undersuit.hottest_fire - ambient] K")

	wearer.deal_damage(DAMAGE_BLUNT, 40)
	TEST_ASSERT(DQ_PATH_CLOSE(suit.damage_taken[DAMAGE_BLUNT], 40), "the suit takes the blow ([suit.damage_taken[DAMAGE_BLUNT]])")
	TEST_ASSERT(DQ_PATH_CLOSE(uniform.damage_taken[DAMAGE_BLUNT], 20), "the uniform takes what the suit's armour lets by ([uniform.damage_taken[DAMAGE_BLUNT]])")
	TEST_ASSERT(DQ_PATH_CLOSE(undersuit.damage_taken[DAMAGE_BLUNT], 10), "the undersuit takes what both let by ([undersuit.damage_taken[DAMAGE_BLUNT]])")

	// Taking the suit off uncovers the layers under it.
	TEST_ASSERT(wearer.slot_remove(suit, floor), "suit off")
	TEST_ASSERT(DQ_PATH_CLOSE(dq_path_step(wearer, uniform, PATH_EFFECT_HEAT), 1), "the uniform is outermost again")

#undef DQ_PATH_CLOSE
