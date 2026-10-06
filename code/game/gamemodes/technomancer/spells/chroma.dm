/datum/technomancer/spell/chroma
	name = "Chroma"
	desc = "Creates light around you, or in a location of your choosing.  You can choose what color the light is.  This could be \
	useful to trick someone into believing you're casting a different spell, or perhaps just for fun."
	cost = 25
	obj_path = /obj/item/spell/chroma
	category = UTILITY_SPELLS

/obj/item/spell/chroma
	name = "chroma"
	desc = "The colors are dazzling."
	icon_state = "darkness"
	cast_methods = CAST_RANGED | CAST_USE
	aspect = ASPECT_LIGHT
	var/color_to_use = "#FFFFFF"

/obj/item/spell/chroma/Initialize(mapload, coreless)
	. = ..()
	set_light(6, 5, l_color = color_to_use)

/obj/effect/temporary_effect/chroma
	name = "chroma"
	desc = "How are you examining what which cannot be seen?"
	invisibility = INVISIBILITY_ABSTRACT
	time_to_die = 2 MINUTES //Despawn after this time, if set.

CAPABILITIES(/obj/effect/temporary_effect/chroma)
	param(nameof(chroma_color), pos = 1, apply = PROC_REF(glow))

/// The glow's colour (its constructor param).
/obj/effect/temporary_effect/chroma/var/chroma_color = "#FFFFFF"

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/effect/temporary_effect/chroma/proc/glow(colour)
	set_light(6, 5, l_color = colour)

/obj/item/spell/chroma/on_ranged_cast(atom/hit_atom, mob/user)
	var/turf/T = get_turf(hit_atom)
	if(T)
		new /obj/effect/temporary_effect/chroma(T, color_to_use)
		to_chat(user, span_notice("You shift the light onto \the [T]."))
		consume(src, user)

/obj/item/spell/chroma/on_use_cast(mob/user)
	open_request(src, /datum/prompt/color, PROC_REF(chroma_color_picked), answerer = user, title = "Color selection", question = "Choose the color you want your light to be.", ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)

/obj/item/spell/chroma/proc/chroma_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/new_color = A.answer.value
	if(new_color)
		color_to_use = new_color
		set_light(6, 5, l_color = new_color)
