// Body slots and worn protection (code/modules/body/slots.dm,
// code/modules/body/worn_protection.dm; roadmap C3).

/// The slot ids a holder declares, in order, joined for comparison.
/proc/dq_test_slot_ids(atom/holder)
	var/list/ids = list()
	for(var/datum/om/relation/slot/def as anything in dq_slot_defs_for(holder))
		ids += def.slot_id
	return jointext(ids, ",")

/// The slot ids the group declared for holder key `key`, joined.
/proc/dq_test_slot_group_ids(key)
	var/list/ids = list()
	for(var/datum/om/relation/slot/def as anything in (om_registry().slot_group_for(key) || list()))
		ids += def.slot_id
	return jointext(ids, ",")

/// Each body plan declares the slots its mobs really have.
/datum/unit_test/dq_body_slot_plans_declare_slots

/datum/unit_test/dq_body_slot_plans_declare_slots/Run()
	var/humanoid = jointext(list(SLOT_ID_HAND_L, SLOT_ID_HAND_R, SLOT_ID_HEAD, SLOT_ID_MASK, SLOT_ID_SUIT, SLOT_ID_UNIFORM, SLOT_ID_GLOVES, SLOT_ID_SHOES, SLOT_ID_EYES, SLOT_ID_EAR_L, SLOT_ID_EAR_R, SLOT_ID_BACK, SLOT_ID_BELT, SLOT_ID_ID, SLOT_ID_SUIT_STORAGE, SLOT_ID_POCKET_L, SLOT_ID_POCKET_R, SLOT_ID_HANDCUFFED, SLOT_ID_LEGCUFFED, SLOT_ID_BODY), ",")

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.slot_holder_key(), H.body.type, "a mob's slot key should cover its body plan")
	TEST_ASSERT_EQUAL(dq_test_slot_ids(H), humanoid, "a humanoid should declare every human inventory slot")

	// Nanoforms are humanoids for equipment.
	TEST_ASSERT_EQUAL(dq_test_slot_group_ids(/datum/body/humanoid/nanoform), humanoid, "a nanoform should declare the humanoid slots")

	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT_EQUAL(dq_test_slot_ids(M), jointext(list(SLOT_ID_HAND_L, SLOT_ID_HAND_R, SLOT_ID_BODY), ","), "a simple body should declare hands and its interior")
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	M.has_hands = FALSE
	TEST_ASSERT_NOTNULL(dq_ledger_refusal(pen, M, SLOT_ID_HAND_L, M), "a simple mob without hands should refuse its hand slots")
	M.has_hands = TRUE
	TEST_ASSERT_NULL(dq_ledger_refusal(pen, M, SLOT_ID_HAND_L, M), "a simple mob with hands should hold things")

	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	TEST_ASSERT_EQUAL(dq_test_slot_ids(R), jointext(list(SLOT_ID_MODULE_1, SLOT_ID_MODULE_2, SLOT_ID_MODULE_3, SLOT_ID_BODY), ","), "a cyborg should declare its three module slots")

	// Machine bodies that aren't cyborgs, and AI cores, have no slots: a
	// decoy shares the plain machine body plan with drones, but is keyed by
	// its own (non-robot) mob type, which declares no slot group.
	var/mob/living/silicon/decoy/decoy = allocate(/mob/living/silicon/decoy)
	TEST_ASSERT_NULL(dq_slot_defs_for(decoy), "a non-cyborg machine mob should declare no slots")

/// A missing hand refuses its hand slot; the other hand still works.
/datum/unit_test/dq_body_slot_missing_hand

/datum/unit_test/dq_body_slot_missing_hand/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	TEST_ASSERT_NULL(dq_ledger_refusal(pen, H, SLOT_ID_HAND_L, H), "a whole human should take a pen in the left hand")

	var/obj/item/organ/external/hand = H.get_organ(BP_L_HAND)
	TEST_ASSERT_NOTNULL(hand, "the human should start with a left hand")
	hand.droplimb(clean = TRUE, disintegrate = DROPLIMB_EDGE)
	TEST_ASSERT(!H.has_body_part(BP_L_HAND), "the left hand should be gone")

	TEST_ASSERT_NOTNULL(dq_ledger_refusal(pen, H, SLOT_ID_HAND_L, H), "a missing left hand should refuse the left hand slot")
	TEST_ASSERT_NOTNULL(dq_ledger_refusal(pen, H, SLOT_ID_HANDCUFFED, H), "cuffs need both hands")
	TEST_ASSERT_NULL(dq_ledger_refusal(pen, H, SLOT_ID_HAND_R, H), "the right hand should still hold things")

