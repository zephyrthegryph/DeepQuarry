/**
 * Possible 'state' options for change_state(state) are:
 * off: Non-spinny
 * on: Spinny and floaty
 */
// neotheology decorative(?) obelisk from Eris
/obj/structure/prop/machine/nt_obelisk
	icon = 'icons/obj/props/decor.dmi'
	icon_state = "nt_obelisk"

/obj/structure/prop/machine/nt_obelisk/change_state(state)
	. = ..()
	switch(state)
		if("off")
			set_icon_state("nt_obelisk")
		if("on")
			set_icon_state("nt_obelisk_on")

/obj/structure/prop/machine/nt_obelisk/starts_on
	icon_state = "nt_obelisk_on"
