/datum/technomancer/spell/destablize
	name = "Destablize"
	desc = "Creates an unstable disturbance at the targeted tile, which will afflict anyone nearby with instability who remains nearby.  This can affect you \
	and your allies as well.  The disturbance lasts for twenty seconds."
	cost = 100
	obj_path = /obj/item/spell/spawner/destablize
	category = OFFENSIVE_SPELLS

/obj/item/spell/spawner/destablize
	name = "destablize"
	desc = "Now your enemies can feel what you go through when you have too much fun."
	icon_state = "destablize"
	cast_methods = CAST_RANGED
	aspect = ASPECT_UNSTABLE
	spawner_type = /obj/effect/temporary_effect/destablize

/obj/item/spell/spawner/destablize
	light_range = 3
	light_power = 2
	light_color = "#C26DDE"
	light_on = TRUE

/obj/item/spell/spawner/destablize/on_ranged_cast(atom/hit_atom, mob/user)
	if(within_range(hit_atom) && pay_energy(2000))
		adjust_instability(15)
		..()

/obj/effect/temporary_effect/destablize
	name = "destablizing disturbance"
	desc = "This can't be good..."
	icon_state = "blueshatter"
	time_to_die = null
	light_range = 6
	light_power = 20
	light_color = "#C26DDE"
	light_on = TRUE
	var/pulses_remaining = 40 // Lasts 20 seconds.
	var/instability_power = 5
	var/instability_range = 6

/obj/effect/temporary_effect/destablize/Initialize(mapload)
	. = ..()
	radiate_loop()

/// A pulse every half second until pulses_remaining runs out.
/obj/effect/temporary_effect/destablize/proc/radiate_loop()
	if(!pulses_remaining)
		lapsed(src)
		return
	after(src, 0.5 SECONDS, PROC_REF(radiate_pulse))

/obj/effect/temporary_effect/destablize/proc/radiate_pulse()
	for(var/mob/living/L in range(src, instability_range) )
		var/radius = max(get_dist(L, src), 1)
		// Being farther away lessens the amount of instabity received.
		var/outgoing_instability = instability_power * ( 1 / (radius**2) )
		L.receive_radiated_instability(outgoing_instability)
	pulses_remaining--
	radiate_loop()
