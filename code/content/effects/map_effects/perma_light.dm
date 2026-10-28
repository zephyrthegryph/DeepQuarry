// Emits light forever with magic. Useful for mood lighting in Points of Interest.
// Be sure to check how it looks ingame, and fiddle with the settings until it looks right.
/obj/effect/map_effect/perma_light
	name = "permanent light"
	icon_state = "permalight"

	light_on = TRUE

/obj/effect/map_effect/perma_light/brighter
	name = "permanent light (bright)"
	icon_state = "permalight"

CAPABILITIES(/obj/effect/map_effect/perma_light/brighter)
	configure(light_glow(range = 5, power = 3, color = "#FFFFFF"))


/obj/effect/map_effect/perma_light/concentrated
	name = "permanent light (concentrated)"

CAPABILITIES(/obj/effect/map_effect/perma_light/concentrated)
	configure(light_glow(range = 2, power = 5))


/obj/effect/map_effect/perma_light/concentrated/incandescent
	name = "permanent light (concentrated incandescent)"

CAPABILITIES(/obj/effect/map_effect/perma_light/concentrated/incandescent)
	configure(light_glow(color = LIGHT_COLOR_INCANDESCENT_TUBE))


// ition Start
/obj/effect/map_effect/perma_light/gateway
	name = "permanent light (gateway)"
	icon_state = "permalight"

CAPABILITIES(/obj/effect/map_effect/perma_light/gateway)
	configure(light_glow(range = 10, power = 5, color = "#b6cdff"))

// ition End
