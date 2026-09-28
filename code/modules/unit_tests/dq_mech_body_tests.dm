// C8b (doc/rewrite/damage.md §5, "Body model for mechs"): mech hits land through the machine
// body plan (code/modules/body/mech_body.dm), which wears the components (body parts) before
// the chassis.

/datum/unit_test/dq_integrity_pool/mech_body

/// Pins the mech so every hit lands and penetrates.
/datum/unit_test/dq_integrity_pool/mech_body/proc/pin_mech(obj/mecha/mech)
	mech.damage_minimum = 0
	mech.minimum_penetration = 0
	var/obj/item/mecha_parts/component/armor/armour = mech.internal_components[MECH_ARMOR]
	if(armour)
		armour.deflect_chance = 0

/datum/unit_test/dq_integrity_pool/mech_body/Run()
	var/turf/T = scratch_turf()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	pin_mech(mech)
	var/datum/mech_body_plan/plan = mech_body_plan()
	TEST_ASSERT(plan == mech_body_plan(), "the mech body plan is a shared flyweight")
	var/obj/item/mecha_parts/component/hull/hull = plan.part(mech, MECH_HULL)
	TEST_ASSERT_NOTNULL(hull, "a ripley has a hull body part")

	// A round through the body path wears the hull.
	var/hull_before = hull.get_integrity()
	var/chassis_before = mech.get_integrity()
	var/obj/item/projectile/P = allocate(/obj/item/projectile)
	P.damage = 40
	P.armor_penetration = 100
	P.nodamage = FALSE
	P.penetrating = 0
	plan.receive_projectile(mech, P)
	TEST_ASSERT(hull.get_integrity() < hull_before, "a projectile injures the hull through the body plan ([hull_before] -> [hull.get_integrity()])")
	TEST_ASSERT(mech.get_integrity() <= chassis_before, "the chassis takes what the parts let through")

	// A packet takes the same path.
	hull_before = hull.get_integrity()
	mech.deal_damage(DAMAGE_BLUNT, 40, MELEE, flags = DAMAGE_PACKET_SILENT)
	TEST_ASSERT(hull.get_integrity() < hull_before, "a damage packet injures the hull through the body plan")

	// Negative legacy damage is a repair, not a hit on the parts.
	var/worn = mech.get_integrity()
	hull_before = hull.get_integrity()
	mech.take_damage(-10, BURN)
	TEST_ASSERT(mech.get_integrity() >= worn, "negative damage repairs the chassis")
	TEST_ASSERT_EQUAL(hull.get_integrity(), hull_before, "a repair does not wear the hull")

	// Internal damage is afflictions, kept per mech and managed by the plan.
	var/datum/mech_affliction/fire = plan.affliction_for(MECHA_INT_FIRE)
	TEST_ASSERT_NOTNULL(fire, "internal fire is a mech affliction")
	TEST_ASSERT(!plan.has_affliction(mech), "a fresh mech has no afflictions")
	TEST_ASSERT(plan.afflict(mech, MECHA_INT_FIRE), "afflict adds a new affliction")
	TEST_ASSERT(!plan.afflict(mech, MECHA_INT_FIRE), "afflict does not stack the same affliction")
	TEST_ASSERT(plan.has_affliction(mech, MECHA_INT_FIRE), "the affliction is set")
	TEST_ASSERT(fire in mech.afflictions, "the mech holds the affliction flyweight")
	TEST_ASSERT(fire in plan.active_afflictions(mech), "status panels see the affliction")
	TEST_ASSERT(plan.cure(mech, MECHA_INT_FIRE), "cure clears it")
	TEST_ASSERT(!plan.has_affliction(mech, MECHA_INT_FIRE), "the affliction is gone")
	TEST_ASSERT(!plan.cure(mech, MECHA_INT_FIRE), "curing an absent affliction does nothing")

	// tick(): a short circuit burns cell capacity; life support failure halts temperature control.
	var/obj/item/cell/cell = mech.get_cell()
	TEST_ASSERT_NOTNULL(cell, "a ripley has a cell")
	cell.charge = cell.maxcharge
	var/cap_before = cell.maxcharge
	plan.afflict(mech, MECHA_INT_SHORT_CIRCUIT)
	plan.afflict(mech, MECHA_INT_TEMP_CONTROL)
	mech.start_process(MECHA_PROC_INT_TEMP)
	plan.tick(mech)
	TEST_ASSERT(cell.maxcharge < cap_before, "a short circuit tick burns cell capacity ([cap_before] -> [cell.maxcharge])")
	TEST_ASSERT(!(mech.current_processes & MECHA_PROC_INT_TEMP), "a life support failure tick stops temperature control")
	plan.cure(mech, MECHA_INT_SHORT_CIRCUIT)
	plan.cure(mech, MECHA_INT_TEMP_CONTROL)
	TEST_ASSERT(mech.current_processes & MECHA_PROC_INT_TEMP, "curing life support restarts temperature control")
	plan.tick(mech)
	TEST_ASSERT(!(mech.current_processes & MECHA_PROC_DAMAGE), "with no afflictions the damage process stops")

	// roll_affliction only adds afflictions from the candidates the mech lacks.
	for(var/i in 1 to 50)
		plan.roll_affliction(mech, list(MECHA_INT_TANK_BREACH), TRUE)
	TEST_ASSERT(plan.has_affliction(mech, MECHA_INT_TANK_BREACH), "rolling past the threshold eventually afflicts")
	TEST_ASSERT(!plan.has_affliction(mech, MECHA_INT_FIRE), "rolling never adds a non-candidate")
	plan.cure(mech, MECHA_INT_TANK_BREACH)
	clear_debris(T)


