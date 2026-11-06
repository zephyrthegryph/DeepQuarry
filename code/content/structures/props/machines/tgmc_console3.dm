/**
 * Possible 'state' options for change_state(state) are:
 * off: Default, boring
 * on: Showing a display/powered up
 */
// A console from TGMC
/obj/structure/prop/machine/tgmc_console3
	name = "console"
	icon_state = "tgmc_console3"

/obj/structure/prop/machine/tgmc_console3/change_state(state)
	. = ..()
	switch(state)
		if("off")
			set_icon_state("tgmc_console3")
		if("on")
			set_icon_state("tgmc_console3_on")

/obj/structure/prop/machine/tgmc_console3/starts_on
	icon_state = "tgmc_console3_on"
