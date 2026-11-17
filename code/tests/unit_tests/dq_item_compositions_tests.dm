// The families of item that used to have no composition now break down into what they are made of, so a crusher, a lathe and a grinder can take them (an item with no
// composition does not break down at all). dq_recycle_conservation (dq_recycle_conservation_tests.dm) holds every declared composition to its design cost.

/// One type from each family that was given a composition: it declares one now, and the grinder takes it.
/proc/dq_item_composition_samples()
	var/static/list/samples = list(
		/obj/item/integrated_circuit/passive/power/solar_cell,
		/obj/item/pda,
		/obj/item/cartridge/medical,
		/obj/item/disk/botany,
		/obj/item/encryptionkey/headset_sec,
		/obj/item/modular_computer/laptop,
		/obj/item/mecha_parts/chassis/ripley,
		/obj/item/robot_parts/l_arm,
		/obj/item/melee/baton,
		/obj/item/grenade/flashbang,
		/obj/item/reagent_containers/hypospray,
		/obj/item/reagent_containers/glass/bottle/antitoxin,
		/obj/item/reagent_containers/blood/empty,
		/obj/item/toy/plushie/carp,
		/obj/item/instrument/violin,
		/obj/item/flag/nt,
		/obj/item/stack/tile/wood,
		/obj/item/stack/tile/carpet,
		/obj/item/clothing/under/color/grey,
		/obj/item/clothing/suit/armor/vest,
		/obj/item/clothing/head/helmet,
		/obj/item/gun/projectile/pistol,
	)
	return samples

/datum/unit_test/dq_item_family_compositions

/datum/unit_test/dq_item_family_compositions/Run()
	for(var/path in dq_item_composition_samples())
		var/list/totals = dq_type_material_totals(path)
		TEST_ASSERT(length(totals), "[path] has no declared composition")
		for(var/material_id in totals)
			TEST_ASSERT(GLOB.name_to_material[material_id], "[path] names the unregistered material '[material_id]'")

/// Every family composition breaks down in a grinder: each material it names has a sheet rule to grind into, so the item's feedstock is not empty.
/datum/unit_test/dq_item_family_grinds

/datum/unit_test/dq_item_family_grinds/Run()
	for(var/path in dq_item_composition_samples())
		if(ispath(path, /obj/item/stack))
			continue
		var/obj/item/item = allocate(path)
		TEST_ASSERT(item_grindable(item), "[path] is not grindable")
		var/list/feed = item_feedstock(item)
		TEST_ASSERT(length(feed), "[path] grinds into nothing (its materials have no grinding rule): [json_encode(item.material_totals())]")

/// Guns are steel, plastic and a little copper, more of it the bigger the gun.
/datum/unit_test/dq_item_gun_composition

/datum/unit_test/dq_item_gun_composition/Run()
	var/list/pistol = dq_type_material_totals(/obj/item/gun/projectile/pistol)
	var/list/rifle = dq_type_material_totals(/obj/item/gun/projectile/automatic/z8)
	TEST_ASSERT(pistol[MAT_STEEL] > 0 && pistol[MAT_PLASTIC] > 0 && pistol[MAT_COPPER] > 0, "a pistol is steel, plastic and copper: [json_encode(pistol)]")
	TEST_ASSERT(dq_recycle_type_total(/obj/item/gun/projectile/automatic/z8) > dq_recycle_type_total(/obj/item/gun/projectile/pistol), "a rifle is worth more material than a pistol")
	TEST_ASSERT(rifle[MAT_STEEL] > pistol[MAT_STEEL], "a rifle has more steel than a pistol")

/// Armour made of a material is worth that material, by its sheets, and not the cloth of a plain garment.
/datum/unit_test/dq_item_material_armor_composition

/datum/unit_test/dq_item_material_armor_composition/Run()
	var/obj/item/clothing/suit/armor/material/makeshift/vest = allocate(/obj/item/clothing/suit/armor/material/makeshift)
	TEST_ASSERT(vest.material, "the plate vest took its default material")
	var/list/totals = vest.material_totals()
	TEST_ASSERT_EQUAL(length(totals), 1, "a steel vest is made of one material: [json_encode(totals)]")
	TEST_ASSERT_EQUAL(totals[MAT_STEEL], 2 * SHEET_MATERIAL_AMOUNT, "a steel plate vest breaks down into its two sheets of steel: [json_encode(totals)]")
	var/obj/item/clothing/head/helmet/material/helmet = allocate(/obj/item/clothing/head/helmet/material)
	TEST_ASSERT(isnull(helmet.material_totals()[MAT_FIBERS]), "a steel helmet has no cloth in it")

/// The round's authentication disk is never recycled.
/datum/unit_test/dq_item_nuke_disk_not_recyclable

/datum/unit_test/dq_item_nuke_disk_not_recyclable/Run()
	TEST_ASSERT(!length(dq_type_material_totals(/obj/item/disk/nuclear)), "the authentication disk has a composition")