/// Armour on a torso-only vest reads in the torso and not the head.
/datum/unit_test/dq_body_slot_torso_vest

/datum/unit_test/dq_body_slot_torso_vest/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/clothing/suit/armor/vest/vest = allocate(/obj/item/clothing/suit/armor/vest)
	vest.body_parts_covered = UPPER_TORSO
	vest.set_armor(dq_armor(list("melee" = 40, "bullet" = 30, "laser" = 0, "energy" = 0, "bomb" = 0, "bio" = 0, "rad" = 0)))
	TEST_ASSERT(H.equip_to_slot_if_possible(vest, slot_wear_suit, disable_warning = TRUE), "the vest should equip")

	TEST_ASSERT_EQUAL(H.body.worn_armor(UPPER_TORSO, "melee"), 40, "the cache should hold the vest's melee armour on the torso")
	TEST_ASSERT_EQUAL(H.body.worn_armor(HEAD, "melee"), 0, "the cache should hold nothing on the head")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BLUNT, BP_TORSO), 40, "a blow to the torso meets the vest")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_PIERCE, BP_TORSO), 30, "a round to the torso meets the vest")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BLUNT, BP_HEAD), 0, "a blow to the head doesn't")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BLUNT, BP_GROIN), 0, "a torso-only vest doesn't cover the groin")

/// Unequipping marks the cache stale, and the next read drops the armour.
/datum/unit_test/dq_body_slot_unequip_updates

/datum/unit_test/dq_body_slot_unequip_updates/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/clothing/suit/armor/vest/vest = allocate(/obj/item/clothing/suit/armor/vest)
	vest.set_armor(dq_armor(list("melee" = 40, "bullet" = 0, "laser" = 0, "energy" = 0, "bomb" = 0, "bio" = 0, "rad" = 0)))
	TEST_ASSERT(H.equip_to_slot_if_possible(vest, slot_wear_suit, disable_warning = TRUE), "the vest should equip")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BLUNT, BP_TORSO), 40, "the vest armours the torso")
	TEST_ASSERT(!(H.body.dirty & BODY_DIRTY_ARMOR), "reading rebuilt the cache")

	H.drop_from_inventory(vest, get_turf(H))
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_ARMOR, "unequipping should mark the worn protection stale")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BLUNT, BP_TORSO), 0, "without the vest the torso is bare")
	TEST_ASSERT_NULL(H.body.armor_by_part, "nothing worn leaves an empty cache")

	// An in-place change on worn clothing goes through worn_protection_changed().
	TEST_ASSERT(H.equip_to_slot_if_possible(vest, slot_wear_suit, disable_warning = TRUE), "the vest should equip again")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BLUNT, BP_TORSO), 40, "the vest armours the torso again")
	vest.set_armor(dq_armor(list("melee" = 10, "bullet" = 0, "laser" = 0, "energy" = 0, "bomb" = 0, "bio" = 0, "rad" = 0)))
	vest.worn_protection_changed()
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BLUNT, BP_TORSO), 10, "a changed vest reads its new armour")

