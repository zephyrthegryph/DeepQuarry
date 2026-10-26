/datum/technomancer/spell/darkness
	name = "Darkness"
	desc = "Disrupts photons moving in a local area, causing darkness to shroud yourself or a position of your choosing."
	cost = 25
	obj_path = /obj/item/spell/spawner/darkness
	category = UTILITY_SPELLS

/obj/item/spell/spawner/darkness
	name = "darkness"
	desc = "Not even light can stand in your way now."
	icon_state = "darkness"
	cast_methods = CAST_RANGED
	aspect = ASPECT_DARK
	spawner_type = /obj/effect/temporary_effect/darkness

CAPABILITIES(/obj/item/spell/spawner/darkness)
	configure(light_glow(range = 6, power = -20, color = "#FFFFFF"))

/obj/item/spell/spawner/darkness/on_ranged_cast(atom/hit_atom, mob/user)
	if(pay_energy(500))
		adjust_instability(4)
		..()

/obj/item/spell/spawner/darkness
	light_on = TRUE

/obj/effect/temporary_effect/darkness
	name = "darkness"
	time_to_die = 2 MINUTES
	invisibility = INVISIBILITY_ABSTRACT
	light_on = TRUE

CAPABILITIES(/obj/effect/temporary_effect/darkness)
	configure(light_glow(range = 6, power = -20))
