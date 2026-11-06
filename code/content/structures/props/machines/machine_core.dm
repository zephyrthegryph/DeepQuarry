/**
 * Possible 'state' options for change_state(state) are:
 * on: Doing some kinda worky thing
 * off: Not doing much of anything
 * empty: No blue crystal thingy
 * loaded: off but without the animation
 */
// some kinda NT thing from Eris
/obj/structure/prop/machine/core
	icon_state = "core_inactive"

/obj/structure/prop/machine/core/change_state(state)
	. = ..()
	switch(state)
		if("on")
			set_icon_state("core_active")
			flick("core_warmup", src)
		if("off")
			set_icon_state("core_inactive")
			flick("core_shutdown", src)
		if("empty")
			set_icon_state("core_empty")
		if("loaded")
			set_icon_state("core_inactive")

/obj/structure/prop/machine/core/starts_on
	icon_state = "core_active"

/obj/structure/prop/machine/core/allinone
	icon_state = "allinone"

/obj/structure/prop/machine/core/bus
	icon_state = "bus"

/obj/structure/prop/machine/core/comm_server
	icon_state = "comm_server"
