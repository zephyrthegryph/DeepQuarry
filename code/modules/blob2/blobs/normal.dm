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

/obj/structure/blob/normal/look_parts(datum/look/look)
	..()
	var/desc_shown
	if(get_integrity_damage() >= max_integrity - 15)
		look.state("blob_damaged")
		desc_shown = "A thin lattice of slightly twitching tendrils."
	else
		look.state("blob")
		desc_shown = "A thick wall of writhing tendrils."
	look.identity(name = look_title ? "[look_title]" : "inert [base_name]", desc = desc_shown)

/obj/structure/blob/normal/pulsed()
	..()

	if(prob(30))
		adjust_scale((rand(10, 13) / 10), (rand(10, 13) / 10))

	else
		adjust_scale(1)
