/**
 * Possible 'state' options for change_state(state) are:
 * off: Inert
 * on: Hand destroying machinery
 */
// 'sorter' from Eris
/obj/structure/prop/machine/sorter
	icon = 'icons/obj/props/decor.dmi'
	icon_state = "sorter"

/obj/structure/prop/machine/sorter/change_state(state)
	. = ..()
	switch(state)
		if("off")
			set_icon_state("sorter")
		if("on")
			set_icon_state("sorter-process")

/obj/structure/prop/machine/sorter/starts_on
	icon_state = "sorter-process"
