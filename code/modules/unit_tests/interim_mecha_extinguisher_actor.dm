/// Observe the real refill boundary while preserving the actual reagent transfer.
/datum/reagents/interim_mecha_refill_probe
	var/last_actor_ref

/datum/reagents/interim_mecha_refill_probe/trans_to_obj(obj/target, amount = 1, multiplier = 1, copy = 0, mob/user = null)
	last_actor_ref = user ? REF(user) : null
	return ..()

/// The equipment UI forwards its controller even when that actor is not the seated pilot.
/datum/unit_test/interim_mecha_extinguisher_ui_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/extinguisher/extinguisher = allocate(/obj/item/mecha_parts/mecha_equipment/tool/extinguisher, T)
	extinguisher.attach(mech)
	TEST_ASSERT_EQUAL(extinguisher.chassis, mech, "the extinguisher mounts on the working mech")
	TEST_ASSERT(extinguisher in mech.equipment, "the UI equipment pool contains the mounted extinguisher")
	extinguisher.reagents.clear_reagents()
	var/obj/structure/reagent_dispensers/dispenser = allocate(/obj/structure/reagent_dispensers, T)
	var/datum/reagents/interim_mecha_refill_probe/source = allocate(/datum/reagents/interim_mecha_refill_probe, 300)
	own_clear(dispenser, nameof(dispenser.reagents))
	rel_set(dispenser, nameof(dispenser.reagents), source)
	rel_set(source, nameof(source.my_atom), dispenser)
	source.add_reagent(REAGENT_ID_WATER, 300)
	rel_set(mech, nameof(mech.active_caller), dispenser)
	TEST_ASSERT_NULL(mech.slot_item(MECHA_SLOT_PILOT), "the controller fixture is not the mech's seated pilot")
	TEST_ASSERT(test_op_handler(mech, "ui_act_ai_use_equipment", actor, null, extinguisher), "the equipment UI action is handled")
	TEST_ASSERT_EQUAL(source.last_actor_ref, REF(actor), "the UI actor reaches the extinguisher's real chemical refill")
	TEST_ASSERT_EQUAL(extinguisher.reagents.get_reagent_amount(REAGENT_ID_WATER), 200, "the mounted extinguisher receives its refill dose")
	TEST_ASSERT_EQUAL(source.get_reagent_amount(REAGENT_ID_WATER), 100, "refilling debits the dispenser by exactly the same dose")
