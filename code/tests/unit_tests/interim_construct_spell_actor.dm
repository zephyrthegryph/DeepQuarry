/// Capture the repair actor while executing the real pylon restoration.
/obj/structure/cult/pylon/interim_actor_probe
	var/last_repair_actor_ref

/obj/structure/cult/pylon/interim_actor_probe/repair(mob/user)
	last_repair_actor_ref = user ? REF(user) : null
	return ..()

/// Construct pylon repair uses the caster passed through the spell chain.
/datum/unit_test/interim_construct_pylon_repair_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/cult/pylon/interim_actor_probe/pylon = allocate(/obj/structure/cult/pylon/interim_actor_probe, T)
	var/datum/spell/aoe_turf/conjure/pylon/spell = allocate(/datum/spell/aoe_turf/conjure/pylon)
	// Exercise repair of an existing pylon without creating a second one.
	spell.summon_amt = 0
	pylon.set_isbroken(TRUE)
	pylon.set_density(FALSE)
	spell.cast(list(T), user)
	TEST_ASSERT_EQUAL(pylon.last_repair_actor_ref, REF(user), "the explicit caster reaches the real pylon repair")
	TEST_ASSERT(!pylon.isbroken, "the spell repairs the broken pylon")
	TEST_ASSERT(pylon.density, "repair restores the pylon's physical density")
