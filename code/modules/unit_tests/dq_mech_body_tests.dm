// C8b (doc/rewrite/damage.md §5, "Body model for mechs"): mech hits land through the machine
// body plan (code/modules/body/mech_body.dm), which wears the components (body parts) before
// the chassis.

/datum/unit_test/dq_integrity_pool/mech_body

/// Pins the mech so every hit lands and penetrates.
/datum/unit_test/dq_integrity_pool/mech_body/proc/pin_mech(obj/mecha/mech)
	mech.deflect_chance = 0
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

	// Internal damage flags are afflictions with a flyweight each.
	var/datum/mech_affliction/fire = plan.affliction_for(MECHA_INT_FIRE)
	TEST_ASSERT_NOTNULL(fire, "internal fire is a mech affliction")
	mech.setInternalDamage(MECHA_INT_FIRE)
	TEST_ASSERT(mech.hasInternalDamage(MECHA_INT_FIRE), "the affliction is set")
	mech.clearInternalDamage(MECHA_INT_FIRE)
	TEST_ASSERT(!mech.hasInternalDamage(MECHA_INT_FIRE), "the affliction clears")
	clear_debris(T)
