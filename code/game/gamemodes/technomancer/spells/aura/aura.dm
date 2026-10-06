/obj/item/spell/aura
	name = "aura template"
	desc = "If you can read me, the game broke!  Yay!"
	icon_state = "generic"
	cast_methods = null
	aspect = null
	var/glow_color = "#FFFFFF"

CAPABILITIES(/obj/item/spell/aura)
	every(2 SECONDS, then(PROC_REF(aura_step)))

/obj/item/spell/aura/Initialize(mapload)
	. = ..()
	set_light(calculate_spell_power(7), calculate_spell_power(4), l_color = glow_color)
	log_and_message_admins("has started casting [src].")

// admins are told the maintained spell stopped.
/obj/item/spell/aura/on_destroy(force)
	log_and_message_admins("has stopped maintaining [src].")
	..()

/obj/item/spell/aura/proc/aura_step(datum/act/timer/A)
	return