/// Dresses `H` in a spread of equipment with known armour, coverage,
/// conductivity and thermal limits, including an accessory.
/datum/unit_test/proc/dq_dress_for_protection(mob/living/carbon/human/H)
	var/obj/item/clothing/under/color/grey/uniform = allocate(/obj/item/clothing/under/color/grey)
	uniform.set_armor(dq_armor(list("melee" = 5, "bullet" = 0, "laser" = 5, "energy" = 0, "bomb" = 0, "bio" = 10, "rad" = 0)))
	uniform.body_parts_covered = UPPER_TORSO | LOWER_TORSO | LEGS | ARMS
	uniform.siemens_coefficient = 0.9
	uniform.heat_protection = 0
	uniform.max_heat_protection_temperature = 0
	uniform.cold_protection = UPPER_TORSO | LOWER_TORSO | LEGS | ARMS
	uniform.min_cold_protection_temperature = 250
	TEST_ASSERT(H.equip_to_slot_if_possible(uniform, slot_w_uniform, disable_warning = TRUE), "the uniform should equip")

	var/obj/item/clothing/suit/armor/vest/vest = allocate(/obj/item/clothing/suit/armor/vest)
	vest.body_parts_covered = UPPER_TORSO | LOWER_TORSO
	vest.set_armor(dq_armor(list("melee" = 40, "bullet" = 30, "laser" = 20, "energy" = 10, "bomb" = 5, "bio" = 0, "rad" = 0)))
	vest.siemens_coefficient = 0.6
	vest.heat_protection = UPPER_TORSO
	vest.max_heat_protection_temperature = 500
	vest.cold_protection = UPPER_TORSO | LOWER_TORSO
	vest.min_cold_protection_temperature = 200
	TEST_ASSERT(H.equip_to_slot_if_possible(vest, slot_wear_suit, disable_warning = TRUE), "the vest should equip")

	var/obj/item/clothing/head/helmet/helmet = allocate(/obj/item/clothing/head/helmet)
	helmet.body_parts_covered = HEAD
	helmet.set_armor(dq_armor(list("melee" = 50, "bullet" = 25, "laser" = 25, "energy" = 5, "bomb" = 20, "bio" = 0, "rad" = 0)))
	helmet.siemens_coefficient = 0.7
	helmet.heat_protection = HEAD
	helmet.max_heat_protection_temperature = 1000
	TEST_ASSERT(H.equip_to_slot_if_possible(helmet, slot_head, disable_warning = TRUE), "the helmet should equip")

	var/obj/item/clothing/gloves/black/gloves = allocate(/obj/item/clothing/gloves/black)
	gloves.body_parts_covered = HANDS
	gloves.set_armor(dq_armor(list("melee" = 10, "bullet" = 0, "laser" = 0, "energy" = 0, "bomb" = 0, "bio" = 0, "rad" = 0)))
	gloves.siemens_coefficient = 0
	gloves.cold_protection = HANDS
	gloves.min_cold_protection_temperature = 100
	TEST_ASSERT(H.equip_to_slot_if_possible(gloves, slot_gloves, disable_warning = TRUE), "the gloves should equip")

	var/obj/item/clothing/shoes/black/shoes = allocate(/obj/item/clothing/shoes/black)
	shoes.body_parts_covered = FEET
	shoes.set_armor(dq_armor(list("melee" = 15, "bullet" = 5, "laser" = 0, "energy" = 0, "bomb" = 0, "bio" = 0, "rad" = 0)))
	shoes.siemens_coefficient = 0.5
	shoes.heat_protection = FEET
	shoes.max_heat_protection_temperature = 800
	TEST_ASSERT(H.equip_to_slot_if_possible(shoes, slot_shoes, disable_warning = TRUE), "the shoes should equip")

	var/obj/item/clothing/glasses/meson/glasses = allocate(/obj/item/clothing/glasses/meson)
	glasses.body_parts_covered = HEAD
	glasses.set_armor(dq_armor(list("melee" = 3, "bullet" = 0, "laser" = 7, "energy" = 0, "bomb" = 0, "bio" = 0, "rad" = 0)))
	TEST_ASSERT(H.equip_to_slot_if_possible(glasses, slot_glasses, disable_warning = TRUE), "the glasses should equip")

	// An accessory attached to worn clothing adds its own armour and heat protection.
	var/obj/item/clothing/accessory/armband/band = allocate(/obj/item/clothing/accessory/armband)
	band.body_parts_covered = ARM_LEFT
	band.set_armor(dq_armor(list("melee" = 12, "bullet" = 0, "laser" = 0, "energy" = 0, "bomb" = 0, "bio" = 0, "rad" = 0)))
	band.heat_protection = ARM_LEFT
	band.max_heat_protection_temperature = 2000
	TEST_ASSERT(uniform.attempt_attach_accessory(band), "the armband should attach to the uniform")

/// The old per-hit armour sum: every covering item's armour list.
/datum/unit_test/proc/dq_old_armor(obj/item/organ/external/E, key)
	. = 0
	for(var/obj/item/clothing/gear in E.get_covering_clothing())
		. += gear.get_armor().value(key)

/// The old per-hit conductivity product over head, mask, suit, uniform, gloves, shoes.
/datum/unit_test/proc/dq_old_siemens(mob/living/carbon/human/H, obj/item/organ/external/E)
	. = max(H.species.siemens_coefficient, 0)
	for(var/obj/item/clothing/C in list(H.get_equipped_item(slot_head), H.get_equipped_item(slot_wear_mask), H.get_equipped_item(slot_wear_suit), H.get_equipped_item(slot_w_uniform), H.get_equipped_item(slot_gloves), H.get_equipped_item(slot_shoes)))
		if(C.body_parts_covered & E.body_part)
			. *= C.siemens_coefficient
	. *= H.factor(BF_SIEMENS)

