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

TRACKED(/obj/item/spell/chroma, color_to_use)

CAPABILITIES(/obj/item/spell/chroma)
	look_glow(PROC_REF(chroma_glow))

/// The spell's light, in the colour picked for it.
/obj/item/spell/chroma/proc/chroma_glow()
	return GLOW(6, 5, color_to_use)

/obj/effect/temporary_effect/chroma
	name = "chroma"
	desc = "How are you examining what which cannot be seen?"
	invisibility = INVISIBILITY_ABSTRACT
	time_to_die = 2 MINUTES //Despawn after this time, if set.

CAPABILITIES(/obj/effect/temporary_effect/chroma)
	param(nameof(chroma_color), pos = 1)
	look_glow(PROC_REF(chroma_glow))

/// The glow's colour (its constructor param).
/obj/effect/temporary_effect/chroma/var/chroma_color = "#FFFFFF"

/// The light the spell left, in its colour.
/obj/effect/temporary_effect/chroma/proc/chroma_glow()
	return GLOW(6, 5, chroma_color)

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
		set_color_to_use(new_color)
