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

CAPABILITIES(/obj/effect/temporary_effect)
	lives_for(nameof(time_to_die))

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

/obj/effect/temporary_effect/cleave_attack/proc/start_slash_fade()
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

/// Rolled before init (rolls()): one of the two lightning sprites.
/obj/effect/temporary_effect/lightning_strike/proc/roll_variant(datum/roller/R)
	return "[icon_state][R.number(1, 2)]"

CAPABILITIES(/obj/effect/temporary_effect/lightning_strike)
	rolls(nameof(icon_state), PROC_REF(roll_variant))

/obj/effect/temporary_effect/lightning_strike/Initialize(mapload)
	animate(src, alpha = 0, time = time_to_die - 1)
	. = ..()

/obj/effect/dummy/lighting_obj
	name = "lighting fx obj"
	desc = "Tell a coder if you're seeing this."
	icon_state = "nothing"
	light_system = MOVABLE_LIGHT
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	light_on = TRUE
	blocks_emissive = EMISSIVE_BLOCK_NONE

CAPABILITIES(/obj/effect/dummy/lighting_obj)
	configure(light_glow(range = MINIMUM_USEFUL_LIGHT_RANGE, color = COLOR_WHITE))
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

CAPABILITIES(/obj/effect/dummy/lighting_obj/moblight/fire)
	configure(light_glow(color = LIGHT_COLOR_FIRE, range = LIGHT_RANGE_FIRE))

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
	setup(PROC_REF(display_light_spot))
	owns_one(nameof(light_spot), /obj/effect/abstract/light_spot, starts = /obj/effect/abstract/light_spot, starts_args = NO_LOC)

/obj/effect/abstract/directional_lighting/proc/display_light_spot()
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


// Only its light component may delete it (a forced qdel()). Anything else that
// deletes what lies on a turf (a cleared tile, a swept block) reaches it too: it
// stays its component's, stepping out of the world until the light casts again.
/obj/effect/abstract/directional_lighting/lifecycle_keep(force)
	if(force)
		return FALSE
	moveToNullspace()
	return TRUE


CAPABILITIES(/obj/effect/temporary_effect/cleave_attack)
	setup(PROC_REF(start_slash_fade))
