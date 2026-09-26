/obj/item/spell/aura
	name = "aura template"
	desc = "If you can read me, the game broke!  Yay!"
	icon_state = "generic"
	cast_methods = null
	aspect = null
	var/glow_color = "#FFFFFF"

/obj/item/spell/aura/Initialize(mapload)
	. = ..()
	set_light(calculate_spell_power(7), calculate_spell_power(4), l_color = glow_color)
	PERIODIC_START(src, PERIODIC_SLOW)
	log_and_message_admins("has started casting [src].")

/obj/item/spell/aura/Destroy()
	PERIODIC_STOP(src)
	log_and_message_admins("has stopped maintaining [src].")
	return ..()

/obj/item/spell/aura/periodic_step()
	return
