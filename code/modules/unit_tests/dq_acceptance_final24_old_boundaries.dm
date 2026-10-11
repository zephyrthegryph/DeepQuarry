// Old-code boundary proof for the three unconverted final24 acceptance clauses.
/datum/unit_test/dq_acceptance_final24_boundary
	abstract_type = /datum/unit_test/dq_acceptance_final24_boundary

/datum/unit_test/dq_acceptance_final24_boundary/limb_order/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.set_species(SPECIES_HUMAN)
	TEST_ASSERT(H.get_organ(BP_L_ARM) && H.get_organ(BP_L_LEG), "Real human has the relevant limbs")
	var/obj/item/clothing/suit/armor/vest/S = allocate(/obj/item/clothing/suit/armor/vest, T)
	var/obj/item/clothing/gloves/combat/G = allocate(/obj/item/clothing/gloves/combat, T)
	var/obj/item/clothing/shoes/boots/jackboots/F = allocate(/obj/item/clothing/shoes/boots/jackboots, T)
	G.set_body_parts_covered(ARMS)
	F.set_body_parts_covered(LEGS)
	TEST_ASSERT(H.equip_to_slot_if_possible(G, SLOT_ID_GLOVES, disable_warning = TRUE), "Actual covering gloves enter wearer slot")
	TEST_ASSERT(H.equip_to_slot_if_possible(F, SLOT_ID_SHOES, disable_warning = TRUE), "Actual covering shoes enter wearer slot")
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_GLOVES), G, "Actual glove occupancy is positive")
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_SHOES), F, "Actual shoe occupancy is positive")
	S.set_body_parts_covered(CHEST)
	TEST_ASSERT_NULL(dq_constraint_refusal(S, CONSTRAINT_EQUIP, S, H), "Nonoverlapping chest garment permits equipment")
	S.set_body_parts_covered(ARMS | LEGS)
	TEST_ASSERT_EQUAL(dq_constraint_refusal(S, CONSTRAINT_EQUIP, S, H), "\the [G] [G.gender == PLURAL ? "are" : "is"] in the way", "Exact glove refusal precedes shoe refusal")
	TEST_ASSERT(H.unEquip(G, target = T), "Actual removal clears glove slot")
	TEST_ASSERT_NULL(H.get_equipped_item(SLOT_ID_GLOVES), "Glove occupancy was really removed")
	TEST_ASSERT_EQUAL(dq_constraint_refusal(S, CONSTRAINT_EQUIP, S, H), "\the [F] [F.gender == PLURAL ? "are" : "is"] in the way", "Clearing gloves exposes exact shoe refusal")
	F.set_body_parts_covered(FEET)
	TEST_ASSERT_NULL(dq_constraint_refusal(S, CONSTRAINT_EQUIP, S, H), "Actual covering-field setter recovers nonoverlapping admission")
	F.set_body_parts_covered(LEGS)
	TEST_ASSERT_EQUAL(dq_constraint_refusal(S, CONSTRAINT_EQUIP, S, H), "\the [F] [F.gender == PLURAL ? "are" : "is"] in the way", "Restoring overlap refuses again")
	TEST_ASSERT(H.unEquip(F, target = T), "Actual final covering removal succeeds")
	TEST_ASSERT_NULL(dq_constraint_refusal(S, CONSTRAINT_EQUIP, S, H), "No remaining covering gear permits equipment")

