/**
 * Possible 'state' options for change_state(state) are:
 * off: Inert
 * on: Hand destroying machinery
 */
// 'smelter' from Eris
/obj/structure/prop/machine/smelter
	icon = 'icons/obj/props/decor.dmi'
	icon_state = "smelter"

/obj/structure/prop/machine/smelter/change_state(state)
	. = ..()
	switch(state)
		if("off")
			set_icon_state("smelter")
		if("on")
			set_icon_state("smelter-process")

/obj/structure/prop/machine/smelter/starts_on
	icon_state = "smelter-process"
