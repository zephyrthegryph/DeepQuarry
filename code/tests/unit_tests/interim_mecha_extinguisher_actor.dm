/// Observe the real refill boundary while preserving the actual reagent transfer.
/datum/reagents/interim_mecha_refill_probe
	var/last_actor_ref

/datum/reagents/interim_mecha_refill_probe/trans_to_obj(obj/target, amount = 1, multiplier = 1, copy = 0, mob/user = null)
	last_actor_ref = user ? REF(user) : null
	return ..()

/// The pilot's click on a reagent dispenser with the extinguisher selected reaches the extinguisher's real refill with the pilot as the actor.
/datum/unit_test/interim_mecha_extinguisher_click_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/pilot = allocate(/mob/living/carbon/human, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/extinguisher/extinguisher = allocate(/obj/item/mecha_parts/mecha_equipment/tool/extinguisher, T)
	extinguisher.attach(mech)
	TEST_ASSERT_EQUAL(extinguisher.chassis, mech, "the extinguisher mounts on the working mech")
	TEST_ASSERT(extinguisher in mech.equipment, "the mech's equipment pool contains the mounted extinguisher")
	extinguisher.reagents.clear_reagents()
	var/obj/structure/reagent_dispensers/dispenser = allocate(/obj/structure/reagent_dispensers, T)
	var/datum/reagents/interim_mecha_refill_probe/source = allocate(/datum/reagents/interim_mecha_refill_probe, 300)
	own_clear(dispenser, nameof(dispenser.reagents))
	rel_set(dispenser, nameof(dispenser.reagents), source)
	rel_set(source, nameof(source.my_atom), dispenser)
	source.add_reagent(REAGENT_ID_WATER, 300)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, pilot, pilot), "the pilot gets in")
	TEST_ASSERT_EQUAL(mech.slot_item(MECHA_SLOT_PILOT), pilot, "the slot identifies the pilot")
	rel_set(mech, nameof(mech.selected), extinguisher)
	mech.click_action(dispenser, pilot, "")
	TEST_ASSERT_EQUAL(source.last_actor_ref, REF(pilot), "the clicking pilot reaches the extinguisher's real chemical refill")
	TEST_ASSERT_EQUAL(extinguisher.reagents.get_reagent_amount(REAGENT_ID_WATER), 200, "the mounted extinguisher receives its refill dose")
	TEST_ASSERT_EQUAL(source.get_reagent_amount(REAGENT_ID_WATER), 100, "refilling debits the dispenser by exactly the same dose")