/datum/unit_test/dq_acceptance_final24_boundary/plate_order/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.set_species(SPECIES_HUMAN)
	var/obj/item/clothing/suit/armor/pcarrier/C = allocate(/obj/item/clothing/suit/armor/pcarrier, T)
	var/obj/item/clothing/gloves/combat/G = allocate(/obj/item/clothing/gloves/combat, T)
	var/obj/item/clothing/shoes/boots/jackboots/F = allocate(/obj/item/clothing/shoes/boots/jackboots, T)
	var/obj/item/clothing/accessory/armor/armguards/A = allocate(/obj/item/clothing/accessory/armor/armguards, T)
	var/obj/item/clothing/accessory/armor/legguards/L = allocate(/obj/item/clothing/accessory/armor/legguards, T)
	G.set_body_parts_covered(ARMS)
	F.set_body_parts_covered(LEGS)
	TEST_ASSERT(H.equip_to_slot_if_possible(G, SLOT_ID_GLOVES, disable_warning = TRUE), "Real gloves occupy wearer slot")
	TEST_ASSERT(H.equip_to_slot_if_possible(F, SLOT_ID_SHOES, disable_warning = TRUE), "Real shoes occupy wearer slot")
	TEST_ASSERT(!(worn_of(C).covers & (ARMS | LEGS)), "Carrier itself does not trigger inherited limb clause")
	TEST_ASSERT_NULL(dq_constraint_refusal(C, CONSTRAINT_EQUIP, C, H), "Empty carrier does not invent plate conflicts")
	TEST_ASSERT(C.attempt_attach_accessory(A), "Real arm accessory attaches to carrier")
	TEST_ASSERT(C.attempt_attach_accessory(L), "Real leg accessory attaches to carrier")
	TEST_ASSERT(A in contents_of(C), "Actual arm accessory is visible to plate consumer")
	TEST_ASSERT(L in contents_of(C), "Actual leg accessory is visible to plate consumer")
	TEST_ASSERT((worn_of(A).covers & ARMS) && (worn_of(L).covers & LEGS), "Actual accessories cover matching regions")
	TEST_ASSERT_EQUAL(dq_constraint_refusal(C, CONSTRAINT_EQUIP, C, H), "\the [A] and \the [G] are in each other's way", "Exact arm plate refusal precedes leg plate refusal")
	A.set_body_parts_covered(CHEST)
	TEST_ASSERT_EQUAL(dq_constraint_refusal(C, CONSTRAINT_EQUIP, C, H), "\the [L] and \the [F] are in each other's way", "Cleared arm coverage exposes actual leg plate reason")
	L.set_body_parts_covered(CHEST)
	TEST_ASSERT_NULL(dq_constraint_refusal(C, CONSTRAINT_EQUIP, C, H), "Real plate coverage setters permit equipment when both cease overlapping")
	A.set_body_parts_covered(ARMS)
	TEST_ASSERT_EQUAL(dq_constraint_refusal(C, CONSTRAINT_EQUIP, C, H), "\the [A] and \the [G] are in each other's way", "Restoring actual arm overlap restores refusal")

/datum/unit_test/dq_acceptance_final24_boundary/species_identity/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/under/fluff/slime_skeleton/I = allocate(/obj/item/clothing/under/fluff/slime_skeleton, T)
	H.set_species(SPECIES_HUMAN)
	TEST_ASSERT_EQUAL(H.get_species(), SPECIES_HUMAN, "Actual initial species is Human")
	TEST_ASSERT_EQUAL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, H), "only slimes can wear this", "Exact original species rejection")
	H.set_species(SPECIES_PROMETHEAN)
	TEST_ASSERT_EQUAL(H.get_species(), SPECIES_PROMETHEAN, "Real species setter produces exact admitted species")
	TEST_ASSERT_NULL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, H), "Exact Promethean identity permits equipment")
	H.set_species(SPECIES_VR)
	TEST_ASSERT_EQUAL(H.get_species(), SPECIES_VR, "Real avatar subtype has distinct species identity")
	TEST_ASSERT(istype(H.species, /datum/species/shapeshifter/promethean), "Real avatar inherits Promethean type, making identity check falsifiable")
	TEST_ASSERT_EQUAL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, H), "only slimes can wear this", "Promethean subtype alone must not satisfy exact identity")
	H.set_species(SPECIES_PROMETHEAN)
	TEST_ASSERT_NULL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, H), "Changing back to admitted identity recovers")
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	TEST_ASSERT(!ishuman(M), "Actual mouse is nonhuman")
	TEST_ASSERT_NULL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, M), "Original nonhuman short circuit remains allowed")

/datum/unit_test/dq_acceptance_final24_boundary/wielded/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/oldtwohanded/I = allocate(/obj/item/oldtwohanded, H.loc)
	TEST_ASSERT_NULL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, H), "Real unwielded item permits equipment")
	I.set_wielded(TRUE)
	TEST_ASSERT_EQUAL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, H), "unwield it first", "Real tracked wield state refuses equipment")
	I.set_wielded(FALSE)
	TEST_ASSERT_NULL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, H), "Actual setter recovers admission")

/datum/unit_test/dq_acceptance_final24_boundary/taur_shapes/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/clothing/suit/drake_cloak/D = allocate(/obj/item/clothing/suit/drake_cloak, H.loc)
	var/obj/item/clothing/suit/barding/B = allocate(/obj/item/clothing/suit/barding, H.loc)
	var/datum/sprite_accessory/tail/taur/drake/drake = allocate(/datum/sprite_accessory/tail/taur/drake)
	var/datum/sprite_accessory/tail/taur/horse/horse = allocate(/datum/sprite_accessory/tail/taur/horse)
	H.tail_style = null // Actual old untracked selector; feature migration must route its real setter later.
	TEST_ASSERT_EQUAL(dq_constraint_refusal(D, CONSTRAINT_EQUIP, D, H), "you need a drake-taur half to wear this", "Clientless real human is refused by drake fit")
	H.tail_style = drake
	TEST_ASSERT_NULL(dq_constraint_refusal(D, CONSTRAINT_EQUIP, D, H), "Real drake accessory shape allows drake cloak")
	TEST_ASSERT_EQUAL(dq_constraint_refusal(B, CONSTRAINT_EQUIP, B, H), "you need a horse-taur half to wear this", "Other real taur shape stays refused")
	H.tail_style = horse
	TEST_ASSERT_NULL(dq_constraint_refusal(B, CONSTRAINT_EQUIP, B, H), "Real horse shape permits barding")
	TEST_ASSERT_EQUAL(dq_constraint_refusal(D, CONSTRAINT_EQUIP, D, H), "you need a drake-taur half to wear this", "Changing real selector invalidates earlier allowed shape")

