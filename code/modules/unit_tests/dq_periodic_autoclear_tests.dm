// Declared periodic work stops when the ownership framework auto-clears the field it is declared on
// (doc/rewrite/ownership.md 1.1 O5 / 4.1, doc/rewrite/systems.md section 5). The related entity is
// destroyed; the framework clears the view or owned var and raises the field's channel through
// own_field_changed(), which re-evaluates the declaration. No body guard or ALLOW is involved.

/// Technomancer core: DECLARE_PERIODIC_WHILE on the `wearer` relation view.
/datum/unit_test/periodic_autoclear_technomancer_wearer

/datum/unit_test/periodic_autoclear_technomancer_wearer/Run()
	var/obj/item/technomancer_core/core = allocate(/obj/item/technomancer_core, test_floor())
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT_NULL(core.periodic_pipe, "an unworn core runs nothing")
	rel_set(core, nameof(core.wearer), H)
	TEST_ASSERT_EQUAL(core.periodic_pipe, PERIODIC_SLOW, "setting the wearer view starts the core's upkeep")
	qdel(H)
	TEST_ASSERT_NULL(core.wearer, "the wearer view is cleared when the wearer is destroyed")
	TEST_ASSERT_NULL(core.periodic_pipe, "the auto-clear raised the field channel and stopped the upkeep")

/// Fusion core: every(when = owned_field) on the owned `owned_field`.
/datum/unit_test/periodic_autoclear_fusion_owned_field

/datum/unit_test/periodic_autoclear_fusion_owned_field/Run()
	var/obj/machinery/power/fusion_core/core = allocate(/obj/machinery/power/fusion_core, test_floor())
	TEST_ASSERT(!condition_holds(core, nameof(core.owned_field)), "a core with no field is gated off")
	rel_set(core, nameof(core.owned_field), new /obj/effect/fusion_em_field(core.loc, core))
	TEST_ASSERT_NOTNULL(core.owned_field, "the core owns its new field")
	TEST_ASSERT(condition_holds(core, nameof(core.owned_field)), "owning a field opens the core's step")
	qdel(core.owned_field)
	TEST_ASSERT_NULL(core.owned_field, "the owned field leaves its owner's var when it is destroyed")
	TEST_ASSERT(!condition_holds(core, nameof(core.owned_field)), "the auto-clear gated the step off")

/// Magnetic gun: DECLARE_PERIODIC_WHILE on capacitor_unsettled, derived from the owned `cell` and
/// `capacitor` and the cross-entity input "capacitor.charge".
/datum/unit_test/periodic_autoclear_magnetic_parts

/datum/unit_test/periodic_autoclear_magnetic_parts/Run()
	// The cell is destroyed: a drained capacitor with no cell has nothing to bleed, so it settles.
	var/obj/item/gun/magnetic/railgun/gun = allocate(/obj/item/gun/magnetic/railgun, test_floor())
	TEST_ASSERT_NOTNULL(gun.cell, "the railgun spawns with a cell")
	TEST_ASSERT_NOTNULL(gun.capacitor, "the railgun spawns with a capacitor")
	gun.capacitor.set_charge(0)
	TEST_ASSERT_EQUAL(gun.periodic_pipe, PERIODIC_SLOW, "draining the capacitor (a relayed input) starts charging")
	qdel(gun.cell)
	TEST_ASSERT_NULL(gun.cell, "the owned cell leaves the gun when it is destroyed")
	TEST_ASSERT_NULL(gun.periodic_pipe, "the cell's auto-clear re-evaluated capacitor_unsettled and stopped the work")

	// The capacitor is destroyed: nothing is left to charge.
	var/obj/item/gun/magnetic/railgun/gun2 = allocate(/obj/item/gun/magnetic/railgun, test_floor())
	gun2.capacitor.set_charge(0)
	TEST_ASSERT_EQUAL(gun2.periodic_pipe, PERIODIC_SLOW, "a drained capacitor with a cell charges")
	qdel(gun2.capacitor)
	TEST_ASSERT_NULL(gun2.capacitor, "the owned capacitor leaves the gun when it is destroyed")
	TEST_ASSERT_NULL(gun2.periodic_pipe, "the capacitor's auto-clear re-evaluated capacitor_unsettled and stopped the work")
