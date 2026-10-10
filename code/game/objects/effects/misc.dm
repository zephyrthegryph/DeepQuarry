//The effect when you wrap a dead body in gift wrap
/obj/effect/spresent
	name = "strange present"
	desc = "It's a ... present?"
	icon = 'icons/obj/gifts.dmi'
	icon_state = "strangepresent"
	density = TRUE
	anchored = FALSE

/obj/effect/temporary_effect
	name = "self deleting effect"
	desc = "How are you examining what which cannot be seen?"
	icon = 'icons/effects/effects.dmi'
	invisibility = INVISIBILITY_NONE
	var/time_to_die = 10 SECONDS // Afer which, it will delete itself.

/obj/effect/temporary_effect/Initialize(mapload)
	. = ..()
	if(time_to_die)
		expire(time_to_die)

// Shown really briefly when attacking with axes.
/obj/effect/temporary_effect/cleave_attack
	name = "cleaving attack"
	desc = "Something swinging really wide."
	icon = 'icons/effects/96x96.dmi'
	icon_state = "cleave"
	plane = ABOVE_MOB_PLANE
	layer = ABOVE_MOB_LAYER
	time_to_die = 6
	alpha = 140
	mouse_opacity = 0
	pixel_x = -32
	pixel_y = -32

/obj/effect/temporary_effect/cleave_attack/Initialize(mapload) // Makes the slash fade smoothly. When completely transparent it should qdel itself.
	. = ..()
	animate(src, alpha = 0, time = time_to_die - 1)

/obj/effect/temporary_effect/shuttle_landing
	name = "shuttle landing"
	desc = "You better move if you don't want to go splat!"
	icon = 'icons/goonstation/featherzone.dmi'
	icon_state = "hazard-corners"
	time_to_die = 5 SECONDS
	plane = PLANE_LIGHTING_ABOVE

// The manifestation of Zeus's might. Or just a really unlucky day.
// This is purely a visual effect, this isn't the part of the code that hurts things.
/obj/effect/temporary_effect/lightning_strike
	name = "lightning"
	desc = "How <i>shocked</i> you must be, to see this text. You must have <i>lightning</i> reflexes. \
	The humor in this description is just so <i>electrifying</i>."
	icon = 'icons/effects/96x256.dmi'
	icon_state = "lightning_strike"
	plane = PLANE_LIGHTING_ABOVE
	time_to_die = 1 SECOND
	pixel_x = -32

/obj/effect/temporary_effect/lightning_strike/Initialize(mapload)
	icon_state += "[rand(1,2)]" // To have two variants of lightning sprites.
	animate(src, alpha = 0, time = time_to_die - 1)
	. = ..()

/obj/effect/dummy/lighting_obj
	name = "lighting fx obj"
	desc = "Tell a coder if you're seeing this."
	icon_state = "nothing"
	light_system = MOVABLE_LIGHT
	light_range = MINIMUM_USEFUL_LIGHT_RANGE
	light_color = COLOR_WHITE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	light_on = TRUE
	blocks_emissive = EMISSIVE_BLOCK_NONE

CAPABILITIES(/obj/effect/dummy/lighting_obj)
	param(nameof(glow_range), pos = 1)
	param(nameof(glow_power), pos = 2)
	param(nameof(glow_color), pos = 3)
	param(nameof(glow_duration), pos = 4, apply = PROC_REF(glow))

/// The light and how long it lasts (its constructor params).
/obj/effect/dummy/lighting_obj/var/glow_range
/obj/effect/dummy/lighting_obj/var/glow_power
/obj/effect/dummy/lighting_obj/var/glow_color
/obj/effect/dummy/lighting_obj/var/glow_duration

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/effect/dummy/lighting_obj/proc/glow(duration)
	if(!isnull(glow_range))
		set_light_range(glow_range)
	if(!isnull(glow_power))
		set_light_power(glow_power)
	if(!isnull(glow_color))
		set_light_color(glow_color)
	if(duration)
		expire(duration)

/obj/effect/dummy/lighting_obj/moblight
	name = "mob lighting fx"

/// A mob's light lives on a mob (keeps_if()): a condition.
/obj/effect/dummy/lighting_obj/moblight/proc/on_a_mob()
	return ismob(loc)

CAPABILITIES(/obj/effect/dummy/lighting_obj/moblight)
	keeps_if(PROC_REF(on_a_mob))

/obj/effect/dummy/lighting_obj/moblight/fire
	name = "fire"
	light_color = LIGHT_COLOR_FIRE
	light_range = LIGHT_RANGE_FIRE

/obj/effect/abstract
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	plane = ABOVE_MOB_PLANE

/obj/effect/abstract/light_spot
	icon = 'icons/effects/eris_flashlight.dmi'
	icon_state = "medium"
	pixel_x = -16
	pixel_y = -16

/obj/effect/abstract/directional_lighting
	var/obj/effect/abstract/light_spot/light_spot
	var/trans_angle
	var/icon_dist

CAPABILITIES(/obj/effect/abstract/directional_lighting)
	owns_one(nameof(light_spot), /obj/effect/abstract/light_spot)

/obj/effect/abstract/directional_lighting/Initialize(mapload)
	rel_set(src, nameof(light_spot), new /obj/effect/abstract/light_spot)
	. = ..()
	vis_contents += light_spot

/obj/effect/abstract/directional_lighting/proc/face_light(atom/movable/source, angle, distance)
	if(!loc) // We're in nullspace
		return

	// Save ourselves some matrix math
	if(angle != trans_angle)
		trans_angle = angle
		// Doing this in one operation (tn = turn(initial(tn), angle)) has strange results...
		light_spot.transform = initial(light_spot.transform)
		light_spot.transform = turn(light_spot.transform, angle)

	if(icon_dist != distance)
		icon_dist = distance
		switch(distance)
			if(0)
				light_spot.icon_state = "vclose"
			if(1)
				light_spot.icon_state = "close"
			if(2)
				light_spot.icon_state = "medium"
			if(3 to INFINITY)
				light_spot.icon_state = "far"


// Only its light component may delete it (a forced qdel()).
/obj/effect/abstract/directional_lighting/lifecycle_keep(force)
	if(force)
		return FALSE
	stack_trace("Directional light atom deleted, but not by our component")
	return TRUE

