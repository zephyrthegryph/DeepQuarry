// Real material constructors, dispatch and invalid-material rejection.
/obj/item/material/knife/dq_init_gold_default
	default_material = MAT_GOLD

/datum/unit_test/dq_init_objects_material

/datum/unit_test/dq_init_objects_material/Run()
	dq_init_objects_fixture_scope()
	var/datum/material/gold = get_material_by_name(MAT_GOLD)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, test_floor(), MAT_GOLD)
	TEST_ASSERT_EQUAL(K.material, gold, "the real positional material constructor reaches the requested material")
	TEST_ASSERT_EQUAL(K.color, gold.icon_colour, "the material setter retains its actual tint")
	TEST_ASSERT_EQUAL(K.max_integrity, max(1, round(gold.integrity / 10)) * MATERIAL_WEAR_UNIT, "material integrity is initialized before construction returns")
	TEST_ASSERT_EQUAL(K.get_integrity(), K.max_integrity, "the newly made material weapon is fully intact")
	TEST_ASSERT_EQUAL(combat_of(K).force, round(gold.edge_damage() * K.force_divisor), "the real sharp-material force is initialized")
	var/obj/item/material/knife/dq_init_gold_default/D = allocate(/obj/item/material/knife/dq_init_gold_default)
	TEST_ASSERT_EQUAL(D.material, gold, "the type/map default is retained without a positional override")
	var/obj/item/material/knife/dq_init_gold_default/overridden = allocate(/obj/item/material/knife/dq_init_gold_default, null, MAT_STEEL)
	TEST_ASSERT_EQUAL(overridden.material, steel, "a real constructor argument overrides the ordinary type default")
	var/obj/item/material/shard/shrapnel/forced = allocate(/obj/item/material/shard/shrapnel, null, MAT_GOLD)
	TEST_ASSERT_EQUAL(forced.material, steel, "the existing forced-material type table still overrides the constructor argument")
	TEST_ASSERT(findtext(forced.desc, steel.display_name), "the shard-specific set_material override still updates its description")
	var/obj/item/material/invalid = new /obj/item/material/knife(null, "dq_nonexistent_material")
	TEST_ASSERT(QDELETED(invalid), "invalid material still deletes the actual object rather than returning a half-initialized weapon")
	qdel(K)
	TEST_ASSERT(!QDELETED(gold), "deleting a weapon does not delete its borrowed registered material singleton")
	TEST_ASSERT_EQUAL(D.material, gold, "a surviving weapon keeps its independent material association")

/datum/unit_test/dq_init_objects_material/descendant_setup

/datum/unit_test/dq_init_objects_material/descendant_setup/Run()
	dq_init_objects_fixture_scope()
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	var/obj/item/material/ashtray/A = allocate(/obj/item/material/ashtray, test_floor(), MAT_STEEL)
	TEST_ASSERT_EQUAL(A.material, steel, "the descendant ashtray receives its requested material")
	TEST_ASSERT_EQUAL(A.max_butts, round(steel.hardness / 5), "descendant setup reads the fully initialized material hardness")
	TEST_ASSERT(A.base_overlay, "descendant setup builds its actual material-dependent base overlay")
	TEST_ASSERT_EQUAL(A.icon_state, "blank", "the descendant's final appearance wins over parent material setup")
	TEST_ASSERT_NULL(A.color, "the ashtray clears parent material tint exactly as before")
	var/obj/item/material/twohanded/T = allocate(/obj/item/material/twohanded, test_floor(), MAT_STEEL)
	var/base_force = (combat_of(T).sharp || combat_of(T).edge) ? steel.edge_damage() : steel.blunt_damage()
	TEST_ASSERT_EQUAL(T.force_wielded, round(base_force * T.force_divisor), "the twohanded update_force override runs through the real material setter")
	TEST_ASSERT_EQUAL(T.force_unwielded, round(T.force_wielded * T.unwielded_force_divisor), "the twohanded override initializes unwielded force")
	TEST_ASSERT_EQUAL(combat_of(T).force, T.force_unwielded, "a newly constructed twohanded weapon starts with its unwielded force")