/// Each mech repair is a declared interaction the resolver picks for the right tool and state,
/// ahead of the mech's catch-all item handler.
/datum/unit_test/dq_integrity_pool/mech_repair_interactions

/// The interaction the resolver picks for Use by `actor` holding `held` on `mech`.
/datum/unit_test/dq_integrity_pool/mech_repair_interactions/proc/picked(mob/living/carbon/human/actor, obj/mecha/mech, obj/item/held)
	var/datum/interaction_resolution/resolution = interactions_for(actor, mech, held)
	var/list/best = resolution.best_for_action(INPUT_ACTION_USE)
	return length(best) == 1 ? best[1] : null

/datum/unit_test/dq_integrity_pool/mech_repair_interactions/Run()
	var/turf/T = scratch_turf()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/mech_body_plan/plan = mech_body_plan()
	mech.state = MECHA_OPERATING

	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	plan.afflict(mech, MECHA_INT_TEMP_CONTROL)
	TEST_ASSERT_EQUAL(picked(H, mech, screwdriver), INTERACTION(/datum/interaction/mecha_treat/fix_temperature), "a screwdriver fixes the temperature controller")
	plan.cure(mech, MECHA_INT_TEMP_CONTROL)

	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	plan.afflict(mech, MECHA_INT_TANK_BREACH)
	TEST_ASSERT_EQUAL(picked(H, mech, welder), INTERACTION(/datum/interaction/mecha_treat/seal_tank), "a welder seals a breached tank first")
	plan.cure(mech, MECHA_INT_TANK_BREACH)
	TEST_ASSERT_EQUAL(picked(H, mech, welder), INTERACTION(/datum/interaction/mecha_weld_repair), "otherwise a welder patches integrity")

	var/obj/item/extinguisher/extinguisher = allocate(/obj/item/extinguisher, T)
	plan.afflict(mech, MECHA_INT_FIRE)
	TEST_ASSERT_EQUAL(picked(H, mech, extinguisher), INTERACTION(/datum/interaction/mecha_treat/extinguish), "an extinguisher puts out an internal fire")
	plan.cure(mech, MECHA_INT_FIRE)

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 5)
	plan.afflict(mech, MECHA_INT_SHORT_CIRCUIT)
	TEST_ASSERT(picked(H, mech, coil) != INTERACTION(/datum/interaction/mecha_treat/fix_wiring), "the wiring is out of reach with the hatch closed")
	mech.state = MECHA_CELL_OPEN
	TEST_ASSERT_EQUAL(picked(H, mech, coil), INTERACTION(/datum/interaction/mecha_treat/fix_wiring), "cable replaces fused wires behind the open hatch")
	plan.cure(mech, MECHA_INT_SHORT_CIRCUIT)

	var/obj/item/stack/nanopaste/paste = allocate(/obj/item/stack/nanopaste, T)
	mech.state = MECHA_PANEL_LOOSE
	TEST_ASSERT_EQUAL(picked(H, mech, paste), INTERACTION(/datum/interaction/mecha_paste_repair), "nanopaste repairs components with the bolts undone")

	// Recalibration is the pilot's, from the cockpit: not a Use action.
	mech.state = MECHA_OPERATING
	plan.afflict(mech, MECHA_INT_CONTROL_LOST)
	var/datum/interaction/recalibrate = INTERACTION(/datum/interaction/mecha_treat/recalibrate)
	TEST_ASSERT_NOTNULL(recalibrate, "recalibration is a declared interaction")
	TEST_ASSERT(recalibrate.applies_to(mech), "it applies while the mech has control damage")
	TEST_ASSERT(recalibrate.why_not(H, mech, null), "only the pilot can recalibrate")
	plan.cure(mech, MECHA_INT_CONTROL_LOST)
	TEST_ASSERT(!recalibrate.applies_to(mech), "it doesn't apply without control damage")
	clear_debris(T)
