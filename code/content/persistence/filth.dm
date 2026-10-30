/obj/effect/decal/cleanable/filth
	name = "filth"
	desc = "Disgusting. Someone from last shift didn't do their job properly."
	icon = 'icons/effects/blood.dmi'
	icon_state = "mfloor1"
	random_icon_states = list("mfloor1", "mfloor2", "mfloor3", "mfloor4", "mfloor5", "mfloor6", "mfloor7")
	color = "#464f33"
	anchored = TRUE
	persistent = TRUE

CAPABILITIES(/obj/effect/decal/cleanable/filth)
	rolls(nameof(alpha), range_of(180, 220))

