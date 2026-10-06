/datum/unit_test/interim_invisible_soil_terminal_cleanup
	var/seedless = FALSE

/datum/unit_test/interim_invisible_soil_terminal_cleanup/seedless
	seedless = TRUE

/datum/unit_test/interim_invisible_soil_terminal_cleanup/Run()
	var/turf/T = test_floor()
	var/datum/seed/seed = SSplants.seeds[PLANT_GLOWSHROOM]
	TEST_ASSERT_NOTNULL(seed, "The real plant service supplies its original registered glowshroom seed")
	seed.update_growth_stages()
	TEST_ASSERT(seed.growth_stages > 0 && seed.get_trait(TRAIT_ENDURANCE) > 0, "The actual registered seed has real constructor growth and endurance")
	var/obj/effect/plant/plant = allocate(/obj/effect/plant, T, seed)
	TEST_ASSERT(plant && !QDELETED(plant), "The real floor plant completes its original seeded constructor")
	TEST_ASSERT_EQUAL(plant.seed(), seed, "The actual original plant retains the exact registered seed")
	plant.invisibility = INVISIBILITY_MAXIMUM
	var/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/soil = allocate(/obj/machinery/portable_atmospherics/hydroponics/soil/invisible, T, seed)
	TEST_ASSERT(soil && !QDELETED(soil) && soil.loc == T, "The actual invisible soil holder completes its real floor constructor")
	TEST_ASSERT_EQUAL(soil.seed, seed, "The actual original holder uses the exact shared registered seed")
	var/obj/scratch = soil.temp_chem_holder
	TEST_ASSERT(scratch && !QDELETED(scratch), "The actual parent constructor creates its real owned chemistry scratch holder")
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT_EQUAL(plant.invisibility, INVISIBILITY_MAXIMUM, "The actual original plant is genuinely masked before holder cleanup")
	if(seedless)
		proto_set(soil, nameof(soil.seed), null)
		TEST_ASSERT_NULL(soil.seed, "The actual holder enters its real seedless terminal processing state")
		TEST_ASSERT_EQUAL(soil.work_step(null), PROCESS_KILL, "Actual seedless processing retains its original terminal scheduler result")
	else
		soil.die()
	TEST_ASSERT(QDELETED(soil), "The actual terminal endpoint consumes the exact original invisible soil holder")
	TEST_ASSERT(QDELETED(scratch), "Actual holder cleanup releases and destroys its exact original owned scratch child")
	TEST_ASSERT(!QDELETED(plant) && plant.loc == T, "Actual holder cleanup preserves the exact original masked plant on its floor")
	TEST_ASSERT_EQUAL(plant.invisibility, initial(plant.invisibility), "The actual on-destroy chain unmasks the original surviving plant")
	TEST_ASSERT_EQUAL(plant.seed(), seed, "Actual holder cleanup preserves the original surviving plant seed identity")
	TEST_ASSERT(!QDELETED(seed), "Actual holder cleanup preserves the shared registered seed")
	TEST_ASSERT(!QDELETED(pen) && pen.loc == T, "Actual holder cleanup preserves the unrelated original floor item")
