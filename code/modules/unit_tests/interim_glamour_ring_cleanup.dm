/datum/unit_test/interim_glamour_ring_cleanup
	var/other_breaker = FALSE

/datum/unit_test/interim_glamour_ring_cleanup/other_actor
	other_breaker = TRUE

/datum/unit_test/interim_glamour_ring_cleanup/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/owner = allocate(/mob/living/carbon/human, T)
	owner.set_species(SPECIES_LLEILL)
	TEST_ASSERT(istype(owner.species, /datum/species/lleill), "The real ring owner genuinely has the Lleill species")
	TEST_ASSERT_EQUAL(length(owner.teleporters), 0, "The real owner starts without any glamour rings")
	var/energy_before = owner.species.lleill_energy
	TEST_ASSERT(energy_before >= 25, "The actual species has enough energy for its real second-ring price")
	owner.lleill_ring_placed(0)
	own_turf_contents(T)
	TEST_ASSERT_EQUAL(length(owner.teleporters), 1, "The actual first-ring completion registers one original ring")
	var/obj/structure/glamour_ring/first = owner.teleporters[1]
	TEST_ASSERT(first && !QDELETED(first) && first.loc == T, "The actual first ring remains on the original floor")
	TEST_ASSERT_EQUAL(first.connected_mob, owner, "The actual constructor callback links its original owner")
	owner.lleill_ring_placed(25)
	own_turf_contents(T)
	TEST_ASSERT_EQUAL(length(owner.teleporters), 2, "The actual second-ring completion retains both original registrations")
	TEST_ASSERT_EQUAL(owner.species.lleill_energy, energy_before - 25, "The real placement callbacks preserve their exact original energy prices")
	var/obj/structure/glamour_ring/second
	for(var/obj/structure/glamour_ring/R as anything in owner.teleporters)
		if(R != first)
			second = R
	TEST_ASSERT(second && !QDELETED(second) && second.loc == T, "The actual second placement creates a distinct original floor ring")
	TEST_ASSERT_EQUAL(second.connected_mob, owner, "The actual second ring has the same real owner")
	var/mob/living/carbon/human/breaker = owner
	if(other_breaker)
		breaker = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(!QDELETED(first), "A ring nobody broke keeps its original ring")
	TEST_ASSERT_EQUAL(length(owner.teleporters), 2, "Leaving the ring alone preserves both original registrations")
	first.ring_broken(breaker)
	TEST_ASSERT(QDELETED(first), "The real break completion consumes the exact selected ring")
	TEST_ASSERT_EQUAL(length(owner.teleporters), 1, "The real break completion removes exactly one owner registration")
	TEST_ASSERT_EQUAL(owner.teleporters[1], second, "The original neighboring ring remains the exact surviving registration")
	TEST_ASSERT(!QDELETED(second) && second.loc == T, "Breaking one ring preserves the original neighboring floor ring")
	TEST_ASSERT_EQUAL(second.connected_mob, owner, "The neighboring ring retains its actual original owner link")
	TEST_ASSERT_EQUAL(owner.species.lleill_energy, energy_before - 25, "Breaking a ring does not refund or debit placement energy")
	TEST_ASSERT(!QDELETED(owner) && !QDELETED(breaker), "The real break completion preserves both actual participants")
