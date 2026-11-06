/**
 * Possible 'state' options for change_state(state) are:
 * whole: Not doing much
 * broken: Stamping mysterious substances
 */
// alien autopsy thing from TGMC
/obj/structure/prop/machine/alien_tank
	icon_state = "tank_larva"

/obj/structure/prop/machine/alien_tank/change_state(state)
	. = ..()
	switch(state)
		if("whole")
			set_icon_state("tank_larva")
		if("broken")
			set_icon_state("tank_broken")

/obj/structure/prop/machine/alien_tank/starts_broken
	icon_state = "tank_broken"
