/// Canonical fighter construction mounts its configured equipment through real attachment.
/datum/unit_test/interim_fighter_loadout_contract/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/mecha/combat/fighter/gunpod/loaded/armed = allocate(/obj/mecha/combat/fighter/gunpod/loaded, T)
	var/obj/mecha/combat/fighter/gunpod/recon/recon = allocate(/obj/mecha/combat/fighter/gunpod/recon, T)
	var/obj/mecha/combat/fighter/gunpod/bare = allocate(/obj/mecha/combat/fighter/gunpod, T)
	assert_loadout(armed, list(/obj/item/mecha_parts/mecha_equipment/weapon/energy/laser, /obj/item/mecha_parts/mecha_equipment/weapon/ballistic/missile_rack/explosive))
	assert_loadout(recon, list(/obj/item/mecha_parts/mecha_equipment/teleporter, /obj/item/mecha_parts/mecha_equipment/tesla_energy_relay))
	TEST_ASSERT_EQUAL(length(bare.equipment), 0, "the unloaded gunpod constructs no mounted equipment")
	TEST_ASSERT_EQUAL(length(bare.slot_contents(MECHA_SLOT_EQUIPMENT)), 0, "the unloaded gunpod hardpoints remain empty")

/datum/unit_test/interim_fighter_loadout_contract/proc/assert_loadout(obj/mecha/combat/fighter/F, list/expected_types)
	TEST_ASSERT(!QDELETED(F), "the canonical fighter completes real construction")
	TEST_ASSERT_EQUAL(length(F.equipment), 2, "the configured fighter has exactly its two original equipment pieces")
	var/list/hardpoints = F.slot_contents(MECHA_SLOT_EQUIPMENT)
	TEST_ASSERT_EQUAL(length(hardpoints), 2, "both real equipment pieces occupy hardpoints")
	for(var/expected_type in expected_types)
		var/obj/item/mecha_parts/mecha_equipment/matched
		var/matches = 0
		for(var/obj/item/mecha_parts/mecha_equipment/E as anything in F.equipment)
			if(E.type == expected_type)
				matched = E
				matches++
		TEST_ASSERT_EQUAL(matches, 1, "each canonical exact equipment type occurs once")
		TEST_ASSERT(!QDELETED(matched), "the original constructed equipment survives attachment")
		TEST_ASSERT_EQUAL(matched.loc, F, "real attachment places the exact equipment inside its fighter")
		TEST_ASSERT_EQUAL(matched.chassis, F, "real attachment binds the exact fighter chassis")
		TEST_ASSERT(matched in hardpoints, "the hardpoint ledger contains the same original equipment object")
		own(matched)
