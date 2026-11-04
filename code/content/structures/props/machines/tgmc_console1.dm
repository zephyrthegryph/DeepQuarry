/**
 * Possible 'state' options for change_state(state) are:
 * off: Default, boring
 * on: Showing a display/powered up
 */
// A console from TGMC
/obj/structure/prop/machine/tgmc_console1
	name = "console"
	icon = 'icons/obj/props/decor.dmi'
	icon_state = "tgmc_console1"

/obj/structure/prop/machine/tgmc_console1/change_state(state)
	. = ..()
	switch(state)
		if("off")
			set_icon_state("tgmc_console1")
		if("on")
			set_icon_state("tgmc_console1_on")

/obj/structure/prop/machine/tgmc_console1/starts_on
	icon_state = "tgmc_console1_on"
