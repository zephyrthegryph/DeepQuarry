/datum/unit_test/dq_acceptance_item_setters/Run()
	var/obj/item/flashlight/I = allocate(/obj/item/flashlight, run_loc_floor_bottom_left)
	TEST_ASSERT(I.set_w_class(ITEMSIZE_HUGE), "The real inherited size setter accepts a new size")
	TEST_ASSERT_EQUAL(I.w_class, ITEMSIZE_HUGE, "Size state really changed")
	TEST_ASSERT(I.vv_edit_var(nameof(I.w_class), ITEMSIZE_TINY), "The real admin mutation route accepts size")
	TEST_ASSERT_EQUAL(I.w_class, ITEMSIZE_TINY, "Admin mutation uses the registered setter")
	TEST_ASSERT(I.set_slot_flags(SLOT_BELT), "The real wearable flags setter changes state")
	TEST_ASSERT_EQUAL(I.slot_flags, SLOT_BELT, "Wearable flags really changed")
	var/list/sheets = list(SPECIES_TESHARI = 'icons/inventory/head/mob_teshari.dmi')
	TEST_ASSERT(I.set_sprite_sheets(sheets), "The real sheet setter accepts a replacement")
	TEST_ASSERT(I.sprite_sheets != sheets, "The stored map is a copy")
	sheets[SPECIES_TESHARI] = null
	TEST_ASSERT_NOTNULL(I.sprite_sheets[SPECIES_TESHARI], "Caller mutation does not silently change stored fit state")
	TEST_ASSERT(I.vv_edit_var(nameof(I.sprite_sheets), null), "Admin sheet clearing uses the registered custom setter")
	TEST_ASSERT_NULL(I.sprite_sheets, "The stored map really clears")
	var/obj/item/clothing/gloves/G = allocate(/obj/item/clothing/gloves, I.loc)
	TEST_ASSERT(G.set_glove_level(3), "The real glove level setter changes layering state")
	TEST_ASSERT_EQUAL(G.glove_level, 3, "The actual glove level changed")
	TEST_ASSERT(G.set_overgloves(TRUE), "The actual overglove setter changes state")
	TEST_ASSERT_EQUAL(G.overgloves, TRUE, "Overglove state really changed")

/obj/item/dq_acceptance_size_cache_probe

CAPABILITIES(/obj/item/dq_acceptance_size_cache_probe)
	op("size_admission", menu(button = "Size admission"), needs(req_at_least(nameof(w_class), ITEMSIZE_NORMAL)), then(PROC_REF(admitted)))

/obj/item/dq_acceptance_size_cache_probe/proc/admitted(datum/act/op/A)
	return OP_OK

/datum/unit_test/dq_acceptance_item_setters/proc/admission(list/rows)
	for(var/list/row as anything in rows)
		if(row["key"] == "size_admission")
			return row
	return null

/datum/unit_test/dq_acceptance_item_setters/native_menu_cache/Run()
	var/builds_before = GLOB.op_menu_builds
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/dq_acceptance_size_cache_probe/P = allocate(/obj/item/dq_acceptance_size_cache_probe, H.loc)
	P.set_w_class(ITEMSIZE_TINY)
	var/list/first = op_menu(H, P, null)
	var/list/refused = admission(first)
	TEST_ASSERT_NOTNULL(refused, "The real native admission row exists")
	TEST_ASSERT(!refused["enabled"], "The actual size requirement refuses tiny state")
	var/builds = GLOB.op_menu_builds
	op_menu(H, P, null)
	TEST_ASSERT_EQUAL(GLOB.op_menu_builds, builds, "An unchanged real tracked menu hits cache")
	P.set_w_class(ITEMSIZE_HUGE)
	TEST_ASSERT(admission(op_menu(H, P, null))["enabled"], "The actual setter invalidates warmed requirement refusal")
	TEST_ASSERT_EQUAL(GLOB.op_menu_builds, builds + 1, "The tracked setter rebuilds the native menu once")
	P.vv_edit_var(nameof(P.w_class), ITEMSIZE_TINY)
	TEST_ASSERT(!admission(op_menu(H, P, null))["enabled"], "The real admin setter route invalidates warmed allowance")
	set_global(nameof(GLOB.op_menu_builds), builds_before)

