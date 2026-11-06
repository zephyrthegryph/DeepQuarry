/**
 * Possible 'state' options for change_state(state) are:
 * off: Default, boring
 * on: Showing a display/powered up
 */
// A console from TGMC
/obj/structure/prop/machine/tgmc_console5
	name = "console"
	icon_state = "tgmc_console5"

/obj/structure/prop/machine/tgmc_console5/change_state(state)
	. = ..()
	switch(state)
		if("off")
			set_icon_state("tgmc_console5")
		if("on")
			set_icon_state("tgmc_console5_on")

/obj/structure/prop/machine/tgmc_console5/starts_on
	icon_state = "tgmc_console5_on"