/datum/unit_test/dq_acceptance_final24_boundary/saddlebag_effect/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/storage/backpack/saddlebag_common/B = allocate(/obj/item/storage/backpack/saddlebag_common, H.loc)
	H.tail_style = null
	TEST_ASSERT_EQUAL(dq_constraint_refusal(B, CONSTRAINT_EQUIP, B, H), lowertext(B.no_message), "Exact old dynamic lowercase rejection")
	var/datum/sprite_accessory/tail/taur/horse/T = allocate(/datum/sprite_accessory/tail/taur/horse)
	H.tail_style = T
	TEST_ASSERT_NULL(dq_constraint_refusal(B, CONSTRAINT_EQUIP, B, H), "Actual taur permits common saddlebag")
	TEST_ASSERT_EQUAL(B.item_state, "[B.icon_base]_[T.icon_sprite_tag]", "Old query effect recorded honestly before draw relocation")

/datum/unit_test/dq_acceptance_final24_boundary/avida_effect/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/clothing/head/fluff/avida/I = allocate(/obj/item/clothing/head/fluff/avida, H.loc)
	H.ear_style = null
	H.ear_secondary_style = null
	TEST_ASSERT_NULL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, H), "Ear clause always permits admission")
	TEST_ASSERT_EQUAL(I.item_state, "avidahatnoears", "Old query changes no-ear appearance; native requirement must not retain this effect")
	var/datum/sprite_accessory/ears/bnnuy/E = allocate(/datum/sprite_accessory/ears/bnnuy)
	H.ear_style = E
	TEST_ASSERT_NULL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, H), "Real allowed primary ear retains admission")
	TEST_ASSERT_EQUAL(I.item_state, initial(I.item_state), "Old query restores original look for actual Bnnuy ears")
	H.ear_style = null
	H.ear_secondary_style = E
	TEST_ASSERT_NULL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, H), "Real secondary ear also retains admission")
	TEST_ASSERT_EQUAL(I.item_state, initial(I.item_state), "Actual secondary ear picks original look")
	H.ear_secondary_style = null
	TEST_ASSERT_NULL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, H), "No-ear recovery still admits")
	TEST_ASSERT_EQUAL(I.item_state, "avidahatnoears", "Real selector clearing restores old no-ear effect")

/datum/unit_test/dq_acceptance_final24_boundary/named_owner_denial/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	TEST_ASSERT_NULL(H.client, "Real clientless actor, no fabricated identity")
	TEST_ASSERT_NULL(H.ckey, "Actual offline actor has no authenticated owner identity")
	var/list/cases = list(
		list(/obj/item/clothing/glasses/welding/tiemgogs, "these don't look like they were made to fit you"),
		list(/obj/item/remote_scene_tool/tally_necklace, "the collar doesn't fit you"),
		list(/obj/item/clothing/head/helmet/space/void/engineering/hazmat/fluff/screehelm, "your face and whoever is meant for this helmet are too different"),
		list(/obj/item/clothing/suit/space/void/engineering/hazmat/fluff/screespess, "it only has three fingers, and room for extra limbs"),
		list(/obj/item/clothing/under/fluff/aluranevines, "wrapping vines around yourself is an odd idea"),
		list(/obj/item/clothing/head/helmet/space/fluff/joan, "it doesn't fit"),
		list(/obj/item/clothing/suit/space/fluff/joan, "it doesn't fit"),
		list(/obj/item/clothing/head/helmet/space/fluff/kate, "it doesn't fit"),
		list(/obj/item/clothing/head/helmet/space/void/security/hasd, "the faceplate is not made for your anatomy"),
		list(/obj/item/clothing/suit/space/void/security/hasd, "this suit is not designed for you"),
		list(/obj/item/clothing/under/skirt/outfit/fluff/nikki, "it doesn't fit"),
		list(/obj/item/clothing/shoes/fluff/nikki, "they don't fit"))
	for(var/list/row as anything in cases)
		var/obj/item/I = allocate(row[1], H.loc)
		TEST_ASSERT_EQUAL(dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, H), row[2], "Real production owner gate retains exact refusal for [I.type]")
	// Nikki RIG requires separate constructor repair before honest old capture; no fake chest substituted.
	// Genuine-client positive ownership coverage is explicitly not supplied by this test.
