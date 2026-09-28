/obj/item/spell/aura
	name = "aura template"
	desc = "If you can read me, the game broke!  Yay!"
	icon_state = "generic"
	cast_methods = null
	aspect = null
	var/glow_color = "#FFFFFF"

DECLARE_PERIODIC(/obj/item/spell/aura, PERIODIC_SLOW)

/obj/item/spell/aura/Initialize(mapload)
	. = ..()
	set_light(calculate_spell_power(7), calculate_spell_power(4), l_color = glow_color)
	log_and_message_admins("has started casting [src].")

// admins are told the maintained spell stopped.
/obj/item/spell/aura/on_destroy(force)
	log_and_message_admins("has stopped maintaining [src].")
	..()

/obj/item/spell/aura/periodic_step()
	return