/// The old per-tick heat or cold protection flags, restricted to the parts
/// thermal protection counts.
/datum/unit_test/proc/dq_old_thermal_flags(mob/living/carbon/human/H, temperature, heat)
	. = 0
	for(var/obj/item/clothing/C in list(H.get_equipped_item(slot_head), H.get_equipped_item(slot_wear_suit), H.get_equipped_item(slot_w_uniform), H.get_equipped_item(slot_shoes), H.get_equipped_item(slot_gloves), H.get_equipped_item(slot_wear_mask)))
		if(heat ? C.handle_high_temperature(temperature) : C.handle_low_temperature(temperature))
			. |= heat ? C.get_heat_protection_flags() : C.get_cold_protection_flags()
	var/parts = 0
	for(var/part in dq_worn_zone_parts())
		parts |= part
	. &= parts

/// The cache gives the same armour as the old per-hit scan, for every part and
/// armour key, and the averaged whole-body armour matches too.
/datum/unit_test/dq_body_slot_cache_matches_scan

/datum/unit_test/dq_body_slot_cache_matches_scan/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	dq_dress_for_protection(H)
	var/list/keys = list("melee", "bullet", "laser", "energy", "bomb", "bio", "rad")
	var/checked = 0
	for(var/obj/item/organ/external/E as anything in H.organs)
		for(var/key in keys)
			TEST_ASSERT_EQUAL(H.worn_armor_organ(E, key), dq_old_armor(E, key), "[key] armour on [E.organ_tag] should match the old scan")
			checked++
	TEST_ASSERT(checked > 0, "the human should have limbs to check")
	TEST_ASSERT_EQUAL(H.worn_armor_organ(H.get_organ(BP_HEAD), "melee"), 53, "helmet and glasses stack on the head")
	TEST_ASSERT_EQUAL(H.worn_armor_organ(H.get_organ(BP_L_ARM), "melee"), 17, "the uniform and the armband stack on the left arm")

	// No zone: the size-weighted average over the limbs, as before.
	var/expected = 0
	var/total = 0
	for(var/organ_name in H.organs_by_name)
		if(organ_name in GLOB.organ_rel_size)
			var/obj/item/organ/external/E = H.organs_by_name[organ_name]
			if(E)
				expected += dq_old_armor(E, "melee") * GLOB.organ_rel_size[organ_name]
				total += GLOB.organ_rel_size[organ_name]
	expected /= max(total, 1)
	TEST_ASSERT(dq_near(H.injury_armor(INJURY_BLUNT, null), expected + H.armor_factor(INJURY_BLUNT)), "whole-body armour [H.injury_armor(INJURY_BLUNT, null)] should match the old average [expected]")

/// Conductivity and thermal protection per zone match the old per-tick scans.
/datum/unit_test/dq_body_slot_insulation_matches_scan

/datum/unit_test/dq_body_slot_insulation_matches_scan/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	dq_dress_for_protection(H)
	for(var/obj/item/organ/external/E as anything in H.organs)
		var/old = dq_old_siemens(H, E)
		TEST_ASSERT(dq_near(H.get_siemens_coefficient_organ(E), old), "conductivity on [E.organ_tag] should be [old], got [H.get_siemens_coefficient_organ(E)]")
	TEST_ASSERT_EQUAL(H.body.worn_siemens(HAND_LEFT), 0, "insulated gloves ground the hands")
	TEST_ASSERT(dq_near(H.body.worn_siemens(UPPER_TORSO), 0.9 * 0.6), "the uniform and vest multiply on the torso")

	for(var/temperature in list(300, 500, 501, 800, 1000, 1500, 2000, 2500))
		TEST_ASSERT_EQUAL(H.get_heat_protection_flags(temperature), dq_old_thermal_flags(H, temperature, TRUE), "heat protection flags at [temperature] K should match the old scan")
	for(var/temperature in list(2.7, 100, 150, 200, 249, 250, 300))
		TEST_ASSERT_EQUAL(H.get_cold_protection_flags(temperature), dq_old_thermal_flags(H, temperature, FALSE), "cold protection flags at [temperature] K should match the old scan")
	TEST_ASSERT(H.get_heat_protection_flags(1500) & ARM_LEFT, "the armband's heat protection counts through the uniform")
	TEST_ASSERT(!(H.get_heat_protection_flags(1500) & UPPER_TORSO), "the vest doesn't protect above 500 K")
