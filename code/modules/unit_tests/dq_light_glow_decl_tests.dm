// Light fixtures declare the glow and draw of the bulb they start with (code/modules/power/lighting_fixture_glow.dm), so a fixture's first
// refresh_light() writes nothing it does not change: the declared light is cast as declared (light_on defaults TRUE). These tests hold the declarations to the bulbs and the init state to the old arithmetic.

/// Every light fixture type declares exactly what its starting bulb gives: glow range, power and colour, and the active draw refresh_light()
/// computes from them. A mismatch prints the line to paste into lighting_fixture_glow.dm (the test prints the lines to put there).
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
		log_world("dq_light_glow_declared: paste into code/modules/power/lighting_fixture_glow.dm:\n[jointext(lines, "\n\n")]")
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
			TEST_ASSERT(L.light_on && L.light, "[type] lit: no light source (the fixture shows on but lights nothing)")
		else if(!L.emergency_mode)
			TEST_ASSERT_EQUAL(glow.range, 0, "[type] dark: glow range")
		TEST_ASSERT_EQUAL(power_of(L).active, glow.range * glow.power * LIGHTING_POWER_FACTOR, "[type]: the active draw follows the glow")
		qdel(L)
		for(var/atom/movable/left in at.contents - had)
			qdel(left) // what the fixture left (a dropped bulb, a broken bulb's sparks): the next fixture starts on a clean tile

/// The range set_glow() gives a light asked for `range`: one below MINIMUM_USEFUL_LIGHT_RANGE (but above 0) is raised to it.
/proc/light_glow_cast_range(range)
	return (range > 0 && range < MINIMUM_USEFUL_LIGHT_RANGE) ? MINIMUM_USEFUL_LIGHT_RANGE : range

/// Every object type that declares a light (glow range and power above 0) casts it once initialised: a static light has its light source and a
/// movable one its overlay light, unless the light is dark on purpose: its glow went to 0 (set_glow(src, GLOW_OFF)), or the type declares
/// `light_on = FALSE` against the /atom default (a lamp that starts switched off). Nothing else may leave a declared light without a source.
/datum/unit_test/dq_light_declared_glow_casts

/datum/unit_test/dq_light_declared_glow_casts/Run()
	var/turf/at = run_loc_floor_bottom_left
	var/atom/base = /atom
	var/default_on = initial(base.light_on)
	var/list/bad = list()
	var/checked = 0
	var/list/room = block(run_loc_floor_bottom_left, run_loc_floor_top_right)
	set_global(nameof(GLOB.narsie_cometh), GLOB.narsie_cometh) // a spawned Nar-Sie announces itself world-wide: teardown puts the flag back
	for(var/type in typesof(/obj))
		if(is_abstract(type))
			continue
		var/datum/type_trait/light_glow/declared = glow_of_type(type)
		if(!declared.range || !declared.power)
			continue
		rand_seed(4242)
		var/list/had = list()
		for(var/turf/T as anything in room)
			had += T.contents
		var/obj/O = new type(at)
		if(!QDELETED(O))
			checked++
			var/datum/type_trait/light_glow/glow = glow_of(O)
			var/system = atom_rules_of(O).light_system
			if(glow.range && glow.power)
				var/obj/typed = type
				if(!O.light_on)
					if(initial(typed.light_on) == default_on)
						bad += "[type]: glow [glow.range]/[glow.power] but light_on FALSE, and the type does not declare light_on = FALSE"
				else if(system == STATIC_LIGHT && !O.light)
					bad += "[type]: lit (glow [glow.range]/[glow.power], light_on) but no light source"
				else if((system == MOVABLE_LIGHT || system == MOVABLE_LIGHT_DIRECTIONAL) && !O.overlay_light)
					bad += "[type]: lit (glow [glow.range]/[glow.power], light_on) but no overlay light"
			qdel(O)
		for(var/turf/T as anything in room)
			for(var/atom/movable/left in T.contents - had)
				qdel(left) // what the object made around it (an anomaly's decoy and countdown): the next type starts on a clean room
	if(length(bad))
		log_world("dq_light_declared_glow_casts:\n[jointext(bad, "\n")]")
	TEST_ASSERT(!length(bad), "[length(bad)] of [checked] object types that declare a light end init without casting it: [jointext(bad.Copy(1, min(length(bad), 8) + 1), " | ")]")
