/// Gradual charging runs its first real step immediately, clamps capacity and stops once its declared countdown is exhausted.
/datum/unit_test/interim_cell_gradual_charge_steps/Run()
	var/obj/item/cell/cell = allocate(/obj/item/cell, run_loc_floor_bottom_left)
	cell.charge = cell.maxcharge - 250
	cell.gradual_charge(0, 2, FALSE, null)
	TEST_ASSERT_EQUAL(cell.charge, cell.maxcharge - 250, "zero requested steps cannot charge the actual cell")
	TEST_ASSERT_EQUAL(cell.gradual_charge_left, 0, "zero requested steps cannot start the countdown")
	cell.gradual_charge(2, 0, FALSE, null)
	TEST_ASSERT_EQUAL(cell.charge, cell.maxcharge - 250, "a zero multiplier cannot charge the actual cell")
	TEST_ASSERT_EQUAL(cell.gradual_charge_left, 0, "a zero multiplier cannot start the countdown")
	cell.gradual_charge(2, 2, FALSE, null)
	TEST_ASSERT_EQUAL(cell.charge, cell.maxcharge - 50, "starting two doubled steps immediately delivers the first two hundred charge")
	TEST_ASSERT_EQUAL(cell.gradual_charge_left, 1, "the immediate step consumes exactly one countdown entry")
	cell.gradual_charge_step()
	TEST_ASSERT_EQUAL(cell.charge, cell.maxcharge, "the second real step clamps at the actual cell capacity")
	TEST_ASSERT_EQUAL(cell.gradual_charge_left, 0, "the final real step exhausts the countdown")
	cell.gradual_charge_step() // "an exhausted countdown stops rather than charging again": the step does nothing, checked below
	TEST_ASSERT_EQUAL(cell.charge, cell.maxcharge, "an exhausted callback cannot overcharge the cell")

/// Actor-bound charging must stop when deletion clears its declared relation, retaining the charge already delivered.
/datum/unit_test/interim_cell_gradual_charge_actor_deletion/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	cell.charge = 0
	TEST_ASSERT(user.put_in_active_hand(cell), "the actual actor holds the actual cell")
	cell.gradual_charge(3, 0.5, FALSE, user)
	TEST_ASSERT_EQUAL(cell.charge, 50, "actor-bound charging immediately delivers its first fifty charge")
	TEST_ASSERT_EQUAL(cell.gradual_charge_left, 2, "two real charge steps remain")
	TEST_ASSERT_EQUAL(cell.gradual_user, user, "the active charging relation references its actual actor")
	TEST_ASSERT(cell.gradual_needs_user, "the real charging sequence requires that actor")
	// Release the cell before deleting its actor so the cell remains independently alive.
	TEST_ASSERT(user.drop_from_inventory(cell, T), "the actual actor releases the charged cell")
	qdel(user)
	TEST_ASSERT(QDELETED(user), "the actual charging actor is deleted")
	TEST_ASSERT(!QDELETED(cell), "the released cell survives independently")
	TEST_ASSERT_NULL(cell.gradual_user, "actor deletion clears the actual charging relation")
	cell.gradual_charge_step() // "the actual pending charging callback stops without its actor": the step does nothing, checked below
	TEST_ASSERT_EQUAL(cell.gradual_charge_left, 0, "losing the actor cancels all remaining steps")
	TEST_ASSERT_EQUAL(cell.charge, 50, "actor-loss cancellation preserves only the charge already delivered")
