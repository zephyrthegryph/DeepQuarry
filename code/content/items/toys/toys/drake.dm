/obj/item/toy/plushie/borgplushie/drake
	icon = 'icons/obj/drakietoy.dmi'
	var/lights_glowing = FALSE

CAPABILITIES(/obj/item/toy/plushie/borgplushie/drake)
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Alternate use"), then(PROC_REF(interaction_alt)))

/// Old click_alt.
/obj/item/toy/plushie/borgplushie/drake/proc/interaction_alt(datum/act/op/A)
	var/mob/living/user = A.actor
	var/turf/T = get_turf(src)
	if(!T.AdjacentQuick(user)) // So people aren't messing with these from across the room
		return TRUE
	set_lights_glowing(!lights_glowing)
	to_chat(user, span_notice("You turn the [src]'s glow-fabric [lights_glowing ? "on" : "off"]."))
	return TRUE

/obj/item/toy/plushie/borgplushie/drake/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	if (lights_glowing)
		look.overlay(emissive_appearance(icon, "[drawn_state]-lights"))

/obj/item/toy/plushie/borgplushie/drake/get_mechanics_info(list/additional_information)
	return "The lights on the plushie can be toggled [lights_glowing ? "off" : "on"] by alt-clicking on it."

/obj/item/toy/plushie/borgplushie/drake/sec
	name = "security drake plushie"
	icon_state = "secdrake"

CAPABILITIES(/obj/item/toy/plushie/borgplushie/drake/sec)
	configure(atom_rules(bubble_icon = "security"))

/obj/item/toy/plushie/borgplushie/drake/med
	name = "medical drake plushie"
	icon_state = "meddrake"

CAPABILITIES(/obj/item/toy/plushie/borgplushie/drake/med)
	configure(atom_rules(bubble_icon = "cardiogram"))

/obj/item/toy/plushie/borgplushie/drake/sci
	name = "science drake plushie"
	icon_state = "scidrake"

CAPABILITIES(/obj/item/toy/plushie/borgplushie/drake/sci)
	configure(atom_rules(bubble_icon = "science"))

/obj/item/toy/plushie/borgplushie/drake/jani
	name = "janitor drake plushie"
	icon_state = "janidrake"

CAPABILITIES(/obj/item/toy/plushie/borgplushie/drake/jani)
	configure(atom_rules(bubble_icon = "synthetic"))

/obj/item/toy/plushie/borgplushie/drake/eng
	name = "engineering drake plushie"
	icon_state = "engdrake"

CAPABILITIES(/obj/item/toy/plushie/borgplushie/drake/eng)
	configure(atom_rules(bubble_icon = "engineering"))

/obj/item/toy/plushie/borgplushie/drake/mine
	name = "mining drake plushie"
	icon_state = "minedrake"

CAPABILITIES(/obj/item/toy/plushie/borgplushie/drake/mine)
	configure(atom_rules(bubble_icon = "notepad"))

/obj/item/toy/plushie/borgplushie/drake/trauma
	name = "trauma drake plushie"
	icon_state = "traumadrake"

CAPABILITIES(/obj/item/toy/plushie/borgplushie/drake/trauma)
	configure(atom_rules(bubble_icon = "medical"))
