/*
 * Home of the floor chemical coating.
 */

/obj/effect/decal/cleanable/chemcoating
	icon = 'icons/effects/effects.dmi'
	icon_state = "dirt"

CAPABILITIES(/obj/effect/decal/cleanable/chemcoating)
	reagents(100)

/obj/effect/decal/cleanable/chemcoating/Initialize(mapload)
	. = ..()
	var/turf/T = get_turf(src)
	if(T)
		for(var/obj/O in get_turf(src))
			if(O == src)
				continue
			if(istype(O, /obj/effect/decal/cleanable/chemcoating))
				var/obj/effect/decal/cleanable/chemcoating/C = O
				if(C.reagents && C.reagents.reagent_list.len)
					C.reagents.trans_to_obj(src,C.reagents.total_volume)
				spent(O)

/obj/effect/decal/cleanable/chemcoating/Bumped(A as mob|obj)
	if(reagents)
		reagents.touch(A)
	return ..()

/obj/effect/decal/cleanable/chemcoating/Crossed(AM as mob|obj)
	Bumped(AM)

DECLARE_APPEARANCE_PROC(/obj/effect/decal/cleanable/chemcoating, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/effect/decal/cleanable/chemcoating/appearance_overlays()
	. = list()
	. += ..()
	color = reagents.get_color()
	. += add_janitor_hud_overlay()
