// The glow and draw each light fixture type starts with: its starting bulb's (light_type) brightness, the range raised as set_glow() raises it, and
// the active draw refresh_light() computes from them. Declared per type, the fixture's first refresh_light() on a powered tile writes nothing,
// where it made every fixture copy its type's trait and publish it. Generated from dq_light_glow_declared's output (it prints the lines again when a
// bulb or a fixture type changes); do not edit by hand.

CAPABILITIES(/obj/machinery/light/small)
	configure(light_glow(range = 4, power = 1, color = "#FFFEB8"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon)
	configure(light_glow(range = 4, power = 1, color = "#00ff15"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/generic_yellow)
	configure(light_glow(range = 4, power = 1, color = "#fff200"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/generic_red)
	configure(light_glow(range = 4, power = 1, color = "#da0205"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/generic_blue)
	configure(light_glow(range = 4, power = 1, color = "#0048ff"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/generic_orange)
	configure(light_glow(range = 4, power = 1, color = "#ff8000"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/generic_pink)
	configure(light_glow(range = 4, power = 1, color = "#ff00ee"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/generic_purple)
	configure(light_glow(range = 4, power = 1, color = "#6200ff"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/looktoucheat)
	configure(light_glow(range = 4, power = 1, color = "#ff00ee"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/altevian)
	configure(light_glow(range = 4, power = 1, color = "#ff8000"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/nif1)
	configure(light_glow(range = 4, power = 1, color = "#0048ff"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/nif2)
	configure(light_glow(range = 4, power = 1, color = "#0048ff"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/bar)
	configure(light_glow(range = 4, power = 1, color = "#6200ff"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/unclothe)
	configure(light_glow(range = 4, power = 1, color = "#ff8000"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/import)
	configure(light_glow(range = 4, power = 1, color = "#fff200"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/police)
	configure(light_glow(range = 4, power = 1, color = "#ff00ee"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/neon/dice)
	configure(light_glow(range = 4, power = 1, color = "#fff200"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/emergency)
	configure(light_glow(range = 4, power = 1, color = "#da0205"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/fairylights)
	configure(light_glow(range = 1.4, power = 0.5, color = "#FFFEB8"))
	configure(uses_power(idle = 2, active = 1.4, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/fluorescent)
	configure(light_glow(range = 4, power = 1, color = "#E0EFFF"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/small/yellowed)
	configure(light_glow(range = 4, power = 0.5, color = "#E1E17D"))
	configure(uses_power(idle = 2, active = 4, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/spot)
	configure(light_glow(range = 8, power = 2, color = "#E0EFF0"))
	configure(uses_power(idle = 2, active = 32, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/lamppost)
	configure(light_glow(range = 4, power = 1, color = "#FFFEB8"))
	configure(uses_power(idle = 2, active = 8, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/fluorescent)
	configure(light_glow(range = 6, power = 1, color = "#E0EFFF"))
	configure(uses_power(idle = 2, active = 12, channel = LIGHT))

CAPABILITIES(/obj/machinery/light/yellowed)
	configure(light_glow(range = 6, power = 0.45, color = "#E1E17D"))
	configure(uses_power(idle = 2, active = 6 * 0.45 * LIGHTING_POWER_FACTOR, channel = LIGHT)) // the product as refresh_light() computes it: 5.4 as a literal is another float
