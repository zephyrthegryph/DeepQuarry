// What the types the Phase C init codemod (tools/codemods/init_overrides.py and its hand families) moved from an Initialize()
// override to a declaration start with: storage contents in starts_with, an exosuit's equipment in its type table, a constant
// light in the light vars. Each test holds under both forms.

/datum/unit_test/dq_init_codemod
	abstract_type = /datum/unit_test/dq_init_codemod

/// Storage boxes whose Initialize() only made their contents hold the same contents from starts_with.
/datum/unit_test/dq_init_codemod/storage_contents

/datum/unit_test/dq_init_codemod/storage_contents/Run()
	var/list/expected = list(
		/obj/item/storage/box/swabs = list(/obj/item/forensics/swab = 14),
		/obj/item/storage/box/evidence = list(/obj/item/evidencebag = 7),
		/obj/item/storage/box/fingerprints = list(/obj/item/sample/print = 14),
		/obj/item/storage/pill_bottle/dice = list(/obj/item/dice = 7),
		/obj/item/storage/dicecup/loaded = list(/obj/item/dice = 5),
		/obj/item/storage/box/botanydisk = list(/obj/item/disk/botany = 7),
		/obj/item/storage/box/nifsofts_security = list(/obj/item/disk/nifsoft/security = 8),
		/obj/item/storage/pill_bottle/benzilate = list(/obj/item/reagent_containers/pill/benzilate = 7),
		/obj/item/storage/box/body_record_disk = list(/obj/item/disk/body_record = 8),
		/obj/item/storage/box/backup_kit = list(/obj/item/implantcase/backup = 7, /obj/item/implanter = 1),
	)
	for(var/box_type in expected)
		var/obj/item/storage/box = allocate(box_type, dq_containment_floor())
		box.make_contents_real()
		var/list/wanted = expected[box_type]
		var/total = 0
		for(var/item_type in wanted)
			var/count = 0
			for(var/obj/item/I in box.contents)
				if(I.type == item_type)
					count++
			TEST_ASSERT_EQUAL(count, wanted[item_type], "[box_type] holds [wanted[item_type]] of [item_type]")
			total += wanted[item_type]
		TEST_ASSERT_EQUAL(length(box.contents), total, "[box_type] holds nothing else")

/// Loaded exosuits whose Initialize() only attached equipment carry the same equipment from their type table.
/datum/unit_test/dq_init_codemod/mecha_equipment

/datum/unit_test/dq_init_codemod/mecha_equipment/Run()
	var/list/expected = list(
		/obj/mecha/medical/odysseus/loaded = list(/obj/item/mecha_parts/mecha_equipment/tool/sleeper = 2, /obj/item/mecha_parts/mecha_equipment/tool/syringe_gun = 1),
		/obj/mecha/working/hoverpod/combatpod = list(/obj/item/mecha_parts/mecha_equipment/weapon/energy/laser = 1, /obj/item/mecha_parts/mecha_equipment/weapon/ballistic/missile_rack/explosive = 1),
		/obj/mecha/working/hoverpod/shuttlepod = list(/obj/item/mecha_parts/mecha_equipment/tool/passenger = 2),
		/obj/mecha/working/ripley/deathripley = list(/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/safety = 1),
		/obj/mecha/combat/gorilla = list(/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay = 1, /obj/item/mecha_parts/mecha_equipment/weapon/ballistic/cannon = 1, /obj/item/mecha_parts/mecha_equipment/weapon/ballistic/missile_rack/explosive = 1, /obj/item/mecha_parts/mecha_equipment/weapon/ballistic/lmg = 1),
	)
	for(var/mech_type in expected)
		var/obj/mecha/M = allocate(mech_type, dq_containment_floor())
		var/list/wanted = expected[mech_type]
		var/total = 0
		for(var/equip_type in wanted)
			var/count = 0
			for(var/obj/item/mecha_parts/mecha_equipment/E as anything in M.equipment)
				if(E.type == equip_type)
					count++
					TEST_ASSERT_EQUAL(E.chassis, M, "[equip_type] is attached to its [mech_type]")
			TEST_ASSERT_EQUAL(count, wanted[equip_type], "[mech_type] carries [wanted[equip_type]] of [equip_type]")
			total += wanted[equip_type]
		TEST_ASSERT_EQUAL(length(M.equipment), total, "[mech_type] carries nothing else")
	var/obj/mecha/combat/gorilla/G = allocate(/obj/mecha/combat/gorilla, dq_containment_floor())
	TEST_ASSERT(istype(G.energy_relay, /obj/item/mecha_parts/mecha_equipment/tesla_energy_relay), "the gorilla's relay is its energy relay")

/// Types whose Initialize() only called set_light() with constants carry the same light in their light vars.
/datum/unit_test/dq_init_codemod/constant_lights

/datum/unit_test/dq_init_codemod/constant_lights/Run()
	var/list/expected = list(
		/obj/item/spell/shield = list(3, 2, "#006AFF"),
		/obj/effect/phase_shift = list(3, 5, "#FA58F4"),
		/obj/item/reagent_containers/food/snacks/suppermattershard = list(1.4, 1.4, "#FFFF00"),
	)
	for(var/light_type in expected)
		var/list/light = expected[light_type]
		var/atom/movable/A = allocate(light_type, dq_containment_floor())
		TEST_ASSERT_EQUAL(A.light_range, light[1], "[light_type] light range")
		TEST_ASSERT_EQUAL(A.light_power, light[2], "[light_type] light power")
		TEST_ASSERT_EQUAL(A.light_color, light[3], "[light_type] light colour")
		TEST_ASSERT(A.light_on, "[light_type] is lit")

/// A stocked pizza box starts with its pizza from pizza_type (starts =) and keeps its tag; a plain box starts empty.
/datum/unit_test/dq_init_codemod/pizzabox_contents

/datum/unit_test/dq_init_codemod/pizzabox_contents/Run()
	var/obj/item/pizzabox/margherita/box = allocate(/obj/item/pizzabox/margherita, dq_containment_floor())
	TEST_ASSERT(istype(box.pizza, /obj/item/reagent_containers/food/snacks/sliceable/pizza/margherita), "the margherita box holds a margherita")
	TEST_ASSERT_EQUAL(box.pizza.loc, box, "inside the box")
	TEST_ASSERT_EQUAL(box.boxtag, "Margherita Deluxe", "and keeps its tag")
	var/obj/item/pizzabox/plain = allocate(/obj/item/pizzabox, dq_containment_floor())
	TEST_ASSERT(isnull(plain.pizza), "a plain box starts empty")
