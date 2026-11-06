/**
 * Possible 'state' options for change_state(state) are:
 * off: Default, boring
 * on: Showing a display/powered up
 */
// A console from TGMC
/obj/structure/prop/machine/tgmc_console2
	name = "console"
	icon_state = "tgmc_console2"

/obj/structure/prop/machine/tgmc_console2/change_state(state)
	. = ..()
	switch(state)
		if("off")
			set_icon_state("tgmc_console2")
		if("on")
			set_icon_state("tgmc_console2_on")

/obj/structure/prop/machine/tgmc_console2/starts_on
	icon_state = "tgmc_console2_on"
