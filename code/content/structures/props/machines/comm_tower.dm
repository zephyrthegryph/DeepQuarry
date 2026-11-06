/**
 * Possible 'state' options for change_state(state) are:
 * off: Boring, static
 * on: Turny and blinky
 */
// experimental science destructor from /tg/
/obj/structure/prop/machine/comm_tower
	icon = 'icons/obj/props/decor.dmi'
	icon = 'icons/obj/props/decor96x96.dmi'
	icon_state = "comm_tower"

/obj/structure/prop/machine/comm_tower/change_state(state)
	. = ..()
	switch(state)
		if("on")
			set_icon_state("comm_tower_on")
		if("off")
			set_icon_state("comm_tower")

/obj/structure/prop/machine/comm_tower/starts_on
	icon_state = "comm_tower_on"
