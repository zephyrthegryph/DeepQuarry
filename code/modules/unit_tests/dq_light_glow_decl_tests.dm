// Light fixtures declare the glow and draw of the bulb they start with (code/modules/power/lighting_glow_decls.dm), so a fixture's first
// refresh_light() writes nothing it does not change. These tests hold the declarations to the bulbs and the init state to the old arithmetic.

/// Every light fixture type declares exactly what its starting bulb gives: glow range, power and colour, and the active draw refresh_light()
/// computes from them. A mismatch prints the line to paste into lighting_glow_decls.dm (the file is generated from this test's output).
/datum/unit_test/dq_light_glow_declared

/datum/unit_test/dq_light_glow_declared/Run()
	var/list/lines = list()
	var/checked = 0
	for(var/type in typesof(/obj/machinery/light))
		var/obj/machinery/light/typed = type
		var/light_type = initial(typed.light_type)
		if(!ispath(light_type, /obj/item/light))
			continue
		var/obj/item/light/bulb = get_light_type_instance(light_type)
		var/datum/type_trait/light_glow/glow = glow_of_type(type)
		var/datum/type_trait/power/draw = power_of_type(type)
		var/range = light_glow_cast_range(bulb.brightness_range)
		var/active = range * bulb.brightness_power * LIGHTING_POWER_FACTOR
		checked++
		if(glow.range != range || glow.power != bulb.brightness_power || glow.color != bulb.brightness_color || draw.active != active)
			lines += "CAPABILITIES([type])\n\tconfigure(light_glow(range = [range], power = [bulb.brightness_power], color = \"[bulb.brightness_color]\"))\n\tconfigure(uses_power(idle = [draw.idle], active = [range] * [bulb.brightness_power] * LIGHTING_POWER_FACTOR, channel = LIGHT))"
	if(length(lines))
		log_world("dq_light_glow_declared: paste into code/modules/power/lighting_glow_decls.dm:\n[jointext(lines, "\n\n")]")
	TEST_ASSERT(!length(lines), "[length(lines)] of [checked] light fixture types declare another glow or draw than their starting bulb (the world log has the lines)")

/// A fixture initialised on a powered and on an unpowered tile ends in the state refresh_light()'s arithmetic gives: lit with its bulb's glow and the
/// draw it implies, or dark with range 0 and no active draw. Every fixture type.
/datum/unit_test/dq_light_glow_init_state

/datum/unit_test/dq_light_glow_init_state/Run()
	var/turf/at = run_loc_floor_bottom_left
	for(var/type in typesof(/obj/machinery/light))
		var/obj/machinery/light/typed = type
		if(!ispath(initial(typed.light_type), /obj/item/light))
			continue
		rand_seed(4242) // the bulb's broken_chance rolls the same every time
		var/list/had = at.contents.Copy()
		var/obj/machinery/light/L = new type(at)
		var/datum/type_trait/light_glow/glow = glow_of(L)
		if(L.on)
			var/range = L.nightshift_enabled ? L.brightness_range_ns : L.brightness_range
			var/power = L.nightshift_enabled ? L.brightness_power_ns : L.brightness_power
			var/color = L.nightshift_enabled ? L.brightness_color_ns : L.brightness_color
			if(L.current_alert)
				range = L.brightness_range
				power = L.brightness_power
				color = L.brightness_color
			TEST_ASSERT_EQUAL(glow.range, light_glow_cast_range(range), "[type] lit: glow range")
			TEST_ASSERT_EQUAL(glow.power, power, "[type] lit: glow power")
			TEST_ASSERT_EQUAL(glow.color, color, "[type] lit: glow colour")
		else if(!L.emergency_mode)
			TEST_ASSERT_EQUAL(glow.range, 0, "[type] dark: glow range")
		TEST_ASSERT_EQUAL(power_of(L).active, glow.range * glow.power * LIGHTING_POWER_FACTOR, "[type]: the active draw follows the glow")
		qdel(L)
		for(var/atom/movable/left in at.contents - had)
			qdel(left) // what the fixture left (a dropped bulb, a broken bulb's sparks): the next fixture starts on a clean tile

/// The range set_glow() gives a light asked for `range`: one below MINIMUM_USEFUL_LIGHT_RANGE (but above 0) is raised to it.
/proc/light_glow_cast_range(range)
	return (range > 0 && range < MINIMUM_USEFUL_LIGHT_RANGE) ? MINIMUM_USEFUL_LIGHT_RANGE : range
