/obj/structure/blob/normal
	name = "normal blob"
	base_name = "blob"
	icon_state = "blob"
	light_range = 0
	max_integrity = 25
	health_regen = 1

/obj/structure/blob/normal/Initialize(mapload, new_overmind)
	. = ..()
	update_integrity(21) // Doesn't start at full health.

DECLARE_APPEARANCE_PROC(/obj/structure/blob/normal, PROC_REF(appearance_overlays), list("get_integrity"))
/obj/structure/blob/normal/appearance_overlays()
	. = list()
	. += ..()
	if(get_integrity() <= 15)
		icon_state = "blob_damaged"
		desc = "A thin lattice of slightly twitching tendrils."
	else
		icon_state = "blob"
		desc = "A thick wall of writhing tendrils."

	if(overmind)
		name = "[overmind.blob_type.name]"
	else
		name = "inert [base_name]"

/obj/structure/blob/normal/pulsed()
	..()

	if(prob(30))
		adjust_scale((rand(10, 13) / 10), (rand(10, 13) / 10))

	else
		adjust_scale(1)
