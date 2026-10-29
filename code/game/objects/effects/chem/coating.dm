/*
 * Home of the floor chemical coating.
 */

/obj/effect/decal/cleanable/chemcoating
	icon = 'icons/effects/effects.dmi'
	icon_state = "dirt"

CAPABILITIES(/obj/effect/decal/cleanable/chemcoating)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_by)))
	setup(PROC_REF(merge_existing_coatings))
	reagents(100)

/obj/effect/decal/cleanable/chemcoating/proc/merge_existing_coatings()
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

/// Something walked into or over the coating: it is touched by what the coating holds.
/obj/effect/decal/cleanable/chemcoating/proc/touched_by(atom/movable/A)
	if(reagents)
		reagents.touch(A)

/// The bump notice (was Bumped()).
/obj/effect/decal/cleanable/chemcoating/proc/bumped_by(datum/act/bump_act)
	var/datum/notice/bumped/N = bump_act
	touched_by(N.bumper)

/obj/effect/decal/cleanable/chemcoating/Crossed(AM as mob|obj)
	touched_by(AM)

/// The coating is the colour of what it holds.
/obj/effect/decal/cleanable/chemcoating/cleanable_look(datum/look/look)
	look.set_color(reagents.get_color())
	janitor_hud(look)
