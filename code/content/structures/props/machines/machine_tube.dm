/**
 * Possible 'state' options for change_state(state) are:
 * down: In the ground, glowing
 * up: Out of the ground, open
 */
// experimental science destructor from /tg/
/obj/structure/prop/machine/tube
	icon = 'icons/obj/props/decor32x64.dmi'
	icon_state = "tube_open"

/obj/structure/prop/machine/tube/change_state(state)
	. = ..()
	switch(state)
		if("down")
			set_icon_state("tube_on")
			flick("tube_down", src)
		if("up")
			set_icon_state("tube_open")
			flick("tube_up", src)

/obj/structure/prop/machine/tube/starts_down
	icon_state = "tube_on"
