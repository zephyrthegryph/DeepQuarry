
/obj/effect/temporary_effect/eruption
	name = "eruption"
	desc = "Oh shit!"
	icon_state = "pool"
	icon = 'icons/effects/64x64.dmi'
	time_to_die = 0.7 SECONDS

	pixel_x = -16

CAPABILITIES(/obj/effect/temporary_effect/eruption)
	param(nameof(extra_time), pos = 1, default = 10 SECONDS)
	param(nameof(color), pos = 2)
	after_init(nameof(eruption_delay), then(PROC_REF(erupt_after_init)))
	derives(nameof(time_to_die), PROC_REF(extended_life))
	derives(nameof(eruption_delay), PROC_REF(delay_before_end))

/// How much longer than its type the eruption lasts (its constructor param).
/obj/effect/temporary_effect/eruption/var/extra_time

// ALLOW(init/INSTANCE_STATE): an eruption erupts on its turf just before it ends
/obj/effect/temporary_effect/eruption/Initialize(mapload)
	. = ..()
	flick("[icon_state]_create",src)

/// It lasts its extra time longer than its type (derives(), at init; read by lives_for()).
/obj/effect/temporary_effect/eruption/proc/extended_life()
	return time_to_die + (extra_time || 0)

/// It erupts just before it ends (derives(), at init, after its life; read by its after_init()).
/obj/effect/temporary_effect/eruption/proc/delay_before_end()
	return time_to_die - 0.2 SECONDS

/// How long after init it erupts: just before it ends (after_init()).
/obj/effect/temporary_effect/eruption/var/eruption_delay = 0

/obj/effect/temporary_effect/eruption/proc/erupt_after_init(datum/act/A)
	on_eruption(get_turf(src))

/obj/effect/temporary_effect/eruption/proc/on_eruption(turf/Target)	// Override for specific functions, as below.
	flick("[icon_state]_erupt",src)
	return TRUE

/obj/effect/temporary_effect/eruption/test/on_eruption(turf/Target)
	flick("[icon_state]_erupt",src)
	if(Target)
		new /obj/effect/explosion(Target)
	return TRUE

/*
 * Subtypes
 */

/obj/effect/temporary_effect/eruption/flamestrike
	desc = "A bubbling pool of fire!"

/obj/effect/temporary_effect/eruption/flamestrike/on_eruption(turf/Target)
	flick("[icon_state]_erupt",src)
	if(Target)
		Target.hotspot_expose(1000, 50, 1)

		for(var/mob/living/L in turf_contents_of_type(Target, /mob/living))
			L.adjust_fire_stacks(2)
			L.ignite_mob()

	return TRUE
