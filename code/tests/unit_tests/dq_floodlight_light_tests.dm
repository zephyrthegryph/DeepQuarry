// An emergency floodlight casts light only while it is switched on AND its cell holds enough charge: the light follows that state through its look,
// whatever last changed it (the switch, the cell taken out, the cell run flat).

/datum/unit_test/dq_floodlight_light
	abstract_type = /datum/unit_test/dq_floodlight_light
	var/obj/machinery/floodlight/light

/datum/unit_test/dq_floodlight_light/Run()
	light = allocate(/obj/machinery/floodlight/starts_on, test_floor())
	refresh_flush()
	TEST_ASSERT(glow_of(light).range > 0, "a floodlight that is on with a charged cell casts light")
	check()

/datum/unit_test/dq_floodlight_light/proc/check()
	return

/datum/unit_test/dq_floodlight_light/switched_off
/datum/unit_test/dq_floodlight_light/cell_removed
/datum/unit_test/dq_floodlight_light/cell_empty
/datum/unit_test/dq_floodlight_light/off_from_the_start

/datum/unit_test/dq_floodlight_light/switched_off/check()
	light.turn_off()
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(light).range, 0, "a floodlight switched off casts nothing")
	TEST_ASSERT(!light.light_on, "and its light source is off")

/datum/unit_test/dq_floodlight_light/cell_removed/check()
	rel_take(light, nameof(light.cell)) // the cell taken out while it is on (the "use" op): the switch is reset too, and the light must go either way
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(light).range, 0, "a floodlight with no cell casts nothing")
	TEST_ASSERT(!light.light_on, "and its light source is off")

/datum/unit_test/dq_floodlight_light/cell_empty/check()
	light.cell.set_charge(0) // run flat (use() is rate-limited, so a drain in one call does not empty it)
	TEST_ASSERT_EQUAL(light.cell.charge, 0, "the cell is flat")
	cell_run_step(light) // the step that finds it: the floodlight shuts down
	TEST_ASSERT(!light.on, "a floodlight whose cell cannot feed a step is switched off by its step")
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(light).range, 0, "and casts nothing")
	TEST_ASSERT(!light.light_on, "its light source is off")

/datum/unit_test/dq_floodlight_light/off_from_the_start/Run()
	var/obj/machinery/floodlight/dark = allocate(/obj/machinery/floodlight, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(dark).range, 0, "a floodlight that was never switched on casts nothing")
	TEST_ASSERT(!dark.light_on, "and its light source is off")
