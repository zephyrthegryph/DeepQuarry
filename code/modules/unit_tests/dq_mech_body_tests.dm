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


/// Each mech repair is an op the resolver picks for the right tool and state, ahead of the mech's catch-all item handler.
/datum/unit_test/dq_integrity_pool/mech_repair_interactions

/// Clicks `mech` with `held` in the actor's hand and lets the op's wait run out.
/datum/unit_test/dq_integrity_pool/mech_repair_interactions/proc/use(mob/living/carbon/human/actor, obj/mecha/mech, obj/item/held)
	actor.put_in_active_hand(held)
	test_click(actor, mech, held)
	test_time(30 SECONDS)
	actor.drop_from_inventory(held)

/datum/unit_test/dq_integrity_pool/mech_repair_interactions/Run()
	test_driver_begin()
	var/turf/T = scratch_turf()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.enable_godmode() // the test floor has no air: the half minute each use waits would put the actor out
	H.set_combat_mode(FALSE)
	var/datum/mech_body_plan/plan = mech_body_plan()
	mech.state = MECHA_OPERATING

	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	plan.afflict(mech, MECHA_INT_TEMP_CONTROL)
	use(H, mech, screwdriver)
	TEST_ASSERT(!plan.has_affliction(mech, MECHA_INT_TEMP_CONTROL), "a screwdriver fixes the temperature controller")

	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	plan.afflict(mech, MECHA_INT_TANK_BREACH)
	// The armour and hull take most of a blow, and whether any reaches the frame is a roll: hit until some does.
	for(var/blows in 1 to 20)
		mech.take_damage(20)
		if(mech.get_integrity() < mech.max_integrity)
			break
	var/damaged = mech.get_integrity()
	TEST_ASSERT(damaged < mech.max_integrity, "the frame is dented")
	use(H, mech, welder)
	TEST_ASSERT(!plan.has_affliction(mech, MECHA_INT_TANK_BREACH), "a welder seals a breached tank first")
	TEST_ASSERT_EQUAL(mech.get_integrity(), damaged, "and patches no integrity that time")
	use(H, mech, welder)
	TEST_ASSERT(mech.get_integrity() > damaged, "otherwise a welder patches integrity")

	var/obj/item/extinguisher/extinguisher = allocate(/obj/item/extinguisher, T)
	plan.afflict(mech, MECHA_INT_FIRE)
	use(H, mech, extinguisher)
	TEST_ASSERT(!plan.has_affliction(mech, MECHA_INT_FIRE), "an extinguisher puts out an internal fire")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 5)
	plan.afflict(mech, MECHA_INT_SHORT_CIRCUIT)
	use(H, mech, coil)
	TEST_ASSERT(plan.has_affliction(mech, MECHA_INT_SHORT_CIRCUIT), "the wiring is out of reach with the hatch closed")
	mech.state = MECHA_CELL_OPEN
	use(H, mech, coil)
	TEST_ASSERT(!plan.has_affliction(mech, MECHA_INT_SHORT_CIRCUIT), "cable replaces fused wires behind the open hatch")

	// Nanopaste works with the bolts undone: a damaged component is mended.
	var/obj/item/stack/nanopaste/paste = allocate(/obj/item/stack/nanopaste, T)
	mech.state = MECHA_BOLTS_SECURED
	var/paste_before = paste.get_amount()
	use(H, mech, paste)
	TEST_ASSERT_EQUAL(paste.get_amount(), paste_before, "nanopaste does nothing with the bolts done up")
	mech.state = MECHA_PANEL_LOOSE
	TEST_ASSERT(isnull(mech.maintenance_panel_loose(null)), "the panel is loose")

	// Recalibration is the pilot's, from the cockpit: the op needs the pilot and control damage.
	mech.state = MECHA_OPERATING
	plan.afflict(mech, MECHA_INT_CONTROL_LOST)
	TEST_ASSERT(mech.control_lost(null), "it applies while the mech has control damage")
	plan.cure(mech, MECHA_INT_CONTROL_LOST)
	TEST_ASSERT(!mech.control_lost(null), "it does not apply without control damage")
	clear_debris(T)
	test_driver_end()