/datum/unit_test/dq_acceptance_tracking_related_fields/Run()
	var/obj/item/clothing/shoes/S = allocate(/obj/item/clothing/shoes, run_loc_floor_bottom_left)
	S.set_body_parts_covered(LEGS)
	TEST_ASSERT_EQUAL(S.body_parts_covered, LEGS, "Coverage changes through actual generated setter")
	TEST_ASSERT(S.vv_edit_var(nameof(S.body_parts_covered), ARMS), "VV dispatch accepts tracked coverage")
	TEST_ASSERT_EQUAL(S.body_parts_covered, ARMS, "VV coverage replacement is real")
	S.set_overshoes(TRUE)
	TEST_ASSERT_EQUAL(S.overshoes, TRUE, "Overshoe state uses real setter")
	var/obj/item/clothing/accessory/W = allocate(/obj/item/clothing/accessory, S.loc)
	W.set_slot(ACCESSORY_SLOT_ARMBAND)
	TEST_ASSERT_EQUAL(W.slot, ACCESSORY_SLOT_ARMBAND, "Accessory attachment slot changes through its setter")
	W.set_valid_accessory_slots(ACCESSORY_SLOT_ARMBAND)
	W.set_restricted_accessory_slots(ACCESSORY_SLOT_ARMBAND)
	TEST_ASSERT_EQUAL(W.valid_accessory_slots, ACCESSORY_SLOT_ARMBAND, "Valid accessory mask remains a scalar bit mask")
	TEST_ASSERT_EQUAL(W.restricted_accessory_slots, ACCESSORY_SLOT_ARMBAND, "Restricted mask remains scalar")

/datum/unit_test/dq_acceptance_tracking_hud_cow/Run()
	var/datum/hud_data/first = allocate(/datum/hud_data)
	var/datum/hud_data/second = allocate(/datum/hud_data)
	TEST_ASSERT(first.equip_slots == second.equip_slots, "New still shares the immutable type slot list")
	var/list/input = first.equip_slots.Copy()
	input -= SLOT_ID_UNIFORM
	first.set_equip_slots(input)
	TEST_ASSERT(first.equip_slots != input, "Dynamic HUD setter detaches the caller list")
	TEST_ASSERT(first.equip_slots != second.equip_slots, "Dynamic edit detaches from the shared type list")
	TEST_ASSERT(!(SLOT_ID_UNIFORM in first.equip_slots), "Only edited HUD loses uniform slot")
	TEST_ASSERT(SLOT_ID_UNIFORM in second.equip_slots, "Other HUD retains uniform slot")
	input += SLOT_ID_UNIFORM
	TEST_ASSERT(!(SLOT_ID_UNIFORM in first.equip_slots), "Caller in-place edits cannot silently mutate stored slots")
	TEST_ASSERT(first.vv_edit_var(nameof(first.equip_slots), second.equip_slots), "VV follows the registered COW setter")
	TEST_ASSERT(first.equip_slots != second.equip_slots, "VV also detaches from the shared input")
	TEST_ASSERT(SLOT_ID_UNIFORM in first.equip_slots, "VV restores actual uniform admission state")

/datum/unit_test/dq_acceptance_tracking_wrapped_species/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/species/shapeshifter/S = allocate(/datum/species/shapeshifter)
	var/map_key = "\ref[H]"
	var/map_before = GLOB.wrapped_species_by_ref[map_key]
	H.set_wrapped_bodytype(SPECIES_TESHARI)
	TEST_ASSERT_EQUAL(H.wrapped_bodytype, SPECIES_TESHARI, "Tracked selector stores the chosen wrapped species")
	TEST_ASSERT_EQUAL(GLOB.wrapped_species_by_ref["\ref[H]"], SPECIES_TESHARI, "Existing compatibility map mirrors the setter")
	TEST_ASSERT_EQUAL(S.get_bodytype(H), GLOB.all_species[SPECIES_TESHARI].get_bodytype(H), "Real shapeshifter getter delegates to the selected species")
	TEST_ASSERT(!H.set_wrapped_bodytype(SPECIES_TESHARI), "Unchanged scalar selector emits no write")
	H.vv_edit_var(nameof(H.wrapped_bodytype), SPECIES_HUMAN)
	TEST_ASSERT_EQUAL(S.get_bodytype(H), GLOB.all_species[SPECIES_HUMAN].get_bodytype(H), "Actual VV setter changes delegated form")
	if(isnull(map_before))
		GLOB.wrapped_species_by_ref -= map_key
	else
		GLOB.wrapped_species_by_ref[map_key] = map_before
	S.set_name(SPECIES_SKRELL)
	TEST_ASSERT_EQUAL(S.name, SPECIES_SKRELL, "Effective base-name state uses real species setter")
	S.set_base_species(SPECIES_HUMAN)
	TEST_ASSERT_EQUAL(S.base_species, SPECIES_HUMAN, "Delegated prototype selector uses actual setter")
