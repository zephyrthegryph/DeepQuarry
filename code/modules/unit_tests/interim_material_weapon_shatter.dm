/// Actual flint blade destruction releases its held source and preserves material debris rules.
/datum/unit_test/interim_material_weapon_shatter
	parent_type = /datum/unit_test/dq_p2_reagents
	var/held_case = FALSE
	var/consumed_case = FALSE

/datum/unit_test/interim_material_weapon_shatter/held
	held_case = TRUE

/datum/unit_test/interim_material_weapon_shatter/consumed
	consumed_case = TRUE

/datum/unit_test/interim_material_weapon_shatter/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = rc_actor(T)
	var/obj/item/material/knife/stone/source = allocate(/obj/item/material/knife/stone, T)
	var/obj/item/material/knife/stone/control = allocate(/obj/item/material/knife/stone, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/datum/material/flint = get_material_by_name(MAT_FLINT)
	TEST_ASSERT_EQUAL(source.get_material(), flint, "The actual stone blade constructor must use canonical flint")
	TEST_ASSERT(source.fragile && source.drops_debris, "The canonical blade must actually use fragile debris-producing destruction")
	TEST_ASSERT_EQUAL(flint.shard_type, SHARD_STONE_PIECE, "The canonical material must create stone-piece debris")
	var/source_integrity = source.get_integrity()
	var/control_integrity = control.get_integrity()
	TEST_ASSERT(source_integrity > 0 && control_integrity > 0, "Both actual constructors must start with positive integrity")
	var/list/before = turf_contents_of_type(T, /obj/item/material/shard)
	if(held_case)
		TEST_ASSERT(actor.put_in_active_hand(source), "The actor must actually hold the exact original blade")
		add_trait(source, TRAIT_NODROP, "interim_material_weapon_shatter")
		source.shatter(FALSE)
		TEST_ASSERT(!QDELETED(source), "A stuck held blade must survive actual shatter refusal")
		TEST_ASSERT_EQUAL(actor.get_active_hand(), source, "Refusal must preserve the exact original hand occupant")
		TEST_ASSERT_EQUAL(source.loc, actor, "Refusal must preserve the actual source holder")
		TEST_ASSERT_EQUAL(source.get_integrity(), source_integrity, "Direct shatter refusal must preserve original integrity")
		TEST_ASSERT_EQUAL(source.get_material(), flint, "Refusal must preserve original material identity")
		TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/item/material/shard) - before), 0, "Refusal must precede debris creation")
		remove_trait(source, TRAIT_NODROP, "interim_material_weapon_shatter")
	if(consumed_case)
		source.shatter(TRUE)
	else
		source.material_wear(source.get_integrity())
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(source), "Actual accepted destruction must consume the exact original blade")
	if(held_case)
		TEST_ASSERT_NULL(actor.get_active_hand(), "Accepted destruction must clear the actual held source")
	var/list/products = turf_contents_of_type(T, /obj/item/material/shard) - before
	TEST_ASSERT_EQUAL(length(products), consumed_case ? 0 : 1, "Actual consumed flag must control the exact debris count")
	if(!consumed_case)
		var/obj/item/material/shard/shard = products[1]
		TEST_ASSERT_EQUAL(shard.type, /obj/item/material/shard, "Actual wear must create the canonical shard type")
		TEST_ASSERT_EQUAL(shard.get_material(), flint, "Actual debris must preserve exact original material identity")
		TEST_ASSERT_EQUAL(shard.loc, T, "Actual debris must occupy the source floor")
	TEST_ASSERT(!QDELETED(control), "Source destruction must preserve the independent original blade")
	TEST_ASSERT_EQUAL(control.get_integrity(), control_integrity, "Destruction must leave independent blade integrity unchanged")
	TEST_ASSERT_EQUAL(control.get_material(), flint, "Destruction must leave independent material identity unchanged")
	TEST_ASSERT_EQUAL(control.loc, T, "Destruction must preserve the independent blade floor")
	TEST_ASSERT(!QDELETED(pen), "Destruction must preserve the original unrelated pen")
	TEST_ASSERT_EQUAL(pen.loc, T, "Destruction must preserve the unrelated pen floor")
